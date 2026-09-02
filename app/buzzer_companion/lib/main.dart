import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'audio/sound_engine.dart';
import 'audio/sonorisation.dart';
import 'audio/sound_library.dart';
import 'ble_link_service.dart';
import 'broadsheet/console_shell.dart';
import 'broadsheet/tokens.dart';
import 'event_logo.dart';
import 'jeu/animation_tirage.dart';
import 'jeu/moteur_quiz.dart';
import 'popout/popout_launcher.dart';
import 'popout/popout_snapshot.dart';
import 'popout/popout_window.dart';
import 'popout/window_launch_args.dart';
import 'protocol.dart';
import 'questionnaires/active_questionnaire.dart';
import 'simulation.dart';
import 'version_check.dart';
import 'questionnaires/catalogue.dart';
import 'questionnaires/questionnaire_store.dart';
import 'team_names.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final windowController = await WindowController.fromCurrentEngine();
  final launchArgs = WindowLaunchArgs.parse(windowController.arguments);

  switch (launchArgs.kind) {
    case WindowKind.main:
      // La console suppose un portable 1440x900 minimum (design_handoff_
      // buzzer_console/README.md) — sans cette taille imposée, le rail
      // droit peut manquer de place et déborder sur un écran plus petit.
      const options = WindowOptions(
        size: Size(1440, 900),
        minimumSize: Size(1440, 900),
        center: true,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      runApp(const BuzzerCompanionApp());
    case WindowKind.popout:
      runApp(const PopoutWindow());
  }
}

class BuzzerCompanionApp extends StatefulWidget {
  const BuzzerCompanionApp({super.key});

  @override
  State<BuzzerCompanionApp> createState() => _BuzzerCompanionAppState();
}

class _BuzzerCompanionAppState extends State<BuzzerCompanionApp> {
  final _ble = BleLinkService();
  final _game = GameState();
  final _popout = PopoutLauncher();
  final _teams = TeamNames();
  final _logo = EventLogo();
  final _questionnaires = QuestionnaireStore();
  final _catalogue = CatalogueStore();
  late final ActiveQuestionnaire _actif;
  late final MoteurQuiz _moteur;
  late final Sonorisation _sons;
  late final AnimationTirage _tirage;
  final _version = VersionCheck();
  late final Simulateur _simulateur;
  late final SoundEngine _sound;
  StreamSubscription<SfxEvent>? _sfxSub;
  StreamSubscription<({int buzzer, int ms})>? _buzzSub;

  @override
  void initState() {
    super.initState();
    // Le lanceur fabrique son instantane d'ouverture par ce chemin unique.
    _popout.instantaneCourant = _instantane;
    _ble.init();
    _game.listenTo(_ble.messages);
    _game.addListener(_pushSnapshotToPopout);
    _actif = ActiveQuestionnaire(_game);
    _simulateur = Simulateur(_game);
    // Moteur de son : joue la bibliothèque embarquée à la place du DFPlayer
    // et renvoie au Mega son état de lecture, qui remplace la broche BUSY
    // (voir SoundEngine).
    _sound = SoundEngine(
      library: SoundLibrary(),
      onBusyChanged: _ble.sendSoundBusy,
    );
    _sound.init();
    // Le rappel des sons se voit sur l'écran public : ses changements
    // doivent donc pousser un instantané, comme ceux du jeu.
    _sound.addListener(_pushSnapshotToPopout);
    // Une seule façon de jouer un son de partie. Elle suit le réglage de
    // sortie audio choisi sur l'écran Buzzers : haut-parleurs du PC ou
    // haut-parleur du buzzer (voir Sonorisation). Créée avant le moteur de
    // jeu, qui s'en sert.
    _sons = Sonorisation(locale: _sound, ble: _ble);
    // Le tirage au sort anime : chenillard qui ralentit, cale sur son bruitage.
    // Partage, parce que deux moments s'en servent : melanger les sons des
    // buzzers, et designer qui ouvre une manche de Vol.
    _tirage = AnimationTirage(ble: _ble, sons: _sons);

    // LE MOTEUR DE JEU DE L'APPLICATION. En mode application, le buzzer ne
    // garde aucun état de partie : il arme des boutons et rapporte les appuis.
    // C'est ici que vivent la question courante, les scores et la fin de
    // partie (voir MoteurQuiz).
    _moteur = MoteurQuiz(ble: _ble, actif: _actif, sons: _sons);
    _moteur.tirage = _tirage;
    _moteur.addListener(_pushSnapshotToPopout);
    _buzzSub = _game.buzzEvents.listen((e) => _moteur.surBuzz(e.buzzer, e.ms));
    // La présence des buzzers reste une observation du matériel : le moteur
    // ne peut pas armer un buzzer qui n'est pas là.
    _game.addListener(_suivrePresence);

    _sound.addListener(_pushSnapshotToPopout);
    _teams.load();
    _teams.addListener(_pushSnapshotToPopout);
    _logo.load();
    _logo.addListener(_pushSnapshotToPopout);
    _sfxSub = _game.sfxEvents.listen(_handleSfx);
    // Silencieux si le site est injoignable : voir VersionCheck.
    _version.init();
  }

  // La présence des buzzers est la seule chose que le matériel sache mieux
  // que l'application : un buzzer débranché ne doit pas être armé, ni compter
  // dans les scores.
  void _suivrePresence() {
    final vu = _game.present;
    if (listEquals(vu, _moteur.presents)) return;
    _moteur.presents = List<bool>.of(vu);
  }

  void _handleSfx(SfxEvent event) {
    switch (event.type) {
      case 'INTRO':
        _sound.playIntro();
      case 'GOOD':
        _sound.playGood();
      case 'BAD':
        _sound.playBad();
      case 'WAIT':
        _sound.playWaiting();
      case 'SPIN':
        _sound.playSpin();
      case 'BUZZ':
        if (event.arg != null) _sound.playBuzzer(event.arg!);
      case 'RANDBUZZ':
        _sound.playRandomBuzzerSound();
      case 'DECOY':
        _sound.playDecoy(_game.present);
    }
  }

  // LE SEUL ENDROIT QUI FABRIQUE L'INSTANTANE DE L'ECRAN PUBLIC.
  //
  // Il y en a eu deux : celui-ci et le bouton du rail droit, qui construisait
  // le sien a l'ouverture de la fenetre. Ils ont diverge. Le bouton ignorait
  // le moteur de jeu, donc l'ecran public s'ouvrait sur un instantane qui se
  // croyait en pleine partie, sans jeu ni question a montrer : vide devant la
  // salle. Le lanceur DEMANDE maintenant l'instantane courant plutot qu'on le
  // lui fabrique de l'exterieur (voir PopoutLauncher.instantaneCourant).
  PopoutSnapshot _instantane() {
    // Deux sources possibles, jamais melangees : le moteur de jeu quand
    // l'application mene, la telemetrie du buzzer quand il joue seul.
    final mene = isAppControl(_game.phase) || _moteur.etape != EtapeQuiz.repos;
    return mene
        ? PopoutSnapshot.duMoteur(
            _moteur,
            _game,
            question: _actif.current,
            teamNames: _teams.all,
            logoPath: _logo.path,
            recallIndex: _sound.recallIndex,
          )
        : PopoutSnapshot.fromGameState(
            _game,
            teamNames: _teams.all,
            logoPath: _logo.path,
            recallIndex: _sound.recallIndex,
          );
  }

  void _pushSnapshotToPopout() => _popout.pushSnapshot(_instantane());

  @override
  void dispose() {
    _sfxSub?.cancel();
    _buzzSub?.cancel();
    _game.removeListener(_suivrePresence);
    _moteur.removeListener(_pushSnapshotToPopout);
    _moteur.dispose();
    _sound.removeListener(_pushSnapshotToPopout);
    _sound.dispose();
    _ble.dispose();
    _game.removeListener(_pushSnapshotToPopout);
    _teams.removeListener(_pushSnapshotToPopout);
    _logo.removeListener(_pushSnapshotToPopout);
    _logo.dispose();
    _teams.dispose();
    _game.dispose();
    _popout.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buzzer Companion',
      theme: ThemeData(
        fontFamily: 'Source Serif 4',
        scaffoldBackgroundColor: BSColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: BSColors.accent,
          surface: BSColors.bg,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: ConsoleShell(
        ble: _ble,
        game: _game,
        popout: _popout,
        sound: _sound,
        teams: _teams,
        logo: _logo,
        questionnaires: _questionnaires,
        catalogue: _catalogue,
        actif: _actif,
        moteur: _moteur,
        sons: _sons,
        tirage: _tirage,
        version: _version,
        simulateur: _simulateur,
      ),
    );
  }
}
