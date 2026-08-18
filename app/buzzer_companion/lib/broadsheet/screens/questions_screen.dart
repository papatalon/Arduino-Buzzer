import 'package:flutter/material.dart';

import '../tokens.dart';

// Écran "Questions" (design_handoff_buzzer_console/README.md, 1g).
// Contrairement aux 3 autres écrans de configuration, celui-ci ne peut pas
// être construit en miroir honnête de l'état réel : la sélection de
// catégories, l'historique anti-répétition (EEPROM) et les questionnaires
// personnels ne sont télémétrés nulle part côté firmware actuellement.
// Plutôt que d'inventer des chiffres, on l'affiche comme un manque connu.
class QuestionsScreen extends StatelessWidget {
  const QuestionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Questions', style: BSType.buzzerNameConsole(size: 26)),
          const SizedBox(height: BSSpace.s6),
          Text(
            "Pas encore de télémétrie pour cet écran.",
            style: BSType.body(size: 17, color: BSColors.neutral700),
          ),
          const SizedBox(height: BSSpace.s2),
          Text(
            "La sélection de catégories, l'historique anti-répétition (EEPROM) "
            "et les questionnaires personnels ne sont envoyés nulle part par le "
            "firmware pour l'instant. Il faudrait de nouveaux messages avant "
            "de construire cet écran pour de vrai.",
            style: BSType.body(size: 15, color: BSColors.neutral600),
          ),
        ],
      ),
    );
  }
}
