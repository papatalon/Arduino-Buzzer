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

  // Lecteur audio introuvable : on le dit clairement une fois au demarrage
  // (le repere "X" en haut a droite restera ensuite, mais un seul
  // caractere serait cryptique si on ne l'a jamais vu explique).
  if (mp3.isSimulation()) {
    display.clear();
    display.setText("PAS DE LECTEUR AUDIO", 0);
    display.setText("Verifie le DFPlayer", 1);
    display.setText("et la carte SD.", 2);
    display.setText("Repere : X en haut", 3);
    delay(3000);
  }
  display.setAudioWarning(mp3.isSimulation());

  // 2. La chanson d'intro démarre : l'écran passe à l'égaliseur (mode BOOT).
  //    Le menu s'affichera à la fin de la musique (voir Buzzer::boot).
  mp3.playInit();         // son d'intro au démarrage (dossier 01)
  buzzer.setBoot();
}

void loop() {
  display.updateScrolling();

  // Detecte le moment precis ou l'app prend le controle (front montant de
  // appInControl) : elle vient peut-etre de se (re)connecter alors que le
  // Mega est deja assis sur sa phase courante depuis un moment, sans
  // transition recente pour l'annoncer - STATE/GAME ne sont envoyes qu'aux
  // transitions, donc l'app resterait autrement aveugle jusqu'a la
  // prochaine. On la resynchronise immediatement ici.
  static bool wasInControl = false;
  bool inControl = BleLink::shared().appInControl();
  if (inControl && !wasInControl) {
    BleLink::shared().send("STATE|" + String((int)currentMode));
    BleLink::shared().send("GAME|" + String((int)buzzer.getGameMode()));
    // Etat du lecteur audio : sans ca, impossible de distinguer "pas de
    // son parce que le volume est bas" de "pas de son parce que le
    // DFPlayer n'a pas ete detecte au demarrage" (mode simulation, voir
    // Mp3::isSimulation). Envoye ici plutot qu'au boot : au demarrage,
    // aucune app n'est encore connectee pour le recevoir.
    BleLink::shared().send(String("AUDIO|") + (mp3.isSimulation() ? "0" : "1")
                           + "|" + String(mp3.getVolume()));
    mp3.sendAllSoundAssignments();
    // Question en cours : QUESTION n'est envoye qu'au tirage, donc une app
    // qui se (re)connecte en pleine partie afficherait une question vide.
    // Type distinct (QSYNC) et non QUESTION : cote app, QUESTION compte une
    // question de plus et efface le dernier buzz - ce qui fausserait le
    // compteur et l'etat "untel s'est trompe" a chaque reconnexion.
    QuestionBank& bank = QuestionBank::shared();
    if (bank.isActive() && bank.questionText().length() > 0) {
      BleLink::shared().send("QSYNC|" + bank.questionCategory() + "|"
                             + bank.questionText() + "|" + bank.answerText());
    }
  }
  wasInControl = inControl;

  currentMode = getCurrentMode();
  updateMode();
  // Ecran fige sur l'ASCII art "controle par l'app" tant que le controle est
  // actif (voir LcdDisplay::setControlOverride) - appele apres updateMode()
  // pour toujours avoir le dernier mot sur ce que la phase courante vient
  // de dessiner.
  display.setControlOverride(inControl);
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

  // Commande App->Mega SELECT_GAME|<n> (voir BleLink::consumeGameSelect) :
  // une vraie commande, pas une simulation de touche - fonctionne peu
  // importe la phase courante (l'app n'est pas soumise a la contrainte
  // sequentielle du clavier physique, contrairement au menu GAME_CHOICE).
  int gameSelect = BleLink::shared().consumeGameSelect();
  if (gameSelect >= 0) {
    return configuration.selectGameIndex(gameSelect);
  }

  // Configuration des sons du DFPlayer pilotee depuis l'app : reproduit ce
  // que fait l'assistant du clavier, qui est verrouille tant que l'app a le
  // controle. N'affecte que l'etat du son, jamais la phase de jeu - on ne
  // court-circuite donc pas le switch, contrairement a SELECT_GAME.
  char soundCmd = BleLink::shared().consumeSoundCommand();
  if (soundCmd != 0) {
    int who = BleLink::shared().soundCommandBuzzer();
    switch (soundCmd) {
      case 'S':
        mp3.shuffleBuzzers();
        mp3.sendAllSoundAssignments();
        break;
      case 'N':
        mp3.cycleSound(who);
        mp3.sendAllSoundAssignments();
        mp3.playBuzzer(who);      // on entend tout de suite le nouveau
        break;
      case 'P':
        mp3.cyclePrevSound(who);
        mp3.sendAllSoundAssignments();
        mp3.playBuzzer(who);
        break;
      case 'E':
        mp3.playBuzzer(who);
        break;
    }
  }

  // Commande App->Mega SET_PRESENT|<masque> : declarer un buzzer absent pour
  // jouer a deux ou a trois. L'assistant du clavier ("A") ne peut pas rendre
  // ce service a l'app - il exige un appui PHYSIQUE sur chaque buzzer
  // present, et le clavier est verrouille de toute facon. Comme la config
  // des sons, ca ne touche pas la phase : on ne court-circuite pas le switch.
  int presenceMask = BleLink::shared().consumePresenceMask();
  if (presenceMask >= 0) {
    buzzer.setPresenceMask(presenceMask);
  }

  // Commande App->Mega SET_CATS|<mask> (voir BleLink::consumeCategoryMask) :
  // contrairement a SELECT_GAME, cette commande termine une etape precise
  // (choix des categories) et n'a de sens que dans son propre ecran - gardee
  // par la phase courante, pas une navigation libre.
  int catMask = BleLink::shared().consumeCategoryMask();
  if (catMask >= 0 && currentMode == QUIZ_CATS) {
    return configuration.confirmCategories(catMask);
  }

  // Quand l'app a pris le controle (voir BleLink::appInControl), elle a
  // 100% la main : le clavier physique est ignore (hors reset/test cable
  // ci-dessus, qui restent une echappatoire de securite dans tous les cas).
  // Sinon, comportement inchange : la touche physique est prioritaire, une
  // commande BLE ne joue que si aucune touche n'a ete pressee ce tour-ci.
  char pressedKey;
  if (BleLink::shared().appInControl()) {
    pressedKey = bleKey;
  } else {
    pressedKey = (physicalKey != NO_KEY) ? physicalKey : bleKey;
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

