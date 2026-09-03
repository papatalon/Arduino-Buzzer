import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import 'jeu/moteur_quiz.dart' show CommandesBuzzer;

const _lastDeviceIdKey = 'last_device_id';
const _lastDeviceNameKey = 'last_device_name';
const _appHandlesSoundKey = 'app_handles_sound';

// Encapsule tout le dialogue BLE avec l'AT-09 : scan, connexion (avec
// reconnexion automatique au dernier appareil connu), et ré-assemblage des
// notifications en messages complets. Ne connaît rien du protocole applicatif
// (STATE/SCORE/...) — ça, c'est le rôle de GameState, qui écoute [messages].
class BleLinkService extends ChangeNotifier implements CommandesBuzzer {
  AvailabilityState availability = AvailabilityState.unknown;
  bool scanning = false;
  final Map<String, BleDevice> devices = {};
  String? connectedDeviceId;
  String? connectedDeviceName;
  String status = 'Prêt.';

  // Compteurs de liaison pour l'écran "Appareil" (design_handoff_buzzer_
  // console/README.md, 1h) : combien de lignes complètes sont arrivées, la
  // dernière telle quelle, et son horodatage (pour un "âge" affiché).
  int messagesReceived = 0;
  String? lastRawMessage;
  DateTime? lastMessageAt;

  // Le MTU BLE (~20 octets sur l'AT-09) fragmente les messages sur plusieurs
  // notifications : on accumule jusqu'au prochain "\n" avant de considérer
  // qu'un message est complet.
  String _rxBuffer = '';
  final _messageController = StreamController<String>.broadcast();
  Stream<String> get messages => _messageController.stream;

  // La caractéristique FFE1 de l'AT-09 sert aux deux sens (notify pour
  // recevoir, write pour envoyer) : trouvée une fois dans
  // _discoverUartCharacteristic, réutilisée par sendKey().
  String? _uartServiceId;
  String? _uartCharacteristicId;
  bool _uartWriteWithoutResponse = true;

  Timer? _refreshTimer;

  // Heartbeat "CTRL|1" (voir BleLink::appInControl côté Mega) : répété tant
  // que l'app est connectée, pour que le firmware sache qu'elle a 100% le
  // contrôle (clavier physique verrouillé) — expire tout seul côté Mega si
  // ce heartbeat cesse, donc pas besoin d'un "CTRL|0" fiable à la
  // déconnexion (envoyé au mieux-effort seulement).
  Timer? _controlHeartbeat;

  // Où sort le son : l'app (défaut) ou le haut-parleur du buzzer. Réglable
  // par l'opérateur — sans haut-parleur côté PC, l'app muette rendrait le
  // buzzer inutilisable. Voyage dans le heartbeat (voir
  // _startControlHeartbeat) pour se rétablir tout seul si le Mega redémarre.
  bool appHandlesSound = true;

  Future<void> setAppHandlesSound(bool value) async {
    appHandlesSound = value;
    notifyListeners();
    // Envoi immédiat : sans ça le changement n'agirait qu'au prochain
    // battement, jusqu'à une seconde plus tard.
    await _writeUartLine(
      connectedDeviceId,
      _uartServiceId,
      _uartCharacteristicId,
      'CTRL|1|${value ? 1 : 0}',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appHandlesSoundKey, value);
  }

  // Dernier "PONG" reçu (réponse du Mega à chaque "CTRL|1", voir
  // BleLink::pollKey côté firmware) — contrairement à la télémétrie de jeu,
  // qui peut légitimement rester silencieuse en attendant un buzz, un
  // heartbeat doit toujours revenir : sert de détecteur fiable de
  // connexion "fantôme" (voir _checkLinkHealth).
  DateTime? _lastPongAt;

  void init() {
    // Réglage de sortie audio retenu d'une session à l'autre : un
    // opérateur sans haut-parleur ne veut pas le rebasculer chaque fois.
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_appHandlesSoundKey);
      if (saved != null && saved != appHandlesSound) {
        appHandlesSound = saved;
        notifyListeners();
      }
    });

    // Rafraîchit en continu (liste d'appareils qui arrivent pendant un scan,
    // âge du dernier message sur l'écran "Appareil") plutôt que de suivre un
    // drapeau "dirty" par type d'évènement — l'UI de cette app reste assez
    // simple pour que le coût d'un rebuild à ce rythme soit négligeable.
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      notifyListeners();
    });

    UniversalBle.onAvailabilityChange = (state) {
      final wasOff = availability != AvailabilityState.poweredOn;
      availability = state;
      // Éteindre le Bluetooth de Windows ne déclenche pas forcément
      // `onConnectionChange` — observé : la console reste affichée comme
      // "connectée" alors qu'il ne peut plus y avoir de lien radio réel.
      // Sans ce radio éteint/indisponible, aucune connexion n'est possible.
      if (state != AvailabilityState.poweredOn && connectedDeviceId != null) {
        connectedDeviceId = null;
        connectedDeviceName = null;
        status = 'Bluetooth indisponible (${state.name}).';
      }
      notifyListeners();
      // Radio qui revient (ex. après un aller-retour off/on qui a servi à
      // purger une session BLE fantôme) : retente la reconnexion sans
      // attendre un clic manuel sur "Se connecter".
      if (wasOff && state == AvailabilityState.poweredOn && connectedDeviceId == null) {
        _tryAutoReconnect();
      }
    };
    UniversalBle.getBluetoothAvailabilityState().then((state) {
      availability = state;
      notifyListeners();
      // La reconnexion automatique n'est tentée qu'une fois l'adaptateur
      // confirmé allumé. Lancée dès init() comme avant, elle partait
      // pendant que la pile Bluetooth de Windows finissait de s'initialiser
      // : la connexion "réussissait" mais la découverte des services ne
      // trouvait aucune caractéristique notifiable. C'est ce qui obligeait
      // à cliquer "Reconnecter" après chaque démarrage — ce bouton, lui,
      // s'exécute forcément une fois la pile prête.
      if (state == AvailabilityState.poweredOn && connectedDeviceId == null) {
        _tryAutoReconnect();
      }
    });

    UniversalBle.onScanResult = (device) {
      // Un appareil BLE alterne entre un paquet d'annonce (souvent sans nom)
      // et une réponse de scan (avec le nom) : ne pas écraser un nom déjà
      // connu par une mise à jour qui n'en a pas.
      final previousName = devices[device.deviceId]?.name;
      if ((device.name == null || device.name!.isEmpty) &&
          previousName != null &&
          previousName.isNotEmpty) {
        device.name = previousName;
      }
      devices[device.deviceId] = device;
    };

    UniversalBle.onConnectionChange = (deviceId, isConnected, error) {
      connectedDeviceId = isConnected ? deviceId : null;
      if (isConnected) {
        connectedDeviceName = devices[deviceId]?.name ?? connectedDeviceName;
      } else {
        connectedDeviceName = null;
        _stopControlHeartbeat();
        // Au mieux-effort seulement (le lien peut déjà être coupé) : le
        // filet de sécurité réel côté Mega est l'expiration du heartbeat
        // (voir BleLink::appInControl), pas ce message.
        _writeUartLine(deviceId, _uartServiceId, _uartCharacteristicId, 'CTRL|0');
        _uartServiceId = null;
        _uartCharacteristicId = null;
      }
      status = isConnected
          ? 'Connecté à ${connectedDeviceName ?? deviceId}'
          : 'Déconnecté${error != null ? " ($error)" : ""}';
      notifyListeners();

      if (isConnected) {
        _discoverUartCharacteristic(deviceId);
        _rememberDevice(deviceId, devices[deviceId]?.name);
      }
    };

    UniversalBle.onValueChange = (deviceId, characteristicId, value, timestamp) {
      _handleIncomingBytes(value);
    };

    // Pas de _tryAutoReconnect() ici : elle est déclenchée par la lecture
    // de l'état de l'adaptateur ci-dessus, une fois celui-ci confirmé prêt.
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stopControlHeartbeat();
    _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'CTRL|0');
    _messageController.close();
    if (scanning) UniversalBle.stopScan();
    super.dispose();
  }

  Future<void> _rememberDevice(String deviceId, String? name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDeviceIdKey, deviceId);
    if (name != null && name.isNotEmpty) {
      await prefs.setString(_lastDeviceNameKey, name);
    }
  }

  // Tente de se reconnecter au dernier appareil connu (par adresse) sans
  // attendre un scan manuel.
  Future<void> _tryAutoReconnect() async {
    // Deux chemins déclenchent cette reconnexion : la lecture initiale de
    // l'état de l'adaptateur et l'évènement onAvailabilityChange, qui
    // arrivent tous deux au démarrage. Sans ce verrou, deux séquences
    // déconnexion/scan/connexion tournaient en parallèle sur le même
    // appareil — et Windows renvoyait alors une base GATT incomplète
    // (services génériques seulement, sans le FFE0 de l'AT-09), d'où
    // "aucune caractéristique notifiable" à chaque démarrage. Constaté
    // dans les traces, pas déduit.
    if (_reconnectInProgress) return;
    _reconnectInProgress = true;
    try {
      await _autoReconnectInner();
    } finally {
      _reconnectInProgress = false;
    }
  }

  Future<void> _autoReconnectInner() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_lastDeviceIdKey);
    if (savedId == null) return;

    connectedDeviceName = prefs.getString(_lastDeviceNameKey);

    // Déconnexion préalable, même si l'app vient de démarrer et se croit
    // déconnectée : quand le processus précédent s'est fermé, Windows garde
    // souvent la connexion BLE ouverte au niveau système. Un connect() dans
    // cet état répond "déjà connecté" sans erreur, mais le nouveau
    // processus se retrouve sans session GATT utilisable — c'est le
    // fantôme classique. C'est exactement ce que faisait le bouton
    // "Reconnecter", seul moyen fiable jusqu'ici de repartir proprement.
    try {
      await UniversalBle.disconnect(savedId);
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (_) {
      // Attendu si Windows ne le considérait effectivement pas connecté.
    }

    // Un bref scan avant de se connecter par adresse force Windows à
    // rafraîchir sa vue de l'appareil plutôt que de réutiliser une session
    // BLE périmée après un reset du périphérique — observé plusieurs fois :
    // connexion + abonnement "réussis" côté app, mais aucune notification
    // ne circule jamais tant que ce rafraîchissement n'a pas eu lieu.
    status = 'Recherche de ${connectedDeviceName ?? savedId}...';
    notifyListeners();
    try {
      await UniversalBle.startScan();
      await Future.delayed(const Duration(milliseconds: 1500));
      await UniversalBle.stopScan();
    } catch (_) {
      // Le scan est une aide au rafraîchissement, pas une étape requise :
      // un échec ici ne doit pas empêcher la tentative de connexion.
    }

    status = 'Reconnexion à ${connectedDeviceName ?? savedId}...';
    notifyListeners();
    try {
      await UniversalBle.connect(savedId);
    } catch (e) {
      status = 'Reconnexion automatique échouée : $e';
      notifyListeners();
    }
  }

  Future<void> toggleScan() async {
    if (scanning) {
      await UniversalBle.stopScan();
      scanning = false;
      notifyListeners();
      return;
    }

    devices.clear();
    scanning = true;
    status = 'Recherche des appareils BLE...';
    notifyListeners();

    try {
      await UniversalBle.startScan();
    } catch (e) {
      scanning = false;
      status = 'Erreur de scan : $e';
      notifyListeners();
    }
  }

  Future<void> connect(BleDevice device) async {
    if (scanning) {
      await UniversalBle.stopScan();
      scanning = false;
    }
    status = 'Connexion à ${device.name ?? device.deviceId}...';
    notifyListeners();
    try {
      await UniversalBle.connect(device.deviceId);
    } catch (e) {
      status = 'Échec de connexion : $e';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    final id = connectedDeviceId;
    if (id != null) await UniversalBle.disconnect(id);
  }

  // Oublie l'appareil sauvegardé (SharedPreferences) et coupe la connexion
  // en cours : la prochaine reconnexion ne pourra plus se faire toute
  // seule avec un identifiant peut-être périmé — il faudra Chercher +
  // Connecter manuellement sur une entrée de scan fraîche. À utiliser si
  // la reconnexion automatique semble coincée sur un appareil qui ne
  // répond plus (voir la mémoire du projet : connexion "fantôme").
  Future<void> forgetDevice() async {
    final id = connectedDeviceId;
    _stopControlHeartbeat();
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastDeviceIdKey);
    await prefs.remove(_lastDeviceNameKey);
    connectedDeviceId = null;
    connectedDeviceName = null;
    _uartServiceId = null;
    _uartCharacteristicId = null;
    status = 'Appareil oublié. Utilise Chercher puis Connecter pour une connexion fraîche.';
    notifyListeners();
  }

  // Déconnecte puis reconnecte tout de suite au même appareil, en un clic —
  // utile en particulier pour purger une connexion "fantôme" (connectée
  // mais silencieuse, voir la mémoire du projet) sans repasser par
  // Chercher + Connecter séparément. Appelée depuis plusieurs endroits (le
  // bouton "Reconnecter", l'échec de découverte, le chien de garde du
  // heartbeat) : un verrou évite que deux reconnexions se chevauchent et se
  // marchent dessus (observé : ça laisse connectedDeviceId pointer vers une
  // session BLE déjà remplacée, et les écritures échouent avec
  // "deviceNotFound").
  bool _reconnectInProgress = false;

  Future<void> reconnect() async {
    if (_reconnectInProgress) return;
    final id = connectedDeviceId;
    if (id == null) return;
    _reconnectInProgress = true;
    try {
      status = 'Reconnexion...';
      notifyListeners();
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {
        // Au mieux-effort : on tente la reconnexion même si la déconnexion a échoué.
      }
      // Même parade que _tryAutoReconnect() : un bref scan avant de se
      // reconnecter force Windows à rafraîchir sa vue de l'appareil plutôt
      // que de réutiliser une session BLE périmée.
      try {
        await UniversalBle.startScan();
        await Future.delayed(const Duration(milliseconds: 1500));
        await UniversalBle.stopScan();
      } catch (_) {}
      try {
        await UniversalBle.connect(id);
      } catch (e) {
        status = 'Reconnexion échouée : $e';
        notifyListeners();
      }
    } finally {
      _reconnectInProgress = false;
    }
  }

  // Simule une touche du clavier matriciel côté firmware (protocole
  // "KEY|<touche>", voir BleLink::pollKey côté Mega). N'importe quelle
  // action App→Mega passe par ici — pas de commande séparée par écran.
  Future<void> sendKey(String key) async {
    final ok = await _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'KEY|$key');
    status = ok
        ? 'Commande KEY|$key envoyée.'
        : 'Envoi impossible : aucune caractéristique BLE identifiée pour écrire.';
    notifyListeners();
  }

  // Choisit directement le jeu d'index [index] (protocole "SELECT_GAME|<n>",
  // voir Configuration::selectGameIndex côté Mega) — une vraie commande, pas
  // une simulation de touche : fonctionne peu importe la phase courante du
  // buzzer, pas seulement depuis le menu de choix du jeu.
  Future<void> selectGame(int index) async {
    final ok = await _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'SELECT_GAME|$index');
    status = ok
        ? 'Jeu sélectionné.'
        : 'Envoi impossible : aucune caractéristique BLE identifiée pour écrire.';
    notifyListeners();
  }

  // Déclare quels buzzers sont en jeu (protocole "SET_PRESENT|<masque>",
  // bit 0 = rouge ... bit 3 = vert). C'est le seul moyen de jouer à deux ou
  // à trois depuis l'app : l'assistant du clavier exige un appui PHYSIQUE
  // sur chaque buzzer présent, geste impossible à piloter à distance, et le
  // clavier est de toute façon verrouillé pendant que l'app a le contrôle.
  // Le record du Reflexe, quand l'application vient de le battre. Le Mega
  // decide s'il l'enregistre : il pourrait recevoir un temps d'une version
  // plus ancienne, ou moins bon que celui qu'il garde.
  Future<void> enregistrerRecord(int ms) => _writeUartLine(connectedDeviceId,
      _uartServiceId, _uartCharacteristicId, 'SET_REC|$ms');

  Future<void> setPresence(List<bool> present) async {
    var mask = 0;
    for (var i = 0; i < present.length && i < 4; i++) {
      if (present[i]) mask |= 1 << i;
    }
    final ok = await _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'SET_PRESENT|$mask');
    status = ok
        ? 'Présence des buzzers mise à jour.'
        : 'Envoi impossible : aucune caractéristique BLE identifiée pour écrire.';
    notifyListeners();
  }

  // Émulation de la broche BUSY du DFPlayer : quand l'app joue les sons à
  // la place du buzzer, le firmware n'a plus aucun repère pour savoir si un
  // son est en cours. Il s'en sert pour caler le chenillard de l'intro sur
  // la musique (Buzzer::songFinished), d'où ce signal.
  Future<void> sendSoundBusy(bool busy) async {
    await _writeUartLine(
      connectedDeviceId,
      _uartServiceId,
      _uartCharacteristicId,
      'SFX_BUSY|${busy ? 1 : 0}',
    );
  }

  // Configuration des sons du DFPlayer, pilotée à distance. Sans ça, en
  // mode « son du buzzer » personne ne pourrait réassigner les sons :
  // l'app ne joue pas, et le clavier du buzzer est verrouillé tant qu'elle
  // a le contrôle. Reproduit l'assistant du clavier.
  Future<void> _sendSoundCommand(String action, int buzzerId) => _writeUartLine(
        connectedDeviceId,
        _uartServiceId,
        _uartCharacteristicId,
        'SND|$action|$buzzerId',
      );

  // Ouvert a Sonorisation, qui route les sons de partie vers le buzzer quand
  // c'est lui qui porte la sortie audio.
  Future<void> sendSoundCommand(String action, int buzzerId) =>
      _sendSoundCommand(action, buzzerId);

  Future<void> buzzerSoundShuffle() => _sendSoundCommand('S', -1);
  Future<void> buzzerSoundNext(int buzzerId) => _sendSoundCommand('N', buzzerId);
  Future<void> buzzerSoundPrevious(int buzzerId) => _sendSoundCommand('P', buzzerId);
  Future<void> buzzerSoundPreview(int buzzerId) => _sendSoundCommand('E', buzzerId);

  // Confirme la sélection de catégories de questions (protocole
  // "SET_CATS|<mask>", voir Configuration::confirmCategories côté Mega) —
  // une vraie commande (pas une simulation de touche) : le masque final
  // est envoyé d'un coup, pas coché case par case, pour éviter les
  // raccourcis dépendants du curseur physique côté firmware.
  Future<void> setCategories(int mask) async {
    final ok = await _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'SET_CATS|$mask');
    status = ok
        ? 'Catégories confirmées.'
        : 'Envoi impossible : aucune caractéristique BLE identifiée pour écrire.';
    notifyListeners();
  }

  // --- Primitives du mode esclave -----------------------------------------
  //
  // En mode application, le buzzer ne fait que gerer les boutons : on lui dit
  // quels buzzers accepter, et il repond BUZZ|<n>|<ms>. Voir AppControl cote
  // firmware.

  // [masque] : bit 0 = rouge ... bit 3 = vert.
  @override
  Future<void> armer(int masque, {bool continu = false}) => _writeUartLine(
      connectedDeviceId,
      _uartServiceId,
      _uartCharacteristicId,
      continu ? 'ARM|$masque|C' : 'ARM|$masque');

  @override
  Future<void> desarmer() => _writeUartLine(
      connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'DISARM');

  @override
  Future<void> allumerLeds(int masque) => _writeUartLine(connectedDeviceId,
      _uartServiceId, _uartCharacteristicId, 'LED|$masque');

  @override
  Future<void> allumerSignal(int masque, {bool avecSonDuel = false}) =>
      _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId,
          avecSonDuel ? 'GO|$masque|S' : 'GO|$masque');

  // Demande le depart au buzzer, sans le faire naviguer dans ses menus.
  //
  // En mode application, le firmware n'est plus le maitre du spectacle : il
  // ne gere que les buzzers. Lui faire defiler ses ecrans de categories puis
  // de nombre de questions revenait a mimer une interface qui n'existe que
  // pour son clavier physique, et l'operateur se retrouvait a choisir des
  // categories de la banque du Mega alors qu'il avait deja choisi son
  // questionnaire dans l'application.
  // [nbQuestions] : 0 pour un depart ouvert, ou le nombre apres lequel le
  // buzzer arrete la partie. Zero avec un questionnaire de l'app, qui sait
  // quand il est epuise ; un nombre en manche libre annoncee d'avance.
  Future<void> startGame(int nbQuestions) async {
    final ok = await _writeUartLine(connectedDeviceId, _uartServiceId,
        _uartCharacteristicId, 'START_GAME|');
    status = ok
        ? 'Partie lancee.'
        : 'Envoi impossible : aucune caracteristique BLE identifiee pour ecrire.';
    notifyListeners();
  }

  // Fixe le nombre de questions et lance la partie. 0 = mode ouvert : le
  // buzzer ne compte plus, c'est l'application qui décide quand la soirée est
  // finie. Une vraie commande plutôt que des appuis rejoués, parce que le
  // compteur du firmware ne reboucle pas : revenir à 0 depuis 99 demanderait
  // 99 pressions.
  Future<void> setQuestionCount(int count) async {
    final ok = await _writeUartLine(
        connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'SET_COUNT|$count');
    status = ok
        ? (count == 0 ? 'Mode ouvert : la partie est lancée.' : 'Partie lancée.')
        : 'Envoi impossible : aucune caractéristique BLE identifiée pour écrire.';
    notifyListeners();
  }

  // Démarre/arrête le heartbeat "CTRL|1" (voir le champ _controlHeartbeat) :
  // tant qu'il est envoyé, le firmware considère que l'app a 100% le
  // contrôle et ignore le clavier physique (hors reset/test câblage).
  void _startControlHeartbeat() {
    _controlHeartbeat?.cancel();
    _lastPongAt = DateTime.now();  // laisse une marge avant le premier chien de garde
    _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId,
        'CTRL|1|${appHandlesSound ? 1 : 0}');
    _controlHeartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId,
        'CTRL|1|${appHandlesSound ? 1 : 0}');
      _checkLinkHealth();
    });
  }

  void _stopControlHeartbeat() {
    _controlHeartbeat?.cancel();
    _controlHeartbeat = null;
    _lastPongAt = null;
  }

  // Filet de sécurité contre une connexion "fantôme" (BLE affiche connecté
  // mais plus rien ne circule, dans un sens ou dans l'autre) : si aucun
  // PONG n'est revenu depuis 4s malgré l'envoi continu du heartbeat (4x sa
  // cadence, marge raisonnable), le lien est mort.
  //
  // Volontairement PAS de reconnexion automatique ici (essayé, puis
  // retiré le 2026-08-19) : le plugin BLE Windows (`universal_ble`) a un
  // bug natif connu où un connect() déclenché justement dans ce genre de
  // contexte (après un échec de type "deviceNotFound") peut faire planter
  // tout le processus sans aucune trace côté Dart (voir issue GitHub
  // Navideck/universal_ble#213 — corrigée en partie, mais on a reproduit
  // un crash très similaire malgré le correctif). Relancer connect()
  // automatiquement en boucle dans cette situation augmente donc le
  // risque de crash plutôt que de le réduire. On se contente de prévenir
  // clairement l'opérateur, qui décide lui-même de reconnecter ou de
  // redémarrer l'app.
  bool _linkWarningShown = false;

  // Vrai tant que le heartbeat revient : l'écran Appareil s'en sert pour
  // afficher un état de liaison fiable, indépendant du texte de [status]
  // (qui, lui, garde le dernier évènement en date et peut donc être périmé).
  bool get linkAlive =>
      _lastPongAt != null && DateTime.now().difference(_lastPongAt!) < const Duration(seconds: 4);

  void _checkLinkHealth() {
    final last = _lastPongAt;
    final silent = last == null || DateTime.now().difference(last) >= const Duration(seconds: 4);
    if (silent && !_linkWarningShown) {
      _linkWarningShown = true;
      status = 'Connexion silencieuse : aucune réponse du buzzer depuis plusieurs secondes. '
          'Clique Reconnecter, ou redémarre l\'app si ça ne suffit pas.';
      notifyListeners();
    } else if (!silent && _linkWarningShown) {
      // Le lien est revenu tout seul : sans ça, l'avertissement resterait
      // affiché indéfiniment et donnerait une fausse impression de panne.
      _linkWarningShown = false;
      status = 'Connecté à ${connectedDeviceName ?? connectedDeviceId} · liaison rétablie';
      notifyListeners();
    }
  }

  // File d'attente des écritures BLE : garantit qu'une seule est en vol à
  // la fois. Sans ça, un clic de l'opérateur peut tomber pile pendant
  // l'écriture périodique du heartbeat (1/s) — deux appels concurrents à
  // UniversalBle.write() sur la même caractéristique. C'est précisément
  // le genre de situation qui fait remonter une exception WinRT non gérée
  // dans le plugin Windows (issue Navideck/universal_ble#213) et tue la
  // liaison, voire le processus. Observé en test : la liaison mourait
  // systématiquement au moment d'une action de l'opérateur, jamais au
  // repos alors que le heartbeat écrivait pourtant en continu.
  Future<void> _writeChain = Future<void>.value();

  // Écriture brute partagée par sendKey() et le heartbeat "CTRL|" — un seul
  // chemin d'écriture BLE, silencieux si la caractéristique n'est pas
  // (encore) identifiée. Retourne si l'écriture a été tentée sans erreur.
  Future<bool> _writeUartLine(String? deviceId, String? serviceId, String? characteristicId, String line) {
    if (deviceId == null || serviceId == null || characteristicId == null) {
      return Future.value(false);
    }

    final result = _writeChain.then((_) async {
      try {
        await UniversalBle.write(
          deviceId,
          serviceId,
          characteristicId,
          Uint8List.fromList(utf8.encode('$line\n')),
          withoutResponse: _uartWriteWithoutResponse,
          // Une écriture qui ne rend jamais la main bloquerait toute la
          // file : on la laisse tomber plutôt que de figer les suivantes.
        ).timeout(const Duration(seconds: 3));
        return true;
      } catch (e) {
        status = "Échec d'envoi de la commande : $e";
        notifyListeners();
        return false;
      }
    });

    // Le maillon suivant attend celui-ci, succès ou échec — sinon une
    // erreur romprait la chaîne et les écritures suivantes partiraient
    // de nouveau en parallèle.
    _writeChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  // Cherche une caractéristique notifiable (celle par laquelle le Mega pousse
  // ses messages) parmi les services de l'appareil connecté, avec une
  // reprise : juste après une connexion, le module peut ne pas encore
  // répondre correctement à la découverte de services (observé plusieurs
  // fois : l'app se dit connectée mais rien n'arrive jamais, sans erreur
  // visible). Un court délai + un essai supplémentaire couvrent ce cas.
  Future<void> _discoverUartCharacteristic(String deviceId, {int attempt = 0}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      final services = await UniversalBle.discoverServices(deviceId);
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.properties.contains(CharacteristicProperty.notify)) {
            await UniversalBle.subscribeNotifications(
              deviceId,
              service.uuid,
              characteristic.uuid,
            );
            _uartServiceId = service.uuid;
            _uartCharacteristicId = characteristic.uuid;
            _uartWriteWithoutResponse =
                characteristic.properties.contains(CharacteristicProperty.writeWithoutResponse) ||
                    !characteristic.properties.contains(CharacteristicProperty.write);
            status = 'Connecté à ${connectedDeviceName ?? deviceId} · abonné aux notifications';
            notifyListeners();
            _startControlHeartbeat();
            return;
          }
        }
      }
      if (attempt == 0) {
        await _discoverUartCharacteristic(deviceId, attempt: 1);
        return;
      }
      _reportDiscoveryFailure('Aucune caractéristique notifiable trouvée.');
    } catch (e) {
      if (attempt == 0) {
        await _discoverUartCharacteristic(deviceId, attempt: 1);
        return;
      }
      _reportDiscoveryFailure('Erreur de découverte des services : $e');
    }
  }

  // Si la découverte de services échoue complètement (deux essais rapides
  // déjà épuisés, pas juste un délai insuffisant) : signale clairement le
  // problème plutôt que de retenter connect() automatiquement. Essayé
  // avant (reconnexion complète auto-déclenchée), puis retiré le
  // 2026-08-19 — voir la note dans _checkLinkHealth : un connect()
  // automatique dans ce genre de contexte peut faire planter tout le
  // processus (bug natif connu du plugin BLE Windows). L'opérateur clique
  // "Reconnecter"/"Oublier" lui-même, ou éteint/rallume le Bluetooth
  // Windows si ça persiste (seule parade fiable observée jusqu'ici).
  void _reportDiscoveryFailure(String message) {
    status = '$message Clique Reconnecter, ou éteins/rallume le Bluetooth de Windows si ça persiste.';
    notifyListeners();
  }

  void _handleIncomingBytes(Uint8List value) {
    _rxBuffer += utf8.decode(value, allowMalformed: true);
    final lines = _rxBuffer.split('\n');
    _rxBuffer = lines.removeLast();  // fragment incomplet, garde pour la prochaine notification
    for (final line in lines) {
      final trimmed = line.trim();  // Serial2.println termine par "\r\n"
      if (trimmed.isEmpty) continue;
      messagesReceived++;
      lastRawMessage = trimmed;
      lastMessageAt = DateTime.now();
      if (trimmed == 'PONG') {
        _lastPongAt = DateTime.now();  // reponse au heartbeat, pas un message de jeu
        continue;
      }
      _messageController.add(trimmed);
    }
  }
}
