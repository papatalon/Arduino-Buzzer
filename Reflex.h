#ifndef REFLEX_H
#define REFLEX_H

#include "LcdDisplay.h"
#include "PhaseMode.h"
#include "Mp3.h"
#include "Buzzer.h"
#include "BleLink.h"

// Le nombre de manches d'une partie se regle dans le menu (ligne "Reflexe" de
// la liste des jeux) et vit dans Buzzer, avec les autres reglages persistants :
// voir GAME_ROUNDS_MIN/MAX/DEFAULT et getGameRounds() dans Buzzer.h.
#define REFLEX_WAIT_MIN_MS 2000      // delai mini avant le signal
#define REFLEX_WAIT_MAX_MS 8000      // delai maxi avant le signal
#define REFLEX_ANSWER_MS 3000        // delai maxi pour buzzer apres le signal

// Record du meilleur temps de reaction, en EEPROM (2 octets, little endian).
// Le bitmap des questions occupe 16..515 (voir QuestionBank.cpp) : 516 est
// libre. Une case jamais ecrite vaut 0xFFFF = aucun record.
#define REFLEX_EEPROM_RECORD 516
#define REFLEX_NO_RECORD 0xFFFF

// Jeu de reflexe pur, sans question. Les LED s'eteignent, un delai aleatoire
// s'ecoule, puis toutes les LED s'allument d'un coup : le premier a buzzer
// remporte la manche et son temps de reaction s'affiche en millisecondes.
// Buzzer AVANT le signal est un faux depart : le joueur est elimine de la
// manche en cours (les autres continuent).
//
// Le signal officiel est la LED, pas le son : digitalWrite est instantane
// alors qu'une commande au DFPlayer met plusieurs ms a partir. Le chrono
// demarre donc juste apres l'allumage, et l'ecran n'est redessine qu'ensuite
// (jamais pendant la mesure, pour ne pas fausser les temps).
//
// Se joue avec le nombre de buzzers declares presents : a un seul, c'est une
// course au record.
class Reflex {
public:
    void reset();                           // nouvelle partie : scores a zero

    // LE RECORD APPARTIENT AU BUZZER, pas a un portable.
    //
    // Il vit en EEPROM et vaut pour les deux modes : une partie menee par
    // l'application compte pour le meme record qu'une partie au clavier. Ces
    // deux methodes l'ouvrent a l'app (messages REC et SET_REC).
    unsigned int record();
    void enregistrerRecord(unsigned int ms);

    void setArm();                          // manche suivante : attente du signal
    PhaseMode arm(char pressedKey);

    void setGo();                           // le signal : LED allumees, chrono lance
    PhaseMode go(char pressedKey);

    void setResult();                       // resultat de la manche
    PhaseMode result(char pressedKey);

    void setGameOver();
    PhaseMode gameOver(char pressedKey);

private:

  int scores[4] = { 0, 0, 0, 0 };
  bool falseStart[4] = { false, false, false, false };  // elimine de la manche

  int round = 0;                 // manche en cours (1..totalRounds)
  // Nombre de manches de LA partie en cours, fige par reset() : changer le
  // reglage dans le menu n'affecte donc pas une partie deja commencee.
  int totalRounds = GAME_ROUNDS_DEFAULT;
  bool aborted = false;          // partie terminee par l'animateur (C)

  // Attente du signal.
  unsigned long armStart = 0;
  unsigned long waitMs = 0;      // delai tire au sort avant le signal

  // Manche en cours.
  unsigned long goStart = 0;     // horodatage du signal
  int winner = -1;               // gagnant de la manche (-1 = personne)
  unsigned int winnerMs = 0;     // son temps de reaction

  // Meilleur temps de la partie (0 = aucune manche gagnee).
  unsigned int bestMs = 0;
  bool newRecord = false;

  int activePlayers();           // buzzers presents encore en lice
  String scoreLine();            // scores compacts : "R2 B1 J0 V1"

  unsigned int readRecord();
  void writeRecord(unsigned int ms);

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
  BleLink& ble = BleLink::shared();
};

#endif
