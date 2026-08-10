#ifndef BLINDTIMER_H
#define BLINDTIMER_H

#include "LcdDisplay.h"
#include "PhaseMode.h"
#include "Mp3.h"
#include "Buzzer.h"

// Le nombre de manches se regle dans le menu (ligne "Chrono aveugle" de la
// liste des jeux) : voir GAME_ROUNDS_* et getGameRounds() dans Buzzer.h.
#define BLIND_TARGET_MIN_S 5         // cible mini annoncee (secondes entieres)
#define BLIND_TARGET_MAX_S 15        // cible maxi
#define BLIND_GRACE_MS 10000         // rab apres la cible avant de couper la manche

// Record du plus petit ecart jamais realise, en EEPROM (2 octets, little
// endian). 516-517 sont pris par le record du Reflexe : on prend 518.
#define BLIND_EEPROM_RECORD 518
#define BLIND_NO_RECORD 0xFFFF

// Chrono aveugle : la machine annonce une duree cible tiree au sort (5 a 15
// secondes), l'animateur donne le depart, puis l'ecran n'affiche plus rien qui
// bouge. Chacun buzze quand il pense que la cible est atteinte ; le plus
// proche remporte la manche.
//
// Aucune connaissance n'est requise, donc petits et grands sont a egalite.
// Toutes les LED s'allument au depart et celle d'un joueur s'eteint quand il a
// buzze : c'est le seul retour visuel, et il ne divulgue aucune duree (juste
// le fait qu'un adversaire s'est deja engage, ce qui fait partie du jeu).
//
// Se joue avec le nombre de buzzers declares presents ; a un seul, c'est une
// course au record de precision.
class BlindTimer {
public:
    void reset();                           // nouvelle partie : scores a zero

    void setAnnounce();                     // annonce la cible, attend le depart
    PhaseMode announce(char pressedKey);

    void setRun();                          // depart : plus rien ne bouge a l'ecran
    PhaseMode run(char pressedKey);

    void setResult();                       // temps de chacun + gagnant
    PhaseMode result(char pressedKey);

    void setGameOver();
    PhaseMode gameOver(char pressedKey);

private:

  int scores[4] = { 0, 0, 0, 0 };
  unsigned long times[4] = { 0, 0, 0, 0 };   // temps de la manche (0 = pas buzze)

  int round = 0;                 // manche en cours (1..totalRounds)
  int totalRounds = GAME_ROUNDS_DEFAULT;     // fige par reset()
  bool aborted = false;          // partie terminee par l'animateur (C)

  unsigned long targetMs = 0;    // cible de la manche
  unsigned long startMs = 0;     // horodatage du depart
  int winner = -1;               // gagnant de la manche (-1 = personne)

  unsigned int bestGapMs = BLIND_NO_RECORD;  // meilleur ecart de la partie
  bool newRecord = false;

  bool allBuzzed();
  String scoreLine();            // scores compacts : "R2 B1 J0 V1"
  String playerCell(int i);      // "R 11,8" ou "R ----"
  void showTimes();              // lignes 1 et 2 : deux joueurs par ligne

  unsigned int readRecord();
  void writeRecord(unsigned int ms);

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
};

#endif
