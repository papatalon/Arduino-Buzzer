import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sound_library.dart';

const _assignmentKey = 'buzzer_sound_assignment';
const _volumeKey = 'app_sound_volume';

// Moteur de son de l'app : joue la bibliotheque embarquee a la place du
// DFPlayer du buzzer (voir le plan "bascule audio").
//
// Deux responsabilites qui n'existaient pas cote app avant :
//
// 1. **Les assignations buzzer -> son appartiennent a l'app.** En mode
//    delegue le Mega ne gere plus que les lumieres, donc son EEPROM et ses
//    constantes *_FILE_COUNT ne font plus autorite. L'assignation est
//    persistee ici (SharedPreferences) et couvre toute la bibliotheque
//    locale, y compris les sons ajoutes apres coup.
//
// 2. **Emulation de la broche BUSY.** Le firmware s'en sert pour caler le
//    chenillard sur la musique d'intro (Buzzer::songFinished). S'il ne joue
//    plus rien, la broche ne bouge plus : l'app doit donc signaler debut et
//    fin de lecture, sinon les lumieres se desynchronisent du son.
//
// Moteur : flutter_soloud, et non audioplayers. Ce dernier a fait planter
// l'app en pleine utilisation — son greffon Windows emet ses evenements
// depuis un fil non-plateforme, ce que Flutter refuse (bug amont connu et
// non corrige : bluefireteam/audioplayers#1635, PR #1961 toujours ouverte).
// flutter_soloud passe par FFI plutot que par des canaux de plateforme :
// cette categorie de panne ne peut pas s'y produire. Il est de surcroit
// concu pour les effets sonores de jeu, donc a faible latence.
class SoundEngine extends ChangeNotifier {
  SoundEngine({required this.library, required this.onBusyChanged});

  final SoundLibrary library;
  // Appelee a chaque changement d'etat de lecture : c'est ce qui alimente
  // SFX_BUSY vers le Mega.
  final void Function(bool busy) onBusyChanged;

  final SoLoud _soloud = SoLoud.instance;
  final Random _random = Random();

  // Sources déjà chargées, gardées en cache : recharger un asset à chaque
  // buzz ajouterait une latence inutile sur le geste le plus fréquent.
  final Map<String, AudioSource> _sources = {};

  SoundHandle? _handle;
  Timer? _busyPoll;

  // Son assigne a chaque buzzer (index 0-3 = Rouge/Bleu/Jaune/Vert), en
  // index dans le dossier 02_Buzzer.
  List<int> assignment = [0, 1, 2, 3];
  double volume = 0.8;
  bool _busy = false;
  bool get busy => _busy;

  String? lastPlayed;

  // Evite de rejouer deux fois de suite le meme son d'une categorie
  // aleatoire, comme le fait deja le firmware (lastGood dans Mp3.cpp).
  final Map<SoundFolder, int> _lastRandom = {};

  Future<void> init() async {
    try {
      await _soloud.init();
    } catch (e) {
      debugPrint('Moteur audio indisponible : $e');
    }
    await library.load();
    final prefs = await SharedPreferences.getInstance();

    final saved = prefs.getStringList(_assignmentKey);
    if (saved != null && saved.length == 4) {
      assignment = saved.map((s) => int.tryParse(s) ?? 0).toList();
    } else {
      shuffleAssignments(persist: false);
    }
    _clampAssignments();

    volume = prefs.getDouble(_volumeKey) ?? 0.8;
    notifyListeners();
  }

  @override
  void dispose() {
    _recallTimer?.cancel();
    _busyPoll?.cancel();
    _soloud.deinit();
    super.dispose();
  }

  // Un son retire de la bibliotheque ne doit pas laisser une assignation
  // pointer dans le vide.
  void _clampAssignments() {
    final max = library.count(SoundFolder.buzzer);
    if (max == 0) return;
    assignment = assignment.map((i) => (i < 0 || i >= max) ? 0 : i).toList();
  }

  Future<void> _persistAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_assignmentKey, assignment.map((i) => '$i').toList());
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    onBusyChanged(value);
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    // Applique au son en cours pour que le curseur s'entende tout de suite ;
    // les suivants le reçoivent à la lecture.
    final handle = _handle;
    if (handle != null && _soloud.getIsValidVoiceHandle(handle)) {
      _soloud.setVolume(handle, volume);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, volume);
    notifyListeners();
  }

  // --- Assignations -------------------------------------------------------

  void shuffleAssignments({bool persist = true}) {
    final max = library.count(SoundFolder.buzzer);
    if (max == 0) return;
    final pool = List<int>.generate(max, (i) => i)..shuffle(_random);
    assignment = List<int>.generate(4, (i) => pool[i % pool.length]);
    if (persist) {
      _persistAssignments();
      notifyListeners();
    }
  }

  // Assigne un son precis (choix direct dans la grille). Contrairement a
  // cycleAssignment, on n'ecarte pas les sons deja pris : l'operateur voit
  // lesquels le sont et decide en connaissance de cause.
  void setAssignment(int buzzerId, int soundIndex) {
    final max = library.count(SoundFolder.buzzer);
    if (buzzerId < 0 || buzzerId > 3 || soundIndex < 0 || soundIndex >= max) return;
    assignment[buzzerId] = soundIndex;
    _persistAssignments();
    notifyListeners();
  }

  // Apercu d'un son du dossier des buzzers sans toucher aux assignations.
  Future<void> previewBuzzerSound(int soundIndex) => _play(SoundFolder.buzzer, soundIndex);

  // --- Rappel des sons ----------------------------------------------------
  //
  // Avant de lancer une partie, l'animateur refait entendre a la salle le son
  // de chaque equipe, un par un, pendant que l'ecran public montre de qui il
  // s'agit. « Ne buzze pas » a toujours eu cette etape (SoundGame::learn) et
  // elle est utile a tous les jeux : personne ne reconnait son buzz s'il ne
  // l'a pas entendu depuis le debut de la soiree.
  //
  // Sequence pilotee ici plutot que dans le firmware : c'est l'app qui
  // possede la bibliotheque et les assignations, et elle sait exactement
  // quand un son se termine (le sondage d'occupation qui sert deja au
  // chenillard de l'intro).

  static const _recallGapMs = 700;   // silence entre deux sons

  List<int> _recallQueue = [];
  Timer? _recallTimer;

  // Buzzer dont le son passe en ce moment, ou null si aucun rappel en cours.
  // Transporte jusqu'a l'ecran public par l'instantane.
  int? recallIndex;

  bool get recalling => recallIndex != null || _recallQueue.isNotEmpty;

  void startRecall(List<bool> present) {
    stopRecall();
    _recallQueue = [
      for (var i = 0; i < 4; i++)
        if (i < present.length && present[i]) i,
    ];
    _nextRecall();
  }

  void stopRecall() {
    _recallTimer?.cancel();
    _recallTimer = null;
    _recallQueue = [];
    if (recallIndex != null) {
      recallIndex = null;
      notifyListeners();
    }
  }

  Future<void> _nextRecall() async {
    if (_recallQueue.isEmpty) {
      recallIndex = null;
      notifyListeners();
      return;
    }
    final who = _recallQueue.removeAt(0);
    recallIndex = who;
    notifyListeners();
    // Attendu, pas lance et oublie : au retour, l'etat « occupe » est deja
    // pose. Sans ca, le premier tic du sondage (150 ms) pourrait tomber
    // pendant le chargement du fichier, voir « libre », et enchainer sur le
    // son suivant avant meme d'avoir joue celui-ci.
    await playBuzzer(who);
    // On enchaine a la FIN du son plutot qu'apres un delai fixe : les sons
    // de la bibliotheque n'ont pas tous la meme duree, et un delai fixe
    // couperait les longs ou laisserait un blanc apres les courts.
    _recallTimer?.cancel();
    _recallTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (_busy) return;
      t.cancel();
      _recallTimer = null;
      Future.delayed(const Duration(milliseconds: _recallGapMs), () {
        if (recallIndex != null) _nextRecall();
      });
    });
  }

  // Fait defiler le son d'un buzzer, en sautant ceux deja pris par un autre
  // buzzer tant qu'il reste des sons libres (meme intention que
  // Mp3::cycleSound cote firmware : deux buzzers ne doivent pas sonner
  // pareil).
  void cycleAssignment(int buzzerId, {int direction = 1}) {
    final max = library.count(SoundFolder.buzzer);
    if (max == 0 || buzzerId < 0 || buzzerId > 3) return;
    var candidate = assignment[buzzerId];
    for (var step = 0; step < max; step++) {
      candidate = (candidate + direction + max) % max;
      final takenByOther = [
        for (var i = 0; i < 4; i++)
          if (i != buzzerId) assignment[i],
      ].contains(candidate);
      if (!takenByOther) break;
    }
    assignment[buzzerId] = candidate;
    _persistAssignments();
    notifyListeners();
  }

  // --- Lecture ------------------------------------------------------------

  Future<void> _play(SoundFolder folder, int index) async {
    final path = library.assetPath(folder, index);
    if (path == null) return;
    lastPlayed = path;
    try {
      final source = _sources[path] ??= await _soloud.loadAsset(path);
      // Un seul son à la fois : sinon deux buzz rapprochés se
      // superposeraient et l'état "occupé" renvoyé au Mega deviendrait
      // ambigu.
      final previous = _handle;
      if (previous != null && _soloud.getIsValidVoiceHandle(previous)) {
        await _soloud.stop(previous);
      }
      _handle = _soloud.play(source, volume: volume);
      _setBusy(true);
      _startBusyPoll();
    } catch (e) {
      debugPrint('Lecture impossible ($path) : $e');
      _setBusy(false);
    }
  }

  // Fin de lecture par sondage du handle. flutter_soloud n'expose pas de
  // rappel de fin simple, et surtout : c'est justement un canal
  // d'évènements natif qui faisait planter l'app avec le paquet précédent.
  // Un sondage à 150 ms est largement assez fin pour le chenillard de
  // l'intro, et ne peut rien casser.
  void _startBusyPoll() {
    _busyPoll?.cancel();
    _busyPoll = Timer.periodic(const Duration(milliseconds: 150), (t) {
      final handle = _handle;
      if (handle == null || !_soloud.getIsValidVoiceHandle(handle)) {
        t.cancel();
        _busyPoll = null;
        _handle = null;
        _setBusy(false);
      }
    });
  }

  Future<void> _playRandom(SoundFolder folder) async {
    final max = library.count(folder);
    if (max == 0) return;
    var index = _random.nextInt(max);
    if (max > 1 && index == _lastRandom[folder]) {
      index = (index + 1) % max;
    }
    _lastRandom[folder] = index;
    await _play(folder, index);
  }

  Future<void> playIntro() => _playRandom(SoundFolder.intro);
  Future<void> playGood() => _playRandom(SoundFolder.good);
  Future<void> playBad() => _playRandom(SoundFolder.bad);
  Future<void> playWaiting() => _playRandom(SoundFolder.waiting);
  Future<void> playSpin() => _playRandom(SoundFolder.divers);

  // Son assigne a un buzzer — sert aussi d'apercu depuis l'ecran Buzzers.
  Future<void> playBuzzer(int buzzerId) async {
    if (buzzerId < 0 || buzzerId > 3) return;
    await _play(SoundFolder.buzzer, assignment[buzzerId]);
  }

  // Duel : un son quelconque du dossier des buzzers, volontairement pas
  // celui d'un joueur en particulier.
  Future<void> playRandomBuzzerSound() => _playRandom(SoundFolder.buzzer);

  // « Ne buzze pas » : un leurre est un son qu'aucun buzzer PRESENT ne
  // possede, sinon un joueur croirait reconnaitre le sien (regle reprise de
  // SoundGame::pickDecoySound). Seule l'app peut le choisir maintenant
  // qu'elle detient les assignations.
  Future<void> playDecoy(List<bool> present) async {
    final max = library.count(SoundFolder.buzzer);
    if (max == 0) return;
    final owned = <int>{
      for (var i = 0; i < 4 && i < present.length; i++)
        if (present[i]) assignment[i],
    };
    final free = [
      for (var i = 0; i < max; i++)
        if (!owned.contains(i)) i,
    ];
    if (free.isEmpty) {
      // Bibliotheque trop petite pour un vrai leurre : le firmware
      // retombait sur un joueur, l'app joue simplement un son au hasard.
      await _playRandom(SoundFolder.buzzer);
      return;
    }
    await _play(SoundFolder.buzzer, free[_random.nextInt(free.length)]);
  }
}
