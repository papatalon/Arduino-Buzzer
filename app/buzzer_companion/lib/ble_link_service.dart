import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

const _lastDeviceIdKey = 'last_device_id';
const _lastDeviceNameKey = 'last_device_name';

// Encapsule tout le dialogue BLE avec l'AT-09 : scan, connexion (avec
// reconnexion automatique au dernier appareil connu), et ré-assemblage des
// notifications en messages complets. Ne connaît rien du protocole applicatif
// (STATE/SCORE/...) — ça, c'est le rôle de GameState, qui écoute [messages].
class BleLinkService extends ChangeNotifier {
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

  // Dernier "PONG" reçu (réponse du Mega à chaque "CTRL|1", voir
  // BleLink::pollKey côté firmware) — contrairement à la télémétrie de jeu,
  // qui peut légitimement rester silencieuse en attendant un buzz, un
  // heartbeat doit toujours revenir : sert de détecteur fiable de
  // connexion "fantôme" (voir _checkLinkHealth).
  DateTime? _lastPongAt;
  bool _recovering = false;

  // Une seule reconnexion complète auto-déclenchée par échec de découverte
  // de services par connexion (voir _escalateDiscoveryFailure) — pour ne
  // pas boucler indéfiniment si le radio Windows est vraiment bloqué.
  bool _triedFullReconnectForDiscovery = false;

  void init() {
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
        _triedFullReconnectForDiscovery = false;  // nouvelle connexion, nouvelle chance
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

    _tryAutoReconnect();
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
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_lastDeviceIdKey);
    if (savedId == null) return;

    connectedDeviceName = prefs.getString(_lastDeviceNameKey);

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

  // Démarre/arrête le heartbeat "CTRL|1" (voir le champ _controlHeartbeat) :
  // tant qu'il est envoyé, le firmware considère que l'app a 100% le
  // contrôle et ignore le clavier physique (hors reset/test câblage).
  void _startControlHeartbeat() {
    _controlHeartbeat?.cancel();
    _lastPongAt = DateTime.now();  // laisse une marge avant le premier chien de garde
    _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'CTRL|1');
    _controlHeartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      _writeUartLine(connectedDeviceId, _uartServiceId, _uartCharacteristicId, 'CTRL|1');
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
  // cadence, marge raisonnable), le lien est mort — reconnexion automatique,
  // sans attendre que l'opérateur le remarque et clique lui-même.
  void _checkLinkHealth() {
    if (_recovering) return;
    final last = _lastPongAt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 4)) return;
    _recovering = true;
    status = 'Connexion silencieuse détectée, reconnexion automatique...';
    notifyListeners();
    reconnect().whenComplete(() => _recovering = false);
  }

  // Écriture brute partagée par sendKey() et le heartbeat "CTRL|" — un seul
  // chemin d'écriture BLE, silencieux si la caractéristique n'est pas
  // (encore) identifiée. Retourne si l'écriture a été tentée sans erreur.
  Future<bool> _writeUartLine(String? deviceId, String? serviceId, String? characteristicId, String line) async {
    if (deviceId == null || serviceId == null || characteristicId == null) return false;
    try {
      await UniversalBle.write(
        deviceId,
        serviceId,
        characteristicId,
        Uint8List.fromList(utf8.encode('$line\n')),
        withoutResponse: _uartWriteWithoutResponse,
      );
      return true;
    } catch (e) {
      status = "Échec d'envoi de la commande : $e";
      notifyListeners();
      return false;
    }
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
      await _escalateDiscoveryFailure(deviceId, 'Aucune caractéristique notifiable trouvée.');
    } catch (e) {
      if (attempt == 0) {
        await _discoverUartCharacteristic(deviceId, attempt: 1);
        return;
      }
      await _escalateDiscoveryFailure(deviceId, 'Erreur de découverte des services : $e');
    }
  }

  // Si la découverte de services échoue complètement (deux essais rapides
  // déjà épuisés, pas juste un délai insuffisant) : une reconnexion
  // complète (déconnexion + scan + reconnexion) a de meilleures chances
  // qu'un nouvel essai de découverte sur la même session BLE, peut-être
  // corrompue. Une seule tentative de ce type par connexion — si ça échoue
  // encore, seul un vrai aller-retour Bluetooth off/on dans les réglages
  // Windows a fonctionné à chaque fois par le passé (voir la mémoire du
  // projet) ; pas de boucle automatique indéfinie dans ce cas.
  Future<void> _escalateDiscoveryFailure(String deviceId, String message) async {
    if (_triedFullReconnectForDiscovery) {
      status = '$message Éteins puis rallume le Bluetooth de Windows pour débloquer.';
      notifyListeners();
      return;
    }
    _triedFullReconnectForDiscovery = true;
    status = '$message Nouvelle tentative de connexion complète...';
    notifyListeners();
    await reconnect();
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
