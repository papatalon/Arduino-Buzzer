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
    this.displayGameMode,
    this.phase,
    this.lastBuzz,
    this.questionCategory,
    this.questionText,
    this.answerText,
    this.questionsAsked = 0,
    this.qcountValue,
    this.teamNames = const ['', '', '', ''],
    this.gameScores = const [0, 0, 0, 0],
    this.gameRound,
    this.gameTotalRounds,
    this.gameWinner,
    this.gameTie = false,
    this.gameFinished = false,
    this.simonLevel,
    this.simonEntered,
    this.simonLength,
    this.reflexWinner,
    this.reflexMs,
    this.reflexBestMs,
    this.reflexRecordMs,
    this.reflexNewRecord = false,
    this.reflexFalseStarts = const [],
    this.blindTargetS,
    this.blindWinner,
    this.blindTimes = const [0, 0, 0, 0],
    this.duelPlayerA,
    this.duelPlayerB,
    this.duelWinner,
    this.duelMs,
    this.duelFalseStarter,
    this.soundLearning,
    this.soundLastOwner,
    this.soundLastClaimed = false,
    this.recallIndex,
    this.logoPath,
  });

  static const empty = PopoutSnapshot(
    scores: [0, 0, 0, 0],
    present: [true, true, true, true],
    flowState: QuestionFlowState.none,
  );

  final List<int> scores;
  final List<bool> present;
  // [gameMode] sert à la logique (y a-t-il un chrono ?) et reste donc
  // toujours renseigné ; [displayGameMode] est ce qu'on montre au public,
  // vide tant qu'aucun jeu n'a été choisi (voir GameState).
  final int? gameMode;
  final int? displayGameMode;
  // Phase courante : dit si une partie tourne vraiment (isGameRunning).
  final int? phase;
  final int? lastBuzz;
  final QuestionFlowState flowState;
  final String? questionCategory;
  final String? questionText;
  final String? answerText;
  final int questionsAsked;
  final int? qcountValue;

  // Noms d'équipe : la fenêtre du pop-out ne partage pas la mémoire de la
  // fenêtre principale, ils doivent donc voyager dans l'instantané. Une
  // entrée vide veut dire « utiliser la couleur ».
  final List<String> teamNames;

  // Jeux non-quiz : scores propres au jeu, progression des manches, et
  // résultat final. Distincts de [scores], qui reste celui du quiz (voir
  // GameLayout dans protocol.dart).
  final List<int> gameScores;
  final int? gameRound;
  final int? gameTotalRounds;
  final int? gameWinner;
  final bool gameTie;
  final bool gameFinished;

  // Simon : aucun score, seulement le niveau atteint.
  final int? simonLevel;
  final int? simonEntered;
  final int? simonLength;

  // Details propres a chaque jeu non-quiz : ce que son ecran public montre
  // et que les autres n'ont pas (temps de reaction, cible, duellistes...).
  final int? reflexWinner;
  final int? reflexMs;
  final int? reflexBestMs;
  final int? reflexRecordMs;
  final bool reflexNewRecord;
  final List<int> reflexFalseStarts;
  final int? blindTargetS;
  final int? blindWinner;
  final List<int> blindTimes;
  final int? duelPlayerA;
  final int? duelPlayerB;
  final int? duelWinner;
  final int? duelMs;
  final int? duelFalseStarter;
  final int? soundLearning;
  final int? soundLastOwner;
  final bool soundLastClaimed;

  // Rappel des sons avant le depart : buzzer dont le son passe en ce moment.
  // Null quand aucun rappel n'est en cours. Pilote par l'app (SoundEngine),
  // pas par le Mega.
  final int? recallIndex;

  // Chemin du logo de la soirée sur le disque (les deux fenêtres tournent
  // sur la même machine), null si l'opérateur n'en a pas choisi.
  final String? logoPath;

  // Nom à afficher pour un buzzer, avec repli sur la couleur.
  String teamName(int index) {
    if (index < 0 || index >= kBuzzerColors.length) return '';
    final custom = index < teamNames.length ? teamNames[index] : '';
    return custom.isNotEmpty ? custom : kBuzzerColors[index].name;
  }

  // teamNames est obligatoire à dessein : un appel qui l'oubliait produisait
  // un écran public muet sur les noms, sans erreur ni avertissement. Le
  // compilateur attrape désormais le cas.
  factory PopoutSnapshot.fromGameState(
    GameState game, {
    required List<String> teamNames,
    required String? logoPath,
    required int? recallIndex,
  }) {
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
      displayGameMode: game.displayGameMode,
      phase: game.phase,
      lastBuzz: game.lastBuzz,
      flowState: game.questionFlowState,
      questionCategory: showQuestion ? game.questionCategory : null,
      questionText: showQuestion ? game.questionText : null,
      answerText: game.answerRevealed ? game.answerText : null,
      questionsAsked: game.questionsAsked,
      qcountValue: game.qcountValue,
      teamNames: teamNames,
      gameScores: game.gameScores,
      gameRound: game.gameRound,
      gameTotalRounds: game.gameTotalRounds,
      gameWinner: game.gameWinner,
      gameTie: game.gameTie,
      gameFinished: game.gameFinished,
      simonLevel: game.simonLevel,
      simonEntered: game.simonEntered,
      simonLength: game.simonLength,
      reflexWinner: game.reflexWinner,
      reflexMs: game.reflexMs,
      reflexBestMs: game.reflexBestMs,
      reflexRecordMs: game.reflexRecordMs,
      reflexNewRecord: game.reflexNewRecord,
      reflexFalseStarts: game.reflexFalseStarts.toList(),
      blindTargetS: game.blindTargetS,
      blindWinner: game.blindWinner,
      blindTimes: game.blindTimes,
      duelPlayerA: game.duelPlayerA,
      duelPlayerB: game.duelPlayerB,
      duelWinner: game.duelWinner,
      duelMs: game.duelMs,
      duelFalseStarter: game.duelFalseStarter,
      soundLearning: game.soundLearning,
      soundLastOwner: game.soundLastOwner,
      soundLastClaimed: game.soundLastClaimed,
      recallIndex: recallIndex,
      logoPath: logoPath,
    );
  }

  factory PopoutSnapshot.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return PopoutSnapshot(
      scores: (json['scores'] as List).cast<int>(),
      present: (json['present'] as List).cast<bool>(),
      gameMode: json['gameMode'] as int?,
      displayGameMode: json['displayGameMode'] as int?,
      phase: json['phase'] as int?,
      lastBuzz: json['lastBuzz'] as int?,
      flowState: QuestionFlowState.values.byName(json['flowState'] as String? ?? 'none'),
      questionCategory: json['questionCategory'] as String?,
      questionText: json['questionText'] as String?,
      answerText: json['answerText'] as String?,
      questionsAsked: json['questionsAsked'] as int? ?? 0,
      qcountValue: json['qcountValue'] as int?,
      teamNames: (json['teamNames'] as List?)?.cast<String>() ?? const ['', '', '', ''],
      gameScores: (json['gameScores'] as List?)?.cast<int>() ?? const [0, 0, 0, 0],
      gameRound: json['gameRound'] as int?,
      gameTotalRounds: json['gameTotalRounds'] as int?,
      gameWinner: json['gameWinner'] as int?,
      gameTie: json['gameTie'] as bool? ?? false,
      gameFinished: json['gameFinished'] as bool? ?? false,
      simonLevel: json['simonLevel'] as int?,
      simonEntered: json['simonEntered'] as int?,
      simonLength: json['simonLength'] as int?,
      reflexWinner: json['reflexWinner'] as int?,
      reflexMs: json['reflexMs'] as int?,
      reflexBestMs: json['reflexBestMs'] as int?,
      reflexRecordMs: json['reflexRecordMs'] as int?,
      reflexNewRecord: json['reflexNewRecord'] as bool? ?? false,
      reflexFalseStarts: (json['reflexFalseStarts'] as List?)?.cast<int>() ?? const [],
      blindTargetS: json['blindTargetS'] as int?,
      blindWinner: json['blindWinner'] as int?,
      blindTimes: (json['blindTimes'] as List?)?.cast<int>() ?? const [0, 0, 0, 0],
      duelPlayerA: json['duelPlayerA'] as int?,
      duelPlayerB: json['duelPlayerB'] as int?,
      duelWinner: json['duelWinner'] as int?,
      duelMs: json['duelMs'] as int?,
      duelFalseStarter: json['duelFalseStarter'] as int?,
      soundLearning: json['soundLearning'] as int?,
      soundLastOwner: json['soundLastOwner'] as int?,
      soundLastClaimed: json['soundLastClaimed'] as bool? ?? false,
      recallIndex: json['recallIndex'] as int?,
      logoPath: json['logoPath'] as String?,
    );
  }

  String encode() => jsonEncode({
        'scores': scores,
        'present': present,
        'gameMode': gameMode,
        'displayGameMode': displayGameMode,
        'phase': phase,
        'lastBuzz': lastBuzz,
        'flowState': flowState.name,
        'questionCategory': questionCategory,
        'questionText': questionText,
        'answerText': answerText,
        'questionsAsked': questionsAsked,
        'qcountValue': qcountValue,
        'teamNames': teamNames,
        'gameScores': gameScores,
        'gameRound': gameRound,
        'gameTotalRounds': gameTotalRounds,
        'gameWinner': gameWinner,
        'gameTie': gameTie,
        'gameFinished': gameFinished,
        'simonLevel': simonLevel,
        'simonEntered': simonEntered,
        'simonLength': simonLength,
        'reflexWinner': reflexWinner,
        'reflexMs': reflexMs,
        'reflexBestMs': reflexBestMs,
        'reflexRecordMs': reflexRecordMs,
        'reflexNewRecord': reflexNewRecord,
        'reflexFalseStarts': reflexFalseStarts,
        'blindTargetS': blindTargetS,
        'blindWinner': blindWinner,
        'blindTimes': blindTimes,
        'duelPlayerA': duelPlayerA,
        'duelPlayerB': duelPlayerB,
        'duelWinner': duelWinner,
        'duelMs': duelMs,
        'duelFalseStarter': duelFalseStarter,
        'soundLearning': soundLearning,
        'soundLastOwner': soundLastOwner,
        'soundLastClaimed': soundLastClaimed,
        'recallIndex': recallIndex,
        'logoPath': logoPath,
      });
}
