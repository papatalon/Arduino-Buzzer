import 'package:flutter/material.dart';

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
class QuestionFlowView extends StatelessWidget {
  const QuestionFlowView({super.key, required this.game});

  final GameState game;

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
          QuestionFlowState.arming => const _ArmingBlock(),
          QuestionFlowState.buzzed => _BuzzedBlock(game: game),
          QuestionFlowState.scored => _ScoredBlock(game: game),
          QuestionFlowState.revealed => const _RevealedBlock(),
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

class _ArmingBlock extends StatelessWidget {
  const _ArmingBlock();

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
          'Lis la question à voix haute, puis donne le top.',
          style: BSType.body(size: 15, color: BSColors.neutral600),
        ),
        const SizedBox(height: BSSpace.s4),
        Text('TOP NON DONNÉ', style: BSType.datelineRail(color: BSColors.neutral600)),
      ],
    );
  }
}

class _BuzzedBlock extends StatelessWidget {
  const _BuzzedBlock({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final idx = game.lastBuzz;
    if (idx == null || idx < 0 || idx >= kBuzzerColors.length) return const SizedBox.shrink();
    final color = kBuzzerColors[idx];
    return Row(
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
    );
  }
}

class _ScoredBlock extends StatelessWidget {
  const _ScoredBlock({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final idx = game.lastBuzz;
    if (idx == null || idx < 0 || idx >= kBuzzerColors.length) return const SizedBox.shrink();
    final color = kBuzzerColors[idx];
    return Row(
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
    );
  }
}

class _RevealedBlock extends StatelessWidget {
  const _RevealedBlock();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const PhosphorDuotone(PhosphorGlyphs.xCircle, size: 20, color: BSColors.neutral600),
        const SizedBox(width: BSSpace.s2),
        Text("Personne n'a trouvé", style: BSType.body(size: 17, color: BSColors.neutral700)),
      ],
    );
  }
}
