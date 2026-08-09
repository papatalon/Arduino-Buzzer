#ifndef BUZZER_H
#define BUZZER_H

#include "PhaseMode.h"
#include "GameMode.h"
#include "LcdDisplay.h"
#include <Arduino.h>
#include "Mp3.h";

#define SCORES_DISPLAY_MS 15000  // durée d'affichage des scores entre les questions
#define WIN_BLINK_MS 1500        // durée du clignotement de la LED du gagnant
#define INTRO_MS 4000            // durée du chenillard d'intro en simulation (pas de BUSY)
#define INTRO_STEP_MS 120        // vitesse du chenillard (ms par LED)
#define INTRO_START_MS 500       // délai avant de tester BUSY (démarrage du DFPlayer)
#define INTRO_MAX_MS 30000       // durée maxi de sécurité du chenillard d'intro
#define BUTTON_DEBOUNCE_MS 200   // anti-rebond commun a tous les boutons de buzzer
#define BOOT_MESSAGE_COUNT 5     // nombre de messages de demarrage disponibles
#define BOOT_DOT_MS 300          // vitesse des points animes du message de demarrage
#define EQ_FRAME_MS 150          // duree d'une image de l'egaliseur (redessin I2C lent)
#define BUZZ_TIME_MAX 60         // duree maxi reglable du chrono de buzz (secondes)
#define BUZZ_WARN_MS 3000        // les LED clignotent sur les dernieres secondes
#define BUZZ_WARN_BLINK_MS 200   // periode du clignotement de fin de chrono
#define VOL_SPIN_MS 2500         // duree du tirage au sort anime (mode Vol)
#define VOL_SPIN_STEP_MS 120     // vitesse du chenillard du tirage

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

    void setWaitingForBuzzer();
    PhaseMode waitingBuzzerIsPressed(PhaseMode currentMode);

    void setBuzzerPressed();
    PhaseMode buzzerIsPressed(PhaseMode currentMode, char pressedKey);

    // Assistant de configuration
    void resetConfigState();                 // ré-active tout, remet l'anti-rebond
    void setEnabled(int buzzerId, bool value);
    bool isEnabled(int buzzerId);
    bool hasFourPlayers();                   // les 4 buzzers sont déclarés présents
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

    void setIntro();                         // lance le chenillard d'intro
    PhaseMode intro(char pressedKey);

    void skipQuestion();                     // passer la question (personne ne marque)

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
  // via buttonPressed()). prevPressed = état précédent, lastEdgeMs = horodatage
  // du dernier front accepté (rejette les fronts trop rapprochés = rebonds).
  bool prevPressed[4] = { false, false, false, false};
  unsigned long lastEdgeMs[4] = { 0, 0, 0, 0};
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

  void loadBuzzTimes();             // relit les durées sauvegardées (EEPROM)
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
  // que la durée de sécurité est écoulée. En simulation : minuteur fixe.
  bool songFinished(unsigned long elapsed);

  void goodAnswer();
  void badAnswer();
  void resetAllBuzzers();
  void displayScores(const char* title, const char* prompt);

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
};

#endif
