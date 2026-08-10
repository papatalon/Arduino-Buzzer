#ifndef SOUNDGAME_H
#define SOUNDGAME_H

#include "LcdDisplay.h"
#include "PhaseMode.h"
#include "Mp3.h"
#include "Buzzer.h"

// Le nombre de sons d'une partie et l'activation des leurres se reglent dans le
// menu (ligne "Ne buzze pas" de la liste des jeux) : voir getGameRounds() et
// getSoundDecoys() dans Buzzer.h.
#define SOUND_LEARN_MS 1800          // duree d'un son pendant l'apprentissage
#define SOUND_INTERVAL_START 2500    // ecart entre deux sons, au debut
#define SOUND_INTERVAL_MIN 1200      // ecart le plus serre (fin de partie)
#define SOUND_INTERVAL_STEP 100      // resserrement a chaque son
#define SOUND_DECOY_PERCENT 30       // proportion de leurres quand ils sont actifs

// « Ne buzze pas » : jeu d'oreille. Chaque joueur a deja SON son de buzz
// (assistant "A") ; la machine enchaine des sons en FLUX CONTINU et il faut
// buzzer quand c'est le sien — surtout pas quand c'est celui d'un autre.
//
// Il n'y a pas de fenetre de reponse arbitraire : la limite, c'est le son
// suivant. L'ecart entre deux sons se resserre au fil de la partie
// (SOUND_INTERVAL_START -> SOUND_INTERVAL_MIN), ce qui fait monter la tension
// et donne une fin naturelle.
//
// Bareme : reconnaitre son son +1 ; buzzer sur le son d'un autre -1 (et on est
// ecarte de ce son, mais son proprietaire peut encore le reclamer) ; laisser
// passer son propre son -1. Cette derniere penalite est indispensable : sans
// elle, ne jamais buzzer serait une stratégie sans risque.
//
// Une phase d'APPRENTISSAGE precede la partie : chaque son est joue une fois,
// LED allumee et couleur nommee. L'assistant garantit 4 fichiers differents,
// pas 4 sons audiblement distincts — c'est le moment de s'en apercevoir.
//
// Leurres (optionnels) : des sons du dossier qui n'appartiennent a personne, et
// sur lesquels personne ne doit buzzer. Ce sont les pieges les plus efficaces.
class SoundGame {
public:
    void reset();                           // nouvelle partie : scores a zero

    void setLearn();                        // apprentissage des sons
    PhaseMode learn(char pressedKey);

    void setPlay();                         // lance le flux continu
    PhaseMode play(char pressedKey);

    void setGameOver();
    PhaseMode gameOver(char pressedKey);

private:

  int scores[4] = { 0, 0, 0, 0 };
  bool aborted = false;

  int totalSounds = 0;           // sons de la partie, fige par reset()
  bool decoys = false;           // leurres actifs, fige par reset()

  // Apprentissage.
  int learnIndex = -1;           // joueur dont le son vient d'etre joue
  unsigned long learnStart = 0;
  bool learnDone = false;

  // Flux continu.
  int played = 0;                // sons deja joues (1..totalSounds)
  unsigned long interval = SOUND_INTERVAL_START;
  unsigned long soundStart = 0;  // horodatage du son en cours
  int owner = -1;                // proprietaire du son en cours (-1 = leurre)
  bool claimed = false;          // son reclame par son proprietaire
  bool buzzed[4];                // a deja buzze sur ce son (bon ou mauvais)

  int pickPlayer();              // un joueur present au hasard (-1 si aucun)
  int pickOwner();               // joueur au hasard, ou -1 pour un leurre
  int pickDecoySound();          // son du dossier appartenant a personne (-1 si aucun)
  void playNext();               // enchaine le son suivant
  void judgeCurrent();           // penalise le proprietaire qui n'a rien fait
  void handleBuzz(int i);

  String scoreLine();            // scores compacts : "R2 B-1 J0 V1"
  void showProgress();

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
};

#endif
