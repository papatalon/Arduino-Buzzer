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

private:
  Buzzer(const Buzzer&) = delete;
  Buzzer& operator=(const Buzzer&) = delete;
    
  // Initialisation du buzzer
  // Array 0:  Buzzer
  // Array 1:  { Pin Led, Pin Button}
  int buzzers[4][3] = {
    {7, 6, 0}, //Rouge
    {9, 8, 1}, //Bleu
    {11, 10, 2}, //Jaune
    {13, 12, 3} // Vert
  };

  bool actives[4] = { true, true, true, true};

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