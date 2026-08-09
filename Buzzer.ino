// #include "DisplayManager.h"
//#include "OledDisplay.h"
#include "LcdDisplay.h"
#include "Configuration.h"
#include "PhaseMode.h"
#include "AppKeypad.h"
#include "Buzzer.h"
#include "Mp3.h"

PhaseMode currentMode = CONFIGURATION;
PhaseMode previousMode = CONFIGURATION;

// Create an instance of DisplayManager
// DisplayManager& displayManager = DisplayManager::shared();
AppKeypad& appKeypad = AppKeypad::shared(); 
Configuration configuration;
Buzzer& buzzer = Buzzer::shared();
//OledDisplay& display = OledDisplay::shared();
Mp3& mp3 = Mp3::shared();
LcdDisplay& display = LcdDisplay::shared();

// Wrapper libre passé à mp3.init() : anime l'écran + les LED pendant les
// attentes de démarrage du DFPlayer (impossible de passer une méthode membre
// directement comme pointeur de fonction C).
void bootTick() {
  buzzer.bootTick();
}

void setup() {
  Serial.begin(9600);

  if(!display.init()) {
    Serial.println("INIT FAIL");
  }

  buzzer.init();

  // Animation de démarrage pendant l'initialisation (bloquante) du DFPlayer.
  buzzer.showBootScreen();
  mp3.init(bootTick);
  buzzer.resetLights();   // fin de l'animation : on éteint les LED

  configuration.init();   // le menu s'affiche une fois tout prêt
  mp3.playInit();         // son d'intro au démarrage (dossier 01)
}

void loop() {
  display.updateScrolling();
  currentMode = getCurrentMode();
  updateMode();
}

PhaseMode getCurrentMode() {
  PhaseMode mode = currentMode;

  char pressedKey = appKeypad.getKey();

  if(appKeypad.isResetActivated(pressedKey)) {
    return RESET;
  }

  // Mode cache de test cablage : accessible uniquement depuis la CONFIGURATION
  // (evite une entree accidentelle en pleine partie).
  if(currentMode == CONFIGURATION && appKeypad.isLedTestActivated(pressedKey)) {
    return LED_TEST;   // mode cache de test cablage (LED + boutons)
  }

  switch (currentMode) {
    case CONFIGURATION:
      mode = configuration.manageConfiguration(pressedKey);
      break;
    case SHUFFLE_BUZZER:
      mode = configuration.shuffleBuzzer(pressedKey);
      break;
    case BUZZER_CONFIG:
      mode = configuration.buzzerConfig(pressedKey);
      break;
    case RESET:
      mode = reset();
      break;
    case INTRO:
      mode = buzzer.intro(pressedKey);
      break;
    case WAITING_BUZZER:
      if (pressedKey == 'C') {
        mode = END_CONFIRM;              // demander confirmation avant de terminer
      } else if (pressedKey == 'B') {
        mode = buzzer.correctLastDecision(currentMode);  // corriger la derniere decision
      } else if (pressedKey == '0') {
        buzzer.skipQuestion();          // passer la question (personne ne marque)
        mode = SHOW_SCORES;             // montre les scores avant la suivante
      } else if (pressedKey == '#') {
        mp3.playWaiting();              // son d'ambiance : la reponse se fait attendre
        mode = buzzer.waitingBuzzerIsPressed(currentMode);
      } else {
        mode = buzzer.waitingBuzzerIsPressed(currentMode);
      }
      break;
    case BUZZER_PRESSED:
      mode = buzzer.buzzerIsPressed(currentMode, pressedKey);
      break;
    case SHOW_SCORES:
      mode = buzzer.showScores(pressedKey);
      break;
    case END_CONFIRM:
      mode = buzzer.endConfirm(pressedKey);
      break;
    case END_GAME:
      mode = buzzer.endGame(pressedKey);
      break;
    case VOLUME:
      mode = configuration.volumeScreen(pressedKey);
      break;
    case LED_TEST:
      mode = buzzer.ledTest(pressedKey);
      break;
  }

  return mode;
}

void updateMode() {
  if(currentMode == previousMode) {
    return;
  }

  previousMode = currentMode;
  switch (currentMode) {
    case CONFIGURATION:
      configuration.init();
      break;
    case SHUFFLE_BUZZER:
      configuration.setShuffleBuzzers();
      break;
    case BUZZER_CONFIG:
      configuration.setBuzzerConfig();
      break;
    case RESET:
      setReset();
      break;
    case INTRO:
      buzzer.setIntro();
      break;
    case WAITING_BUZZER:
      buzzer.setWaitingForBuzzer();
      break;
    case BUZZER_PRESSED:
      buzzer.setBuzzerPressed();
      break;
    case SHOW_SCORES:
      buzzer.setShowScores();
      break;
    case END_CONFIRM:
      buzzer.setEndConfirm();
      break;
    case END_GAME:
      buzzer.setEndGame();
      break;
    case VOLUME:
      configuration.setVolumeScreen();
      break;
    case LED_TEST:
      buzzer.setLedTest();
      break;
  }
}

void setReset() {
  // displayManager.setMessages("Reinitialisation...", "");
}

PhaseMode reset() {
  buzzer.resetLights();
  return CONFIGURATION;
}

