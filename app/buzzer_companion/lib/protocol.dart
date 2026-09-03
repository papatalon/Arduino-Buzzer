import 'dart:async';

import 'package:flutter/material.dart';

// Couleurs des LED physiques des buzzers — fixes, pas une palette
// catégorielle arbitraire. Index 0-3 = Rouge/Bleu/Jaune/Vert, dans l'ordre
// utilisé partout côté firmware (Buzzer::colorName, scores[], enabled[]...).
class BuzzerColor {
  final String name;
  final Color fill;
  final Color onFill;
  const BuzzerColor(this.name, this.fill, this.onFill);
}

const kBuzzerColors = [
  BuzzerColor('Rouge', Color(0xFFE63946), Colors.white),
  BuzzerColor('Bleu', Color(0xFF3A86FF), Colors.white),
  BuzzerColor('Jaune', Color(0xFFFFD60A), Color(0xFF3D2F00)),
  BuzzerColor('Vert', Color(0xFF2ECC71), Colors.white),
];

// Doit rester dans le même ordre que GameMode.h (GAME_MODE_COUNT exclu).
const kGameModeNames = [
  'Classique',
  'Pénalité',
  'Chrono classique',
  'Chrono pénalité',
  'Vol',
  'Simon',
  'Simon inverse',
  'Réflexe',
  'Chrono aveugle',
  'Ne buzze pas',
  'Duel',
];

// Doit rester dans le même ordre que Questions.cpp (CAT0_NAME..CAT9_NAME).
// Catégories fixes, compilées dans le firmware (pas de carte SD/EEPROM) —
// à resynchroniser seulement si Questions.cpp change.
const kCategoryNames = [
  'Culture générale',
  'Histoire',
  'Géographie',
  'Sciences et nature',
  'Sports',
  'Musique',
  'Cinéma et télé',
  'Québec',
  'Bouffe et cuisine',
  'Mots et langue',
];

// Doit rester dans le même ordre que PhaseMode.h. Fragile par construction :
// un ajout/retrait dans l'enum Arduino doit se refléter ici.
const kPhaseNames = [
  'BOOT', 'CONFIGURATION', 'GAME_CHOICE', 'SHUFFLE_BUZZER', 'BUZZER_CONFIG',
  'RESET', 'INTRO', 'WAITING_BUZZER', 'BUZZER_PRESSED', 'ANSWER_REVEAL',
  'SHOW_SCORES', 'END_CONFIRM', 'END_GAME', 'VOLUME', 'CHRONO',
  'QUIZ_CATS', 'QUIZ_COUNT', 'VOL_SPIN', 'SIMON_SHOW', 'SIMON_PLAY',
  'SIMON_OVER', 'ROUNDS_SETUP', 'REFLEX_ARM', 'REFLEX_GO', 'REFLEX_RESULT',
  'REFLEX_OVER', 'BLIND_ANNOUNCE', 'BLIND_RUN', 'BLIND_RESULT', 'BLIND_OVER',
  'SOUND_SETUP', 'SOUND_LEARN', 'SOUND_PLAY', 'SOUND_OVER', 'DUEL_ARM',
  'DUEL_GO', 'DUEL_RESULT', 'DUEL_OVER', 'LED_TEST',
  // Le buzzer est passé en esclave : l'application mène, il ne fait plus que
  // gérer les boutons. Voir AppControl côté firmware.
  'APP_CONTROL',
];

// Libellés courts, présentables, pour les phases qui comptent le plus pour
// l'opérateur ; le reste retombe sur le nom brut de l'enum (voir phaseLabel).
const Map<String, String> _friendlyPhaseLabels = {
  'CONFIGURATION': 'Menu',
  'WAITING_BUZZER': 'En attente d\'un buzz',
  'BUZZER_PRESSED': 'Un buzzer a sonné',
  'SHOW_SCORES': 'Scores',
  'END_GAME': 'Fin de partie',
  'BUZZER_CONFIG': 'Configuration des sons',
  'GAME_CHOICE': 'Choix du jeu',
};

// Une fois la phase à ANSWER_REVEAL (personne n'a trouvé) ou SHOW_SCORES
// (quelqu'un a trouvé), la question est terminée et sa réponse peut
// atteindre l'écran public — avant ça, elle reste console-only (voir le
// tableau de confidentialité du handoff de design).
final int _kPhaseAnswerReveal = kPhaseNames.indexOf('ANSWER_REVEAL');
final int _kPhaseShowScores = kPhaseNames.indexOf('SHOW_SCORES');
final int _kPhaseBuzzerPressed = kPhaseNames.indexOf('BUZZER_PRESSED');
final int _kPhaseWaitingBuzzer = kPhaseNames.indexOf('WAITING_BUZZER');
final int _kPhaseChrono = kPhaseNames.indexOf('CHRONO');
final int _kPhaseRoundsSetup = kPhaseNames.indexOf('ROUNDS_SETUP');
final int _kPhaseSoundSetup = kPhaseNames.indexOf('SOUND_SETUP');
final int _kPhaseQuizCats = kPhaseNames.indexOf('QUIZ_CATS');
final int _kPhaseQuizCount = kPhaseNames.indexOf('QUIZ_COUNT');
final int _kPhaseConfiguration = kPhaseNames.indexOf('CONFIGURATION');
final int _kPhaseAppControl = kPhaseNames.indexOf('APP_CONTROL');
final int _kPhaseIntro = kPhaseNames.indexOf('INTRO');
final int _kPhaseEndConfirm = kPhaseNames.indexOf('END_CONFIRM');
final int _kPhaseEndGame = kPhaseNames.indexOf('END_GAME');

// Fin de partie : confirmation avant de terminer, puis ecran final. Ces
// deux phases n'avaient aucune interface — l'operateur cliquait
// "Terminer la partie" et se retrouvait bloque devant un ecran sans
// boutons, sans moyen de confirmer ni d'annuler.
bool isEndConfirmPhase(int? phase) => phase != null && phase == _kPhaseEndConfirm;
bool isEndGamePhase(int? phase) => phase != null && phase == _kPhaseEndGame;

// Sous-écrans de réglage après un choix de jeu (durée, manches, sons,
// catégories/nombre de questions) — voir GameSetupView. Contrairement au
// flux de question, ces phases n'ont pas besoin d'un enum dédié : une
// seule vérification suffit pour savoir s'il faut afficher GameSetupView
// à la place du contenu normal.
bool isGameSetupPhase(int? phase) =>
    phase != null &&
    (phase == _kPhaseChrono ||
        phase == _kPhaseRoundsSetup ||
        phase == _kPhaseSoundSetup);

// Écrans que l'application NE MIROITE PLUS.
//
// En mode application, le questionnaire est choisi dans l'app et la banque du
// Mega reste en retrait : ses écrans de catégories et de nombre de questions
// n'existent que pour son clavier physique. Les mirroiter revenait à faire
// choisir des catégories du Mega à quelqu'un qui avait déjà choisi son
// questionnaire dans l'application.
//
// Le buzzer peut quand même s'y trouver, si quelqu'un y a navigué avant que
// l'app prenne la main. D'où ce repérage : la console le dit et propose de
// reprendre la main, au lieu d'afficher un écran qui n'a plus de sens.
bool isFirmwareOnlyPhase(int? phase) =>
    phase != null && (phase == _kPhaseQuizCats || phase == _kPhaseQuizCount);

// L'APPLICATION MENE. Le buzzer a lache tout etat de partie : il arme des
// boutons et rapporte les appuis, rien de plus (voir AppControl cote
// firmware). La console ne montre donc plus ses ecrans a lui, elle montre le
// moteur de jeu de l'app.
bool isAppControl(int? phase) => phase != null && phase == _kPhaseAppControl;

// Au menu CONFIGURATION (rien en cours) : c'est là que la console propose
// « Lancer la partie » (KEY|#), qui enchaîne selon le jeu choisi.
bool isAtConfigurationMenu(int? phase) => phase != null && phase == _kPhaseConfiguration;

// Jeux avec un chrono à lancer manuellement (Chrono classique=2, Chrono
// pénalité=3, Vol=4 — mêmes index que kGameModeNames/GameMode.h). Les
// autres jeux de quiz (Classique, Pénalité) n'ont pas de chrono du tout :
// le flux de question (QuestionFlowView) et le pop-out ne doivent montrer
// le bouton "Lancer le chrono"/l'attente CHRONO_START que pour ceux-ci.
bool usesChrono(int? gameMode) => gameMode == 2 || gameMode == 3 || gameMode == 4;

// Trois familles d'écrans, parce que les onze jeux n'ont pas la même matière
// à montrer. Sans cette distinction, l'écran public affichait le tableau des
// scores du QUIZ pendant un Réflexe ou un Simon : périmé au mieux, faux au
// pire, puisque ces jeux tiennent leurs propres scores (voir GSCORE) ou n'en
// ont aucun.
//
//   quiz    (0-4)   question, réponse, scores du quiz, chrono
//   manches (7-10)  scores propres au jeu + « Manche X sur Y »
//   simon   (5-6)   aucun score : le niveau atteint, seul
enum GameLayout { quiz, manches, simon }

GameLayout layoutFor(int? gameMode) {
  if (gameMode == 5 || gameMode == 6) return GameLayout.simon;
  if (gameMode != null && gameMode >= 7 && gameMode <= 10) return GameLayout.manches;
  return GameLayout.quiz;
}

// Nombre de buzzers admis par le jeu, ou null s'il s'accommode de n'importe
// quel nombre. Simon se joue de deux à quatre (la séquence n'est tirée que
// parmi les couleurs en jeu, mais à un seul joueur il suffirait d'appuyer à
// chaque fois) et le Duel à exactement deux. Le firmware refuse le lancement
// autrement (Configuration::manageConfiguration), et son avertissement
// s'affiche sur un LCD que l'app fige : mieux vaut que la console le dise
// elle-même, avant le clic.
({int min, int max})? playerRange(int? gameMode) {
  if (gameMode == 5 || gameMode == 6) return (min: 2, max: 4);  // Simon, Simon inverse
  if (gameMode == 10) return (min: 2, max: 2);                  // Duel
  return null;
}

// Est-ce que CE jeu marque des points ? Répondu jeu par jeu, pas déduit
// d'un défaut : Simon et Simon inverse sont collaboratifs et n'en ont
// aucun, et le prochain jeu ajouté devra répondre à la question plutôt que
// d'hériter d'un tableau des scores qu'il ne remplira jamais.
bool gameHasScores(int? gameMode) => gameMode != null && gameMode != 5 && gameMode != 6;

// Phases de menu, de configuration et de repos : rien ne se joue, donc
// l'écran public n'a aucun score à montrer — même pour un jeu qui en a. Sans
// cette distinction, la salle voyait un tableau de zéros avant même le
// début de la soirée.
final Set<int> _kIdlePhases = {
  kPhaseNames.indexOf('BOOT'),
  kPhaseNames.indexOf('CONFIGURATION'),
  kPhaseNames.indexOf('GAME_CHOICE'),
  kPhaseNames.indexOf('SHUFFLE_BUZZER'),
  kPhaseNames.indexOf('BUZZER_CONFIG'),
  kPhaseNames.indexOf('RESET'),
  kPhaseNames.indexOf('VOLUME'),
  kPhaseNames.indexOf('CHRONO'),
  kPhaseNames.indexOf('QUIZ_CATS'),
  kPhaseNames.indexOf('QUIZ_COUNT'),
  kPhaseNames.indexOf('ROUNDS_SETUP'),
  kPhaseNames.indexOf('SOUND_SETUP'),
  kPhaseNames.indexOf('LED_TEST'),
  // APP_CONTROL en fait partie, et c'est important : dans cette phase le
  // buzzer n'a AUCUNE partie a lui. Il arme des boutons pour l'application,
  // du debut a la fin de la soiree. Le compter comme une partie qui tourne
  // faisait basculer l'ecran public en mise en page de partie, sans jeu ni
  // question a montrer : un ecran vide devant la salle. Ce qui tourne ou
  // non, en mode application, c'est le moteur de jeu qui le dit.
  kPhaseNames.indexOf('APP_CONTROL'),
};

// END_CONFIRM et END_GAME en font partie : la partie n'est pas finie tant
// que la salle n'a pas vu le résultat.
bool isGameRunning(int? phase) => phase != null && !_kIdlePhases.contains(phase);

// Comparaison par nom plutôt que par index magique : les écrans publics
// distinguent une demi-douzaine de phases chacun, et « phase == 24 » ne se
// relit pas.
bool isPhase(int? phase, String name) =>
    phase != null && phase >= 0 && phase < kPhaseNames.length && kPhaseNames[phase] == name;

// Écrans de fin des jeux non-quiz (un par jeu côté firmware) : c'est là que
// le gagnant annoncé par GOVER a un sens à l'écran.
final Set<int> _kGameResultPhases = {
  kPhaseNames.indexOf('SIMON_OVER'),
  kPhaseNames.indexOf('REFLEX_OVER'),
  kPhaseNames.indexOf('BLIND_OVER'),
  kPhaseNames.indexOf('SOUND_OVER'),
  kPhaseNames.indexOf('DUEL_OVER'),
};

bool isGameResultPhase(int? phase) => phase != null && _kGameResultPhases.contains(phase);

// « Manche 2 sur 5 » (« Son 2 sur 12 » pour Ne buzze pas, où les manches
// sont des sons). Chaîne vide tant qu'aucune manche n'a commencé.
String roundProgressLabel(int? round, int? total, {int? gameMode}) {
  if (round == null || round <= 0) return '';
  final noun = gameMode == 9 ? 'Son' : 'Manche';
  if (total == null || total <= 0) return '$noun $round';
  return '$noun $round sur $total';
}

// "Question 3" (nombre ouvert) ou "Question 3 sur 20" (nombre fixe) —
// chaîne vide tant qu'aucune question n'a encore été posée.
String questionProgressLabel(int questionsAsked, int? qcountValue) {
  if (questionsAsked <= 0) return '';
  if (qcountValue != null && qcountValue > 0) return 'Question $questionsAsked sur $qcountValue';
  return 'Question $questionsAsked';
}

// Les 4 états du flux d'une question (design_handoff_buzzer_console/
// README.md, "Le flux d'une question (Chrono pénalité)") que l'app sait
// distinguer avec la télémétrie actuelle. `none` couvre tout le reste
// (menus, écrans de configuration...) : pas encore modélisé ici.
enum QuestionFlowState { arming, buzzed, scored, revealed, none }

// Chaîne vide quand la donnée n'existe pas encore — jamais de tiret cadratin
// nulle part dans l'app (retour explicite du client).
String phaseLabel(int? phase) {
  if (phase == null || phase < 0 || phase >= kPhaseNames.length) return '';
  final raw = kPhaseNames[phase];
  return _friendlyPhaseLabels[raw] ?? raw;
}

String gameModeName(int? mode) {
  if (mode == null || mode < 0 || mode >= kGameModeNames.length) return '';
  return kGameModeNames[mode];
}

List<int>? _parseInts(List<String> raw) {
  final result = <int>[];
  for (final r in raw) {
    final v = int.tryParse(r);
    if (v == null) return null;
    result.add(v);
  }
  return result;
}

// Évènement sonore reçu du Mega : un type ("GOOD", "BUZZ"...) et, pour
// BUZZ, l'index de la couleur concernée.
class SfxEvent {
  const SfxEvent(this.type, this.arg);
  final String type;
  final int? arg;
}

// État de la partie, reconstruit à partir des messages du protocole
// Mega -> app (voir le plan companion-app pour le détail des messages).
class GameState extends ChangeNotifier {
  List<int> scores = [0, 0, 0, 0];
  List<bool> present = [true, true, true, true];
  int? gameMode;
  int? phase;
  int? lastBuzz;
  final List<int?> buzzerSound = [null, null, null, null];

  String? questionCategory;
  String? questionText;
  String? answerText;
  // Vrai quand la question affichée vient d'un questionnaire de
  // l'application et non de la banque du buzzer. Sert à l'étiqueter sur la
  // console ; l'écran public, lui, ne fait aucune différence.
  bool appQuestion = false;
  bool chronoStarted = false;

  // Sous-écrans de réglage (voir isGameSetupPhase/GameSetupView) : valeur en
  // cours d'ajustement, telle qu'affichée sur le LCD du buzzer.
  int? setupChronoStep;      // 0 = 1re reponse, 1 = autres reponses
  int? setupChronoSeconds;
  int? setupRoundsCount;
  int? setupSoundStep;       // 0 = nombre de sons, 1 = leurres
  int? setupSoundValue;      // nombre de sons (step 0) ou 0/1 booleen (step 1)
  int? qcatMask;             // bitmask des 10 categories cochees
  int? qcountValue;          // nombre de questions (0 = Ouvert)

  // Jeux non-quiz : chacun tient SES propres scores cote firmware, sans
  // rapport avec ceux du quiz (voir BleLink::sendGameScores). Les melanger
  // afficherait devant la salle des points qui n'ont pas ete marques dans
  // le jeu en cours.
  List<int> gameScores = [0, 0, 0, 0];
  int? gameRound;
  int? gameTotalRounds;
  int? gameWinner;           // null = personne (egalite, abandon)
  bool gameTie = false;
  // Distingue "abandon" (GOVER|-1|0) de "partie en cours" : sans ce
  // drapeau, les deux se ressemblent (aucun gagnant, aucune egalite) et
  // l'ecran public resterait sur la manche courante apres un abandon.
  bool gameFinished = false;

  // Simon (message SIMON) : pas de score du tout, juste le niveau atteint et
  // l'avancement dans la sequence en cours.
  int? simonLevel;
  int? simonEntered;
  int? simonLength;

  // Reflexe : resultat de la derniere manche et record. Rien n'arrive
  // pendant l'attente ni au signal, volontairement (voir Reflex::setResult).
  int? reflexWinner;         // -1 = personne
  int? reflexMs;             // temps du gagnant de la manche
  int? reflexBestMs;         // meilleur temps de la partie (0 = aucun)
  int? reflexRecordMs;       // record persistant (65535 = aucun)
  bool reflexNewRecord = false;
  final Set<int> reflexFalseStarts = {};

  // Chrono aveugle : cible annoncee, puis temps de chacun au resultat.
  int? blindTargetS;

  // Le record du Chrono aveugle : le plus petit ecart jamais realise. Il vit
  // en EEPROM sur le Mega et vaut pour les deux modes, comme celui du
  // Reflexe. 65535 veut dire « aucun ».
  int? blindRecordMs;
  int? blindWinner;
  List<int> blindTimes = [0, 0, 0, 0];   // ms, 0 = n'a pas buzze

  // Duel : les deux duellistes et le resultat de la manche.
  int? duelPlayerA;
  int? duelPlayerB;
  int? duelWinner;
  int? duelMs;
  int? duelFalseStarter;     // -1 = pas de faux depart

  // Ne buzze pas : le son en cours d'apprentissage, et le proprietaire du
  // dernier son JOUE (revele seulement une fois la fenetre fermee).
  int? soundLearning;        // -1 = apprentissage termine
  int? soundLastOwner;       // -1 = leurre, -2 = rien a reveler
  bool soundLastClaimed = false;

  // Etat du lecteur audio du buzzer (message AUDIO, envoye a la prise de
  // controle) : permet de distinguer "silencieux parce que le volume est
  // bas" de "silencieux parce que le DFPlayer n'a pas ete detecte au
  // demarrage" (mode simulation cote firmware). Null tant qu'aucun
  // message AUDIO n'est arrive.
  bool? audioPlayerDetected;
  int? audioVolume;

  // Intervalle exige par le jeu quand le Mega vient de refuser un lancement
  // (message WARN|PLAYERS). Null le reste du temps.
  ({int min, int max})? playersWarning;

  // Fin de partie (message ENDGAME) : en cas d'egalite, '#' lance un bris
  // d'egalite au lieu de revenir au menu — l'interface a besoin de le
  // savoir pour ne pas proposer un bouton qui ment sur ce qu'il fait.
  bool endGameTie = false;
  int? endGameWinner;   // null = aucun buzzer present

  // Nombre de questions posees depuis le debut de la partie courante
  // (compte cote app, incremente a chaque QUESTION recu, remis a zero au
  // retour a INTRO). Avec qcountValue, permet d'afficher "Question N" ou
  // "Question N sur M".
  int questionsAsked = 0;

  // Le Mega garde toujours un jeu en mémoire (le dernier choisi, conservé
  // en EEPROM) et l'annonce dès la connexion. L'afficher au démarrage
  // laisserait croire qu'un jeu est prêt alors que l'opérateur n'a rien
  // choisi. On ne l'affiche donc qu'une fois choisi dans cette session —
  // ou si une partie est déjà en cours, cas d'une app relancée en pleine
  // soirée, où masquer le jeu serait cette fois trompeur.
  bool _gameChosen = false;

  // Vrai entre le clic sur un jeu et la réponse du buzzer. La console
  // navigue vers « Partie » tout de suite, sans attendre l'aller-retour BLE
  // (~200 ms) : sans ce drapeau, elle affichait pendant ce temps l'écran de
  // lancement complet, règles comprises, avant d'être remplacée par l'écran
  // de réglage du jeu. Ça se voyait comme un clignotement.
  //
  // Le firmware annonce toujours la phase d'arrivée après un SELECT_GAME,
  // même quand elle ne change pas (voir Configuration::selectGameIndex), donc
  // l'attente se termine dans tous les cas.
  bool awaitingSelection = false;
  Timer? _selectionTimeout;

  void markGameChosen() {
    _gameChosen = true;
    awaitingSelection = true;
    // Garde-fou : si la réponse ne vient pas (lien coupé au mauvais moment),
    // la console ne doit pas rester bloquée sur « Envoi au buzzer » toute la
    // soirée.
    _selectionTimeout?.cancel();
    _selectionTimeout = Timer(const Duration(seconds: 2), () {
      if (awaitingSelection) {
        awaitingSelection = false;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  // Condition volontairement affirmative : une première version disait
  // « afficher sauf si on est au menu », ce qui affichait le jeu au
  // démarrage tant qu'aucun message d'état n'était arrivé — la phase était
  // alors inconnue, donc « pas au menu » était vrai. On exige une preuve
  // positive qu'une partie tourne.
  //
  // Cette preuve est la phase, pas la présence d'une question : les cinq
  // jeux non-quiz (Simon, Réflexe...) n'en posent jamais, donc une app
  // relancée en pleine partie de Simon se croyait au repos.
  // Le jeu que l'application considère comme choisi POUR CETTE SÉANCE.
  //
  // Null tant que l'opérateur n'en a pas choisi un lui-même, même si le
  // buzzer en annonce un. Le Mega garde en mémoire le dernier jeu joué et le
  // renvoie dès qu'on se connecte : l'app affichait donc « Classique · Actif »
  // à l'ouverture, alors que personne ne l'avait choisi ce soir-là. Une
  // soirée commence en décidant à quoi on joue.
  //
  // Conséquence assumée : une application redémarrée pendant qu'une partie
  // tourne n'adopte pas cette partie. Les boutons de conduite restent
  // disponibles (ils se déduisent de la phase, pas du jeu), donc on peut
  // toujours la terminer, mais l'app ne prétend pas l'avoir voulue.
  int? get displayGameMode => _gameChosen ? gameMode : null;

  bool get answerRevealed => phase == _kPhaseAnswerReveal || phase == _kPhaseShowScores;

  // Déduit de la PHASE seule, jamais de la présence d'une question.
  //
  // Le garde-fou « pas de question, pas de flux » avait du sens quand la
  // banque du Mega fournissait toujours un texte. Il casse deux cas depuis :
  //
  //   Le questionnaire LIBRE, où l'animateur pose ses propres questions et
  //   où il n'y a donc jamais de texte. La console n'aurait affiché aucun
  //   bouton de conduite, pour toute la partie.
  //
  //   Une application redémarrée en pleine partie : le buzzer est en attente
  //   d'un buzz, l'app n'a plus de question, et l'animateur se retrouvait
  //   devant un écran sans la moindre sortie.
  //
  // Une question absente veut dire « rien à afficher là », pas « aucune
  // partie en cours ». La conduite ne dépend pas du texte.
  QuestionFlowState get questionFlowState {
    if (phase == _kPhaseAnswerReveal) return QuestionFlowState.revealed;
    if (phase == _kPhaseShowScores) return QuestionFlowState.scored;
    if (phase == _kPhaseBuzzerPressed) return QuestionFlowState.buzzed;
    if (phase == _kPhaseWaitingBuzzer) return QuestionFlowState.arming;
    return QuestionFlowState.none;
  }

  // Lignes reçues mais ni reconnues ni exploitables (type inconnu, nombre de
  // champs inattendu, exception de parsing) — pour l'écran "Appareil"
  // (design_handoff_buzzer_console/README.md, 1h, "lignes rejetées").
  int messagesRejected = 0;

  StreamSubscription<String>? _sub;

  // Les évènements sonores sont un flux et non un état : rejouer le même
  // son deux fois de suite doit produire deux notifications distinctes, ce
  // qu'un champ observable ne permettrait pas.
  final _sfxController = StreamController<SfxEvent>.broadcast();
  Stream<SfxEvent> get sfxEvents => _sfxController.stream;

  // Les appuis sont un FLUX, pas un état : deux buzz du même joueur doivent
  // produire deux évènements, ce qu'un champ observable ne permettrait pas.
  // C'est ce qui alimente le moteur de jeu de l'application (MoteurQuiz).
  final _buzzController = StreamController<({int buzzer, int ms})>.broadcast();
  Stream<({int buzzer, int ms})> get buzzEvents => _buzzController.stream;

  // Question fournie par un questionnaire de l'application. Elle se pose aux
  // MÊMES champs que ceux qu'alimente la banque du buzzer : tout l'aval (la
  // console, l'écran public, la règle qui garde la réponse cachée jusqu'à la
  // fin de la question) fonctionne sans rien changer.
  //
  // En mode applicatif la banque du buzzer est en retrait (masque de
  // catégories à zéro), donc les deux ne s'écrivent jamais dessus.
  void setAppQuestion(String? category, String? question, String? answer,
      {int? numero}) {
    final vide = question == null || question.isEmpty;
    // Le compteur de l'écran public compte les QUESTION reçues du buzzer.
    // En mode applicatif il n'en arrive aucune : sans ça, la salle verrait
    // « question 0 » pendant toute la soirée.
    if (numero != null && questionsAsked != numero) questionsAsked = numero;
    // Sans ce garde, chaque notification de l'état de partie déclencherait
    // une réécriture, donc une notification, et ainsi de suite.
    if (questionCategory == category &&
        questionText == (vide ? null : question) &&
        answerText == (vide ? null : answer) &&
        appQuestion == !vide) {
      return;
    }
    questionCategory = category;
    questionText = vide ? null : question;
    answerText = vide ? null : answer;
    appQuestion = !vide;
    notifyListeners();
  }

  void listenTo(Stream<String> messages) {
    _sub?.cancel();
    _sub = messages.listen(_handleMessage);
  }

  // Injecte une ligne comme si elle venait du buzzer. Sert au simulateur
  // (voir lib/simulation.dart), qui permet de travailler les écrans de jeu
  // sans matériel branché.
  //
  // Volontairement le MÊME chemin que le vrai lien : un simulateur qui
  // écrirait directement dans les champs prouverait que les écrans savent
  // afficher des champs, pas qu'ils savent afficher ce que le firmware
  // envoie. Les deux se ressemblent jusqu'au jour où un message change.
  void injecter(String ligne) => _handleMessage(ligne);

  @override
  void dispose() {
    _selectionTimeout?.cancel();
    _sub?.cancel();
    _sfxController.close();
    _buzzController.close();
    super.dispose();
  }

  void _handleMessage(String line) {
    var handled = false;
    try {
      final parts = line.split('|');
      if (parts.isEmpty) return;

      switch (parts[0]) {
        case 'SCORE':
          final parsed = _parseInts(parts.sublist(1));
          if (parsed != null && parsed.length == 4) {
            scores = parsed;
            handled = true;
          }
          break;
        case 'PRESENT':
          final parsed = _parseInts(parts.sublist(1));
          if (parsed != null && parsed.length == 4) {
            present = parsed.map((v) => v != 0).toList();
            // La présence vient de changer : un avertissement « il en faut
            // quatre » n'a plus lieu d'être affiché tant qu'on n'a pas
            // réessayé de lancer.
            playersWarning = null;
            handled = true;
          }
          break;
        case 'WARN':
          // "WARN|PLAYERS|<min>|<max>" : le Mega a refusé de lancer la
          // partie faute du bon nombre de buzzers. Son message va sur le
          // LCD, que l'app fige quand elle a le contrôle, donc sans ce
          // relais le clic sur « Lancer la partie » resterait sans effet ni
          // explication.
          if (parts.length == 4 && parts[1] == 'PLAYERS') {
            final min = int.tryParse(parts[2]);
            final max = int.tryParse(parts[3]);
            if (min != null && max != null) {
              playersWarning = (min: min, max: max);
              handled = true;
            }
          }
          break;
        case 'GAME':
          if (parts.length == 2) {
            gameMode = int.tryParse(parts[1]);
            handled = true;
          }
          break;
        case 'STATE':
          if (parts.length == 2) {
            final newPhase = int.tryParse(parts[1]);
            if (newPhase == _kPhaseIntro && phase != _kPhaseIntro) {
              questionsAsked = 0; // nouvelle partie qui commence
            }
            phase = newPhase;
            // Le buzzer a dit où il a atterri : la console peut afficher.
            _selectionTimeout?.cancel();
            awaitingSelection = false;
            handled = true;
          }
          break;
        case 'BUZZ':
          // Deux formes. « BUZZ|n » vient du mode autonome, où le firmware
          // mène. « BUZZ|n|ms » vient du mode esclave : le temps de réaction
          // est mesuré sur le Mega, parce qu'un aller-retour Bluetooth
          // ajouterait de 30 à 100 ms de gigue.
          if (parts.length == 2 || parts.length == 3) {
            final qui = int.tryParse(parts[1]);
            if (qui != null && qui >= 0 && qui < 4) {
              lastBuzz = qui;
              final ms = parts.length == 3 ? int.tryParse(parts[2]) : null;
              _buzzController.add((buzzer: qui, ms: ms ?? 0));
              handled = true;
            }
          }
          break;
        case 'QUESTION':
          if (parts.length == 4) {
            questionCategory = parts[1];
            questionText = parts[2];
            answerText = parts[3];
            lastBuzz = null; // une nouvelle question efface le dernier buzz
            chronoStarted = false;
            questionsAsked++;
            // Le buzzer fournit la question : ce n'est plus celle de l'app.
            appQuestion = false;
            handled = true;
          }
          break;
        case 'CFG_SOUND':
          if (parts.length == 3) {
            final color = int.tryParse(parts[1]);
            final sound = int.tryParse(parts[2]);
            if (color != null && color >= 0 && color < 4) {
              buzzerSound[color] = sound;
              handled = true;
            }
          }
          break;
        case 'SOUND':
          // Ancien format (dossier/fichier), encore émis quand le buzzer
          // joue lui-même : l'app n'en fait rien, les index du Mega ne
          // correspondent pas forcément à sa bibliothèque. Reconnu, donc
          // pas compté comme rejeté.
          handled = true;
          break;
        case 'SFX':
          // Évènement sonore sémantique : le Mega dit ce qui se passe
          // ("le bleu a buzzé", "bonne réponse"), l'app choisit le fichier
          // dans sa propre bibliothèque. Voir Mp3::delegateToApp.
          if (parts.length >= 2) {
            final arg = parts.length >= 3 ? int.tryParse(parts[2]) : null;
            _sfxController.add(SfxEvent(parts[1], arg));
            handled = true;
          }
          break;
        case 'ENDGAME':
          if (parts.length == 3) {
            final tie = int.tryParse(parts[1]);
            final winner = int.tryParse(parts[2]);
            if (tie != null && winner != null) {
              endGameTie = tie != 0;
              endGameWinner = winner >= 0 ? winner : null;
              handled = true;
            }
          }
          break;
        case 'QSYNC':
          // Renvoi de la question en cours a la (re)connexion — mêmes
          // champs que QUESTION, mais sans les effets de bord : ce n'est
          // pas une nouvelle question, donc ni compteur incrémenté ni
          // dernier buzz effacé (voir Buzzer.ino, bloc de resynchro).
          if (parts.length == 4) {
            questionCategory = parts[1];
            questionText = parts[2];
            answerText = parts[3];
            handled = true;
          }
          break;
        case 'AUDIO':
          if (parts.length == 3) {
            final detected = int.tryParse(parts[1]);
            final vol = int.tryParse(parts[2]);
            if (detected != null && vol != null) {
              audioPlayerDetected = detected != 0;
              audioVolume = vol;
              handled = true;
            }
          }
          break;
        case 'CHRONO_START':
          chronoStarted = true;
          handled = true;
          break;
        case 'CHRONO_CFG':
          if (parts.length == 3) {
            setupChronoStep = int.tryParse(parts[1]);
            setupChronoSeconds = int.tryParse(parts[2]);
            handled = setupChronoStep != null && setupChronoSeconds != null;
          }
          break;
        case 'ROUNDS_CFG':
          if (parts.length == 2) {
            setupRoundsCount = int.tryParse(parts[1]);
            handled = setupRoundsCount != null;
          }
          break;
        case 'SOUND_CFG':
          if (parts.length == 3) {
            setupSoundStep = int.tryParse(parts[1]);
            setupSoundValue = int.tryParse(parts[2]);
            handled = setupSoundStep != null && setupSoundValue != null;
          }
          break;
        case 'QCAT_CFG':
          if (parts.length == 2) {
            qcatMask = int.tryParse(parts[1]);
            handled = qcatMask != null;
          }
          break;
        case 'GSCORE':
          final parsed = _parseInts(parts.sublist(1));
          if (parsed != null && parsed.length == 4) {
            gameScores = parsed;
            handled = true;
          }
          break;
        case 'GROUND':
          if (parts.length == 3) {
            final round = int.tryParse(parts[1]);
            final total = int.tryParse(parts[2]);
            if (round != null && total != null) {
              gameRound = round;
              gameTotalRounds = total;
              // Manche 0 = le reset() du jeu : une nouvelle partie commence,
              // donc le resultat de la precedente ne doit plus rester
              // affiche.
              if (round == 0) {
                gameWinner = null;
                gameTie = false;
                gameFinished = false;
                soundLastOwner = null;
                soundLearning = null;
              }
              // Nouvelle manche : le résultat de la précédente ne doit plus
              // rester à l'écran pendant qu'on attend le signal. Réflexe,
              // Chrono aveugle et Duel n'envoient GROUND qu'une fois par
              // manche, donc c'est le bon repère. « Ne buzze pas » l'envoie
              // à chaque son, d'où l'absence de soundLastOwner ici : il
              // effacerait la révélation aussitôt affichée.
              reflexFalseStarts.clear();
              reflexWinner = null;
              reflexMs = null;
              blindWinner = null;
              blindTimes = [0, 0, 0, 0];
              duelWinner = null;
              duelMs = null;
              duelFalseStarter = null;
              handled = true;
            }
          }
          break;
        case 'GOVER':
          if (parts.length == 3) {
            final winner = int.tryParse(parts[1]);
            final tie = int.tryParse(parts[2]);
            if (winner != null && tie != null) {
              gameWinner = winner >= 0 ? winner : null;
              gameTie = tie != 0;
              gameFinished = true;
              handled = true;
            }
          }
          break;
        case 'RFLX':
          if (parts.length == 4) {
            final w = int.tryParse(parts[1]);
            final ms = int.tryParse(parts[2]);
            final best = int.tryParse(parts[3]);
            if (w != null && ms != null && best != null) {
              reflexWinner = w;
              reflexMs = ms;
              reflexBestMs = best;
              handled = true;
            }
          }
          break;
        case 'RFLXF':
          if (parts.length == 2) {
            final who = int.tryParse(parts[1]);
            if (who != null && who >= 0 && who < 4) {
              reflexFalseStarts.add(who);
              handled = true;
            }
          }
          break;
        // LE RECORD DU REFLEXE, envoye par le Mega a la connexion et apres
        // chaque mise a jour. Il vit en EEPROM : une partie menee par
        // l'application compte pour le meme record qu'une partie au clavier,
        // parce qu'il appartient au buzzer et non a l'ordinateur.
        case 'RECB':
          if (parts.length >= 2) {
            blindRecordMs = int.tryParse(parts[1]);
            handled = blindRecordMs != null;
          }
          break;
        case 'REC':
          if (parts.length >= 2) {
            reflexRecordMs = int.tryParse(parts[1]);
            handled = reflexRecordMs != null;
          }
          break;
        case 'RFLXR':
          if (parts.length == 4) {
            reflexBestMs = int.tryParse(parts[1]);
            reflexRecordMs = int.tryParse(parts[2]);
            reflexNewRecord = parts[3] != '0';
            handled = reflexBestMs != null && reflexRecordMs != null;
          }
          break;
        case 'BLND':
          if (parts.length == 2) {
            blindTargetS = int.tryParse(parts[1]);
            handled = blindTargetS != null;
          }
          break;
        case 'BLNDR':
          if (parts.length == 6) {
            final w = int.tryParse(parts[1]);
            final t = _parseInts(parts.sublist(2));
            if (w != null && t != null && t.length == 4) {
              blindWinner = w;
              blindTimes = t;
              handled = true;
            }
          }
          break;
        case 'DUELP':
          if (parts.length == 3) {
            duelPlayerA = int.tryParse(parts[1]);
            duelPlayerB = int.tryParse(parts[2]);
            handled = duelPlayerA != null && duelPlayerB != null;
          }
          break;
        case 'DUELR':
          if (parts.length == 4) {
            duelWinner = int.tryParse(parts[1]);
            duelMs = int.tryParse(parts[2]);
            duelFalseStarter = int.tryParse(parts[3]);
            handled = duelWinner != null && duelMs != null && duelFalseStarter != null;
          }
          break;
        case 'SNDL':
          if (parts.length == 2) {
            soundLearning = int.tryParse(parts[1]);
            handled = soundLearning != null;
          }
          break;
        case 'SNDO':
          if (parts.length == 3) {
            soundLastOwner = int.tryParse(parts[1]);
            soundLastClaimed = parts[2] != '0';
            handled = soundLastOwner != null;
          }
          break;
        case 'SIMON':
          if (parts.length == 4) {
            final level = int.tryParse(parts[1]);
            final entered = int.tryParse(parts[2]);
            final length = int.tryParse(parts[3]);
            if (level != null && entered != null && length != null) {
              simonLevel = level;
              simonEntered = entered;
              simonLength = length;
              handled = true;
            }
          }
          break;
        case 'QCOUNT_CFG':
          if (parts.length == 2) {
            qcountValue = int.tryParse(parts[1]);
            handled = qcountValue != null;
          }
          break;
      }

      if (handled) {
        notifyListeners();
      } else {
        messagesRejected++;
        notifyListeners();
      }
      return;
    } catch (_) {
      // Ligne malformée (ex. coupée pendant une reconnexion) : ignorée
      // plutôt que de faire planter le parseur.
      messagesRejected++;
      notifyListeners();
    }
  }
}
