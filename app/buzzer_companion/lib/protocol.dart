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

  void listenTo(Stream<String> messages) {
    _sub?.cancel();
    _sub = messages.listen(_handleMessage);
  }

  @override
  void dispose() {
    _sub?.cancel();
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
            handled = true;
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
            phase = int.tryParse(parts[1]);
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
          // Pas encore consommé côté UI (viendra avec la lecture de son
          // dans l'app) — reconnu, donc pas compté comme rejeté.
          handled = true;
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
