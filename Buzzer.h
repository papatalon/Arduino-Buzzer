#ifndef BUZZER_H
#define BUZZER_H

#include "PhaseMode.h"
#include "LcdDisplay.h"
#include <Arduino.h>
#include "Mp3.h";

#define SCORES_DISPLAY_MS 15000  // durée d'affichage des scores entre les questions
#define WIN_BLINK_MS 1500        // durée du clignotement de la LED du gagnant
#define INTRO_MS 4000            // durée du chenillard d'intro au lancement
#define INTRO_STEP_MS 120        // vitesse du chenillard (ms par LED)

class Buzzer {
public:

    Buzzer();

    static Buzzer& shared();

    void init();
    void resetLights();

    // Mode cache de test cablage (entree *1) : LED + boutons.
    void setLedTest();                       // entree : allume les 4 LED
    PhaseMode ledTest(char pressedKey);      // touche = tout on/off ; bouton = sa LED

    void setWaitingForBuzzer();
    PhaseMode waitingBuzzerIsPressed(PhaseMode currentMode);

    void setBuzzerPressed();
    PhaseMode buzzerIsPressed(PhaseMode currentMode, char pressedKey);

    // Assistant de configuration
    void resetConfigState();                 // ré-active tout, remet l'anti-rebond
    void setEnabled(int buzzerId, bool value);
    bool isEnabled(int buzzerId);
    bool wasPressed(int buzzerId);           // front montant d'un appui (anti-rebond)
    void setLed(int buzzerId, bool on);

    // Score et modes de jeu
    void setPenaltyMode(bool value);
    void togglePenaltyMode();
    bool isPenaltyMode();
    void resetScores();

    void setIntro();                         // lance le chenillard d'intro
    PhaseMode intro(char pressedKey);

    void skipQuestion();                     // passer la question (personne ne marque)

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
  bool ledTestPrev[4] = { false, false, false, false}; // anti-rebond boutons
  bool ledTestMaster = true;                       // état de la bascule globale (touche)

  // Buzzer présent / dans le pool (déclaré via l'assistant de configuration).
  bool enabled[4] = { true, true, true, true};
  // État précédent du bouton, pour l'anti-rebond pendant la configuration.
  bool prevPressed[4] = { false, false, false, false};

  // Scores par buzzer et mode de jeu.
  int scores[4] = { 0, 0, 0, 0};
  bool penaltyMode = false;           // false = Classique, true = Pénalité (-1 si mauvaise)
  unsigned long scoresShownAt = 0;    // horodatage d'affichage des scores
  unsigned long introStart = 0;       // horodatage du début de l'intro

  // Mémoire de la dernière décision (pour correction).
  int lastJudgedBuzzer = -1;
  bool lastWasGood = false;

  int questionNumber = 1;   // numéro de la question en cours

  bool tiebreak = false;    // bris d'égalité en cours
  bool endTie = false;      // l'écran de fin affiche une égalité

  void enterTiebreak();     // n'autorise que les ex æquo à buzzer

  int currentBuzzerId;

  void goodAnswer();
  void badAnswer();
  void resetAllBuzzers();
  const char* colorName(int i);
  void displayScores(const char* title, const char* prompt);

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
};

#endif
