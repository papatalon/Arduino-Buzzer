import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../broadsheet/tokens.dart';
import 'popout_content.dart';
import 'popout_snapshot.dart';

const popoutChannel = WindowMethodChannel(
  'popout_state',
  mode: ChannelMode.unidirectional,
);

// La vraie fenêtre "écran public" (design_handoff_buzzer_console/README.md).
// Aucun contrôle de jeu : ni bouton, ni curseur actif — elle ne reçoit que
// de l'état, poussé par la console via [popoutChannel]. Pas de position
// mémorisée entre les sessions (décision du client, 2026-08-17) : on la
// rouvre centrée à chaque fois plutôt que de retrouver son écran.
//
// Seule exception à la règle "aucun contrôle" : le plein écran se commande
// d'ici, et de nulle part ailleurs. Il s'applique à l'écran où se trouve la
// FENÊTRE : piloté depuis la console, il recouvrait le moniteur de
// l'animateur. Le geste juste est donc de glisser d'abord la fenêtre sur le
// projecteur, puis de basculer depuis elle.
//
// Trois façons de le faire, parce qu'aucune ne convient à toutes les
// situations : double-clic (le réflexe des lecteurs vidéo), F11, et un
// bouton discret qui n'apparaît que quand la souris bouge sur la fenêtre.
// Échap sort toujours : une fenêtre sans barre de titre qui recouvre la
// barre des tâches doit pouvoir se reprendre au clavier, même si la console
// a planté.
class PopoutWindow extends StatefulWidget {
  const PopoutWindow({super.key});

  @override
  State<PopoutWindow> createState() => _PopoutWindowState();
}

class _PopoutWindowState extends State<PopoutWindow> {
  PopoutSnapshot _snapshot = PopoutSnapshot.empty;
  bool _fullScreen = false;

  // Le bouton n'existe que pendant que la souris bouge sur la fenêtre. Sur
  // un projecteur, le curseur est ailleurs la plupart du temps : rien
  // n'apparaît donc jamais devant la salle.
  bool _pointerActive = false;
  Timer? _pointerTimer;

  void _wakePointer() {
    _pointerTimer?.cancel();
    if (!_pointerActive) setState(() => _pointerActive = true);
    _pointerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _pointerActive = false);
    });
  }

  @override
  void dispose() {
    _pointerTimer?.cancel();
    super.dispose();
  }

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

  // Deux opérations distinctes, et c'est le piège : setFullScreen agrandit
  // la fenêtre par-dessus la barre des tâches, mais ne touche PAS au style
  // de son cadre. La barre de titre restait donc en haut de l'image
  // projetée. Il faut la masquer soi-même.
  //
  // L'ordre compte dans les deux sens : on retire le cadre avant d'agrandir,
  // et on le remet après avoir réduit, sinon Windows recalcule la géométrie
  // à partir d'un cadre qui n'est déjà plus le bon et la fenêtre revient
  // décalée.
  Future<void> _setFullScreen(bool on) async {
    if (_fullScreen == on) return;
    if (on) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    }
    if (mounted) setState(() => _fullScreen = on);
  }

  Future<void> _setUpWindow() async {
    const options = WindowOptions(
      size: Size(1280, 720),
      center: true,
      title: 'Buzzer : écran public',
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
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _setFullScreen(false);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.f11) {
              _setFullScreen(!_fullScreen);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            onHover: (_) => _wakePointer(),
            onExit: (_) {
              _pointerTimer?.cancel();
              if (mounted) setState(() => _pointerActive = false);
            },
            child: GestureDetector(
              // Double-clic : le geste que tout le monde essaie d'abord sur
              // une image plein cadre.
              onDoubleTap: () => _setFullScreen(!_fullScreen),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: PopoutContent(snapshot: _snapshot),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: AnimatedOpacity(
                      opacity: _pointerActive ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      // Ignoré tant qu'il est invisible : un bouton
                      // transparent qui attrape quand même les clics est
                      // pire que pas de bouton du tout.
                      child: IgnorePointer(
                        ignoring: !_pointerActive,
                        child: _FullScreenToggle(
                          fullScreen: _fullScreen,
                          onTap: () => _setFullScreen(!_fullScreen),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Volontairement du texte et non une icône : le design system n'a pas de
// glyphe de plein écran, et sur une fenêtre destinée à être projetée, un
// mot est plus explicite qu'un pictogramme qu'il faut décoder. Petites
// capitales espacées, comme les autres métadonnées de cet écran.
class _FullScreenToggle extends StatefulWidget {
  const _FullScreenToggle({required this.fullScreen, required this.onTap});

  final bool fullScreen;
  final VoidCallback onTap;

  @override
  State<_FullScreenToggle> createState() => _FullScreenToggleState();
}

class _FullScreenToggleState extends State<_FullScreenToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          color: _hovered ? BSColors.neutral200 : BSColors.neutral100,
          child: Text(
            widget.fullScreen ? 'QUITTER LE PLEIN ÉCRAN  ·  ÉCHAP' : 'PLEIN ÉCRAN  ·  F11',
            style: BSType.datelineRail(
              color: _hovered ? BSColors.text : BSColors.neutral600,
            ),
          ),
        ),
      ),
    );
  }
}
