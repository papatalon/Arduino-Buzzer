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

PhaseMode Buzzer::waitingBuzzerIsPressed(PhaseMode currentMode) {

  for (int i = 0; i < 4; i++) {
    int buttonPin = buzzers[i][1];
    if (enabled[i] && actives[i] && digitalRead(buttonPin) == LOW) { // Button pressed
      currentBuzzerId = i;

      int ledPin = buzzers[currentBuzzerId][0];
      digitalWrite(ledPin, HIGH);

      mp3.playBuzzer(currentBuzzerId);

      return BUZZER_PRESSED;
    }
  }

  return currentMode;
}

void Buzzer::setWaitingForBuzzer() {
  display.clear();
  display.setText("    EN ATTENTE", 0);
  display.setText("   D'UNE REPONSE", 1);
  // "B:corriger" n'a de sens que si une décision a déjà été prise.
  if (lastJudgedBuzzer >= 0) {
    display.setText("B:corriger   C:fin", 3);
  } else {
    display.setText("C: terminer", 3);
  }
}

void Buzzer::setBuzzerPressed() {
    display.clear();
    display.setText(String("BIP ! -> ") + colorName(currentBuzzerId), 0);
    display.setText("A: Bonne reponse", 1);
    display.setText("D: Mauvaise reponse", 2);
    int ledPin = buzzers[currentBuzzerId][0];
    digitalWrite(ledPin, HIGH);
}

PhaseMode Buzzer::buzzerIsPressed(PhaseMode currentMode, char pressedKey) {

  switch (pressedKey) {
    case 'A':
      Buzzer::goodAnswer();
      return SHOW_SCORES;       // fin de question -> écran des scores
    case 'D':
      Buzzer::badAnswer();
      return WAITING_BUZZER;    // même question, les autres peuvent répondre
      break;
    default:
      return currentMode;
  };


  return currentMode;
}

void Buzzer::goodAnswer() {
  int ledPin = buzzers[currentBuzzerId][0];

  scores[currentBuzzerId]++;        // bonne réponse : +1
  lastJudgedBuzzer = currentBuzzerId;
  lastWasGood = true;

  mp3.playGoodAnswer();
  digitalWrite(ledPin, LOW);

  blink();
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

void Buzzer::blink() {
  int ledPin = buzzers[currentBuzzerId][0];
  int delayTime = 100;

  // Blink the LED 5 times
  for (int i = 0; i < 10; i++) {
    digitalWrite(ledPin, HIGH); // Turn the LED on
    delay(delayTime);        // Wait for the specified delay time
    digitalWrite(ledPin, LOW);  // Turn the LED off
    delay(delayTime);        // Wait for the specified delay time
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
    return END_GAME;                 // terminer la partie depuis l'écran scores
  }
  if (pressedKey == 'B') {
    return correctLastDecision(SHOW_SCORES);  // corriger la dernière décision
  }
  if (pressedKey == '#') {
    return WAITING_BUZZER;           // passer tout de suite à la question suivante
  }
  if (millis() - scoresShownAt >= SCORES_DISPLAY_MS) {
    return WAITING_BUZZER;           // au bout de 15 s, question suivante
  }
  return SHOW_SCORES;
}

void Buzzer::setEndGame() {
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

  String prompt;
  if (!any) {
    prompt = "Aucun buzzer #menu";
  } else if (count > 1) {
    prompt = String("EGALITE ") + best + "pts #menu";
  } else {
    prompt = String("Gagne:") + colorName(winner) + " #menu";
  }

  displayScores("FIN DE PARTIE", prompt.c_str());

  if (any && count == 1) {
    mp3.playGoodAnswer();            // son de victoire
  }
}

PhaseMode Buzzer::endGame(char pressedKey) {
  if (pressedKey == '#') {
    resetLights();
    return CONFIGURATION;
  }
  return END_GAME;
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

