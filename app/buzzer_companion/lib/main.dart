import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ble_link_service.dart';
import 'broadsheet/console_shell.dart';
import 'broadsheet/tokens.dart';
import 'popout/popout_launcher.dart';
import 'popout/popout_snapshot.dart';
import 'popout/popout_window.dart';
import 'popout/window_launch_args.dart';
import 'protocol.dart';

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

  @override
  void initState() {
    super.initState();
    _ble.init();
    _game.listenTo(_ble.messages);
    _game.addListener(_pushSnapshotToPopout);
  }

  void _pushSnapshotToPopout() {
    _popout.pushSnapshot(PopoutSnapshot.fromGameState(_game));
  }

  @override
  void dispose() {
    _ble.dispose();
    _game.removeListener(_pushSnapshotToPopout);
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
      home: ConsoleShell(ble: _ble, game: _game, popout: _popout),
    );
  }
}
