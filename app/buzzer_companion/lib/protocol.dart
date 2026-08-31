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
        phase == _kPhaseSoundSetup ||
        phase == _kPhaseQuizCats ||
        phase == _kPhaseQuizCount);

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
};

// END_CONFIRM et END_GAME en font partie : la partie n'est pas finie tant
// que la salle n'a pas vu le résultat.
bool isGameRunning(int? phase) => phase != null && !_kIdlePhases.contains(phase);

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
  void markGameChosen() {
    _gameChosen = true;
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
  int? get displayGameMode {
    if (_gameChosen) return gameMode;
    return isGameRunning(phase) ? gameMode : null;
  }

  bool get answerRevealed => phase == _kPhaseAnswerReveal || phase == _kPhaseShowScores;

  QuestionFlowState get questionFlowState {
    if (questionText == null) return QuestionFlowState.none;
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

  void listenTo(Stream<String> messages) {
    _sub?.cancel();
    _sub = messages.listen(_handleMessage);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sfxController.close();
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
            handled = true;
          }
          break;
        case 'BUZZ':
          if (parts.length == 2) {
            lastBuzz = int.tryParse(parts[1]);
            handled = true;
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
              }
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
