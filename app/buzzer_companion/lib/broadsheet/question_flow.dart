import 'package:flutter/material.dart';

import '../ble_link_service.dart';
import '../protocol.dart';
import 'phosphor_duotone.dart';
import 'pulse.dart';
import 'tokens.dart';

// Colonne centrale de la console pendant une question (design_handoff_
// buzzer_console/README.md, "Le flux d'une question (Chrono pénalité)").
// Les quatre états gérés avec la télémétrie actuelle : 3b (armée) → 1a
// (buzz) → 3d (point marqué) → 3c (révélation). La question ne bouge pas
// entre ces états — seul le bloc sous elle change de contenu — et la
// réponse reste visible en tout temps sur la console (contrat de
// confidentialité : seul le pop-out doit attendre une révélation).
//
// Les boutons envoient "KEY|<touche>" au firmware (BleLink::pollKey côté
// Mega) : chaque action rejoue exactement la touche physique correspondante
// dans la même machine à états, vérifiée dans Buzzer.cpp avant d'écrire ce
// fichier — voir la touche affichée à droite de chaque bouton.
class QuestionFlowView extends StatelessWidget {
  const QuestionFlowView({super.key, required this.game, required this.ble});

  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final state = game.questionFlowState;
    final revealed = state == QuestionFlowState.revealed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if ((game.questionCategory ?? '').isNotEmpty)
          Text(game.questionCategory!.toUpperCase(), style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        Text(
          game.questionText ?? '',
          style: revealed
              ? BSType.body(size: 44, color: BSColors.neutral700).copyWith(fontWeight: FontWeight.w600, height: 1.1)
              : BSType.questionConsole(),
        ),
        const SizedBox(height: BSSpace.s3),
        _AnswerBlock(state: state, answer: game.answerText ?? ''),
        const SizedBox(height: BSSpace.s6),
        switch (state) {
          QuestionFlowState.arming => _ArmingBlock(ble: ble),
          QuestionFlowState.buzzed => _BuzzedBlock(game: game, ble: ble),
          QuestionFlowState.scored => _ScoredBlock(game: game, ble: ble),
          QuestionFlowState.revealed => _RevealedBlock(ble: ble),
          QuestionFlowState.none => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.state, required this.answer});
  final QuestionFlowState state;
  final String answer;

  @override
  Widget build(BuildContext context) {
    if (state == QuestionFlowState.revealed) {
      return Container(
        padding: const EdgeInsets.all(BSSpace.s3),
        decoration: const BoxDecoration(
          color: BSColors.accent2_100,
          border: Border(left: BorderSide(color: BSColors.accent2, width: 5)),
        ),
        child: Text(answer, style: BSType.answerConsole(color: BSColors.accent2_800)),
      );
    }
    return Text(answer, style: BSType.answerConsole());
  }
}

// --- Boutons partagés, alignés sur le design system (btn-primary/
// btn-secondary/ghost) --------------------------------------------------

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.shortcut, required this.onPressed});
  final String label;
  final String shortcut;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: BSColors.accent,
        foregroundColor: BSColors.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: _ButtonLabel(label: label, shortcut: shortcut, color: BSColors.bg),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.shortcut, required this.onPressed});
  final String label;
  final String shortcut;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: BSColors.text,
        side: const BorderSide(color: BSColors.divider),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: _ButtonLabel(label: label, shortcut: shortcut, color: BSColors.text),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.shortcut, required this.onPressed});
  final String label;
  final String shortcut;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
      child: _ButtonLabel(label: label, shortcut: shortcut, color: BSColors.accent700),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.label, required this.shortcut, required this.color});
  final String label;
  final String shortcut;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: BSType.body(size: 15, color: color).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Opacity(
          opacity: 0.6,
          child: Text(shortcut, style: BSType.body(size: 13, color: color)),
        ),
      ],
    );
  }
}

// --- Blocs par état ------------------------------------------------------

class _ArmingBlock extends StatelessWidget {
  const _ArmingBlock({required this.ble});
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: BSSpace.s2),
              Pulse(
                duration: const Duration(seconds: 2),
                delay: Duration(milliseconds: i * 250),
                child: Container(width: 26, height: 52, color: BSColors.neutral300),
              ),
            ],
          ],
        ),
        const SizedBox(height: BSSpace.s3),
        Text("Personne n'a buzzé", style: BSType.body(size: 17, color: BSColors.neutral700)),
        const SizedBox(height: BSSpace.s1),
        Text(
          'Lis la question à voix haute, puis lance le chrono.',
          style: BSType.body(size: 15, color: BSColors.neutral600),
        ),
        const SizedBox(height: BSSpace.s4),
        Text('CHRONO NON LANCÉ', style: BSType.datelineRail(color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            _PrimaryButton(label: 'Lancer le chrono', shortcut: 'D', onPressed: () => ble.sendKey('D')),
            const SizedBox(width: BSSpace.s3),
            _SecondaryButton(label: 'Révéler la réponse', shortcut: '0', onPressed: () => ble.sendKey('0')),
          ],
        ),
        const SizedBox(height: BSSpace.s2),
        Row(
          children: [
            _GhostButton(label: 'Corriger', shortcut: 'B', onPressed: () => ble.sendKey('B')),
            const SizedBox(width: BSSpace.s3),
            _GhostButton(label: 'Terminer la partie', shortcut: 'C', onPressed: () => ble.sendKey('C')),
          ],
        ),
      ],
    );
  }
}

class _BuzzedBlock extends StatelessWidget {
  const _BuzzedBlock({required this.game, required this.ble});
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final idx = game.lastBuzz;
    if (idx == null || idx < 0 || idx >= kBuzzerColors.length) return const SizedBox.shrink();
    final color = kBuzzerColors[idx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Pulse(child: Container(width: 52, height: 52, color: color.fill)),
            const SizedBox(width: BSSpace.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${color.name} a buzzé', style: BSType.buzzerNameConsole(size: 38)),
                Text(
                  'Chrono arrêté · les autres buzzers sont neutralisés',
                  style: BSType.body(size: 15, color: BSColors.neutral600),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            _PrimaryButton(label: 'Bonne réponse', shortcut: 'A', onPressed: () => ble.sendKey('A')),
            const SizedBox(width: BSSpace.s3),
            _SecondaryButton(label: 'Mauvaise réponse', shortcut: 'D', onPressed: () => ble.sendKey('D')),
          ],
        ),
      ],
    );
  }
}

class _ScoredBlock extends StatelessWidget {
  const _ScoredBlock({required this.game, required this.ble});
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final idx = game.lastBuzz;
    if (idx == null || idx < 0 || idx >= kBuzzerColors.length) return const SizedBox.shrink();
    final color = kBuzzerColors[idx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 80, height: 80, color: color.fill),
            const SizedBox(width: BSSpace.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${color.name} marque', style: BSType.buzzerNameConsole(size: 56)),
                Text('${game.scores[idx]}', style: BSType.scoreConsole(color: BSColors.accent700)),
              ],
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            _PrimaryButton(label: 'Continuer maintenant', shortcut: '#', onPressed: () => ble.sendKey('#')),
            const SizedBox(width: BSSpace.s3),
            _GhostButton(label: 'Corriger', shortcut: 'B', onPressed: () => ble.sendKey('B')),
          ],
        ),
      ],
    );
  }
}

class _RevealedBlock extends StatelessWidget {
  const _RevealedBlock({required this.ble});
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const PhosphorDuotone(PhosphorGlyphs.xCircle, size: 20, color: BSColors.neutral600),
            const SizedBox(width: BSSpace.s2),
            Text("Personne n'a trouvé", style: BSType.body(size: 17, color: BSColors.neutral700)),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        _PrimaryButton(label: 'Continuer', shortcut: '#', onPressed: () => ble.sendKey('#')),
      ],
    );
  }
}
