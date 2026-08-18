import 'dart:convert';

import '../protocol.dart';

// Instantané de l'état à synchroniser vers la fenêtre de l'écran public —
// c'est aussi un contrat de confidentialité : seuls les champs présents ici
// PEUVENT atteindre le pop-out (design_handoff_buzzer_console/README.md,
// tableau "Règles de confidentialité"). [answerText] est gardé à null tant
// que [GameState.answerRevealed] est faux, dès la construction — la donnée
// sensible n'est jamais sérialisée, pas seulement cachée côté UI.
class PopoutSnapshot {
  const PopoutSnapshot({
    required this.scores,
    required this.present,
    required this.flowState,
    this.gameMode,
    this.lastBuzz,
    this.questionCategory,
    this.questionText,
    this.answerText,
  });

  static const empty = PopoutSnapshot(
    scores: [0, 0, 0, 0],
    present: [true, true, true, true],
    flowState: QuestionFlowState.none,
  );

  final List<int> scores;
  final List<bool> present;
  final int? gameMode;
  final int? lastBuzz;
  final QuestionFlowState flowState;
  final String? questionCategory;
  final String? questionText;
  final String? answerText;

  factory PopoutSnapshot.fromGameState(GameState game) => PopoutSnapshot(
        scores: game.scores,
        present: game.present,
        gameMode: game.gameMode,
        lastBuzz: game.lastBuzz,
        flowState: game.questionFlowState,
        questionCategory: game.questionText != null ? game.questionCategory : null,
        questionText: game.questionText,
        answerText: game.answerRevealed ? game.answerText : null,
      );

  factory PopoutSnapshot.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return PopoutSnapshot(
      scores: (json['scores'] as List).cast<int>(),
      present: (json['present'] as List).cast<bool>(),
      gameMode: json['gameMode'] as int?,
      lastBuzz: json['lastBuzz'] as int?,
      flowState: QuestionFlowState.values.byName(json['flowState'] as String? ?? 'none'),
      questionCategory: json['questionCategory'] as String?,
      questionText: json['questionText'] as String?,
      answerText: json['answerText'] as String?,
    );
  }

  String encode() => jsonEncode({
        'scores': scores,
        'present': present,
        'gameMode': gameMode,
        'lastBuzz': lastBuzz,
        'flowState': flowState.name,
        'questionCategory': questionCategory,
        'questionText': questionText,
        'answerText': answerText,
      });
}
