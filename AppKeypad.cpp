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

// Mode cache de test cablage : la sequence '*' puis '1' (dans les 2 s)
// bascule vers LED_TEST. Le '*' initial a deja arme previousKey/previousMillis
// via isResetActivated(), appele juste avant. Fenetre volontairement large
// (2 s) car on enchaine deux touches differentes, plus lent qu'un double-tap.
bool AppKeypad::isLedTestActivated(char pressedKey) {

  if(pressedKey && pressedKey == '1') {
    unsigned long currentMillis = millis();
    if(previousKey == '*' && currentMillis - previousMillis < 2000) {
      previousKey = ' ';          // consomme la sequence
      Serial.println(F("[MODE] Entree dans LED_TEST (sequence *1)."));
      return true;
    }
  }

  return false;
}