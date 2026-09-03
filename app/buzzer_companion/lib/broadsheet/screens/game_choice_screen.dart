import 'package:flutter/material.dart';

import '../../ble_link_service.dart';
import '../../game_rules.dart';
import '../../jeu/moteur_quiz.dart';
import '../../protocol.dart';
import '../tokens.dart';
// LA GRILLE DES ONZE JEUX, posee dans l'ecran « Partie ».
//
// Elle a eu son propre onglet dans la barre laterale, a cote de « Partie ».
// C'etait un flux etrange : on choisissait le jeu d'un cote, et l'autre ecran
// reclamait deja un questionnaire sans savoir s'il y aurait des questions.
// Choisir un jeu, choisir ses questions et lancer sont trois etapes d'une
// seule chose, elles vivent donc au meme endroit, dans cet ordre.
//
// Les regles completes vivent dans lib/game_rules.dart : la carte n'en montre
// que la phrase d'accroche, le detail apparait une fois le jeu retenu, au
// moment ou l'animateur l'explique a la salle.
class GrilleDesJeux extends StatelessWidget {
  const GrilleDesJeux({
    super.key,
    required this.game,
    required this.ble,
    required this.moteur,
    required this.onChoisi,
  });

  final GameState game;
  final BleLinkService ble;
  // Le choix est d'abord celui de l'APPLICATION : c'est elle qui mene la
  // partie. Le buzzer n'est prevenu que lorsqu'il joue seul.
  final MoteurQuiz moteur;
  final VoidCallback onChoisi;

  @override
  Widget build(BuildContext context) {
    // La coche suit le moteur, pas la telemetrie du buzzer.
    return ListenableBuilder(
      listenable: moteur,
      builder: (context, _) => Wrap(
        spacing: BSSpace.s4,
        runSpacing: BSSpace.s4,
        children: [
          for (var i = 0; i < kGameModeNames.length; i++)
            // SIMON INVERSE N'A PAS SA CARTE. Ce n'est pas un autre jeu : les
            // regles, le materiel et le deroulement sont les memes, seul le
            // sens de la repetition change. Deux cartes cote a cote pour ca
            // faisaient choisir avant d'avoir explique, alors que le sens se
            // decide au moment de lancer. Il devient un reglage de la console
            // de Simon, qui repose bien jeuChoisi sur 6.
            if (i != 6)
              _GameCard(
                index: i,
                // La carte de Simon reste allumee dans les deux sens.
                active: i == 5
                    ? (moteur.jeuChoisi == 5 || moteur.jeuChoisi == 6)
                    : moteur.jeuChoisi == i,
                onSelect: () {
                  moteur.choisirJeu(i);
                  // En mode application le buzzer ne garde aucun jeu en
                  // memoire : le lui envoyer le remettrait a mener.
                  if (!isAppControl(game.phase)) ble.selectGame(i);
                  // Choix delibere de l'operateur : a partir d'ici le jeu
                  // actif peut etre annonce partout (voir displayGameMode).
                  game.markGameChosen();
                  onChoisi();
                },
              ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.index, required this.active, required this.onSelect});
  final int index;
  final bool active;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 320,
      padding: const EdgeInsets.only(top: BSSpace.s2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: active ? BSColors.accent2 : BSColors.text, width: 2)),
        color: active ? BSColors.accent2_100 : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(active ? BSSpace.s3 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(kGameModeNames[index], style: BSType.buzzerNameConsole(size: 23)),
                ),
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    color: BSColors.accent2_100,
                    child: Text('Actif', style: BSType.body(size: 12, color: BSColors.accent2_800)),
                  ),
              ],
            ),
            const SizedBox(height: BSSpace.s1),
            Text(kGameRules[index].pitch, style: BSType.body(size: 15, color: BSColors.neutral700)),
            if (kGameRules[index].setup.isNotEmpty) ...[
              const SizedBox(height: BSSpace.s1),
              Text(kGameRules[index].setup, style: BSType.body(size: 13, color: BSColors.neutral600)),
            ],
          ],
        ),
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onSelect, child: card),
    );
  }
}
