#include "AppKeypad.h"
#include "PhaseMode.h"

// La librairie Keypad debounce a 10 ms par defaut : trop court pour un
// clavier membrane bon marche, ce qui peut faire lire une touche deux fois
// pour un seul appui (ex. "2" pour regler le nombre de questions compte pour
// 2 incrementations au lieu d'une). 25 ms filtre ce rebond sans ajouter de
// latence perceptible.
AppKeypad::AppKeypad() {
  customKeypad.setDebounceTime(25);
}

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