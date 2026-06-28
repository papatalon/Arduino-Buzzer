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

private:

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
};

#endif