import 'package:flutter/material.dart';

import '../../audio/sound_engine.dart';
import '../../audio/sound_library.dart';
import '../../protocol.dart';
import '../tokens.dart';

// Grille de tous les sons du dossier des buzzers. Faire défiler un par un
// avec les chevrons devient vite pénible sur une trentaine de sons : ici
// l'opérateur voit tout d'un coup, écoute en cliquant, et choisit.
//
// N'existe qu'en mode « son application » : quand c'est le buzzer qui joue,
// l'app ne connaît pas les noms des fichiers de sa carte SD.
//
// L'ouverture est ANNONCÉE au moteur de son, qui la transporte jusqu'à
// l'écran public : la personne qui choisit doit voir la même grille que
// l'animateur, sinon elle choisit à l'aveugle pendant qu'il clique.
Future<void> showSoundPicker(BuildContext context, SoundEngine sound, int buzzerId) async {
  sound.ouvrirGrille(buzzerId);
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => _SoundPickerDialog(sound: sound, buzzerId: buzzerId),
    );
  } finally {
    // Dans un `finally` : la grille se ferme au clavier (Échap) et au clic
    // hors du cadre autant que par le bouton, et l'écran public ne doit
    // rester bloqué dessus dans aucun de ces cas.
    sound.fermerGrille();
  }
}

class _SoundPickerDialog extends StatelessWidget {
  const _SoundPickerDialog({required this.sound, required this.buzzerId});
  final SoundEngine sound;
  final int buzzerId;

  @override
  Widget build(BuildContext context) {
    final color = kBuzzerColors[buzzerId];
    final total = sound.library.count(SoundFolder.buzzer);

    return Dialog(
      backgroundColor: BSColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ListenableBuilder(
        listenable: sound,
        builder: (context, _) {
          return SizedBox(
            width: 860,
            height: 620,
            child: Padding(
              padding: const EdgeInsets.all(BSSpace.s6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 20, height: 20, color: color.fill),
                      const SizedBox(width: BSSpace.s2),
                      Text('Son de ${color.name}', style: BSType.buzzerNameConsole(size: 24)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
                        child: const Text('Fermer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: BSSpace.s1),
                  Text(
                    'Clique un son pour l\'entendre et l\'attribuer. $total sons '
                    'disponibles. L\'écran public montre la même grille.',
                    style: BSType.body(size: 15, color: BSColors.neutral600),
                  ),
                  const SizedBox(height: BSSpace.s4),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 260,
                        mainAxisExtent: 58,
                        crossAxisSpacing: BSSpace.s2,
                        mainAxisSpacing: BSSpace.s2,
                      ),
                      itemCount: total,
                      itemBuilder: (context, i) {
                        // Un son déjà porté par un autre buzzer reste
                        // choisissable, mais on le signale : deux buzzers
                        // au même son rendent la partie confuse.
                        int? takenBy;
                        for (var b = 0; b < 4; b++) {
                          if (b != buzzerId && sound.assignment[b] == i) takenBy = b;
                        }
                        return _SoundTile(
                          label: sound.library.displayName(SoundFolder.buzzer, i),
                          index: i,
                          selected: sound.assignment[buzzerId] == i,
                          takenBy: takenBy,
                          onTap: () {
                            sound.setAssignment(buzzerId, i);
                            sound.previewBuzzerSound(i);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({
    required this.label,
    required this.index,
    required this.selected,
    required this.takenBy,
    required this.onTap,
  });
  final String label;
  final int index;
  final bool selected;
  final int? takenBy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: BSSpace.s2, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? BSColors.accent100 : null,
            border: Border(
              top: BorderSide(color: selected ? BSColors.accent : BSColors.divider, width: 2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                // Pas de repli sur « Son N » ici : nomLisible s'en charge
                // deja pour les fichiers dont il ne reste rien apres
                // nettoyage.
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BSType.body(size: 14, color: selected ? BSColors.accent800 : BSColors.text)
                    .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text('${index + 1}', style: BSType.body(size: 12, color: BSColors.neutral600)),
                  if (takenBy != null) ...[
                    const SizedBox(width: 6),
                    Container(width: 10, height: 10, color: kBuzzerColors[takenBy!].fill),
                    const SizedBox(width: 4),
                    Text(
                      'pris par ${kBuzzerColors[takenBy!].name}',
                      style: BSType.body(size: 12, color: BSColors.neutral600),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
