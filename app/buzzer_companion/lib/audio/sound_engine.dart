import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sound_library.dart';

const _volumeKey = 'app_sound_volume';

// Moteur de son de l'app : joue la bibliotheque embarquee a la place du
// DFPlayer du buzzer (voir le plan "bascule audio").
//
// Deux responsabilites qui n'existaient pas cote app avant :
//
// 1. **Les assignations buzzer -> son appartiennent a l'app.** En mode
//    delegue le Mega ne gere plus que les lumieres, donc son EEPROM et ses
//    constantes *_FILE_COUNT ne font plus autorite.
//
//    Elles sont TIREES AU SORT A CHAQUE DEMARRAGE, et non conservees d'une
//    fois a l'autre. Elles l'etaient, sous forme d'indices dans la liste
//    triee du dossier 02_Buzzer, et c'etait un piege : ajouter un seul
//    fichier decale alphabetiquement tous les indices suivants, si bien que
//    le rouge changeait de son sans que personne n'ait touche a un reglage.
//
//    Enregistrer le nom du fichier plutot que sa position aurait corrige ca,
//    mais ne rien enregistrer est plus simple encore, et pour un jeu de
//    party c'est meme un gain : des sons differents d'une soiree a l'autre,
//    personne ne se lasse. Le choix tient toute la seance, l'app restant
//    ouverte ; les boutons « Changer » et « Melanger » restent disponibles.
//
//    Le prix, assume : un redemarrage EN PLEIN MILIEU d'une soiree rebat les
//    quatre sons. Entre deux jeux ce n'est rien, puisqu'ils sont rappeles au
//    debut de chaque partie ; en pleine manche de « Ne buzze pas », dont
//    tout le mecanisme repose sur la reconnaissance de son propre son, ce le
//    serait. Un redemarrage en pleine manche casse deja bien d'autres
//    choses.
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

  // Paresseux : SoLoud.instance exige le greffon natif des sa construction,
  // donc un champ ordinaire rendait le moteur impossible a instancier hors
  // d'une vraie application. Il ne se construit maintenant qu'a la premiere
  // utilisation, ce qui est de toute facon plus sain pour un objet aussi
  // lourd.
  late final SoLoud _soloud = SoLoud.instance;
  // Vrai une fois le moteur natif demarre. Sert a ne pas l'arreter s'il n'a
  // jamais demarre : sur un poste sans peripherique audio, init() echoue et
  // dispose() appelait quand meme deinit().
  bool _demarre = false;
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
      _demarre = true;
    } catch (e) {
      debugPrint('Moteur audio indisponible : $e');
    }
    await library.load();
    shuffleAssignments();

    final prefs = await SharedPreferences.getInstance();
    volume = prefs.getDouble(_volumeKey) ?? 0.8;
    notifyListeners();
  }

  @override
  void dispose() {
    _recallTimer?.cancel();
    _busyPoll?.cancel();
    _plafond?.cancel();
    if (_demarre) _soloud.deinit();
    super.dispose();
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

  // Quatre sons DISTINCTS tant que la bibliotheque en offre assez : deux
  // buzzers qui sonnent pareil rendent « Ne buzze pas » injouable. Le modulo
  // n'est un repli que pour une bibliotheque de moins de quatre sons.
  void shuffleAssignments() {
    final max = library.count(SoundFolder.buzzer);
    if (max == 0) return;
    final pool = List<int>.generate(max, (i) => i)..shuffle(_random);
    assignment = List<int>.generate(4, (i) => pool[i % pool.length]);
    notifyListeners();
  }

  // Assigne un son precis (choix direct dans la grille). Contrairement a
  // cycleAssignment, on n'ecarte pas les sons deja pris : l'operateur voit
  // lesquels le sont et decide en connaissance de cause.
  void setAssignment(int buzzerId, int soundIndex) {
    final max = library.count(SoundFolder.buzzer);
    if (buzzerId < 0 || buzzerId > 3 || soundIndex < 0 || soundIndex >= max) return;
    assignment[buzzerId] = soundIndex;
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
      _plafonnerSiBuzz(folder);
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

  // DUREE MAXI D'UN SON DE BUZZER.
  //
  // La bibliotheque va de la demi-seconde a une dizaine de secondes. Laisses
  // entiers, les plus longs couvrent la question suivante et retardent toute
  // la soiree. Le firmware applique la meme limite a la carte SD quand c'est
  // lui qui sonne (BUZZ_MAX_MS dans Mp3.h) : la coupure ne doit pas dependre
  // de la sortie choisie.
  //
  // Seuls les sons de BUZZER sont plafonnes. Une musique d'ouverture ou un
  // son d'attente doit pouvoir durer, c'est leur role.
  static const _buzzMaxMs = 2000;
  Timer? _plafond;

  void _plafonnerSiBuzz(SoundFolder folder) {
    _plafond?.cancel();
    _plafond = null;
    if (folder != SoundFolder.buzzer) return;
    final vise = _handle;
    _plafond = Timer(const Duration(milliseconds: _buzzMaxMs), () async {
      _plafond = null;
      // Un autre son a pu commencer entre-temps : on ne coupe que celui
      // qu'on avait vise.
      if (vise == null || _handle != vise) return;
      if (_soloud.getIsValidVoiceHandle(vise)) await _soloud.stop(vise);
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

  /// Coupe net la voix en cours. Utilise quand l'animateur ecourte
  /// l'ouverture : la musique ne doit pas continuer par-dessus la question.
  Future<void> arreter() async {
    _plafond?.cancel();
    _plafond = null;
    final courant = _handle;
    _handle = null;
    if (courant != null && _soloud.getIsValidVoiceHandle(courant)) {
      await _soloud.stop(courant);
    }
    _setBusy(false);
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
