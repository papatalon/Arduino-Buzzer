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
    if (actives[i] && digitalRead(buttonPin) == LOW) { // Button pressed
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
      return WAITING_BUZZER;
    case 'D':
      Buzzer::badAnswer();
      return WAITING_BUZZER;
      break;
    default:
      return currentMode;
  };


  return currentMode;
}

void Buzzer::goodAnswer() {
  int ledPin = buzzers[currentBuzzerId][0];

  mp3.playGoodAnswer();
  digitalWrite(ledPin, LOW);

  Buzzer:blink();
  Buzzer::resetAllBuzzers();
}

void Buzzer::badAnswer() {
  int ledPin = buzzers[currentBuzzerId][0];

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
