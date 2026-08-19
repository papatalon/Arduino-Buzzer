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
    this.questionsAsked = 0,
    this.qcountValue,
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
  final int questionsAsked;
  final int? qcountValue;

  factory PopoutSnapshot.fromGameState(GameState game) {
    // La question elle-même n'est pas listée comme sensible dans le tableau
    // de confidentialité du design, mais le client a précisé que sur le
    // pop-out, elle ne doit apparaître qu'une fois le chrono lancé — pas
    // avant, pendant que l'animateur la lit encore à voix haute. Seuls les
    // jeux avec un chrono (Chrono classique/pénalité, Vol) ont cette
    // attente : les autres (Classique, Pénalité...) n'envoient jamais
    // CHRONO_START, donc la question resterait cachée pour toujours sans
    // cette garde.
    final needsChronoGate = usesChrono(game.gameMode);
    final showQuestion = game.questionText != null &&
        !(needsChronoGate && game.questionFlowState == QuestionFlowState.arming && !game.chronoStarted);
    return PopoutSnapshot(
      scores: game.scores,
      present: game.present,
      gameMode: game.gameMode,
      lastBuzz: game.lastBuzz,
      flowState: game.questionFlowState,
      questionCategory: showQuestion ? game.questionCategory : null,
      questionText: showQuestion ? game.questionText : null,
      answerText: game.answerRevealed ? game.answerText : null,
      questionsAsked: game.questionsAsked,
      qcountValue: game.qcountValue,
    );
  }

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
      questionsAsked: json['questionsAsked'] as int? ?? 0,
      qcountValue: json['qcountValue'] as int?,
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
        'questionsAsked': questionsAsked,
        'qcountValue': qcountValue,
      });
}
