import 'package:flutter/material.dart';

import '../ble_link_service.dart';
import '../protocol.dart';
import '../questionnaires/active_questionnaire.dart';
import 'tokens.dart';

// Sous-écrans de réglage après un choix de jeu (durée du chrono, nombre de
// manches, nombre de sons + leurres) — voir
// isGameSetupPhase() dans protocol.dart. Contrairement au choix du jeu
// (GameChoiceScreen), la plupart de ces écrans n'ont aucune ambiguïté de
// curseur : une seule valeur ajustée à la fois, entièrement visible via la
// télémétrie (CHRONO_CFG/ROUNDS_CFG/SOUND_CFG), donc les boutons
// +/-/confirmer/annuler réutilisent tels quels "KEY|2"/"KEY|8"/"KEY|#"/
// "KEY|*" (mêmes touches que le clavier physique).
//
// CES TROIS ÉCRANS SONT UN RESTE, et ils sont à reprendre. Ce sont encore
// des miroirs de la machine à états du firmware : l'application y rejoue des
// touches au lieu de posséder le réglage. Le même travail que celui fait
// pour les catégories et le nombre de questions reste à faire ici, pour que
// la durée du chrono, le nombre de manches et le nombre de sons appartiennent
// à l'application et lui soient dits en une commande.
class GameSetupView extends StatelessWidget {
  const GameSetupView(
      {super.key, required this.game, required this.ble, required this.actif});

  final GameState game;
  final BleLinkService ble;
  final ActiveQuestionnaire actif;

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
    // Plus de QUIZ_CATS ni de QUIZ_COUNT : ces écrans n'existent que pour le
    // clavier physique du buzzer. En mode application, le questionnaire est
    // choisi dans l'app et le départ se demande en une commande
    // (BleLinkService.startGame), sans faire naviguer le firmware dans ses
    // menus.
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
