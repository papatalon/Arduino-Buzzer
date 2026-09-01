import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'audio/sound_engine.dart';
import 'audio/sound_library.dart';
import 'ble_link_service.dart';
import 'broadsheet/console_shell.dart';
import 'broadsheet/tokens.dart';
import 'event_logo.dart';
import 'popout/popout_launcher.dart';
import 'popout/popout_snapshot.dart';
import 'popout/popout_window.dart';
import 'popout/window_launch_args.dart';
import 'protocol.dart';
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
  late final SoundEngine _sound;
  StreamSubscription<SfxEvent>? _sfxSub;

  @override
  void initState() {
    super.initState();
    _ble.init();
    _game.listenTo(_ble.messages);
    _game.addListener(_pushSnapshotToPopout);

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
    _teams.load();
    _teams.addListener(_pushSnapshotToPopout);
    _logo.load();
    _logo.addListener(_pushSnapshotToPopout);
    _sfxSub = _game.sfxEvents.listen(_handleSfx);
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

  void _pushSnapshotToPopout() {
    _popout.pushSnapshot(
        PopoutSnapshot.fromGameState(
      _game,
      teamNames: _teams.all,
      logoPath: _logo.path,
      recallIndex: _sound.recallIndex,
    ));
  }

  @override
  void dispose() {
    _sfxSub?.cancel();
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
      ),
    );
  }
}
