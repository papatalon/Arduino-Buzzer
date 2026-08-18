import 'package:flutter/material.dart';

import '../../protocol.dart';
import '../tokens.dart';

// Écran "Buzzers" (design_handoff_buzzer_console/README.md, 1e), en lecture
// seule : identité, présence, son assigné. Pas de boutons "Écouter" /
// "Changer" / "Allumer" ni de réglage de volume — ils dépendent tous de
// commandes App→Mega qui n'existent pas encore (voir la décision "lecture
// seule d'abord" pour ces écrans).
const _kWiring = ['bouton 5 · LED 6', 'bouton 7 · LED 8', 'bouton 9 · LED 10', 'bouton 11 · LED 12'];

class BuzzersScreen extends StatelessWidget {
  const BuzzersScreen({super.key, required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Buzzers', style: BSType.buzzerNameConsole(size: 26)),
          const SizedBox(height: BSSpace.s6),
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const Padding(
              padding: EdgeInsets.symmetric(vertical: BSSpace.s3),
              child: SizedBox(height: 1, child: ColoredBox(color: BSColors.divider)),
            ),
            _BuzzerRow(index: i, game: game),
          ],
        ],
      ),
    );
  }
}

class _BuzzerRow extends StatelessWidget {
  const _BuzzerRow({required this.index, required this.game});
  final int index;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final color = kBuzzerColors[index];
    final present = game.present[index];
    final sound = game.buzzerSound[index];

    return Opacity(
      opacity: present ? 1 : 0.55,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 18, height: 18, color: color.fill),
          const SizedBox(width: BSSpace.s2),
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(color.name, style: BSType.buzzerNameConsole(size: 21)),
                Text(_kWiring[index], style: BSType.body(size: 15, color: BSColors.neutral600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: present ? BSColors.accent100 : BSColors.neutral100),
            child: Text(
              present ? 'Présent' : 'Absent',
              style: BSType.body(size: 13, color: present ? BSColors.accent800 : BSColors.neutral800),
            ),
          ),
          const SizedBox(width: BSSpace.s4),
          Text(
            sound == null
                ? 'Aucun son assigné'
                : present
                    ? 'Son $sound'
                    : 'Son $sound (devient un leurre)',
            style: BSType.body(size: 15, color: BSColors.neutral700),
          ),
        ],
      ),
    );
  }
}
