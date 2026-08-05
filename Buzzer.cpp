#include "Buzzer.h"

Buzzer::Buzzer() {}

// === Required for Singletons ===
// Define the single instance as a static member
Buzzer& Buzzer::shared() {
  static Buzzer instance;
  return instance;
}

void Buzzer::init() {
  for (int buzzerId = 0; buzzerId < 4; buzzerId++) {
    pinMode(buzzers[buzzerId][0],OUTPUT);
    pinMode(buzzers[buzzerId][1],INPUT_PULLUP);
  }
}

void Buzzer::resetLights() {
  for (int buzzerId = 0; buzzerId < 4; buzzerId++) {
    digitalWrite(buzzers[buzzerId][0], LOW);
  }
}

// === Mode cache de test cablage (LED_TEST), entree via *1 ===
// A l'entree, les 4 LED s'allument. Ensuite :
//  - une touche du clavier bascule TOUTES les LED (test des sorties LED) ;
//  - un appui sur un bouton de buzzer bascule SA propre LED et affiche la
//    couleur (test conjoint du bouton et de la LED, couleur par couleur).
// Sortie : ** (reset) -> retour a la configuration.
void Buzzer::setLedTest() {
  ledTestMaster = true;
  for (int i = 0; i < 4; i++) {
    ledTestOn[i] = true;
    ledTestPrev[i] = false;
    setLed(i, true);
  }
  display.clear();
  display.setText("Test LED + boutons", 0);
  display.setText("Touche: tout on/off", 1);
  display.setText("Bouton: sa LED", 2);
  display.setText("**  = retour config", 3);
}

PhaseMode Buzzer::ledTest(char pressedKey) {
  // Touche du clavier : bascule globale de toutes les LED.
  if (pressedKey) {
    ledTestMaster = !ledTestMaster;
    for (int i = 0; i < 4; i++) {
      ledTestOn[i] = ledTestMaster;
      setLed(i, ledTestMaster);
    }
    display.setText(ledTestMaster ? "Tout: ON" : "Tout: OFF", 3);
  }

  // Boutons des buzzers : bascule la LED du buzzer appuye (front descendant).
  for (int i = 0; i < 4; i++) {
    bool pressedNow = (digitalRead(buzzers[i][1]) == LOW);
    bool edge = pressedNow && !ledTestPrev[i];
    ledTestPrev[i] = pressedNow;

    if (edge) {
      ledTestOn[i] = !ledTestOn[i];
      setLed(i, ledTestOn[i]);
      display.setText(String(colorName(i)) + ": " + (ledTestOn[i] ? "ON" : "OFF"), 3);
    }
  }

  return LED_TEST;
}

PhaseMode Buzzer::waitingBuzzerIsPressed(PhaseMode currentMode) {
  PhaseMode result = currentMode;

  for (int i = 0; i < 4; i++) {
    bool pressedNow = (digitalRead(buzzers[i][1]) == LOW);
    // Front descendant uniquement : un bouton maintenu ne se redéclenche pas.
    bool edge = pressedNow && !prevPressed[i];
    prevPressed[i] = pressedNow;

    if (result == currentMode && enabled[i] && actives[i] && edge) {
      currentBuzzerId = i;
      digitalWrite(buzzers[i][0], HIGH);
      mp3.playBuzzer(i);
      result = BUZZER_PRESSED;
    }
  }

  return result;
}

void Buzzer::setWaitingForBuzzer() {
  // Mémorise l'état courant des boutons : un bouton déjà maintenu en entrant
  // en attente devra être relâché avant de pouvoir buzzer (anti-rebond).
  for (int i = 0; i < 4; i++) {
    prevPressed[i] = (digitalRead(buzzers[i][1]) == LOW);
  }

  display.clear();

  if (tiebreak) {
    // Repères : LED allumées pour les ex æquo + liste des couleurs en lice.
    String parts = "";
    for (int i = 0; i < 4; i++) {
      bool inPlay = enabled[i] && actives[i];
      setLed(i, inPlay);
      if (inPlay) {
        if (parts.length() > 0) {
          parts += " ";
        }
        parts += colorName(i);
      }
    }
    display.setText("  BRIS D'EGALITE", 0);
    display.setText("   Buzzez vite !", 1);
    display.setText(parts, 2);
    return;
  }

  display.setText(String("Question ") + questionNumber, 0);
  display.setText("    EN ATTENTE", 1);
  display.setText("   D'UNE REPONSE", 2);
  // "B:corriger" n'a de sens que si une décision a déjà été prise.
  if (lastJudgedBuzzer >= 0) {
    display.setText("B:corr 0:pass C:fin", 3);
  } else {
    display.setText("0:passer   C:fin", 3);
  }
}

void Buzzer::setBuzzerPressed() {
    display.clear();
    display.setText(String("BIP ! -> ") + colorName(currentBuzzerId), 0);
    display.setText("A: Bonne reponse", 1);
    display.setText("D: Mauvaise reponse", 2);
    display.setText("0 = passer", 3);
    int ledPin = buzzers[currentBuzzerId][0];
    digitalWrite(ledPin, HIGH);
}

PhaseMode Buzzer::buzzerIsPressed(PhaseMode currentMode, char pressedKey) {

  // Bris d'égalité : règles particulières.
  if (tiebreak) {
    if (pressedKey == 'A') {                 // bonne réponse -> gagne la partie
      scores[currentBuzzerId]++;
      mp3.playGoodAnswer();
      setLed(currentBuzzerId, false);
      tiebreak = false;
      return END_GAME;
    }
    if (pressedKey == 'D') {                  // éliminé du bris
      mp3.playBadAnswer();
      actives[currentBuzzerId] = false;
      setLed(currentBuzzerId, false);

      int remaining = 0;
      int last = -1;
      for (int i = 0; i < 4; i++) {
        if (enabled[i] && actives[i]) {
          remaining++;
          last = i;
        }
      }
      if (remaining <= 1) {                   // dernier en lice -> gagnant
        if (remaining == 1) {
          scores[last]++;
        }
        tiebreak = false;
        return END_GAME;
      }
      return WAITING_BUZZER;                   // le bris continue
    }
    return currentMode;
  }

  switch (pressedKey) {
    case 'A':
      Buzzer::goodAnswer();
      return SHOW_SCORES;       // fin de question -> écran des scores
    case 'D':
      Buzzer::badAnswer();
      return WAITING_BUZZER;    // même question, les autres peuvent répondre
      break;
    case '0':
      Buzzer::skipQuestion();
      return WAITING_BUZZER;    // question abandonnée, personne ne marque
    default:
      return currentMode;
  };


  return currentMode;
}

void Buzzer::setIntro() {
  introStart = millis();
  display.clear();
  display.setText("   C'EST PARTI !", 0);
  display.setText("  Que le meilleur", 1);
  display.setText("     gagne !", 2);
}

PhaseMode Buzzer::intro(char pressedKey) {
  unsigned long elapsed = millis() - introStart;

  // N'importe quelle touche, ou la fin du minuteur, lance la 1re question.
  if (pressedKey || elapsed >= INTRO_MS) {
    resetLights();
    return WAITING_BUZZER;
  }

  // Chenillard festif : les LED s'allument l'une après l'autre.
  int step = (elapsed / INTRO_STEP_MS) % 4;
  for (int i = 0; i < 4; i++) {
    setLed(i, i == step);
  }
  return INTRO;
}

void Buzzer::skipQuestion() {
  if (tiebreak) {
    return;                  // pas de "passer" pendant un bris d'égalité
  }
  resetLights();
  resetAllBuzzers();         // tous les buzzers présents redeviennent actifs
  lastJudgedBuzzer = -1;     // plus de décision à corriger
  lastWasGood = false;
  questionNumber++;          // on passe à la question suivante
}

void Buzzer::goodAnswer() {
  int ledPin = buzzers[currentBuzzerId][0];

  scores[currentBuzzerId]++;        // bonne réponse : +1
  lastJudgedBuzzer = currentBuzzerId;
  lastWasGood = true;
  questionNumber++;                 // question résolue -> on passe à la suivante

  mp3.playGoodAnswer();
  digitalWrite(ledPin, LOW);

  // Le clignotement de la LED se fait sans blocage pendant l'écran des
  // scores (voir showScores), pour ne pas figer le clavier ni l'afficheur.
  resetAllBuzzers();
}

void Buzzer::badAnswer() {
  int ledPin = buzzers[currentBuzzerId][0];

  if (penaltyMode) {
    scores[currentBuzzerId]--;      // mode Pénalité : -1 (peut être négatif)
  }
  lastJudgedBuzzer = currentBuzzerId;
  lastWasGood = false;

  mp3.playBadAnswer();

  actives[currentBuzzerId] = false;
  digitalWrite(ledPin, LOW);
}

PhaseMode Buzzer::correctLastDecision(PhaseMode fallback) {
  if (lastJudgedBuzzer < 0) {
    return fallback;                // rien à corriger
  }

  int id = lastJudgedBuzzer;
  if (lastWasGood) {
    scores[id]--;                  // annule le +1 d'une bonne réponse
    if (questionNumber > 1) {
      questionNumber--;            // on rouvre la question
    }
  } else {
    actives[id] = true;            // ré-active le buzzer écarté
    if (penaltyMode) {
      scores[id]++;                // annule le -1 de la pénalité
    }
  }

  currentBuzzerId = id;            // on revient juger ce même buzzer
  return BUZZER_PRESSED;
}

void Buzzer::resetAllBuzzers() {
  for(int i = 0; i < 4; i++) {
    actives[i] = true;
  }
}

const char* Buzzer::colorName(int i) {
  switch (i) {
    case 0: return "Rouge";
    case 1: return "Bleu";
    case 2: return "Jaune";
    case 3: return "Vert";
    default: return "?";
  }
}

void Buzzer::setPenaltyMode(bool value) {
  penaltyMode = value;
}

void Buzzer::togglePenaltyMode() {
  penaltyMode = !penaltyMode;
}

bool Buzzer::isPenaltyMode() {
  return penaltyMode;
}

void Buzzer::resetScores() {
  for (int i = 0; i < 4; i++) {
    scores[i] = 0;
  }
  lastJudgedBuzzer = -1;
  lastWasGood = false;
  questionNumber = 1;
  tiebreak = false;
  endTie = false;
  // Nouvelle partie : tous les buzzers présents redeviennent actifs.
  for (int i = 0; i < 4; i++) {
    actives[i] = true;
  }
}

void Buzzer::displayScores(const char* title, const char* prompt) {
  display.clear();
  display.setText(title, 0);

  // N'affiche que les buzzers présents, jusqu'à 2 par ligne.
  String line1 = "";
  String line2 = "";
  int shown = 0;
  for (int i = 0; i < 4; i++) {
    if (!enabled[i]) {
      continue;
    }
    String entry = String(colorName(i)) + ":" + scores[i];
    if (shown == 0) {
      line1 = entry;
    } else if (shown == 1) {
      line1 += "   " + entry;
    } else if (shown == 2) {
      line2 = entry;
    } else {
      line2 += "   " + entry;
    }
    shown++;
  }

  display.setText(line1, 1);
  display.setText(line2, 2);
  display.setText(prompt, 3);
}

void Buzzer::setShowScores() {
  scoresShownAt = millis();
  displayScores("      SCORES", "#=suite B=corr C=fin");
}

PhaseMode Buzzer::showScores(char pressedKey) {
  if (pressedKey == 'C') {
    setLed(currentBuzzerId, false);
    return END_CONFIRM;              // demander confirmation avant de terminer
  }
  if (pressedKey == 'B') {
    setLed(currentBuzzerId, false);
    return correctLastDecision(SHOW_SCORES);  // corriger la dernière décision
  }
  if (pressedKey == '#') {
    setLed(currentBuzzerId, false);
    return WAITING_BUZZER;           // passer tout de suite à la question suivante
  }
  if (millis() - scoresShownAt >= SCORES_DISPLAY_MS) {
    setLed(currentBuzzerId, false);
    return WAITING_BUZZER;           // au bout de 15 s, question suivante
  }

  // Courte célébration : la LED du gagnant clignote ~1,5 s puis s'éteint.
  unsigned long elapsed = millis() - scoresShownAt;
  if (elapsed < WIN_BLINK_MS) {
    setLed(currentBuzzerId, ((millis() / 250) % 2) == 0);
  } else {
    setLed(currentBuzzerId, false);
  }
  return SHOW_SCORES;
}

void Buzzer::setEndConfirm() {
  display.clear();
  display.setText("TERMINER LA PARTIE ?", 0);
  display.setText("# = oui", 2);
  display.setText("* = non (continuer)", 3);
}

PhaseMode Buzzer::endConfirm(char pressedKey) {
  if (pressedKey == '#') {
    return END_GAME;
  }
  if (pressedKey == '*') {
    return WAITING_BUZZER;   // on reprend la partie
  }
  return END_CONFIRM;
}

void Buzzer::setEndGame() {
  resetLights();   // éteint d'éventuelles LED restées allumées (bris d'égalité)

  // Détermine le meilleur score parmi les buzzers présents.
  int best = 0;
  bool any = false;
  for (int i = 0; i < 4; i++) {
    if (enabled[i] && (!any || scores[i] > best)) {
      best = scores[i];
      any = true;
    }
  }

  int count = 0;
  int winner = -1;
  for (int i = 0; i < 4; i++) {
    if (enabled[i] && scores[i] == best) {
      count++;
      winner = i;
    }
  }

  endTie = (any && count > 1);

  String prompt;
  if (!any) {
    prompt = "Aucun buzzer #menu";
  } else if (endTie) {
    prompt = "#=bris   *=menu";    // égalité : proposer un bris d'égalité
  } else {
    prompt = String("Gagne:") + colorName(winner) + " #menu";
  }

  displayScores(endTie ? "EGALITE !" : "FIN DE PARTIE", prompt.c_str());

  if (any && count == 1) {
    mp3.playGoodAnswer();            // son de victoire
  }
}

PhaseMode Buzzer::endGame(char pressedKey) {
  if (endTie) {
    if (pressedKey == '#') {         // lancer le bris d'égalité
      enterTiebreak();
      return WAITING_BUZZER;
    }
    if (pressedKey == '*') {         // accepter l'égalité
      resetLights();
      return CONFIGURATION;
    }
    return END_GAME;
  }

  if (pressedKey == '#') {
    resetLights();
    return CONFIGURATION;
  }
  return END_GAME;
}

void Buzzer::enterTiebreak() {
  // Meilleur score parmi les présents.
  int best = 0;
  bool any = false;
  for (int i = 0; i < 4; i++) {
    if (enabled[i] && (!any || scores[i] > best)) {
      best = scores[i];
      any = true;
    }
  }
  // Seuls les ex æquo peuvent buzzer (les autres restent présents mais neutralisés).
  for (int i = 0; i < 4; i++) {
    actives[i] = (enabled[i] && scores[i] == best);
  }
  tiebreak = true;
}

void Buzzer::resetConfigState() {
  for (int i = 0; i < 4; i++) {
    enabled[i] = true;
    prevPressed[i] = false;
  }
}

void Buzzer::setEnabled(int buzzerId, bool value) {
  enabled[buzzerId] = value;
}

bool Buzzer::isEnabled(int buzzerId) {
  return enabled[buzzerId];
}

bool Buzzer::wasPressed(int buzzerId) {
  bool pressedNow = (digitalRead(buzzers[buzzerId][1]) == LOW);
  bool edge = pressedNow && !prevPressed[buzzerId];
  prevPressed[buzzerId] = pressedNow;
  return edge;
}

void Buzzer::setLed(int buzzerId, bool on) {
  digitalWrite(buzzers[buzzerId][0], on ? HIGH : LOW);
}

