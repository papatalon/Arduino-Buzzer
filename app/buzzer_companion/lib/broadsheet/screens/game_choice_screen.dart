import 'package:flutter/material.dart';

import '../../ble_link_service.dart';
import '../../protocol.dart';
import '../tokens.dart';

// Écran "Choix du jeu" (design_handoff_buzzer_console/README.md, 1f) : les
// 11 modes, celui actif marqué. Seuls les jeux qui s'appliquent en une
// seule confirmation au clavier (Classique, Pénalité, Simon, Simon
// inverse) sont sélectionnables en un clic (commande "SELECT_GAME|<n>",
// voir Configuration::selectGameIndex côté Mega) — les 7 autres
// enchaînent sur un sous-écran de réglage (durée, manches, sons) qui n'a
// pas encore d'UI côté app, donc ils restent affichés mais inertes pour
// l'instant.
//
// Les phrases de règle sont une description approximative déduite des noms
// et du code existant (Questions.h, Simon.h, Reflex.h, SoundGame.h...) — à
// faire vérifier par le propriétaire du firmware si un libellé est faux.
const _kRules = [
  'Le premier à buzzer répond ; bonne réponse, un point.',
  'Comme Classique, mais une mauvaise réponse retire un point.',
  'Un temps limité est accordé pour buzzer.',
  'Chrono et pénalité combinés.',
  'Un joueur désigné répond en premier ; les autres peuvent lui voler la question.',
  'Les joueurs répètent une séquence de couleurs qui s\'allonge.',
  'Comme Simon, mais la séquence se répète en sens inverse.',
  'Le temps de réaction au signal de départ est le score.',
  'Chaque joueur vise une durée cible sans la voir défiler.',
  'Buzzer sur le mauvais son élimine le joueur.',
  'Deux joueurs s\'affrontent en tête-à-tête.',
];

// Jeux qui s'appliquent en une seule confirmation au clavier (pas de
// sous-écran de réglage) — les seuls sélectionnables depuis l'app pour
// l'instant. Index : voir GameMode.h / kGameModeNames.
const _kSimpleGameIndices = {0, 1, 5, 6};

class GameChoiceScreen extends StatelessWidget {
  const GameChoiceScreen({super.key, required this.game, required this.ble});
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Choix du jeu', style: BSType.buzzerNameConsole(size: 26)),
          const SizedBox(height: BSSpace.s6),
          Wrap(
            spacing: BSSpace.s4,
            runSpacing: BSSpace.s4,
            children: [
              for (var i = 0; i < kGameModeNames.length; i++)
                _GameCard(
                  index: i,
                  active: game.gameMode == i,
                  onSelect: _kSimpleGameIndices.contains(i) ? () => ble.selectGame(i) : null,
                ),
            ],
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
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final enabled = onSelect != null;
    final card = Container(
      width: 320,
      padding: const EdgeInsets.only(top: BSSpace.s2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: active ? BSColors.accent2 : BSColors.text, width: 2)),
        color: active ? BSColors.accent2_100 : null,
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
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
              Text(_kRules[index], style: BSType.body(size: 15, color: BSColors.neutral700)),
              if (!enabled) ...[
                const SizedBox(height: BSSpace.s1),
                Text(
                  'Nécessite le clavier pour l\'instant',
                  style: BSType.body(size: 13, color: BSColors.neutral600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!enabled) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onSelect, child: card),
    );
  }
}
