import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../ble_link_service.dart';
import '../../protocol.dart';
import '../phosphor_duotone.dart';
import '../tokens.dart';

// Écran "Appareil" (design_handoff_buzzer_console/README.md, 1h). Seul des
// 4 écrans de configuration à être pleinement fonctionnel dès maintenant :
// scanner/connecter/déconnecter sont des actions BLE locales, pas des
// commandes App→Mega. Les compteurs de liaison et la trame brute (pensés
// dans la maquette comme le contenu du rail droit) sont montrés ici, dans
// la colonne centrale — le rail droit lui-même reste le châssis invariant
// validé à l'étape 1 (tableau des buzzers + écran public).
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.ble, required this.game});
  final BleLinkService ble;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Appareil', style: BSType.buzzerNameConsole(size: 26)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: ble.toggleScan,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BSColors.text,
                    side: const BorderSide(color: BSColors.divider),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  icon: PhosphorDuotone(
                    ble.scanning ? PhosphorGlyphs.xCircle : PhosphorGlyphs.magnifyingGlass,
                    size: 16,
                  ),
                  label: Text(ble.scanning ? 'Arrêter' : 'Chercher', style: BSType.body(size: 14)),
                ),
              ],
            ),
            const SizedBox(height: BSSpace.s4),
            if (ble.connectedDeviceId != null) ...[
              // Toujours affiché séparément de la liste de scan : un
              // appareil déjà connecté cesse d'annoncer, donc il ne
              // réapparaîtrait jamais dans un nouveau scan — vider la
              // liste avant de rescanner (toggleScan) le ferait sinon
              // disparaître de l'écran, sans façon de le déconnecter.
              Text('CONNECTÉ', style: BSType.sectionKicker()),
              const SizedBox(height: BSSpace.s2),
              _ConnectedRow(ble: ble),
              const SizedBox(height: BSSpace.s4),
              Container(height: 1, color: BSColors.divider),
              const SizedBox(height: BSSpace.s4),
            ],
            _DeviceList(ble: ble),
            const SizedBox(height: BSSpace.s6),
            Container(height: 1, color: BSColors.divider),
            const SizedBox(height: BSSpace.s4),
            Text('DIAGNOSTIC DE LIAISON', style: BSType.sectionKicker()),
            const SizedBox(height: BSSpace.s3),
            _Diagnostics(ble: ble, game: game),
          ],
        ),
      ),
    );
  }
}

class _ConnectedRow extends StatelessWidget {
  const _ConnectedRow({required this.ble});
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final name = ble.connectedDeviceName?.isNotEmpty == true ? ble.connectedDeviceName! : '(sans nom)';
    return Container(
      width: 620,
      padding: const EdgeInsets.symmetric(horizontal: BSSpace.s3, vertical: BSSpace.s2),
      color: BSColors.accent100,
      child: Row(
        children: [
          const PhosphorDuotone(PhosphorGlyphs.bluetoothConnected, size: 18, color: BSColors.accent700),
          const SizedBox(width: BSSpace.s2),
          Expanded(
            child: Text(name, style: BSType.body(size: 16, color: BSColors.text).copyWith(fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            color: BSColors.accent100,
            child: Text('Connecté', style: BSType.body(size: 12, color: BSColors.accent800)),
          ),
          const SizedBox(width: BSSpace.s2),
          TextButton(
            onPressed: ble.reconnect,
            style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
            child: const Text('Reconnecter'),
          ),
          const SizedBox(width: BSSpace.s2),
          TextButton(
            onPressed: ble.disconnect,
            style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.ble});
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final devices = ble.devices.values.where((d) => d.deviceId != ble.connectedDeviceId).toList()
      ..sort((a, b) {
        final byName = (a.name ?? '').compareTo(b.name ?? '');
        return byName != 0 ? byName : a.deviceId.compareTo(b.deviceId);
      });

    if (devices.isEmpty) {
      return Text(
        ble.scanning ? 'Recherche en cours...' : "Aucun autre appareil trouvé. Clique « Chercher ».",
        style: BSType.body(size: 15, color: BSColors.neutral600),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < devices.length; i++) ...[
          if (i > 0) const Padding(
            padding: EdgeInsets.symmetric(vertical: BSSpace.s2),
            child: SizedBox(height: 1, child: ColoredBox(color: BSColors.divider)),
          ),
          _DeviceRow(device: devices[i], ble: ble),
        ],
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.ble});
  final BleDevice device;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final name = device.name?.isNotEmpty == true ? device.name! : '(sans nom)';
    return SizedBox(
      width: 620,
      child: Row(
        children: [
          const PhosphorDuotone(PhosphorGlyphs.bluetooth, size: 18, color: BSColors.neutral500),
          const SizedBox(width: BSSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: BSType.body(size: 16, color: BSColors.text).copyWith(fontWeight: FontWeight.w600)),
                Text(
                  '${device.deviceId} · RSSI ${device.rssi ?? "?"}',
                  style: BSType.body(size: 13, color: BSColors.neutral600),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => ble.connect(device),
            style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
            child: const Text('Connecter'),
          ),
        ],
      ),
    );
  }
}

class _Diagnostics extends StatelessWidget {
  const _Diagnostics({required this.ble, required this.game});
  final BleLinkService ble;
  final GameState game;

  String _age() {
    final at = ble.lastMessageAt;
    if (at == null) return 'Jamais';
    final seconds = DateTime.now().difference(at).inSeconds;
    if (seconds < 1) return "à l'instant";
    if (seconds < 60) return '$seconds s';
    return '${seconds ~/ 60} min';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Stat(label: 'Messages reçus', value: '${ble.messagesReceived}'),
            const SizedBox(width: BSSpace.s6),
            _Stat(label: 'Lignes rejetées', value: '${game.messagesRejected}'),
            const SizedBox(width: BSSpace.s6),
            _Stat(label: 'Dernier message', value: _age()),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        Text('TRAME BRUTE', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s1),
        Text(
          ble.lastRawMessage ?? 'Aucun message reçu',
          style: BSType.body(size: 15, color: BSColors.text).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: BSType.body(size: 13, color: BSColors.neutral600)),
        Text(value, style: BSType.scoreConsole(color: BSColors.text)),
      ],
    );
  }
}
