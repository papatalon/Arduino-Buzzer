import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../broadsheet/tokens.dart';
import 'popout_content.dart';
import 'popout_snapshot.dart';

const popoutChannel = WindowMethodChannel(
  'popout_state',
  mode: ChannelMode.unidirectional,
);

// La vraie fenêtre "écran public" (design_handoff_buzzer_console/README.md).
// Aucun contrôle : ni bouton, ni curseur actif, ni raccourci — elle ne
// reçoit que de l'état, poussé par la console via [popoutChannel]. Pas de
// position mémorisée entre les sessions (décision du client, 2026-08-17) :
// on la rouvre centrée à chaque fois plutôt que de retrouver son écran.
class PopoutWindow extends StatefulWidget {
  const PopoutWindow({super.key});

  @override
  State<PopoutWindow> createState() => _PopoutWindowState();
}

class _PopoutWindowState extends State<PopoutWindow> {
  PopoutSnapshot _snapshot = PopoutSnapshot.empty;

  @override
  void initState() {
    super.initState();
    _setUpWindow();
    _registerCloseHandler();

    popoutChannel.setMethodCallHandler((call) async {
      if (call.method == 'updateState') {
        setState(() => _snapshot = PopoutSnapshot.decode(call.arguments as String));
      }
      return null;
    });
  }

  // WindowController n'a pas de .close() intégré : la fenêtre principale ne
  // peut qu'invoquer 'window_close' sur ce canal ; c'est cette fenêtre-ci qui
  // doit se fermer elle-même via son propre window_manager (voir le README
  // de desktop_multi_window, section "Extend WindowController").
  Future<void> _registerCloseHandler() async {
    final self = await WindowController.fromCurrentEngine();
    await self.setWindowMethodHandler((call) async {
      if (call.method == 'window_close') await windowManager.close();
      return null;
    });
  }

  Future<void> _setUpWindow() async {
    const options = WindowOptions(
      size: Size(1280, 720),
      center: true,
      title: 'Buzzer — écran public',
      backgroundColor: BSColors.bg,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(fontFamily: 'Source Serif 4', scaffoldBackgroundColor: BSColors.bg),
      home: Scaffold(
        backgroundColor: BSColors.bg,
        body: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: FittedBox(
              fit: BoxFit.contain,
              child: PopoutContent(snapshot: _snapshot),
            ),
          ),
        ),
      ),
    );
  }
}
