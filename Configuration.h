#ifndef CONFIGURATION_H
#define CONFIGURATION_H

#include "LcdDisplay.h"
#include "PhaseMode.h"
#include "Mp3.h"
#include "Buzzer.h"

class Configuration {
public:
    void init();
    PhaseMode manageConfiguration(char pressedKey);
    void setGameChoice();                    // sous-menu "C" : choix du jeu
    PhaseMode gameChoice(char pressedKey);
    void setChronoScreen();                  // reglage des durees du chrono
    PhaseMode chronoScreen(char pressedKey);
    void setShuffleBuzzers();
    PhaseMode shuffleBuzzer(char pressedKey);
    void setBuzzerConfig();
    PhaseMode buzzerConfig(char pressedKey);
    void setVolumeScreen();
    PhaseMode volumeScreen(char pressedKey);

private:

  // Étapes de l'assistant de configuration d'un buzzer.
  enum CfgStep { CFG_PROMPT, CFG_CHOOSING };

  // Étapes de l'écran "Sons aléatoires" (confirmation avant d'écraser).
  enum ShufStep { SHUF_CONFIRM, SHUF_DONE };

  // Liste déroulante du sous-menu "C" (jeux + réglages, ex. Chrono) : tout
  // tient sur 3 lignes visibles ; curseur ">" déplacé par 2/8, la fenêtre
  // défile automatiquement si la liste dépasse ces 3 lignes. Le contenu de
  // la liste (GAME_LIST) est défini dans Configuration.cpp.
  int gameCursor = 0;        // ligne en surbrillance (index dans GAME_LIST)
  int gameWindowTop = 0;     // première ligne affichée (haut de la fenêtre visible)
  void showGameChoice();
  void scrollGameWindow();               // recale gameWindowTop sur gameCursor

  int cfgIndex = 0;          // buzzer en cours de configuration (0..3)
  CfgStep cfgStep = CFG_PROMPT;
  ShufStep shufStep = SHUF_CONFIRM;

  // Vrai quand l'avertissement "Simon = 4 joueurs" occupe l'écran à la place
  // du menu : la touche suivante redessine le menu avant d'être traitée.
  bool warningShown = false;
  void showFourPlayersWarning();

  // Réglage du chrono en deux étapes (1re réponse, puis autres réponses),
  // ouvert depuis une ligne "Chrono ..." de la liste déroulante ;
  // chronoTargetMode retient pour quel mode (Classique ou Pénalité).
  enum ChronoStep { CHRONO_FIRST, CHRONO_NEXT };
  ChronoStep chronoStep = CHRONO_FIRST;
  GameMode chronoTargetMode = GAME_CLASSIC;
  int chronoCursor = 0;      // valeur (secondes) en cours de réglage
  void showChronoStep();

  void showConfigPrompt();
  void showConfigChoice();
  PhaseMode advanceConfig();
  const char* colorName(int i);

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
};

#endif
