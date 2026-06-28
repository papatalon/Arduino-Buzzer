#ifndef BUZZER_H
#define BUZZER_H

#include "PhaseMode.h"
#include "LcdDisplay.h"
#include <Arduino.h>
#include "Mp3.h";

class Buzzer {
public:

    Buzzer();

    static Buzzer& shared();

    void init();
    void resetLights();

    void setWaitingForBuzzer();
    PhaseMode waitingBuzzerIsPressed(PhaseMode currentMode);

    void setBuzzerPressed();
    PhaseMode buzzerIsPressed(PhaseMode currentMode, char pressedKey);

    void initMp3Index();
    void endConfiguration();

    // Assistant de configuration
    void resetConfigState();                 // ré-active tout, remet l'anti-rebond
    void setEnabled(int buzzerId, bool value);
    bool isEnabled(int buzzerId);
    bool wasPressed(int buzzerId);           // front montant d'un appui (anti-rebond)
    void setLed(int buzzerId, bool on);

private:
  Buzzer(const Buzzer&) = delete;
  Buzzer& operator=(const Buzzer&) = delete;

  // Initialisation du buzzer
  // Array 0:  Buzzer
  // Array 1:  { Pin Led, Pin Button}
  int buzzers[4][3] = {
    {6, 5, 0}, //Rouge
    {8, 7, 1}, //Bleu
    {10, 9, 2}, //Jaune
    {12, 11, 3} // Vert
  };

  bool actives[4] = { true, true, true, true};

  // Buzzer présent / dans le pool (déclaré via l'assistant de configuration).
  bool enabled[4] = { true, true, true, true};
  // État précédent du bouton, pour l'anti-rebond pendant la configuration.
  bool prevPressed[4] = { false, false, false, false};

  int currentBuzzerId;
  unsigned long previousMillis = 0;

  void goodAnswer();
  void badAnswer();
  void resetAllBuzzers();
  void blink();

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
};

#endif
