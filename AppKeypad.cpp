#include "AppKeypad.h"
#include "PhaseMode.h"

AppKeypad::AppKeypad() {}

// === Required for Singletons ===
// Define the single instance as a static member
AppKeypad& AppKeypad::shared() {
  static AppKeypad instance;
  return instance;
}

char AppKeypad::getKey() {
  return customKeypad.getKey();
}


bool AppKeypad::isResetActivated(char pressedKey) {

  if(pressedKey && pressedKey == '*') {
    unsigned long currentMillis = millis();
    if(previousKey == '*' && currentMillis - previousMillis < 400) {
      return true;
    } else  {
      previousKey = pressedKey;
      previousMillis = currentMillis;
    }
  }

  return false;
}

// Mode cache de test cablage : la sequence '*' puis '1' (dans les 400 ms)
// bascule vers LED_TEST. Le '*' initial a deja arme previousKey/previousMillis
// via isResetActivated(), appele juste avant.
bool AppKeypad::isLedTestActivated(char pressedKey) {

  if(pressedKey && pressedKey == '1') {
    unsigned long currentMillis = millis();
    if(previousKey == '*' && currentMillis - previousMillis < 400) {
      previousKey = ' ';          // consomme la sequence
      return true;
    }
  }

  return false;
}