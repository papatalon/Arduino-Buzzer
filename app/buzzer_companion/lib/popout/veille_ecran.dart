import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// Empêcher Windows d'éteindre l'écran pendant qu'une salle regarde le
// pop-out.
//
// LE PROBLÈME : l'écran public passe des minutes entières sans une seule
// touche ni un seul mouvement de souris. Windows ne surveille que le clavier
// et la souris; il ne voit ni le BLE, ni les phrases qui tournent, ni la
// projection. Avec les réglages par défaut, l'écran de la salle s'éteint au
// bout de dix minutes d'attente, exactement pendant qu'on explique les
// règles.
//
// IL FAUT DEUX PARADES, parce que Windows a deux minuteries distinctes et
// qu'aucune API ne couvre les deux :
//
// 1. SetThreadExecutionState, l'API des lecteurs vidéo et des logiciels de
//    présentation : elle annonce au système que l'application est en usage,
//    ce qui retient l'extinction de l'écran et la mise en veille. Elle ne
//    touche à aucun réglage de l'utilisateur et n'a aucun effet persistant :
//    le verrou disparaît avec le processus, même si l'application plante.
//    Sa documentation dit noir sur blanc qu'elle n'arrête PAS un économiseur
//    d'écran, d'où le point suivant.
//
// 2. Une entrée inerte, envoyée avec SendInput : un déplacement de souris de
//    zéro pixel. Aucun curseur ne bouge, aucune touche n'entre dans
//    l'application, mais le compteur d'inactivité de la session repart à
//    zéro, et c'est lui que l'économiseur d'écran surveille.
//
// CE QUE LA DEUXIÈME PARADE IMPLIQUE, ET C'EST VOULU : tant que l'écran
// public est ouvert, la session ne se verrouille pas non plus toute seule.
// Un poste d'animation projeté devant une salle ne doit ni s'éteindre ni
// demander un mot de passe au milieu d'une manche. Dès que la fenêtre se
// ferme, le comportement normal de Windows revient, sans rien à restaurer.
//
// L'ÉTAT DE LA PREMIÈRE PARADE EST ATTACHÉ AU FIL D'EXÉCUTION qui appelle,
// pas au processus. Le code Dart ne promet pas de rester sur le même fil
// pour toujours, d'où le réarmement périodique : il ne coûte rien quand tout
// va bien, remet le verrou en place si l'isolat a changé de fil sous nos
// pieds, et sert de battement à l'entrée inerte par la même occasion.

// Le verrou reste en vigueur jusqu'au prochain appel qui le relâche.
const _esContinuous = 0x80000000;

// Garde le système éveillé (pas de mise en veille).
const _esSystemRequired = 0x00000001;

// Garde l'écran allumé, ce qui est le vrai but ici.
const _esDisplayRequired = 0x00000002;

// Une entrée de type souris, et le seul drapeau qui nous intéresse : un
// déplacement relatif, qu'on demande nul.
const _inputMouse = 0;
const _mouseeventfMove = 0x0001;

/// L'appel qui pose l'état d'exécution, isolé derrière une fonction pour que
/// la logique ci-dessous se teste sans Windows.
typedef PoserEtatVeille = int Function(int drapeaux);

/// L'envoi de l'entrée inerte, isolé pour la même raison. Retourne le nombre
/// d'événements que Windows a acceptés, donc 1 quand tout va bien : un envoi
/// refusé est silencieux autrement, et c'est exactement le genre de panne
/// qu'on ne voit qu'en salle.
typedef SignalerPresence = int Function();

int _poserViaWindows(int drapeaux) => _setThreadExecutionState(drapeaux);

typedef _SetThreadExecutionStateNative = Uint32 Function(Uint32);
typedef _SetThreadExecutionStateDart = int Function(int);

final _setThreadExecutionState = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<_SetThreadExecutionStateNative, _SetThreadExecutionStateDart>(
  'SetThreadExecutionState',
);

// Les deux structures de SendInput. Leur disposition n'est pas décorative :
// l'appel prend la taille de INPUT en dernier paramètre et refuse tout ce
// qui ne correspond pas exactement à ce que le système attend (40 octets en
// 64 bits, l'union commençant après le remplissage qui suit le type).
final class _MouseInput extends Struct {
  @Int32()
  external int dx;
  @Int32()
  external int dy;
  @Uint32()
  external int mouseData;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

final class _Input extends Struct {
  @Uint32()
  external int type;
  external _MouseInput mi;
}

typedef _SendInputNative = Uint32 Function(Uint32, Pointer<_Input>, Int32);
typedef _SendInputDart = int Function(int, Pointer<_Input>, int);

final _sendInput = DynamicLibrary.open('user32.dll')
    .lookupFunction<_SendInputNative, _SendInputDart>('SendInput');

// Le tampon est alloué une seule fois pour toute la vie du processus : cette
// fonction part toutes les quarante-cinq secondes pendant des heures, et
// rien dans son contenu ne change d'un envoi à l'autre.
final Pointer<_Input> _tamponEntree = () {
  final p = calloc<_Input>();
  p.ref.type = _inputMouse;
  p.ref.mi.dx = 0;
  p.ref.mi.dy = 0;
  p.ref.mi.dwFlags = _mouseeventfMove;
  return p;
}();

/// Publique pour être vérifiable à la main sur un vrai Windows : c'est un
/// appel système dont l'échec ne se voit nulle part ailleurs.
int signalerPresenceWindows() =>
    _sendInput(1, _tamponEntree, sizeOf<_Input>());

/// Tient l'écran allumé tant que quelqu'un le demande.
///
/// [poser], [signaler] et [actif] ne sont là que pour les tests : en vrai,
/// ce sont les appels Windows, et seulement sous Windows.
class VeilleEcran {
  VeilleEcran({
    PoserEtatVeille? poser,
    SignalerPresence? signaler,
    bool? actif,
  })  : _poser = poser ?? _poserViaWindows,
        _signaler = signaler ?? signalerPresenceWindows,
        _actif = actif ?? Platform.isWindows;

  final PoserEtatVeille _poser;
  final SignalerPresence _signaler;
  final bool _actif;

  Timer? _rearmement;

  bool get tientLEcranAllume => _rearmement != null;

  /// Combien de temps entre deux réarmements. La plus courte attente que
  /// Windows accepte, pour l'écran comme pour l'économiseur, est d'une
  /// minute : passer bien en dessous laisse de la marge même si un
  /// réarmement est retardé.
  static const intervalleRearmement = Duration(seconds: 45);

  /// Demande à Windows de garder l'écran allumé. Sans effet si c'est déjà
  /// le cas : l'appelant peut le redemander sans compter ses appels.
  void interdireLaVeille() {
    if (!_actif || _rearmement != null) return;
    _demander();
    _rearmement = Timer.periodic(intervalleRearmement, (_) => _demander());
  }

  /// Rend la main au système. À appeler dès que l'écran public se ferme :
  /// une console laissée ouverte toute la nuit ne doit pas empêcher un
  /// portable de dormir, ni retenir le verrouillage de la session.
  void permettreLaVeille() {
    if (_rearmement == null) return;
    _rearmement!.cancel();
    _rearmement = null;
    // ES_CONTINUOUS seul, sans les deux autres drapeaux : c'est la façon
    // documentée d'effacer l'état, pas de le remplacer. L'entrée inerte,
    // elle, n'a rien à défaire : elle ne laissait aucune trace.
    _poser(_esContinuous);
  }

  void _demander() {
    _poser(_esContinuous | _esSystemRequired | _esDisplayRequired);
    _signaler();
  }

  void dispose() => permettreLaVeille();
}
