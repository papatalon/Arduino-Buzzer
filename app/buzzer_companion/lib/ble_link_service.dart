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

  // Le MTU BLE (~20 octets sur l'AT-09) fragmente les messages sur plusieurs
  // notifications : on accumule jusqu'au prochain "\n" avant de considérer
  // qu'un message est complet.
  String _rxBuffer = '';
  final _messageController = StreamController<String>.broadcast();
  Stream<String> get messages => _messageController.stream;

  bool _devicesDirty = false;
  Timer? _refreshTimer;

  void init() {
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_devicesDirty) {
        _devicesDirty = false;
        notifyListeners();
      }
    });

    UniversalBle.onAvailabilityChange = (state) {
      availability = state;
      notifyListeners();
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
      _devicesDirty = true;
    };

    UniversalBle.onConnectionChange = (deviceId, isConnected, error) {
      connectedDeviceId = isConnected ? deviceId : null;
      if (isConnected) {
        connectedDeviceName = devices[deviceId]?.name ?? connectedDeviceName;
      } else {
        connectedDeviceName = null;
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
            status = 'Connecté à ${connectedDeviceName ?? deviceId} · abonné aux notifications';
            notifyListeners();
            return;
          }
        }
      }
      if (attempt == 0) {
        await _discoverUartCharacteristic(deviceId, attempt: 1);
        return;
      }
      status = 'Aucune caractéristique notifiable trouvée.';
      notifyListeners();
    } catch (e) {
      if (attempt == 0) {
        await _discoverUartCharacteristic(deviceId, attempt: 1);
        return;
      }
      status = 'Erreur de découverte des services : $e';
      notifyListeners();
    }
  }

  void _handleIncomingBytes(Uint8List value) {
    _rxBuffer += utf8.decode(value, allowMalformed: true);
    final lines = _rxBuffer.split('\n');
    _rxBuffer = lines.removeLast();  // fragment incomplet, garde pour la prochaine notification
    for (final line in lines) {
      final trimmed = line.trim();  // Serial2.println termine par "\r\n"
      if (trimmed.isNotEmpty) _messageController.add(trimmed);
    }
  }
}
