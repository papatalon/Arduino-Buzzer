#ifndef CONFIGURATION_H
#define CONFIGURATION_H

#include "LcdDisplay.h"
#include "PhaseMode.h"
#include "Mp3.h"
#include "Buzzer.h"

class Configuration {
public:
    void init();
    PhaseMode manageConfiguration(char pressedKey);
    void setShuffleBuzzers();
    PhaseMode shuffleBuzzer(char pressedKey);
    void setBuzzerConfig();
    PhaseMode buzzerConfig(char pressedKey);
    void setVolumeScreen();
    PhaseMode volumeScreen(char pressedKey);

private:

  // Étapes de l'assistant de configuration d'un buzzer.
  enum CfgStep { CFG_PROMPT, CFG_CHOOSING };

  // Étapes de l'écran "Sons aléatoires" (confirmation avant d'écraser).
  enum ShufStep { SHUF_CONFIRM, SHUF_DONE };

  int cfgIndex = 0;          // buzzer en cours de configuration (0..3)
  CfgStep cfgStep = CFG_PROMPT;
  ShufStep shufStep = SHUF_CONFIRM;

  void showConfigPrompt();
  void showConfigChoice();
  PhaseMode advanceConfig();
  const char* colorName(int i);

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
};

#endif
