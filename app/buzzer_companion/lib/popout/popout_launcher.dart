import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import 'popout_snapshot.dart';
import 'popout_window.dart';
import 'window_launch_args.dart';

// Ouvre/pilote la fenêtre de l'écran public depuis la console.
class PopoutLauncher extends ChangeNotifier {
  PopoutLauncher() {
    // Si l'animateur ferme la fenêtre elle-même (bouton natif, Alt+F4), rien
    // ne le dit spontanément à ce contrôleur : sans ce suivi, le bouton
    // "Détacher" resterait bloqué sur "réattacher" indéfiniment.
    _windowsChangedSub = onWindowsChanged.listen((_) => _checkStillOpen());
  }

  // QUI SAIT FABRIQUER L'INSTANTANE COURANT. Pose une seule fois par
  // l'application au demarrage.
  //
  // Le lanceur le DEMANDE au lieu qu'on le lui passe : le fabriquer demande
  // de savoir si le moteur de jeu mene la partie ou si on suit le buzzer, et
  // un bouton dans un rail lateral n'a pas a connaitre cette regle. Il y a
  // eu deux endroits pour la fabriquer, ils ont diverge, et l'ecran public
  // s'ouvrait sur un instantane qui se croyait en pleine partie.
  PopoutSnapshot Function()? instantaneCourant;

  bool get isOpen => _controller != null;

  WindowController? _controller;
  StreamSubscription<void>? _windowsChangedSub;

  Future<void> _checkStillOpen() async {
    final controller = _controller;
    if (controller == null) return;
    final all = await WindowController.getAll();
    final stillOpen = all.any((c) => c.windowId == controller.windowId);
    if (!stillOpen) {
      _controller = null;
      notifyListeners();
    }
  }

  // [currentSnapshot] est poussé juste après l'ouverture : sans ça, une
  // fenêtre ouverte après le début de la partie reste bloquée sur l'état
  // vide jusqu'au prochain message BLE, ce qui a fait croire une fois que
  // rien ne fonctionnait alors que seule la synchronisation initiale
  // manquait.
  Future<void> open() async {
    if (_controller != null) {
      await _controller!.show();
      await _pousserCourant();
      return;
    }

    _controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: const WindowLaunchArgs(kind: WindowKind.popout).encode(),
      ),
    );
    notifyListeners();
    // La nouvelle fenêtre doit finir d'enregistrer son gestionnaire de canal
    // (PopoutWindow.initState, asynchrone) avant de pouvoir recevoir quoi
    // que ce soit — WindowController.create ne garantit que la création de
    // la fenêtre native, pas la fin de l'init Dart côté nouvel engine.
    await Future.delayed(const Duration(milliseconds: 400));
    await _pousserCourant();
  }

  Future<void> _pousserCourant() async {
    final instantane = instantaneCourant?.call();
    if (instantane != null) await pushSnapshot(instantane);
  }

  Future<void> pushSnapshot(PopoutSnapshot snapshot) async {
    if (_controller == null) return;
    try {
      await popoutChannel.invokeMethod('updateState', snapshot.encode());
    } catch (_) {
      // Fenêtre fermée entre la vérification ci-dessus et l'envoi : un
      // instantané perdu est sans conséquence, le suivant suivra.
    }
  }

  Future<void> close() async {
    final controller = _controller;
    if (controller == null) return;
    // Oublié AVANT d'attendre la fermeture : sinon, pendant que la fenêtre
    // se ferme, un instantané poussé par la télémétrie continuerait de
    // viser un canal en train de disparaître.
    _controller = null;
    notifyListeners();
    // Pas de .close() intégré à WindowController : on demande à la fenêtre
    // de se fermer elle-même (voir le handler enregistré dans
    // PopoutWindow._registerCloseHandler).
    try {
      await controller.invokeMethod('window_close');
    } catch (_) {
      // La fenêtre a pu disparaître entre-temps (fermeture native) : rien
      // à rattraper, l'état local est déjà à jour.
    }
  }

  @override
  void dispose() {
    _windowsChangedSub?.cancel();
    super.dispose();
  }
}
