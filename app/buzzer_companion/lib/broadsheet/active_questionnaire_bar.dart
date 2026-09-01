import 'package:flutter/material.dart';

import '../questionnaires/active_questionnaire.dart';
import 'tokens.dart';

// Le bandeau du questionnaire en jeu, au-dessus du flux de question.
//
// Il répond à trois questions que l'animateur se pose pendant la partie : de
// quel questionnaire viennent les questions, où en est-on, et comment
// rattraper si ça décale. Le troisième point n'est pas du luxe :
// l'avancement est déduit des transitions de phase du buzzer (voir
// ActiveQuestionnaire), et une déduction peut se tromper. Deux flèches
// valent mieux qu'une soirée finie décalée d'un cran.
class ActiveQuestionnaireBar extends StatelessWidget {
  const ActiveQuestionnaireBar({super.key, required this.actif});

  final ActiveQuestionnaire actif;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: actif,
      builder: (context, _) {
        if (!actif.active) return const SizedBox.shrink();
        final epuise = actif.exhausted;
        return Container(
          margin: const EdgeInsets.only(bottom: BSSpace.s4),
          padding: const EdgeInsets.only(top: BSSpace.s2, bottom: BSSpace.s2),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: BSColors.accent, width: 3),
              bottom: BorderSide(color: BSColors.divider),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('QUESTIONNAIRE DE L\'APPLICATION', style: BSType.sectionKicker()),
                    const SizedBox(height: 2),
                    Text(
                      actif.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BSType.buzzerNameConsole(size: 21),
                    ),
                    Text(
                      epuise
                          ? 'Toutes les questions ont été posées'
                          : '${actif.origine} · question ${actif.index + 1} sur ${actif.total}',
                      style: BSType.body(
                        size: 14,
                        color: epuise ? BSColors.accent2_800 : BSColors.neutral600,
                      ),
                    ),
                  ],
                ),
              ),
              // Rattrapage manuel. Désactivé aux extrémités plutôt que caché :
              // une flèche qui disparaît déplace les autres boutons au moment
              // où on veut cliquer.
              IconButton(
                tooltip: 'Question précédente',
                onPressed: actif.index > 0 ? actif.previous : null,
                color: BSColors.neutral700,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Question suivante',
                onPressed: actif.index < actif.total ? actif.next : null,
                color: BSColors.neutral700,
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: actif.clear,
                style: TextButton.styleFrom(foregroundColor: BSColors.neutral600),
                child: const Text('Retirer'),
              ),
            ],
          ),
        );
      },
    );
  }
}
