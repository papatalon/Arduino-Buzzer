// #include "DisplayManager.h"
//#include "OledDisplay.h"
#include "LcdDisplay.h"
#include "Configuration.h"
#include "PhaseMode.h"
#include "AppKeypad.h"
#include "Buzzer.h"
#include "Simon.h"
#include "Mp3.h"
#include "QuestionBank.h"

PhaseMode currentMode = BOOT;
PhaseMode previousMode = BOOT;

// Create an instance of DisplayManager
// DisplayManager& displayManager = DisplayManager::shared();
AppKeypad& appKeypad = AppKeypad::shared(); 
Configuration configuration;
Simon simon;
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

  // Amorce le générateur aléatoire avant tout tirage (message de démarrage,
  // sons des buzzers...). A0 est laissée flottante : sa lecture est du bruit.
  randomSeed(analogRead(0));

  if(!display.init()) {
    Serial.println("INIT FAIL");
  }

  buzzer.init();
  QuestionBank::shared().init();   // compte les questions de chaque categorie

  // 1. Message rigolo + points animés pendant l'init (bloquante) du DFPlayer.
  buzzer.showBootScreen();
  mp3.init(bootTick);

  // 2. La chanson d'intro démarre : l'écran passe à l'égaliseur (mode BOOT).
  //    Le menu s'affichera à la fin de la musique (voir Buzzer::boot).
  mp3.playInit();         // son d'intro au démarrage (dossier 01)
  buzzer.setBoot();
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
    case BOOT:
      mode = buzzer.boot(pressedKey);
      break;
    case CONFIGURATION:
      mode = configuration.manageConfiguration(pressedKey);
      break;
    case GAME_CHOICE:
      mode = configuration.gameChoice(pressedKey);
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
      } else if (pressedKey == 'D') {
        buzzer.startBuzzTimer();        // "top" : lance le chrono de buzz
        mode = buzzer.waitingBuzzerIsPressed(currentMode);
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
    case CHRONO:
      mode = configuration.chronoScreen(pressedKey);
      break;
    case QUIZ_CATS:
      mode = configuration.quizCats(pressedKey);
      break;
    case QUIZ_COUNT:
      mode = configuration.quizCount(pressedKey);
      break;
    case VOL_SPIN:
      mode = buzzer.volSpin(pressedKey);
      break;
    case SIMON_SHOW:
      mode = simon.showSequence(pressedKey);
      break;
    case SIMON_PLAY:
      mode = simon.playSequence(pressedKey);
      break;
    case SIMON_OVER:
      mode = simon.gameOver(pressedKey);
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
    case BOOT:
      buzzer.setBoot();
      break;
    case CONFIGURATION:
      configuration.init();
      break;
    case GAME_CHOICE:
      configuration.setGameChoice();
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
      simon.reset();      // nouvelle partie : sequence Simon repartie de zero
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
    case CHRONO:
      configuration.setChronoScreen();
      break;
    case QUIZ_CATS:
      configuration.setQuizCats();
      break;
    case QUIZ_COUNT:
      configuration.setQuizCount();
      break;
    case VOL_SPIN:
      buzzer.setVolSpin();
      break;
    case SIMON_SHOW:
      simon.setShowSequence();
      break;
    case SIMON_PLAY:
      simon.setPlaySequence();
      break;
    case SIMON_OVER:
      simon.setGameOver();
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

