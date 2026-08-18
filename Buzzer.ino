// #include "DisplayManager.h"
//#include "OledDisplay.h"
#include "LcdDisplay.h"
#include "Configuration.h"
#include "PhaseMode.h"
#include "AppKeypad.h"
#include "Buzzer.h"
#include "Simon.h"
#include "Reflex.h"
#include "BlindTimer.h"
#include "SoundGame.h"
#include "Duel.h"
#include "Mp3.h"
#include "QuestionBank.h"
#include "BleLink.h"

PhaseMode currentMode = BOOT;
PhaseMode previousMode = BOOT;

// Create an instance of DisplayManager
// DisplayManager& displayManager = DisplayManager::shared();
AppKeypad& appKeypad = AppKeypad::shared(); 
Configuration configuration;
Simon simon;
Reflex reflex;
BlindTimer blindTimer;
SoundGame soundGame;
Duel duel;
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
  BleLink::shared().init();

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

  char physicalKey = appKeypad.getKey();
  // Toujours lu, meme si une touche physique vient d'arriver : sans ca, les
  // octets qui arrivent pendant ce tour resteraient dans le tampon serie de
  // l'AT-09 et deborderaient a la longue.
  char bleKey = BleLink::shared().pollKey();

  // Les sequences cachees (reset, test cablage) restent reservees au clavier
  // physique : une commande BLE ne doit pas pouvoir les declencher, et ne
  // doit pas non plus polluer leur fenetre de detection (previousKey/
  // previousMillis dans AppKeypad), qui n'a de sens que pour de vraies
  // frappes successives.
  if(appKeypad.isResetActivated(physicalKey)) {
    return RESET;
  }

  // Mode cache de test cablage : accessible uniquement depuis la CONFIGURATION
  // (evite une entree accidentelle en pleine partie).
  if(currentMode == CONFIGURATION && appKeypad.isLedTestActivated(physicalKey)) {
    return LED_TEST;   // mode cache de test cablage (LED + boutons)
  }

  // La touche physique est prioritaire ; une commande BLE ne joue que si
  // aucune touche n'a ete pressee ce tour-ci.
  char pressedKey = (physicalKey != NO_KEY) ? physicalKey : bleKey;

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
        mode = buzzer.skipQuestion();   // passer la question -> scores (ou reponse d'abord)
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
    case ANSWER_REVEAL:
      mode = buzzer.answerReveal(pressedKey);
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
    case ROUNDS_SETUP:
      mode = configuration.roundsScreen(pressedKey);
      break;
    case REFLEX_ARM:
      mode = reflex.arm(pressedKey);
      break;
    case REFLEX_GO:
      mode = reflex.go(pressedKey);
      break;
    case REFLEX_RESULT:
      mode = reflex.result(pressedKey);
      break;
    case REFLEX_OVER:
      mode = reflex.gameOver(pressedKey);
      break;
    case BLIND_ANNOUNCE:
      mode = blindTimer.announce(pressedKey);
      break;
    case BLIND_RUN:
      mode = blindTimer.run(pressedKey);
      break;
    case BLIND_RESULT:
      mode = blindTimer.result(pressedKey);
      break;
    case BLIND_OVER:
      mode = blindTimer.gameOver(pressedKey);
      break;
    case SOUND_SETUP:
      mode = configuration.soundSetup(pressedKey);
      break;
    case SOUND_LEARN:
      mode = soundGame.learn(pressedKey);
      break;
    case SOUND_PLAY:
      mode = soundGame.play(pressedKey);
      break;
    case SOUND_OVER:
      mode = soundGame.gameOver(pressedKey);
      break;
    case DUEL_ARM:
      mode = duel.arm(pressedKey);
      break;
    case DUEL_GO:
      mode = duel.go(pressedKey);
      break;
    case DUEL_RESULT:
      mode = duel.result(pressedKey);
      break;
    case DUEL_OVER:
      mode = duel.gameOver(pressedKey);
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
  BleLink::shared().send("STATE|" + String((int)currentMode));
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
      reflex.reset();     // ... et scores des jeux en manches remis a zero
      blindTimer.reset();
      soundGame.reset();
      duel.reset();
      buzzer.setIntro();
      break;
    case WAITING_BUZZER:
      buzzer.setWaitingForBuzzer();
      break;
    case BUZZER_PRESSED:
      buzzer.setBuzzerPressed();
      break;
    case ANSWER_REVEAL:
      buzzer.setAnswerReveal();
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
    case ROUNDS_SETUP:
      configuration.setRoundsScreen();
      break;
    case REFLEX_ARM:
      reflex.setArm();
      break;
    case REFLEX_GO:
      reflex.setGo();
      break;
    case REFLEX_RESULT:
      reflex.setResult();
      break;
    case REFLEX_OVER:
      reflex.setGameOver();
      break;
    case BLIND_ANNOUNCE:
      blindTimer.setAnnounce();
      break;
    case BLIND_RUN:
      blindTimer.setRun();
      break;
    case BLIND_RESULT:
      blindTimer.setResult();
      break;
    case BLIND_OVER:
      blindTimer.setGameOver();
      break;
    case SOUND_SETUP:
      configuration.setSoundSetup();
      break;
    case SOUND_LEARN:
      soundGame.setLearn();
      break;
    case SOUND_PLAY:
      soundGame.setPlay();
      break;
    case SOUND_OVER:
      soundGame.setGameOver();
      break;
    case DUEL_ARM:
      duel.setArm();
      break;
    case DUEL_GO:
      duel.setGo();
      break;
    case DUEL_RESULT:
      duel.setResult();
      break;
    case DUEL_OVER:
      duel.setGameOver();
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

