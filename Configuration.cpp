#include "Configuration.h"

void Configuration::init() {
  display.clear();
  display.setText(String("MENU  Mode: ") + (buzzer.isPenaltyMode() ? "Penalite" : "Classique"), 0);
  display.setText("A: Configurer les sons   B: Sons aleatoires", 1);
  display.setText("C: Changer de mode", 2);
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
    case 'C':
      buzzer.togglePenaltyMode();   // bascule Classique <-> Pénalité
      init();                       // redessine le menu avec le nouveau mode
      return CONFIGURATION;
    case '#':
      buzzer.resetScores();         // nouvelle partie : scores remis à zéro
      return WAITING_BUZZER;
  }

  return CONFIGURATION;
}

void Configuration::setShuffleBuzzers() {
  // On NE mélange pas encore : on demande confirmation pour éviter
  // d'écraser une configuration faite via l'assistant.
  shufStep = SHUF_CONFIRM;
  display.clear();
  display.setText("SONS ALEATOIRES", 0);
  display.setText("Ecrase les sons configures", 1);
  display.setText("# = confirmer", 2);
  display.setText("* = annuler", 3);
}

PhaseMode Configuration::shuffleBuzzer(char pressedKey) {
  if (shufStep == SHUF_CONFIRM) {
    if (pressedKey == '*') {
      return CONFIGURATION;          // annulé : aucun son modifié
    }
    if (pressedKey == '#') {
      mp3.shuffleBuzzers();          // confirmé : on re-tire les sons
      shufStep = SHUF_DONE;
      display.clear();
      display.setText("Sons changes", 0);
      display.setText("aleatoirement", 1);
      display.setText("# = retour au menu", 3);
    }
    return SHUFFLE_BUZZER;
  }

  // SHUF_DONE
  if (pressedKey == '#') {
    return CONFIGURATION;
  }
  return SHUFFLE_BUZZER;
}

const char* Configuration::colorName(int i) {
  switch (i) {
    case 0: return "Rouge";
    case 1: return "Bleu";
    case 2: return "Jaune";
    case 3: return "Vert";
    default: return "?";
  }
}

void Configuration::showConfigPrompt() {
  display.clear();
  display.setText("CONFIG BUZZER", 0);
  display.setText(String(colorName(cfgIndex)) + " : appuyez sur le buzzer", 1);
  display.setText("* = passer (absent)", 2);
  display.setText("# = terminer", 3);
}

void Configuration::showConfigChoice() {
  display.clear();
  display.setText(String(colorName(cfgIndex)) + " - son " + String(mp3.getSound(cfgIndex) + 1), 0);
  display.setText("A = valider", 1);
  display.setText("B = autre son", 2);
  display.setText("* = passer (absent)", 3);
}

PhaseMode Configuration::advanceConfig() {
  cfgIndex++;
  if (cfgIndex >= 4) {
    buzzer.resetLights();
    return CONFIGURATION; // tous les buzzers traités -> retour au menu
  }
  cfgStep = CFG_PROMPT;
  showConfigPrompt();
  return BUZZER_CONFIG;
}

void Configuration::setBuzzerConfig() {
  mp3.resetConfig();         // déverrouille tous les sons
  buzzer.resetConfigState(); // ré-active tous les buzzers + anti-rebond
  buzzer.resetLights();
  cfgIndex = 0;
  cfgStep = CFG_PROMPT;
  showConfigPrompt();
}

PhaseMode Configuration::buzzerConfig(char pressedKey) {
  // Lecture du bouton physique à chaque tick (front montant anti-rebond).
  bool pressed = buzzer.wasPressed(cfgIndex);

  // Sortie de l'assistant à tout moment.
  if (pressedKey == '#') {
    buzzer.resetLights();
    return CONFIGURATION;
  }

  if (cfgStep == CFG_PROMPT) {
    if (pressedKey == '*') {            // buzzer absent
      buzzer.setEnabled(cfgIndex, false);
      return advanceConfig();
    }
    if (pressed) {                      // buzzer présent : on joue son son
      buzzer.setEnabled(cfgIndex, true);
      mp3.ensureUnlockedSound(cfgIndex);
      buzzer.setLed(cfgIndex, true);
      mp3.playBuzzer(cfgIndex);
      cfgStep = CFG_CHOOSING;
      showConfigChoice();
    }
    return BUZZER_CONFIG;
  }

  // CFG_CHOOSING
  if (pressedKey == 'B') {              // essayer un autre son
    mp3.cycleSound(cfgIndex);
    mp3.playBuzzer(cfgIndex);
    showConfigChoice();
  } else if (pressedKey == 'A') {       // valider et verrouiller
    mp3.lockSound(cfgIndex);
    buzzer.setLed(cfgIndex, false);
    return advanceConfig();
  } else if (pressedKey == '*') {       // finalement absent
    buzzer.setEnabled(cfgIndex, false);
    buzzer.setLed(cfgIndex, false);
    return advanceConfig();
  } else if (pressed) {                 // ré-appui : rejoue le son courant
    mp3.playBuzzer(cfgIndex);
  }

  return BUZZER_CONFIG;
}