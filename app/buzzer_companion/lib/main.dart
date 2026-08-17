import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  runApp(const BuzzerCompanionApp());
}

class BuzzerCompanionApp extends StatelessWidget {
  const BuzzerCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buzzer Companion — Spike BLE',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const BleSpikePage(),
    );
  }
}

class BleSpikePage extends StatefulWidget {
  const BleSpikePage({super.key});

  @override
  State<BleSpikePage> createState() => _BleSpikePageState();
}

class _BleSpikePageState extends State<BleSpikePage> {
  AvailabilityState _availability = AvailabilityState.unknown;
  bool _scanning = false;
  final Map<String, BleDevice> _devices = {};
  String? _connectedDeviceId;
  String _status = 'Prêt.';

  // Service/caractéristique UART découverts après connexion (typiquement
  // FFE0/FFE1 sur un clone HM-10, mais on les découvre au lieu de les figer
  // en dur pour ne pas dépendre d'une hypothèse sur ce module précis).
  String? _uartServiceId;
  String? _uartCharacteristicId;
  final List<String> _receivedLines = [];

  // Les annonces BLE arrivent plusieurs fois par seconde par appareil : un
  // setState() par paquet fait clignoter la liste. On accumule les résultats
  // et on ne rafraîchit l'UI qu'à intervalle fixe.
  bool _devicesDirty = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();

    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_devicesDirty) {
        setState(() => _devicesDirty = false);
      }
    });

    UniversalBle.onAvailabilityChange = (state) {
      setState(() => _availability = state);
    };
    UniversalBle.getBluetoothAvailabilityState().then((state) {
      setState(() => _availability = state);
    });

    UniversalBle.onScanResult = (device) {
      // Un appareil BLE alterne entre un paquet d'annonce (souvent sans nom)
      // et une réponse de scan (avec le nom) : ne pas écraser un nom déjà
      // connu par une mise à jour qui n'en a pas.
      final previousName = _devices[device.deviceId]?.name;
      if ((device.name == null || device.name!.isEmpty) &&
          previousName != null &&
          previousName.isNotEmpty) {
        device.name = previousName;
      }
      _devices[device.deviceId] = device;
      _devicesDirty = true;
    };

    UniversalBle.onConnectionChange = (deviceId, isConnected, error) {
      setState(() {
        _connectedDeviceId = isConnected ? deviceId : null;
        final name = _devices[deviceId]?.name ?? deviceId;
        _status = isConnected
            ? 'Connecté à $name'
            : 'Déconnecté de $name${error != null ? " ($error)" : ""}';
        if (!isConnected) {
          _uartServiceId = null;
          _uartCharacteristicId = null;
        }
      });
      if (isConnected) _discoverUartCharacteristic(deviceId);
    };

    UniversalBle.onValueChange = (deviceId, characteristicId, value, timestamp) {
      setState(() => _receivedLines.add(utf8.decode(value, allowMalformed: true)));
    };
  }

  // Cherche une caractéristique notifiable (celle par laquelle le Mega va
  // pousser ses messages) parmi les services de l'appareil connecté.
  Future<void> _discoverUartCharacteristic(String deviceId) async {
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
            setState(() {
              _uartServiceId = service.uuid;
              _uartCharacteristicId = characteristic.uuid;
              _status = 'Abonné aux notifications ($_uartServiceId)';
            });
            return;
          }
        }
      }
      setState(() => _status = 'Aucune caractéristique notifiable trouvée.');
    } catch (e) {
      setState(() => _status = 'Erreur de découverte des services : $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_scanning) UniversalBle.stopScan();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await UniversalBle.stopScan();
      setState(() => _scanning = false);
      return;
    }

    setState(() {
      _devices.clear();
      _scanning = true;
      _status = 'Recherche des appareils BLE...';
    });

    try {
      await UniversalBle.startScan();
    } catch (e) {
      setState(() {
        _scanning = false;
        _status = 'Erreur de scan : $e';
      });
    }
  }

  Future<void> _connect(BleDevice device) async {
    if (_scanning) {
      await UniversalBle.stopScan();
      setState(() => _scanning = false);
    }
    setState(() => _status = 'Connexion à ${device.name ?? device.deviceId}...');
    try {
      await UniversalBle.connect(device.deviceId);
    } catch (e) {
      setState(() => _status = 'Échec de connexion : $e');
    }
  }

  Future<void> _disconnect(String deviceId) async {
    await UniversalBle.disconnect(deviceId);
  }

  @override
  Widget build(BuildContext context) {
    // Tri stable (nom puis id) : le RSSI change à chaque annonce, trier
    // dessus ferait sauter les lignes de position en permanence.
    final devices = _devices.values.toList()
      ..sort((a, b) {
        final byName = (a.name ?? '').compareTo(b.name ?? '');
        return byName != 0 ? byName : a.deviceId.compareTo(b.deviceId);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Spike BLE — AT-09')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bluetooth : ${_availability.name}'),
                const SizedBox(height: 4),
                Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: devices.isEmpty
                ? const Center(child: Text('Aucun appareil trouvé pour le moment.'))
                : ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final isConnected = device.deviceId == _connectedDeviceId;
                      return ListTile(
                        key: ValueKey(device.deviceId),
                        title: Text(device.name?.isNotEmpty == true
                            ? device.name!
                            : '(sans nom)'),
                        subtitle: Text('${device.deviceId} • RSSI ${device.rssi ?? "?"}'),
                        trailing: FilledButton(
                          onPressed: isConnected
                              ? () => _disconnect(device.deviceId)
                              : () => _connect(device),
                          child: Text(isConnected ? 'Déconnecter' : 'Connecter'),
                        ),
                      );
                    },
                  ),
          ),
          if (_connectedDeviceId != null) ...[
            const Divider(height: 1),
            SizedBox(
              height: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Messages reçus (${_uartCharacteristicId ?? "en recherche..."})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _receivedLines.length,
                      itemBuilder: (context, index) => Text(
                        _receivedLines[_receivedLines.length - 1 - index],
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleScan,
        icon: Icon(_scanning ? Icons.stop : Icons.search),
        label: Text(_scanning ? 'Arrêter le scan' : 'Chercher des appareils'),
      ),
    );
  }
}
