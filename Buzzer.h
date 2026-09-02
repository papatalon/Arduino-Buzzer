#ifndef BUZZER_H
#define BUZZER_H

#include "PhaseMode.h"
#include "GameMode.h"
#include "LcdDisplay.h"
#include <Arduino.h>
#include "Mp3.h";
#include "BleLink.h"

#define SCORES_DISPLAY_MS 15000  // durée d'affichage des scores entre les questions
#define WIN_BLINK_MS 1500        // durée du clignotement de la LED du gagnant
#define INTRO_MS 4000            // durée du chenillard d'intro en simulation (pas de BUSY)
#define INTRO_STEP_MS 120        // vitesse du chenillard (ms par LED)
#define INTRO_START_MS 500       // délai avant de tester BUSY (démarrage du DFPlayer)
#define INTRO_MAX_MS 30000       // durée maxi de sécurité du chenillard d'intro
#define BUTTON_DEBOUNCE_MS 200   // anti-rebond commun a tous les boutons de buzzer
#define BOOT_MESSAGE_COUNT 8     // nombre de messages de demarrage disponibles
#define BOOT_DOT_MS 300          // vitesse des points animes du message de demarrage
#define EQ_FRAME_MS 150          // duree d'une image de l'egaliseur (redessin I2C lent)
#define BUZZ_TIME_MAX 60         // duree maxi reglable du chrono de buzz (secondes)
#define GAME_ROUNDS_MIN 1        // nombre de manches d'une partie : mini
#define GAME_ROUNDS_MAX 20       // ... maxi
#define GAME_ROUNDS_DEFAULT 5    // ... valeur par defaut (avant tout reglage)
#define SOUND_ROUNDS_DEFAULT 12  // ... sauf Ne buzze pas : un flux court serait plat
#define BUZZ_WARN_MS 3000        // les LED clignotent sur les dernieres secondes
#define BUZZ_WARN_BLINK_MS 200   // periode du clignotement de fin de chrono
#define VOL_SPIN_SIM_MS 11000        // duree simulee du tirage (pas de BUSY), calee sur le son
#define VOL_SPIN_STEP_MS_INITIAL 40  // vitesse initiale du chenillard, calee sur le 1er clic du son
#define VOL_SPIN_STEP_MS_MAX 300     // vitesse la plus lente, atteinte en fin d'animation
#define VOL_SPIN_STEP_TAU_MS 3600.0  // constante de ralentissement (voir ledChaseEnabled)

class Buzzer {
public:

    Buzzer();

    static Buzzer& shared();

    void init();
    void resetLights();

    // Démarrage en deux temps :
    //  1. pendant l'initialisation (bloquante) du DFPlayer : message
    //     humoristique tiré au hasard + points animés (showBootScreen/bootTick) ;
    //  2. pendant la chanson d'intro : égaliseur plein écran (setBoot/boot),
    //     puis passage au menu quand la musique est finie.
    void showBootScreen();
    void bootTick();
    void setBoot();
    PhaseMode boot(char pressedKey);

    // Mode cache de test cablage (entree *1) : LED + boutons.
    void setLedTest();                       // entree : allume les 4 LED
    PhaseMode ledTest(char pressedKey);      // touche = tout on/off ; bouton = sa LED

    // Vol : tirage au sort anime du 1er joueur (chenillard + son), avant la
    // 1re question.
    void setVolSpin();
    PhaseMode volSpin(char pressedKey);

    // Animation générique de "tirage au sort" (chenillard qui ralentit +
    // son du dossier 06) : utilisée par volSpin() ci-dessus, et réutilisable
    // ailleurs (ex. menu "Sons au hasard"). startSpinAnimation() lance le
    // chronomètre et le son ; tickSpinAnimation() fait avancer le chenillard
    // et renvoie vrai quand l'animation (le son) est terminée — à appeler à
    // chaque tick tant qu'elle renvoie faux.
    void startSpinAnimation();
    bool tickSpinAnimation();

    void setWaitingForBuzzer();
    PhaseMode waitingBuzzerIsPressed(PhaseMode currentMode);

    void setBuzzerPressed();
    PhaseMode buzzerIsPressed(PhaseMode currentMode, char pressedKey);

    // Question passée sans réponse (banque active) : affiche la réponse
    // avant l'écran des scores, pour que l'animateur la découvre aussi.
    void setAnswerReveal();
    PhaseMode answerReveal(char pressedKey);

    // Assistant de configuration
    void resetConfigState();                 // ré-active tout, remet l'anti-rebond
    void setEnabled(int buzzerId, bool value);
    void setPresenceMask(int mask);          // les 4 d'un coup (app, SET_PRESENT)
    bool isEnabled(int buzzerId);
    // Renvoie la presence des 4 buzzers a l'application. Publique parce que
    // l'app en a besoin des sa connexion : c'est du materiel, pas du jeu.
    void sendPresenceNow();
    int playerCount();                       // combien de buzzers en jeu (0-4)
    bool hasExactlyTwoPlayers();             // exactement 2 (requis par le jeu Duel)
    bool wasPressed(int buzzerId);           // front montant d'un appui (anti-rebond)
    void armButtons();                       // ignore les boutons déjà maintenus
    void setLed(int buzzerId, bool on);
    const char* colorName(int i);            // "Rouge", "Bleu", "Jaune", "Vert"

    // Score et jeu sélectionné
    void setGameMode(GameMode value);
    GameMode getGameMode();
    const char* gameModeName();               // nom du jeu courant
    const char* gameModeName(GameMode mode);  // nom d'un jeu quelconque (menu)
    bool isPenaltyMode();                    // Pénalité ou Chrono pénalité
    bool isChronoMode();                     // Chrono classique ou Chrono pénalité
    void resetScores();

    // Chrono de buzz (en secondes, 0 = désactivé), réglé séparément pour
    // Classique et Pénalité. Deux durées par mode : celle de la 1re réponse,
    // lancée par l'animateur (« top », touche D) une fois la question lue, et
    // celle des réponses suivantes, qui part toute seule après une mauvaise
    // réponse. Le tout est sauvegardé en EEPROM.
    int getFirstBuzzTime(GameMode mode);
    int getNextBuzzTime(GameMode mode);
    void setFirstBuzzTime(GameMode mode, int seconds);
    void setNextBuzzTime(GameMode mode, int seconds);
    void saveBuzzTimes();
    void startBuzzTimer();                   // « top » de l'animateur

    // Nombre de manches d'une partie, pour les jeux qui se jouent en manches
    // (Réflexe, Chrono aveugle). Réglé depuis la liste des jeux et sauvegardé
    // en EEPROM, comme les durées de chrono — un réglage par jeu.
    int getGameRounds(GameMode mode);
    void setGameRounds(GameMode mode, int n);
    void saveGameRounds();

    // Ne buzze pas : sons « leurres » (n'appartenant à personne) mêlés au flux.
    bool getSoundDecoys();
    void setSoundDecoys(bool value);
    void saveSoundDecoys();

    void setIntro();                         // lance le chenillard d'intro
    PhaseMode intro(char pressedKey);

    // Passer la question (personne ne marque). Renvoie ANSWER_REVEAL si la
    // banque est active (pour montrer la réponse à l'animateur), sinon
    // directement SHOW_SCORES.
    PhaseMode skipQuestion();

    // Nombre de questions de la partie (0 = ouvert : l'animateur termine
    // avec C). Choisi sur l'écran QUIZ_COUNT au lancement.
    void setQuestionLimit(int n);

    void setShowScores();                    // écran scores entre les questions
    PhaseMode showScores(char pressedKey);
    void setEndConfirm();                    // confirmation avant de terminer
    PhaseMode endConfirm(char pressedKey);
    void setEndGame();                       // écran fin de partie (gagnant + son)
    PhaseMode endGame(char pressedKey);

    // Correction d'une erreur de l'animateur : annule la dernière décision
    // (bonne/mauvaise) et revient juger le même buzzer.
    PhaseMode correctLastDecision(PhaseMode fallback);

private:
  Buzzer(const Buzzer&) = delete;
  Buzzer& operator=(const Buzzer&) = delete;

  void sendPresence();                       // telemetrie PRESENT|r|b|j|v

  // Brochage des buzzers : { Pin LED, Pin Bouton }
  int buzzers[4][2] = {
    {6, 5},   //Rouge
    {8, 7},   //Bleu
    {10, 9},  //Jaune
    {12, 11}  //Vert
  };

  bool actives[4] = { true, true, true, true};

  // État du mode de test câblage (LED_TEST).
  bool ledTestOn[4] = { true, true, true, true};   // état voulu de chaque LED
  bool ledTestMaster = true;                       // état de la bascule globale (touche)

  // Buzzer présent / dans le pool (déclaré via l'assistant de configuration).
  bool enabled[4] = { true, true, true, true};
  // Détection de front + anti-rebond des boutons de buzzer (lecture centralisée
  // via buttonPressed()). Le front d'appui est accepté immédiatement (aucune
  // latence pour une course de buzz), mais un nouvel appui n'est réarmé
  // qu'après un relâchement stable de BUTTON_DEBOUNCE_MS : ça filtre le rebond
  // de contact au relâchement, qui sinon ressemblait à un second appui.
  bool prevPressed[4] = { false, false, false, false};
  bool releasing[4] = { false, false, false, false};      // relâchement en cours de confirmation
  unsigned long releaseStartMs[4] = { 0, 0, 0, 0};         // début du relâchement (à confirmer)
  bool buttonPressed(int buzzerId);   // front descendant anti-rebondi

  // Scores par buzzer et jeu sélectionné (sous-menu "C" du menu).
  int scores[4] = { 0, 0, 0, 0};
  GameMode gameMode = GAME_CLASSIC;
  unsigned long scoresShownAt = 0;    // horodatage d'affichage des scores
  unsigned long introStart = 0;       // horodatage du début de l'intro

  // Mémoire de la dernière décision (pour correction).
  int lastJudgedBuzzer = -1;
  bool lastWasGood = false;

  int questionNumber = 1;   // numéro de la question en cours

  // Banque de questions : limite de la partie (0 = ouvert) et n° de la
  // dernière question tirée (pour ne tirer qu'une question par n°, pas à
  // chaque retour sur l'écran d'attente pendant la même question).
  int questionLimit = 0;
  int lastDrawnQuestion = 0;

  // Mode Vol : la question est adressée à volTurn (LED allumée, seul buzzer
  // armé) ; s'il rate, les autres présents peuvent la voler. Le 1er joueur
  // est tiré au sort ; ensuite le tour passe au buzzer présent suivant à
  // chaque question résolue.
  int volTurn = 0;
  unsigned long volSpinStart = 0;     // horodatage du début du tirage au sort
  unsigned long volSpinNextStepAt = 0;  // horodatage (elapsed) du prochain pas du chenillard
  unsigned int volSpinIntervalMs = 0;   // intervalle courant entre 2 pas (croît avec le temps)
  int volSpinStepIndex = 0;             // position courante dans le chenillard du tirage
  int nextEnabledBuzzer(int from);   // prochain buzzer présent après 'from'
  int randomEnabledBuzzer();         // un buzzer présent tiré au hasard
  void ledChaseEnabled(unsigned long elapsed);  // chenillard limité aux buzzers présents

  // Chrono de buzz, indexé par mode (0 = Chrono classique, 1 = Chrono
  // pénalité, 2 = Vol ; Classique/Pénalité/Simon n'utilisent pas ce chrono).
  // `timerLimit` est la durée retenue pour l'écran d'attente courant (1re
  // réponse ou suivante) ; le chrono n'est armé que si elle est > 0.
  // `secondaryRound` distingue les deux cas : vrai dès qu'une mauvaise
  // réponse a été donnée sur la question en cours.
  int firstBuzzTime[3] = { 10, 10, 10 };
  int nextBuzzTime[3] = { 5, 5, 5 };
  bool secondaryRound = false;
  int timerLimit = 0;               // durée du chrono de l'écran courant (s)
  bool timerRunning = false;
  unsigned long timerEnd = 0;
  int lastShownSecs = -1;           // évite de redessiner le LCD à chaque tick
  bool timeUp = false;              // la question s'est terminée au chrono

  // Répartit un texte sur plusieurs lignes de l'écran (coupe aux espaces).
  void wrapText(String text, int from, int to);

  // Manches par jeu : 0 = Réflexe, 1 = Chrono aveugle, 2 = Ne buzze pas, 3 = Duel.
  int gameRounds[4] = { GAME_ROUNDS_DEFAULT, GAME_ROUNDS_DEFAULT, SOUND_ROUNDS_DEFAULT, GAME_ROUNDS_DEFAULT };
  bool soundDecoys = true;          // Ne buzze pas : leurres actifs par défaut

  void loadBuzzTimes();             // relit les durées sauvegardées (EEPROM)
  void loadGameRounds();            // idem pour le nombre de manches par jeu
  void loadSoundDecoys();           // idem pour les leurres de Ne buzze pas
  void drawBuzzTimer(unsigned long remaining);   // barre + secondes restantes
  PhaseMode tickBuzzTimer();        // décompte : SHOW_SCORES si temps écoulé

  bool tiebreak = false;    // bris d'égalité en cours
  bool endTie = false;      // l'écran de fin affiche une égalité

  void enterTiebreak();     // n'autorise que les ex æquo à buzzer

  // Initialisé : une question peut se terminer sans qu'aucun buzzer n'ait été
  // pressé (touche « passer » ou chrono écoulé), et les écrans de scores
  // éteignent la LED de currentBuzzerId.
  int currentBuzzerId = 0;

  // Démarrage : message tiré au hasard, horodatage et état des animations.
  int bootMessage = 0;
  unsigned long bootStart = 0;
  unsigned long lastEqFrame = 0;
  int lastDots = -1;
  uint8_t eqHeights[20];
  void updateEqualizer();             // fait danser les barres d'une image
  void ledChase(unsigned long elapsed);  // chenillard des 4 LED

  // Vrai quand la chanson lancée il y a `elapsed` ms est terminée (BUSY), ou
  // que la durée de sécurité est écoulée. En simulation : minuteur fixe de
  // durée `simDurationMs` (par défaut celle de la chanson d'intro).
  bool songFinished(unsigned long elapsed, unsigned long simDurationMs = INTRO_MS);

  void goodAnswer();
  void badAnswer();
  void resetAllBuzzers();
  void displayScores(const char* title, const char* prompt);

  // Telemetrie app compagnon (BLE) : un seul point de construction du message
  // SCORE, appele partout ou scores[] change (bonne/mauvaise reponse,
  // correction, remise a zero).
  void sendScoreTelemetry();

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  BleLink& ble = BleLink::shared();
};

#endif
