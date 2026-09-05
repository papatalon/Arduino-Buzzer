import 'dart:io';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../ble_link_service.dart';
import '../../event_logo.dart';
import '../../protocol.dart';
import '../../simulation.dart';
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
  const DeviceScreen({
    super.key,
    required this.ble,
    required this.game,
    required this.logo,
    required this.simulateur,
  });
  final BleLinkService ble;
  final GameState game;
  final EventLogo logo;
  final Simulateur simulateur;

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
            const SizedBox(height: BSSpace.s6),
            Container(height: 1, color: BSColors.divider),
            const SizedBox(height: BSSpace.s4),
            Text('LOGO DE LA SOIRÉE', style: BSType.sectionKicker()),
            const SizedBox(height: BSSpace.s3),
            _LogoSetting(logo: logo),
            const SizedBox(height: BSSpace.s6),
            Container(height: 1, color: BSColors.divider),
            const SizedBox(height: BSSpace.s4),
            Text('SIMULATION', style: BSType.sectionKicker()),
            const SizedBox(height: BSSpace.s3),
            _SimulationPanel(simulateur: simulateur, game: game),
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
          const SizedBox(width: BSSpace.s2),
          TextButton(
            onPressed: ble.forgetDevice,
            style: TextButton.styleFrom(foregroundColor: BSColors.neutral600),
            child: const Text('Oublier'),
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

  // Distingue les trois cas qui se ressemblent tous "pas de son" quand on
  // est devant le buzzer : lecteur absent, lecteur présent mais muet, ou
  // lecteur qui fonctionne (voir GameState.audioPlayerDetected).
  String _audio() {
    final detected = game.audioPlayerDetected;
    if (detected == null) return '';
    if (!detected) return 'Absent';
    final vol = game.audioVolume;
    if (vol != null && vol <= 0) return 'Muet';
    return 'Volume ${vol ?? ""}';
  }

  Color? _audioColor() {
    final detected = game.audioPlayerDetected;
    if (detected == null) return null;
    if (!detected || (game.audioVolume ?? 1) <= 0) return BSColors.accent2_800;
    return BSColors.accent700;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // UN WRAP ET NON UN ROW : les cinq compteurs débordaient de 57 pixels
        // à droite, hors de la fenêtre, et le cinquième était donc invisible.
        //
        // Les serrer aurait été pire. Ce sont les chiffres qu'on lit quand la
        // liaison se comporte mal, en gros caractères pour se lire de loin
        // pendant qu'on manipule le buzzer : les rétrécir ou les tronquer
        // enlèverait justement ce qui les rend utiles. Ils passent donc à la
        // ligne quand la place manque.
        Wrap(
          spacing: BSSpace.s6,
          runSpacing: BSSpace.s3,
          children: [
            // État en direct, calculé à partir du heartbeat plutôt que du
            // texte de statut (qui garde le dernier évènement et peut être
            // périmé) — voir BleLinkService.linkAlive.
            _Stat(
              label: 'Liaison',
              value: ble.linkAlive ? 'Vivante' : 'Silencieuse',
              color: ble.linkAlive ? BSColors.accent700 : BSColors.accent2_800,
            ),
            _Stat(label: 'Messages reçus', value: '${ble.messagesReceived}'),
            _Stat(label: 'Lignes rejetées', value: '${game.messagesRejected}'),
            _Stat(label: 'Dernier message', value: _age()),
            _Stat(label: 'Audio', value: _audio(), color: _audioColor()),
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
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: BSType.body(size: 13, color: BSColors.neutral600)),
        Text(value, style: BSType.scoreConsole(color: color ?? BSColors.text)),
      ],
    );
  }
}

// Import du logo affiché en haut de l'écran public. Réglage général de la
// soirée, pas propre à un buzzer : il vit donc ici et non sur l'écran
// Buzzers. Le bouton « Retirer » est aussi important que le choix lui-même
// (demande explicite du client) : une image mise pour une soirée doit
// pouvoir partir aussi vite qu'elle est arrivée.
class _LogoSetting extends StatelessWidget {
  const _LogoSetting({required this.logo});
  final EventLogo logo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: logo,
      builder: (context, _) {
        final path = logo.path;
        return SizedBox(
          width: 620,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (path != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 56, maxWidth: 180),
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(
                      'Image introuvable',
                      style: BSType.body(size: 14, color: BSColors.accent2_800),
                    ),
                  ),
                ),
                const SizedBox(width: BSSpace.s3),
              ],
              Expanded(
                child: Text(
                  path ?? "Aucune image choisie. L'écran public n'affiche alors aucun emplacement vide.",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BSType.body(size: 14, color: BSColors.neutral600),
                ),
              ),
              const SizedBox(width: BSSpace.s3),
              OutlinedButton(
                onPressed: logo.pick,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BSColors.text,
                  side: const BorderSide(color: BSColors.divider),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                child: Text(path == null ? 'Choisir une image' : 'Changer', style: BSType.body(size: 14)),
              ),
              if (path != null) ...[
                const SizedBox(width: BSSpace.s2),
                TextButton(
                  onPressed: logo.clear,
                  style: TextButton.styleFrom(foregroundColor: BSColors.accent2_800),
                  child: const Text('Retirer'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// Rejoue une partie sans buzzer branché, pour pouvoir regarder les écrans de
// jeu. Sur l'écran Appareil, avec les autres outils de diagnostic : c'est un
// instrument de travail, pas une fonction de soirée.
//
// Les lignes injectées sont celles du vrai protocole (voir
// lib/simulation.dart), donc ce qu'on regarde est ce que le firmware
// produirait.
class _SimulationPanel extends StatelessWidget {
  const _SimulationPanel({required this.simulateur, required this.game});

  final Simulateur simulateur;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simulateur,
      builder: (context, _) {
        return SizedBox(
          width: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Rejoue une partie sans buzzer, pour regarder les écrans de jeu. "
                "Allez à « Partie » ou ouvrez l'écran public pendant que ça se "
                "déroule.",
                style: BSType.body(size: 15, color: BSColors.neutral700),
              ),
              const SizedBox(height: BSSpace.s3),
              for (final scenario in kScenarios) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        scenario.nom,
                        style: BSType.body(size: 17, color: BSColors.text)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => simulateur.jouer(scenario),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BSColors.text,
                        side: const BorderSide(color: BSColors.divider),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: Text(
                        simulateur.encours == scenario ? 'Rejouer' : 'Jouer',
                        style: BSType.body(size: 14),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: BSSpace.s3),
                  child: Text(
                    scenario.description,
                    style: BSType.body(size: 14, color: BSColors.neutral600),
                  ),
                ),
              ],
              if (simulateur.actif) ...[
                Text(
                  'En cours : ${simulateur.encours!.nom}, '
                  'étape ${simulateur.etape} sur ${simulateur.total}',
                  style: BSType.body(size: 15, color: BSColors.accent700),
                ),
                const SizedBox(height: BSSpace.s2),
              ],
              Row(
                children: [
                  TextButton(
                    onPressed: simulateur.actif ? simulateur.arreter : null,
                    style: TextButton.styleFrom(foregroundColor: BSColors.neutral600),
                    child: const Text('Arrêter'),
                  ),
                  TextButton(
                    onPressed: () {
                      simulateur.arreter();
                      remettreAuMenu(game);
                    },
                    style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
                    child: const Text('Revenir au menu'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
