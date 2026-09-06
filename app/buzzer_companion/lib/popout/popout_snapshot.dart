import 'dart:convert';

import '../jeu/moteur_quiz.dart';
import '../jeu/moteur_chrono_aveugle.dart';
import '../jeu/moteur_ne_buzze_pas.dart';
import '../jeu/moteur_reflexe.dart';
import '../jeu/moteur_simon.dart';
import '../protocol.dart';
import '../questionnaires/questionnaire.dart';

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
    this.simonSequence = const [],
    this.simonFautif,
    this.simonAttendu,
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
    this.vueSons = VueDesSons.aucune,
    this.enLice = const [true, true, true, true],
    this.motFinal = '',
    this.motAttention = '',
    this.motTirage = '',
    this.phaseJeu,
    this.brisEgalite = false,
    this.chronoRestant,
    this.chronoTotal = 0,
    this.logoPath,
    this.appMene = false,
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

  // L'APPLICATION MENE : ce qui suit vient du moteur de jeu de l'app, pas de
  // la telemetrie du buzzer. L'ecran public s'en sert pour savoir quand une
  // partie tourne vraiment, puisque la phase du buzzer ne le dit plus (il
  // reste en APP_CONTROL du debut a la fin).
  final bool appMene;

  // Qui peut encore repondre A CETTE QUESTION. Une mauvaise reponse ecarte
  // son auteur jusqu'a la suivante, et la salle doit le voir : sans ca, on
  // regarde quelqu'un attendre sans comprendre qu'il ne joue plus ce tour-ci.
  // Tout le monde en lice hors partie, et pour les jeux non-quiz.
  final List<bool> enLice;

  // La phrase projetee sous le resultat. Tiree une seule fois par le moteur,
  // a la fin de la partie : la retirer ici, a chaque reconstruction de la
  // fenetre, la ferait clignoter devant la salle.
  final String motFinal;

  // En manche libre, la phrase projetee a la place de la question. Vide des
  // qu'un questionnaire fournit un texte.
  final String motAttention;

  // Le decompte en cours, en secondes, ou null si aucun chrono ne tourne.
  // La salle doit le voir aussi grand que l'animateur : c'est elle qui
  // pousse les joueurs a se decider.
  // Ce qui se joue pendant le tirage au sort du mode Vol. L'ecran public
  // reste sur son plan d'attente pendant ce temps : cette phrase y prend la
  // place du message ordinaire, pour dire ce qui est en train de se decider.
  final String motTirage;

  // LA PHASE QUE L'ECRAN DOIT RENDRE, quand elle differe de celle du buzzer.
  //
  // En mode autonome les deux sont la meme chose. En mode application le
  // buzzer reste en APP_CONTROL du debut a la fin de la soiree : c'est le
  // moteur de jeu qui sait ou on en est, et il le dicte ici. Ca permet aux
  // ecrans des jeux (ReflexZone et compagnie) de servir dans les deux modes
  // sans etre reecrits.
  final int? phaseJeu;

  int? get phaseAffichee => phaseJeu ?? phase;

  // Un bris d'egalite se joue EN PLUS des manches prevues : annoncer
  // « manche 3 sur 2 » ou « question 26 sur 25 » n'aurait aucun sens. La
  // progression laisse donc sa place au nom de ce qui se joue.
  final bool brisEgalite;

  // VRAI TANT QUE LA MANCHE EN COURS PEUT ENCORE SE JOUER.
  //
  // C'est le moment ou etre ecarte veut dire quelque chose, et ou la salle
  // doit le voir. Une fois la manche tranchee, tout le monde revient : garder
  // la mention serait faux.
  //
  // Deux formes selon le jeu, parce que « une question ouverte » et « une
  // manche de Reflexe en cours » ne se lisent pas au meme endroit.
  bool get mancheOuverte {
    if (flowState == QuestionFlowState.arming ||
        flowState == QuestionFlowState.buzzed) {
      return true;
    }
    return isPhase(phaseAffichee, 'REFLEX_ARM') ||
        isPhase(phaseAffichee, 'REFLEX_GO');
  }

  final int? chronoRestant;
  final int chronoTotal;

  // Simon : aucun score, seulement le niveau atteint.
  final int? simonLevel;
  final int? simonEntered;
  final int? simonLength;

  // LA SEQUENCE, montree a la salle une fois la partie finie. Pendant la
  // partie elle reste vide : c'est exactement ce que les joueurs doivent
  // retenir de tete, l'afficher serait jouer a leur place.
  final List<int> simonSequence;

  // Qui a rompu la chaine, et la couleur qu'il fallait. Les deux vont
  // ensemble : nommer le fautif seul le designe, nommer aussi ce qui etait
  // attendu raconte la sequence.
  final int? simonFautif;
  final int? simonAttendu;

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

  // TOUT CE QUE LA SALLE VOIT DU CHOIX DES SONS. Voir [VueDesSons].
  final VueDesSons vueSons;

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
  // L'ECRAN PUBLIC QUAND L'APPLICATION MENE.
  //
  // Rien ici ne vient du buzzer : il reste en APP_CONTROL du debut a la fin
  // de la partie et ne tient plus ni score, ni question, ni fin de partie.
  // On remplit donc les memes champs que la telemetrie remplissait, avec les
  // valeurs du moteur, ce qui laisse la fenetre publique telle quelle : elle
  // sait deja les rendre.
  // L'ECRAN PUBLIC PENDANT UN CHRONO AVEUGLE mene par l'application.
  // L'ECRAN PUBLIC PENDANT « NE BUZZE PAS » mene par l'application.
  //
  // Comme pour les autres, rien de nouveau n'est dessine : SoundGameZone
  // existe pour le mode autonome et lit une PHASE A AFFICHER.
  //
  // C'EST LE SON PRECEDENT QUI EST MONTRE, jamais celui en cours. Reveler a
  // qui appartient le son qui joue repondrait a la question avant les
  // joueurs, et c'est toute la question du jeu.
  factory PopoutSnapshot.duNeBuzzePas(
    MoteurNeBuzzePas moteur, {
    required List<String> teamNames,
    required String? logoPath,
  }) {
    final phase = switch (moteur.etape) {
      EtapeNeBuzzePas.ecoute => 'SOUND_LEARN',
      EtapeNeBuzzePas.flux => 'SOUND_PLAY',
      EtapeNeBuzzePas.finie => 'SOUND_OVER',
      EtapeNeBuzzePas.repos => null,
    };
    return PopoutSnapshot(
      appMene: true,
      phaseJeu: phase == null ? null : kPhaseNames.indexOf(phase),
      gameMode: 9,
      displayGameMode: 9,
      scores: const [0, 0, 0, 0],
      gameScores: List<int>.of(moteur.scores),
      present: List<bool>.of(moteur.presents),
      flowState: QuestionFlowState.none,
      gameWinner:
          moteur.etape == EtapeNeBuzzePas.finie ? moteur.vainqueur : null,
      gameTie: moteur.etape == EtapeNeBuzzePas.finie && moteur.egalite,
      gameFinished: moteur.etape == EtapeNeBuzzePas.finie,
      motFinal: moteur.motFinal,
      // -1 veut dire « ecoute terminee », comme cote firmware.
      soundLearning: moteur.aQuiLeTour ?? -1,
      // -2 : aucun son n'est encore passe, donc rien a reveler. Null : le son
      // precedent etait un leurre.
      soundLastOwner: !moteur.aDejaJoue
          ? -2
          : (moteur.precedentEtaitLeurre ? null : moteur.proprietairePrecedent),
      soundLastClaimed: moteur.precedentReclame,
      teamNames: teamNames,
      logoPath: logoPath,
    );
  }

  //
  // Comme pour le Reflexe, rien de nouveau n'est dessine : BlindZone existe
  // pour le mode autonome et lit une PHASE A AFFICHER, que le moteur dicte.
  //
  // LA CIBLE N'EST DONNEE QU'AVANT LE DEPART. Pendant la course elle reste
  // affichee (la salle doit s'en souvenir), mais aucun temps ecoule ne l'est :
  // tout l'interet du jeu est de ne pas savoir.
  factory PopoutSnapshot.duChronoAveugle(
    MoteurChronoAveugle moteur, {
    required List<String> teamNames,
    required String? logoPath,
  }) {
    final phase = switch (moteur.etape) {
      EtapeChronoAveugle.annonce => 'BLIND_ANNOUNCE',
      EtapeChronoAveugle.course => 'BLIND_RUN',
      EtapeChronoAveugle.resultat => 'BLIND_RESULT',
      EtapeChronoAveugle.finie => 'BLIND_OVER',
      EtapeChronoAveugle.repos => null,
    };
    return PopoutSnapshot(
      appMene: true,
      phaseJeu: phase == null ? null : kPhaseNames.indexOf(phase),
      gameMode: 8,
      displayGameMode: 8,
      scores: const [0, 0, 0, 0],
      gameScores: List<int>.of(moteur.scores),
      present: List<bool>.of(moteur.presents),
      flowState: QuestionFlowState.none,
      gameRound: moteur.manche,
      gameTotalRounds: moteur.manchesPrevues,
      brisEgalite: moteur.brisEgalite,
      gameWinner:
          moteur.etape == EtapeChronoAveugle.finie ? moteur.vainqueur : null,
      gameTie: moteur.etape == EtapeChronoAveugle.finie && moteur.egalite,
      gameFinished: moteur.etape == EtapeChronoAveugle.finie,
      motFinal: moteur.motFinal,
      blindTargetS: moteur.cibleSecondes,
      blindWinner: moteur.gagnant,
      // Zero veut dire « n'a pas pese », comme cote firmware.
      blindTimes: [for (var i = 0; i < 4; i++) moteur.temps[i] ?? 0],
      teamNames: teamNames,
      logoPath: logoPath,
    );
  }

  // L'ECRAN PUBLIC PENDANT UN REFLEXE mene par l'application.
  //
  // SIMON : le seul jeu SANS AUCUN SCORE.
  //
  // [gameScores] reste null a dessein, et pas a zero : la mise en page lit
  // « pas de scores » et masque le tableau (voir GameLayout.simon). Quatre
  // zeros afficheraient un tableau vide devant la salle, qui ne souleve
  // qu'une question. C'est le cas qui avait motive toute la mise en page par
  // jeu, et rien de nouveau n'est dessine ici : SimonZone existe deja pour le
  // mode autonome et lit les memes champs.
  factory PopoutSnapshot.duSimon(
    MoteurSimon moteur, {
    required List<String> teamNames,
    required String? logoPath,
  }) {
    final phase = switch (moteur.etape) {
      // La pause « bravo » reste sur l'ecran de repetition : basculer sur la
      // demonstration deux secondes avant qu'elle commence ferait clignoter
      // le titre pour rien.
      EtapeSimon.demonstration => 'SIMON_SHOW',
      EtapeSimon.repetition || EtapeSimon.bravo => 'SIMON_PLAY',
      EtapeSimon.finie => 'SIMON_OVER',
      EtapeSimon.repos => null,
    };
    final mode = moteur.alEnvers ? 6 : 5;
    return PopoutSnapshot(
      appMene: true,
      phaseJeu: phase == null ? null : kPhaseNames.indexOf(phase),
      gameMode: mode,
      displayGameMode: mode,
      scores: const [0, 0, 0, 0],
      present: List<bool>.of(moteur.presents),
      flowState: QuestionFlowState.none,
      // Jeu collaboratif : jamais de gagnant individuel, meme a la fin.
      gameFinished: moteur.etape == EtapeSimon.finie,
      motFinal: moteur.motFinal,
      // Les niveaux REUSSIS. L'ecran ajoute 1 tant que la partie tourne, pour
      // annoncer celui qui se joue : envoyer le niveau affiche le compterait
      // deux fois.
      simonLevel: moteur.niveau,
      simonEntered: moteur.saisis,
      simonLength: moteur.sequence.length,
      // LA SEQUENCE NE VOYAGE QU'UNE FOIS LA PARTIE FINIE. C'est ce que les
      // joueurs doivent retenir de tete : la projeter pendant qu'ils la
      // rejouent serait jouer a leur place. Apres, elle n'a plus rien a
      // proteger et c'est ce que tout le monde veut voir.
      simonSequence: moteur.etape == EtapeSimon.finie
          ? List<int>.of(moteur.sequence)
          : const [],
      simonFautif: moteur.etape == EtapeSimon.finie ? moteur.fautif : null,
      simonAttendu:
          moteur.etape == EtapeSimon.finie ? moteur.couleurAttendue : null,
      teamNames: teamNames,
      logoPath: logoPath,
    );
  }

  // Rien de nouveau n'est dessine : on remplit les memes champs que la
  // telemetrie du Mega remplissait, et [phaseJeu] dit a ReflexZone ou on en
  // est. L'ecran du jeu sert donc dans les deux modes sans etre reecrit.
  factory PopoutSnapshot.duReflexe(
    MoteurReflexe moteur, {
    required List<String> teamNames,
    required String? logoPath,
  }) {
    final duel = moteur.jeu == JeuDeVitesse.duel;
    final mode = duel ? 10 : 7;
    final phase = switch (moteur.etape) {
      EtapeReflexe.attente => duel ? 'DUEL_ARM' : 'REFLEX_ARM',
      EtapeReflexe.signal => duel ? 'DUEL_GO' : 'REFLEX_GO',
      EtapeReflexe.resultat => duel ? 'DUEL_RESULT' : 'REFLEX_RESULT',
      EtapeReflexe.finie => duel ? 'DUEL_OVER' : 'REFLEX_OVER',
      EtapeReflexe.repos => null,
    };
    return PopoutSnapshot(
      appMene: true,
      phaseJeu: phase == null ? null : kPhaseNames.indexOf(phase),
      // Reflexe (7) et Duel (10) se rangent tous deux dans la mise en page
      // « manches » : leurs points sont les leurs, pas ceux d'un quiz
      // precedent. L'ecran public a deja une zone pour chacun.
      gameMode: mode,
      displayGameMode: mode,
      scores: const [0, 0, 0, 0],
      gameScores: List<int>.of(moteur.scores),
      present: List<bool>.of(moteur.presents),
      // Un faux depart ecarte son auteur de la manche : la salle doit le voir
      // dans le bandeau, comme pour une mauvaise reponse au quiz.
      enLice: List<bool>.of(moteur.enLice),
      flowState: QuestionFlowState.none,
      brisEgalite: moteur.brisEgalite,
      gameRound: moteur.manche,
      gameTotalRounds: moteur.manchesPrevues,
      gameWinner: moteur.etape == EtapeReflexe.finie ? moteur.vainqueur : null,
      gameTie: moteur.etape == EtapeReflexe.finie && moteur.egalite,
      gameFinished: moteur.etape == EtapeReflexe.finie,
      motFinal: moteur.motFinal,
      reflexWinner: duel ? null : moteur.gagnant,
      reflexMs: duel ? null : moteur.tempsGagnant,
      reflexBestMs: duel ? null : moteur.meilleurTemps,
      reflexRecordMs: duel ? null : moteur.record,
      reflexNewRecord: !duel && moteur.recordBattu,
      // L'ecran du Duel a ses propres champs : il met les deux duellistes
      // face a face, ce que la zone du Reflexe ne fait pas.
      duelPlayerA: duel ? _premierPresent(moteur.presents) : null,
      duelPlayerB: duel ? _dernierPresent(moteur.presents) : null,
      duelWinner: duel ? moteur.gagnant : null,
      duelMs: duel ? moteur.tempsGagnant : null,
      duelFalseStarter: duel ? _premierFautif(moteur.fautifs) : null,
      reflexFalseStarts: [
        for (var i = 0; i < 4; i++)
          if (moteur.fautifs[i]) i
      ],
      teamNames: teamNames,
      logoPath: logoPath,
    );
  }

  factory PopoutSnapshot.duMoteur(
    MoteurQuiz moteur,
    GameState game, {
    required QuizQuestion? question,
    required List<String> teamNames,
    required String? logoPath,
    required VueDesSons vueSons,
  }) {
    // Meme regle que pour le firmware : sur les jeux avec chrono, la salle ne
    // voit la question qu'une fois le « top » donne, pas pendant que
    // l'animateur la lit encore a voix haute.
    final porteChrono = moteur.utiliseChrono && moteur.chronoPremiere > 0;
    final avantLeTop = porteChrono &&
        moteur.etape == EtapeQuiz.attente &&
        !moteur.secondeChance &&
        !moteur.chronoActif &&
        !moteur.tempsEcoule;
    final montrer = question != null && !avantLeTop;

    final flow = switch (moteur.etape) {
      EtapeQuiz.attente => QuestionFlowState.arming,
      EtapeQuiz.buzze => QuestionFlowState.buzzed,
      EtapeQuiz.scores => QuestionFlowState.scored,
      EtapeQuiz.revelee => QuestionFlowState.revealed,
      // Pendant l'ouverture, l'ecran public reste sur son plan d'attente, qui
      // annonce deja le jeu en grand : c'est exactement ce qu'il faut montrer
      // pendant que la musique joue.
      EtapeQuiz.repos || EtapeQuiz.intro || EtapeQuiz.finie =>
        QuestionFlowState.none,
    };
    // La reponse ne sort qu'une fois la question tranchee : c'est le contrat
    // de confidentialite, et il se tient ici, a la serialisation.
    final revelee = moteur.etape == EtapeQuiz.revelee || moteur.etape == EtapeQuiz.scores;

    return PopoutSnapshot(
      appMene: true,
      enLice: List<bool>.of(moteur.enLice),
      scores: List<int>.of(moteur.scores),
      present: List<bool>.of(moteur.presents),
      gameMode: moteur.jeu,
      displayGameMode: moteur.jeu,
      phase: game.phase,
      lastBuzz: moteur.etape == EtapeQuiz.buzze ? moteur.buzzeur : moteur.dernierJuge,
      flowState: flow,
      questionCategory: montrer && question.category.isNotEmpty ? question.category : null,
      questionText: montrer ? question.question : null,
      answerText: revelee ? question?.answer : null,
      questionsAsked: moteur.numeroQuestion,
      qcountValue: moteur.limiteQuestions,
      teamNames: teamNames,
      gameWinner: moteur.gagnant,
      gameTie: moteur.egalite,
      gameFinished: moteur.etape == EtapeQuiz.finie,
      motFinal: moteur.motFinal,
      motAttention: moteur.motAttention,
      motTirage: moteur.motTirage,
      brisEgalite: moteur.brisEgalite,
      chronoRestant: moteur.chronoRestant,
      chronoTotal: moteur.chronoTotal,
      vueSons: vueSons,
      logoPath: logoPath,
    );
  }

  factory PopoutSnapshot.fromGameState(
    GameState game, {
    required List<String> teamNames,
    required String? logoPath,
    required VueDesSons vueSons,
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
      vueSons: vueSons,
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
      appMene: json['appMene'] as bool? ?? false,
      enLice: (json['enLice'] as List?)?.cast<bool>() ??
          const [true, true, true, true],
      motFinal: json['motFinal'] as String? ?? '',
      motAttention: json['motAttention'] as String? ?? '',
      motTirage: json['motTirage'] as String? ?? '',
      phaseJeu: json['phaseJeu'] as int?,
      brisEgalite: json['brisEgalite'] as bool? ?? false,
      chronoRestant: json['chronoRestant'] as int?,
      chronoTotal: json['chronoTotal'] as int? ?? 0,
      simonLevel: json['simonLevel'] as int?,
      simonEntered: json['simonEntered'] as int?,
      simonLength: json['simonLength'] as int?,
      simonSequence: (json['simonSequence'] as List?)?.cast<int>() ?? const [],
      simonFautif: json['simonFautif'] as int?,
      simonAttendu: json['simonAttendu'] as int?,
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
      vueSons: VueDesSons.decode(json['vueSons'] as Map<String, dynamic>?),
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
        'appMene': appMene,
        'enLice': enLice,
        'motFinal': motFinal,
        'motAttention': motAttention,
        'motTirage': motTirage,
        'phaseJeu': phaseJeu,
        'brisEgalite': brisEgalite,
        'chronoRestant': chronoRestant,
        'chronoTotal': chronoTotal,
        'simonLevel': simonLevel,
        'simonEntered': simonEntered,
        'simonLength': simonLength,
        'simonSequence': simonSequence,
        'simonFautif': simonFautif,
        'simonAttendu': simonAttendu,
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
        'vueSons': vueSons.encode(),
        'logoPath': logoPath,
      });
}

// CE QUE LA SALLE VOIT DU CHOIX DES SONS.
//
// Trois moments, et un seul à la fois : le rappel des sons avant le départ,
// le mélange animé, et la grille ouverte pendant qu'une équipe choisit. Tous
// les trois se passent HORS partie, sur la console de l'animateur, et
// jusqu'ici la salle ne voyait rien : elle regardait quelqu'un cliquer.
//
// Regroupés plutôt que dispersés en champs libres dans l'instantané : ils
// partagent la même source (SoundEngine et l'animation du tirage), le même
// public, et ils s'excluent l'un l'autre. Les noms de sons voyagent tout
// faits, parce que la fenêtre du pop-out ne partage ni la bibliothèque ni la
// mémoire de la console.
class VueDesSons {
  const VueDesSons({
    this.rappel,
    this.melange = false,
    this.revelation = false,
    this.melangeAllume,
    this.melangeNoms = const ['', '', '', ''],
    this.grilleBuzzer,
    this.grilleSons = const [],
    this.grilleAssignation = const [0, 1, 2, 3],
  });

  static const aucune = VueDesSons();

  /// Rappel des sons avant le départ : buzzer dont le son passe en ce moment.
  /// Null quand aucun rappel n'est en cours. Piloté par l'app (SoundEngine),
  /// pas par le Mega.
  final int? rappel;

  /// La roue tourne pour rebrasser les sons.
  final bool melange;

  /// La roue s'est arrêtée et le résultat est encore à l'écran.
  final bool revelation;

  /// Le buzzer allumé à cet instant par le chenillard, ou null.
  final int? melangeAllume;

  /// Le nom montré sous chaque buzzer : celui qui défile pendant le mélange,
  /// celui qui vient d'être tiré pendant la révélation.
  final List<String> melangeNoms;

  /// Pour qui la grille est ouverte, ou null si elle est fermée.
  final int? grilleBuzzer;

  /// Tous les sons offerts, dans l'ordre et la numérotation de la console :
  /// la salle et l'animateur doivent pouvoir se dire un numéro.
  final List<String> grilleSons;

  /// Le son porté par chaque buzzer, pour marquer ceux qui sont déjà pris.
  final List<int> grilleAssignation;

  /// Vrai dès qu'il y a quelque chose à montrer. L'écran public s'en sert
  /// pour passer devant son plan d'attente.
  bool get quelqueChose =>
      rappel != null || melange || revelation || grilleBuzzer != null;

  factory VueDesSons.decode(Map<String, dynamic>? json) {
    if (json == null) return aucune;
    return VueDesSons(
      rappel: json['rappel'] as int?,
      melange: json['melange'] as bool? ?? false,
      revelation: json['revelation'] as bool? ?? false,
      melangeAllume: json['melangeAllume'] as int?,
      melangeNoms:
          (json['melangeNoms'] as List?)?.cast<String>() ?? const ['', '', '', ''],
      grilleBuzzer: json['grilleBuzzer'] as int?,
      grilleSons: (json['grilleSons'] as List?)?.cast<String>() ?? const [],
      grilleAssignation:
          (json['grilleAssignation'] as List?)?.cast<int>() ?? const [0, 1, 2, 3],
    );
  }

  Map<String, dynamic> encode() => {
        'rappel': rappel,
        'melange': melange,
        'revelation': revelation,
        'melangeAllume': melangeAllume,
        'melangeNoms': melangeNoms,
        'grilleBuzzer': grilleBuzzer,
        // La liste complète ne part QUE quand la grille est ouverte : une
        // trentaine de noms à chaque instantané, y compris pendant une partie
        // où personne ne la regarde, ne servirait qu'à grossir le message.
        'grilleSons': grilleBuzzer == null ? const <String>[] : grilleSons,
        'grilleAssignation': grilleAssignation,
      };
}

// Les deux duellistes se deduisent des buzzers presents, comme le fait le
// firmware : le jeu exige exactement deux joueurs, peu importe lesquels.
int? _premierPresent(List<bool> presents) {
  for (var i = 0; i < presents.length; i++) {
    if (presents[i]) return i;
  }
  return null;
}

int? _dernierPresent(List<bool> presents) {
  for (var i = presents.length - 1; i >= 0; i--) {
    if (presents[i]) return i;
  }
  return null;
}

int? _premierFautif(List<bool> fautifs) {
  for (var i = 0; i < fautifs.length; i++) {
    if (fautifs[i]) return i;
  }
  return null;
}
