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
      previousMillis = millis();

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
  display.setText("     EN ATTENTE", 0);
  display.setText("    D'UNE REPONSE", 1);
  display.setText("C = terminer la partie", 3);
}

void Buzzer::setBuzzerPressed() {
    display.clear();
    display.setText("  BIP!!!!!", 0);
    display.setText("A: Bonne réponse", 1);
    display.setText("D: Mauvaise réponse", 2);
    int ledPin = buzzers[currentBuzzerId][0];
    //Buzzer:blink();
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

  mp3.playGoodAnswer();
  digitalWrite(ledPin, LOW);

  Buzzer:blink();
  Buzzer::resetAllBuzzers();
}

void Buzzer::badAnswer() {
  int ledPin = buzzers[currentBuzzerId][0];

  if (penaltyMode) {
    scores[currentBuzzerId]--;      // mode Pénalité : -1 (peut être négatif)
  }

  mp3.playBadAnswer();

  actives[currentBuzzerId] = false;
  digitalWrite(ledPin, LOW);
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
}

void Buzzer::displayScores(const char* title, const char* prompt) {
  display.clear();
  display.setText(title, 0);
  display.setText(String(colorName(0)) + ":" + scores[0] + "   " + colorName(1) + ":" + scores[1], 1);
  display.setText(String(colorName(2)) + ":" + scores[2] + "   " + colorName(3) + ":" + scores[3], 2);
  display.setText(prompt, 3);
}

void Buzzer::setShowScores() {
  scoresShownAt = millis();
  displayScores("      SCORES", "# = question suivante");
}

PhaseMode Buzzer::showScores(char pressedKey) {
  if (pressedKey == 'C') {
    return END_GAME;                 // terminer la partie depuis l'écran scores
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

  display.clear();
  display.setText("FIN DE PARTIE", 0);
  display.setText(String(colorName(0)) + ":" + scores[0] + "   " + colorName(1) + ":" + scores[1], 1);
  display.setText(String(colorName(2)) + ":" + scores[2] + "   " + colorName(3) + ":" + scores[3], 2);

  if (!any) {
    display.setText("Aucun buzzer  #=menu", 3);
  } else if (count > 1) {
    display.setText(String("EGALITE (") + best + " pts)  #=menu", 3);
  } else {
    display.setText(String("Gagnant: ") + colorName(winner) + "  #=menu", 3);
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

void Buzzer::initMp3Index() {
  for(int i = 0; i < 4; i++) {
    buzzers[currentBuzzerId][2] = -1;
  }
}

void Buzzer::endConfiguration() {
  // Array to track used values
  // int buzzerSoundCount = mp3.getBuzzerSoundCount();

  // bool usedValues[buzzerSoundCount] = {}; // Index 0 to 10, where 0 will not be used


  // // Mark existing values as used
  // for (int i = 0; i < 4; i++) {
  //   int soundIndex = buzzers[i][2];
  //   if (soundIndex != -1) {
  //     usedValues[soundIndex] = true;
  //   }
  // }

  // // Fill in -1 values with unique random numbers between 1 and 10
  // for (int i = 0; i < 4; i++) {
  //   if (buzzers[i][2] == -1) {
  //     int newValue;
  //     do {
  //       newValue = random(0, buzzerSoundCount); // Generate a random number between 1 and 10
  //     } while (usedValues[newValue]); // Repeat if the value is already used

  //     buzzers[i][2] = newValue; // Assign the unique random value
  //     usedValues[newValue] = true; // Mark the value as used
  //   }
  // }
}
