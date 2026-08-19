import 'package:flutter/material.dart';

import '../ble_link_service.dart';
import '../protocol.dart';
import 'tokens.dart';

// Sous-écrans de réglage après un choix de jeu (durée du chrono, nombre de
// manches, nombre de sons + leurres, catégories/nombre de questions) — voir
// isGameSetupPhase() dans protocol.dart. Contrairement au choix du jeu
// (GameChoiceScreen), la plupart de ces écrans n'ont aucune ambiguïté de
// curseur : une seule valeur ajustée à la fois, entièrement visible via la
// télémétrie (CHRONO_CFG/ROUNDS_CFG/SOUND_CFG/QCOUNT_CFG), donc les boutons
// +/-/confirmer/annuler réutilisent tels quels "KEY|2"/"KEY|8"/"KEY|#"/
// "KEY|*" (mêmes touches que le clavier physique). Exception : les
// catégories (multi-sélection, voir _QuizCatsSetup) envoient une vraie
// commande (SET_CATS|<mask>) plutôt que de rejouer des touches.
class GameSetupView extends StatelessWidget {
  const GameSetupView({super.key, required this.game, required this.ble});

  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final phase = game.phase;
    final Widget body;
    if (phase == kPhaseNames.indexOf('CHRONO')) {
      body = _ChronoSetup(game: game, ble: ble);
    } else if (phase == kPhaseNames.indexOf('ROUNDS_SETUP')) {
      body = _RoundsSetup(game: game, ble: ble);
    } else if (phase == kPhaseNames.indexOf('SOUND_SETUP')) {
      body = _SoundSetup(game: game, ble: ble);
    } else if (phase == kPhaseNames.indexOf('QUIZ_CATS')) {
      body = _QuizCatsSetup(game: game, ble: ble);
    } else if (phase == kPhaseNames.indexOf('QUIZ_COUNT')) {
      body = _QuizCountSetup(game: game, ble: ble);
    } else {
      body = const SizedBox.shrink();
    }
    return Align(alignment: Alignment.topLeft, child: body);
  }
}

String _formatSeconds(int? seconds) {
  if (seconds == null) return '';
  if (seconds <= 0) return 'Désactivé';
  return '$seconds s';
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: BSType.buzzerNameConsole(size: 26)),
        const SizedBox(height: BSSpace.s2),
        Text(subtitle, style: BSType.body(size: 17, color: BSColors.neutral700)),
        const SizedBox(height: BSSpace.s6),
        Text(value, style: BSType.scoreConsole(color: BSColors.accent700)),
        const SizedBox(height: BSSpace.s6),
        Row(
          children: [
            OutlinedButton(
              onPressed: onDecrement,
              style: OutlinedButton.styleFrom(
                foregroundColor: BSColors.text,
                side: const BorderSide(color: BSColors.divider),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              child: const Text('−'),
            ),
            const SizedBox(width: BSSpace.s3),
            OutlinedButton(
              onPressed: onIncrement,
              style: OutlinedButton.styleFrom(
                foregroundColor: BSColors.text,
                side: const BorderSide(color: BSColors.divider),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              child: const Text('+'),
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            FilledButton(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: BSColors.accent,
                foregroundColor: BSColors.bg,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: const Text('Confirmer'),
            ),
            const SizedBox(width: BSSpace.s3),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChronoSetup extends StatelessWidget {
  const _ChronoSetup({required this.game, required this.ble});
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final isFirst = game.setupChronoStep == 0;
    return _SetupCard(
      title: gameModeName(game.gameMode),
      subtitle: isFirst ? 'Délai pour la première réponse' : 'Délai pour les réponses suivantes',
      value: _formatSeconds(game.setupChronoSeconds),
      onIncrement: () => ble.sendKey('2'),
      onDecrement: () => ble.sendKey('8'),
      onConfirm: () => ble.sendKey('#'),
      onCancel: () => ble.sendKey('*'),
    );
  }
}

class _RoundsSetup extends StatelessWidget {
  const _RoundsSetup({required this.game, required this.ble});
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    return _SetupCard(
      title: gameModeName(game.gameMode),
      subtitle: 'Nombre de manches',
      value: '${game.setupRoundsCount ?? ''}',
      onIncrement: () => ble.sendKey('2'),
      onDecrement: () => ble.sendKey('8'),
      onConfirm: () => ble.sendKey('#'),
      onCancel: () => ble.sendKey('*'),
    );
  }
}

class _SoundSetup extends StatelessWidget {
  const _SoundSetup({required this.game, required this.ble});
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final isCount = game.setupSoundStep == 0;
    if (isCount) {
      return _SetupCard(
        title: gameModeName(game.gameMode),
        subtitle: 'Nombre de sons',
        value: '${game.setupSoundValue ?? ''}',
        onIncrement: () => ble.sendKey('2'),
        onDecrement: () => ble.sendKey('8'),
        onConfirm: () => ble.sendKey('#'),
        onCancel: () => ble.sendKey('*'),
      );
    }
    // Étape "leurres" : un booléen, pas un compteur — un seul bouton pour
    // basculer (2 et 8 font strictement la même chose côté firmware).
    final decoysOn = game.setupSoundValue == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(gameModeName(game.gameMode), style: BSType.buzzerNameConsole(size: 26)),
        const SizedBox(height: BSSpace.s2),
        Text('Sons leurres', style: BSType.body(size: 17, color: BSColors.neutral700)),
        const SizedBox(height: BSSpace.s6),
        Text(decoysOn ? 'Oui' : 'Non', style: BSType.scoreConsole(color: BSColors.accent700)),
        const SizedBox(height: BSSpace.s6),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => ble.sendKey('2'),
              style: OutlinedButton.styleFrom(
                foregroundColor: BSColors.text,
                side: const BorderSide(color: BSColors.divider),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: const Text('Changer'),
            ),
            const SizedBox(width: BSSpace.s3),
            FilledButton(
              onPressed: () => ble.sendKey('#'),
              style: FilledButton.styleFrom(
                backgroundColor: BSColors.accent,
                foregroundColor: BSColors.bg,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: const Text('Confirmer'),
            ),
            const SizedBox(width: BSSpace.s3),
            TextButton(
              onPressed: () => ble.sendKey('*'),
              style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuizCountSetup extends StatelessWidget {
  const _QuizCountSetup({required this.game, required this.ble});
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final value = game.qcountValue;
    return _SetupCard(
      title: 'Nombre de questions',
      subtitle: gameModeName(game.gameMode),
      value: value == null ? '' : (value == 0 ? 'Ouvert' : '$value'),
      onIncrement: () => ble.sendKey('2'),
      onDecrement: () => ble.sendKey('8'),
      onConfirm: () => ble.sendKey('#'),
      onCancel: () => ble.sendKey('*'),
    );
  }
}

// Choix des catégories de questions : seul écran de ce fichier avec un état
// local (Set<int> _selected) — l'opérateur coche/décoche librement sans
// rien envoyer, puis "Confirmer" transmet le masque final en une seule
// commande (SET_CATS|<mask>, voir Configuration::confirmCategories côté
// Mega). Initialisé une fois depuis la télémétrie (game.qcatMask) : pas
// resynchronisé ensuite pour ne pas écraser une sélection en cours.
class _QuizCatsSetup extends StatefulWidget {
  const _QuizCatsSetup({required this.game, required this.ble});
  final GameState game;
  final BleLinkService ble;

  @override
  State<_QuizCatsSetup> createState() => _QuizCatsSetupState();
}

class _QuizCatsSetupState extends State<_QuizCatsSetup> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    final mask = widget.game.qcatMask ?? ((1 << kCategoryNames.length) - 1);
    _selected = {for (var i = 0; i < kCategoryNames.length; i++) if (mask & (1 << i) != 0) i};
  }

  int get _mask => _selected.fold(0, (m, i) => m | (1 << i));

  @override
  Widget build(BuildContext context) {
    final allSelected = _selected.length == kCategoryNames.length;
    final noneSelected = _selected.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Catégories de questions', style: BSType.buzzerNameConsole(size: 26)),
        const SizedBox(height: BSSpace.s4),
        _CatRow(
          label: 'Toutes',
          checked: allSelected,
          onTap: () => setState(() => _selected = {for (var i = 0; i < kCategoryNames.length; i++) i}),
        ),
        _CatRow(
          label: 'Aucune (questionnaire perso)',
          checked: noneSelected,
          onTap: () => setState(() => _selected = {}),
        ),
        const SizedBox(height: BSSpace.s2),
        for (var i = 0; i < kCategoryNames.length; i++)
          _CatRow(
            label: kCategoryNames[i],
            checked: _selected.contains(i),
            onTap: () => setState(() {
              if (!_selected.remove(i)) _selected.add(i);
            }),
          ),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            FilledButton(
              onPressed: () => widget.ble.setCategories(_mask),
              style: FilledButton.styleFrom(
                backgroundColor: BSColors.accent,
                foregroundColor: BSColors.bg,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: const Text('Confirmer'),
            ),
            const SizedBox(width: BSSpace.s3),
            TextButton(
              onPressed: () => widget.ble.sendKey('*'),
              style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CatRow extends StatelessWidget {
  const _CatRow({required this.label, required this.checked, required this.onTap});
  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: checked ? BSColors.accent700 : BSColors.neutral600,
              ),
              const SizedBox(width: BSSpace.s2),
              Text(label, style: BSType.body(size: 16, color: BSColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}
