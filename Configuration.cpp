#include "Configuration.h"

void Configuration::init() {
  display.clear();
  display.setText("    CONFIGURATION", 0);
  display.setText("A: Configurer les sons des buzzers", 1);
  display.setText("B: Sons aléatoires", 2);
  display.setText("#: Démarrer la partie", 3);
}

PhaseMode Configuration::manageConfiguration(char pressedKey) {

  if(!pressedKey) {
    return CONFIGURATION;
  }

  switch(pressedKey) {
    case 'A':
      return BUZZER_CONFIG;
    case 'B':
      return SHUFFLE_BUZZER;
    case '#':
      return WAITING_BUZZER;
  }

  return CONFIGURATION;
}

void Configuration::setShuffleBuzzers() {

  mp3.shuffleBuzzers();

  display.clear();
  display.setText("    CONFIGURATION", 0);
  display.setText("Les sons ont été changés aléatoirement", 1);
  display.setText("#: Retourner au menu", 3);
}

PhaseMode Configuration::shuffleBuzzer(char pressedKey) {
  if(!pressedKey) {
    return SHUFFLE_BUZZER;
  }

  switch(pressedKey) {
    case '#':
      return CONFIGURATION;
  }

  return SHUFFLE_BUZZER;
}

void Configuration::setBuzzerConfig() {
  buzzer.initMp3Index();

  display.clear();
  display.setText("    CONFIGURATION", 0);
  display.setText("Appuyez sur un buzzer pour le configurer", 1);
  display.setText("#: Retourner au menu", 3);

}

 PhaseMode Configuration::buzzerConfig(char pressedKey) {
  switch(pressedKey) {
    case '#': 
      buzzer.endConfiguration();
      return CONFIGURATION;
  }

  return BUZZER_CONFIG;
 }