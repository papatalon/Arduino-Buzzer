#ifndef DUEL_H
#define DUEL_H

#include "LcdDisplay.h"
#include "PhaseMode.h"
#include "Mp3.h"
#include "Buzzer.h"

// Le nombre de manches se regle dans le menu (ligne "Duel" de la liste des
// jeux) : voir GAME_ROUNDS_* et getGameRounds() dans Buzzer.h.
#define DUEL_WAIT_MIN_MS 2000        // delai mini avant le signal
#define DUEL_WAIT_MAX_MS 7000        // delai maxi avant le signal
#define DUEL_ANSWER_MS 3000          // delai maxi pour buzzer apres le signal

// Duel au son, pour EXACTEMENT 2 joueurs (obligatoirement, comme Simon exige
// 4 : voir Buzzer::hasExactlyTwoPlayers()). A la difference du Reflexe, le
// signal de depart n'est PAS visuel mais SONORE (un son de buzzer tire au
// hasard, voir setGo()) : les deux duellistes peuvent jouer les yeux fermes,
// dos a dos. Comme il n'y a qu'un seul haut-parleur, les deux l'entendent au
// meme instant : la course entre les deux appuis reste juste quel que soit
// le delai de demarrage reel du DFPlayer, qui touche les deux joueurs de
// facon identique.
//
// Les deux buzzers qui s'affrontent sont ceux declares presents (assistant
// "A") : peu importe lesquels (Rouge contre Vert, Bleu contre Jaune...), le
// jeu exige seulement qu'il y en ait exactement deux.
//
// Bareme identique au Reflexe : premier a buzzer apres le signal gagne la
// manche ; buzzer avant est un faux depart qui offre la manche a l'adversaire
// sans qu'il ait besoin d'appuyer.
class Duel {
public:
    void reset();                           // nouvelle partie : scores a zero

    void setArm();                          // manche suivante : attente du signal
    PhaseMode arm(char pressedKey);

    void setGo();                           // le signal sonore : chrono lance
    PhaseMode go(char pressedKey);

    void setResult();                       // resultat de la manche
    PhaseMode result(char pressedKey);

    void setGameOver();
    PhaseMode gameOver(char pressedKey);

private:

  int scores[4] = { 0, 0, 0, 0 };

  // Les deux duellistes, determines a chaque reset() parmi les buzzers
  // presents (Configuration a deja verifie qu'il y en a exactement deux
  // avant de lancer la partie).
  int playerA = 0;
  int playerB = 1;
  void findPlayers();

  int round = 0;                 // manche en cours (1..totalRounds)
  int totalRounds = GAME_ROUNDS_DEFAULT;     // fige par reset()
  bool aborted = false;          // partie terminee par l'animateur (C)

  unsigned long armStart = 0;
  unsigned long waitMs = 0;      // delai tire au sort avant le signal

  unsigned long goStart = 0;     // horodatage du signal
  int winner = -1;               // gagnant de la manche (-1 = personne)
  unsigned int winnerMs = 0;     // son temps de reaction (0 si faux depart)
  bool falseStart = false;       // la manche s'est decidee par faux depart
  int falseStarter = -1;

  String scoreLine();            // "Rouge 2   Vert 1"

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
};

#endif
