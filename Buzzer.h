#ifndef BUZZER_H
#define BUZZER_H

#include "PhaseMode.h"
#include "LcdDisplay.h"
#include <Arduino.h>
#include "Mp3.h";

#define SCORES_DISPLAY_MS 15000  // durée d'affichage des scores entre les questions

class Buzzer {
public:

    Buzzer();

    static Buzzer& shared();

    void init();
    void resetLights();

    void setWaitingForBuzzer();
    PhaseMode waitingBuzzerIsPressed(PhaseMode currentMode);

    void setBuzzerPressed();
    PhaseMode buzzerIsPressed(PhaseMode currentMode, char pressedKey);

    void initMp3Index();
    void endConfiguration();

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

    void setShowScores();                    // écran scores entre les questions
    PhaseMode showScores(char pressedKey);
    void setEndGame();                       // écran fin de partie (gagnant + son)
    PhaseMode endGame(char pressedKey);

private:
  Buzzer(const Buzzer&) = delete;
  Buzzer& operator=(const Buzzer&) = delete;

  // Initialisation du buzzer
  // Array 0:  Buzzer
  // Array 1:  { Pin Led, Pin Button}
  int buzzers[4][3] = {
    {6, 5, 0}, //Rouge
    {8, 7, 1}, //Bleu
    {10, 9, 2}, //Jaune
    {12, 11, 3} // Vert
  };

  bool actives[4] = { true, true, true, true};

  // Buzzer présent / dans le pool (déclaré via l'assistant de configuration).
  bool enabled[4] = { true, true, true, true};
  // État précédent du bouton, pour l'anti-rebond pendant la configuration.
  bool prevPressed[4] = { false, false, false, false};

  // Scores par buzzer et mode de jeu.
  int scores[4] = { 0, 0, 0, 0};
  bool penaltyMode = false;           // false = Classique, true = Pénalité (-1 si mauvaise)
  unsigned long scoresShownAt = 0;    // horodatage d'affichage des scores

  int currentBuzzerId;
  unsigned long previousMillis = 0;

  void goodAnswer();
  void badAnswer();
  void resetAllBuzzers();
  void blink();
  const char* colorName(int i);
  void displayScores(const char* title, const char* prompt);

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
};

#endif
