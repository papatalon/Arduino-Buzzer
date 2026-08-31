import 'package:flutter/material.dart';

import '../../audio/sound_engine.dart';
import '../../audio/sound_library.dart';
import '../../ble_link_service.dart';
import '../../protocol.dart';
import '../../team_names.dart';
import '../tokens.dart';
import 'sound_picker.dart';

// Écran "Buzzers" (design_handoff_buzzer_console/README.md, 1e) : identité,
// présence, et son assigné.
//
// L'assignation son↔buzzer appartient désormais à l'app, pas au Mega : en
// mode « son application » le buzzer ne gère plus que les lumières. Cet
// écran est donc le seul endroit où la changer — l'assistant de
// configuration du LCD n'a plus d'effet sur ce qu'on entend.
class BuzzersScreen extends StatelessWidget {
  const BuzzersScreen({
    super.key,
    required this.game,
    required this.sound,
    required this.ble,
    required this.teams,
  });
  final GameState game;
  final SoundEngine sound;
  final BleLinkService ble;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([sound, ble, teams]),
      builder: (context, _) {
        return SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('Buzzers', style: BSType.buzzerNameConsole(size: 26)),
                    const SizedBox(width: BSSpace.s4),
                    // Même geste dans les deux modes, seul le destinataire
                    // change : la bibliothèque de l'app, ou le DFPlayer via
                    // une commande à distance.
                    OutlinedButton(
                      onPressed: ble.appHandlesSound
                          ? sound.shuffleAssignments
                          : ble.buzzerSoundShuffle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BSColors.text,
                        side: const BorderSide(color: BSColors.divider),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: Text('Mélanger les sons', style: BSType.body(size: 14)),
                    ),
                    // Affiché seulement s'il y a quelque chose à réinitialiser :
                    // un bouton toujours présent inviterait au clic malheureux
                    // alors qu'il n'y a rien à défaire.
                    if (teams.anyCustom) ...[
                      const SizedBox(width: BSSpace.s2),
                      TextButton(
                        onPressed: () => _confirmResetNames(context, teams),
                        style: TextButton.styleFrom(foregroundColor: BSColors.neutral700),
                        child: Text('Réinitialiser les noms', style: BSType.body(size: 14)),
                      ),
                    ],
                  ],
                ),
                if (!ble.appHandlesSound) ...[
                  const SizedBox(height: BSSpace.s2),
                  Text(
                    'Le son sort du buzzer : ces sons viennent de sa carte SD, '
                    'pas de la bibliothèque de l\'application.',
                    style: BSType.body(size: 15, color: BSColors.neutral600),
                  ),
                ],
                const SizedBox(height: BSSpace.s6),
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: BSSpace.s3),
                      child: SizedBox(height: 1, child: ColoredBox(color: BSColors.divider)),
                    ),
                  _BuzzerRow(index: i, game: game, sound: sound, ble: ble, teams: teams),
                ],
                const SizedBox(height: BSSpace.s6),
                Container(height: 1, color: BSColors.divider),
                const SizedBox(height: BSSpace.s4),
                Text('SORTIE DU SON', style: BSType.sectionKicker()),
                const SizedBox(height: BSSpace.s3),
                _OutputControl(ble: ble),
                const SizedBox(height: BSSpace.s3),
                if (ble.appHandlesSound) _VolumeControl(sound: sound),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Confirmation avant d'effacer : perdre quatre noms saisis à la main d'un
// clic malheureux, juste avant une soirée, serait pénible à refaire.
Future<void> _confirmResetNames(BuildContext context, TeamNames teams) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: BSColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text('Réinitialiser les noms ?', style: BSType.buzzerNameConsole(size: 22)),
      content: Text(
        'Les quatre équipes reprendront le nom de leur couleur.',
        style: BSType.body(size: 16, color: BSColors.neutral700),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: BSColors.neutral700),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: BSColors.accent,
            foregroundColor: BSColors.bg,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          child: const Text('Réinitialiser'),
        ),
      ],
    ),
  );
  if (confirmed == true) await teams.clearAll();
}

class _BuzzerRow extends StatelessWidget {
  const _BuzzerRow({
    required this.index,
    required this.game,
    required this.sound,
    required this.ble,
    required this.teams,
  });
  final int index;
  final GameState game;
  final SoundEngine sound;
  final BleLinkService ble;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final color = kBuzzerColors[index];
    final present = game.present[index];
    final appOwnsSound = ble.appHandlesSound;

    // Deux sources d'assignation selon qui joue : la bibliothèque de l'app,
    // ou celle du DFPlayer telle qu'annoncée par le Mega (CFG_SOUND). En
    // afficher une pendant que l'autre sonne serait trompeur.
    final String name;
    if (appOwnsSound) {
      name = sound.library.displayName(SoundFolder.buzzer, sound.assignment[index]);
    } else {
      final megaSound = game.buzzerSound[index];
      name = megaSound == null ? 'Aucun son assigné' : 'Son ${megaSound + 1} de la carte SD';
    }

    return Opacity(
      opacity: present ? 1 : 0.55,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 18, height: 18, color: color.fill),
          const SizedBox(width: BSSpace.s2),
          // Nom d'équipe éditable, avec la couleur en dessous : la couleur
          // reste l'identité physique du buzzer (câblage, LED), le nom
          // n'est qu'une étiquette de présentation.
          SizedBox(
            width: 190,
            child: _TeamNameField(index: index, teams: teams),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: present ? BSColors.accent100 : BSColors.neutral100),
            child: Text(
              present ? 'Présent' : 'Absent',
              style: BSType.body(size: 13, color: present ? BSColors.accent800 : BSColors.neutral800),
            ),
          ),
          const SizedBox(width: BSSpace.s3),
          // Le nom prend la place restante plutôt qu'une largeur fixe :
          // avec trois boutons, une largeur figée faisait déborder la
          // rangée sur les fenêtres étroites. Cliquable en mode app pour
          // ouvrir la grille de tous les sons — plus pratique que de
          // défiler un par un sur une trentaine de fichiers.
          Expanded(
            child: appOwnsSound
                ? MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => showSoundPicker(context, sound, index),
                      child: Text(
                        name.isEmpty ? 'Aucun son' : name,
                        style: BSType.body(size: 15, color: BSColors.accent700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                : Text(
                    name.isEmpty ? 'Aucun son' : name,
                    style: BSType.body(size: 15, color: BSColors.neutral700),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const SizedBox(width: BSSpace.s2),
          // Mêmes gestes dans les deux modes : ce qui change, c'est qui
          // exécute. En mode buzzer, une commande part au Mega et c'est lui
          // qui déplace son assignation et joue l'aperçu — sinon, avec le
          // clavier verrouillé, plus personne ne pourrait reconfigurer.
          TextButton(
            onPressed: () => appOwnsSound
                ? sound.playBuzzer(index)
                : ble.buzzerSoundPreview(index),
            style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
            child: const Text('Écouter'),
          ),
          // Chevrons plutôt que "Précédent"/"Suivant" en toutes lettres :
          // trois boutons texte faisaient déborder la rangée.
          IconButton(
            tooltip: 'Son précédent',
            onPressed: () {
              if (appOwnsSound) {
                sound.cycleAssignment(index, direction: -1);
                sound.playBuzzer(index);   // on entend tout de suite le nouveau
              } else {
                ble.buzzerSoundPrevious(index);
              }
            },
            color: BSColors.accent700,
            icon: const Icon(Icons.chevron_left, size: 22),
          ),
          IconButton(
            tooltip: 'Son suivant',
            onPressed: () {
              if (appOwnsSound) {
                sound.cycleAssignment(index);
                sound.playBuzzer(index);
              } else {
                ble.buzzerSoundNext(index);
              }
            },
            color: BSColors.accent700,
            icon: const Icon(Icons.chevron_right, size: 22),
          ),
        ],
      ),
    );
  }
}

// Choix de la sortie audio. Le repli sur le buzzer existe pour le cas très
// concret d'un poste sans haut-parleur : l'app garde le contrôle du jeu,
// mais c'est le DFPlayer qui sonne, comme avant la bascule.
// Champ de saisie du nom d'équipe. Stateful pour garder son contrôleur :
// un champ reconstruit à chaque notification perdrait la position du
// curseur pendant la frappe.
class _TeamNameField extends StatefulWidget {
  const _TeamNameField({required this.index, required this.teams});
  final int index;
  final TeamNames teams;

  @override
  State<_TeamNameField> createState() => _TeamNameFieldState();
}

class _TeamNameFieldState extends State<_TeamNameField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.teams.rawName(widget.index));
    // Le champ garde son propre contrôleur, donc une modification venue
    // d'ailleurs (bouton « Réinitialiser ») changerait le modèle sans que
    // l'affichage suive. On resynchronise sur notification.
    widget.teams.addListener(_syncFromModel);
  }

  void _syncFromModel() {
    final external = widget.teams.rawName(widget.index);
    // Pendant la frappe, modèle et champ sont déjà identiques : la garde
    // évite de replacer le curseur à chaque caractère saisi.
    if (external == _controller.text) return;
    _controller.text = external;
    _controller.selection = TextSelection.collapsed(offset: external.length);
  }

  @override
  void dispose() {
    widget.teams.removeListener(_syncFromModel);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = kBuzzerColors[widget.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          onChanged: (v) => widget.teams.setName(widget.index, v),
          style: BSType.buzzerNameConsole(size: 21),
          cursorColor: BSColors.accent,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            // Le nom de couleur sert d'invite : tant qu'aucune équipe n'est
            // nommée, c'est ce qui s'affiche partout ailleurs.
            hintText: color.name,
            hintStyle: BSType.buzzerNameConsole(size: 21).copyWith(color: BSColors.neutral500),
            border: const UnderlineInputBorder(borderSide: BorderSide(color: BSColors.divider)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: BSColors.divider)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: BSColors.accent)),
          ),
        ),
        const SizedBox(height: 2),
        Text(color.name, style: BSType.body(size: 13, color: BSColors.neutral600)),
      ],
    );
  }
}

class _OutputControl extends StatelessWidget {
  const _OutputControl({required this.ble});
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _OutputChoice(
          label: 'Haut-parleurs du PC',
          detail: 'Bibliothèque de l\'application',
          selected: ble.appHandlesSound,
          onTap: () => ble.setAppHandlesSound(true),
        ),
        const SizedBox(width: BSSpace.s3),
        _OutputChoice(
          label: 'Haut-parleur du buzzer',
          detail: 'Carte SD du DFPlayer',
          selected: !ble.appHandlesSound,
          onTap: () => ble.setAppHandlesSound(false),
        ),
      ],
    );
  }
}

class _OutputChoice extends StatelessWidget {
  const _OutputChoice({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(BSSpace.s3),
          decoration: BoxDecoration(
            color: selected ? BSColors.accent100 : null,
            border: Border(
              top: BorderSide(color: selected ? BSColors.accent : BSColors.divider, width: 2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: BSType.body(size: 16, color: selected ? BSColors.accent800 : BSColors.text)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(detail, style: BSType.body(size: 13, color: BSColors.neutral600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.sound});
  final SoundEngine sound;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 200,
          child: Text('Volume de l\'application', style: BSType.body(size: 15, color: BSColors.neutral700)),
        ),
        SizedBox(
          width: 260,
          child: Slider(
            value: sound.volume,
            activeColor: BSColors.accent,
            onChanged: sound.setVolume,
          ),
        ),
        Text('${(sound.volume * 100).round()} %', style: BSType.body(size: 15, color: BSColors.neutral700)),
      ],
    );
  }
}
