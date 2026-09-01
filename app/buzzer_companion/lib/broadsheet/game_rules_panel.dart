import 'package:flutter/material.dart';

import '../game_rules.dart';
import 'tokens.dart';

// Les règles du jeu choisi, en clair, sur l'écran de l'animateur. Placées
// juste avant « Lancer la partie » parce que c'est exactement le moment où
// il les explique à la salle : le jeu est choisi, la partie n'est pas
// commencée, tout le monde attend.
//
// Ce sont des phrases entières et non des mots-clés : au micro, devant une
// salle, reformuler « chrono court après erreur » demande de réfléchir,
// alors qu'une phrase se lit d'un trait. Voir lib/game_rules.dart.
class GameRulesPanel extends StatelessWidget {
  const GameRulesPanel({super.key, required this.gameMode});

  final int? gameMode;

  @override
  Widget build(BuildContext context) {
    final rules = rulesFor(gameMode);
    if (rules == null) return const SizedBox.shrink();

    return SizedBox(
      width: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('À EXPLIQUER AUX JOUEURS', style: BSType.sectionKicker()),
          const SizedBox(height: BSSpace.s3),
          for (var i = 0; i < rules.howTo.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: BSSpace.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Numérotées : elles se disent dans cet ordre, et un
                  // animateur qui reprend son souffle retrouve sa place.
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${i + 1}',
                      style: BSType.body(size: 19, color: BSColors.accent2)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rules.howTo[i],
                      style: BSType.body(size: 19, color: BSColors.text),
                    ),
                  ),
                ],
              ),
            ),
          if (rules.setup.isNotEmpty) ...[
            const SizedBox(height: BSSpace.s2),
            Row(
              children: [
                Container(width: 4, height: 20, color: BSColors.accent),
                const SizedBox(width: BSSpace.s2),
                // Note à l'opérateur, pas à la salle : ce qu'il faut avoir
                // réglé pour que le jeu démarre.
                Text(rules.setup, style: BSType.body(size: 16, color: BSColors.neutral700)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
