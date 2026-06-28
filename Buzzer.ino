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

void setup() {
  Serial.begin(9600);

  if(!display.init()) {
    Serial.println("INIT FAIL");
  }

  buzzer.init();
  configuration.init();
  mp3.init();
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
    case WAITING_BUZZER:
      mode = buzzer.waitingBuzzerIsPressed(currentMode);
      break;
    case BUZZER_PRESSED:
      mode = buzzer.buzzerIsPressed(currentMode, pressedKey);
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
    case WAITING_BUZZER:
      buzzer.setWaitingForBuzzer();
      break;
    case BUZZER_PRESSED:
      buzzer.setBuzzerPressed();
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

