#ifndef SIMON_H
#define SIMON_H

#include "LcdDisplay.h"
#include "PhaseMode.h"
#include "Mp3.h"
#include "Buzzer.h"

#define SIMON_MAX_LEVEL 32      // longueur maxi de la sequence (1 octet par etape)
#define SIMON_START_MS 1500     // pause avant la demo (le temps de lire l'ecran)
#define SIMON_ON_MS 600         // duree d'allumage d'une couleur pendant la demo
#define SIMON_GAP_MS 250        // silence entre deux couleurs de la demo
#define SIMON_ECHO_MS 400       // duree d'allumage de la LED a l'appui d'un joueur
#define SIMON_ROUND_MS 2000     // pause "BRAVO" entre deux niveaux
#define SIMON_TIMEOUT_MS 10000  // delai maxi entre deux appuis avant echec

// Jeu collaboratif de memoire, facon "Simon". Se joue obligatoirement a 4 :
// chaque joueur tient une couleur. La machine joue une sequence de couleurs
// (LED + son configure du buzzer correspondant), que l'equipe doit rejouer
// dans l'ordre (ou a l'envers en mode GAME_SIMON_REVERSE, voir reset()) ;
// chacun appuie quand SA couleur passe. La sequence s'allonge d'une couleur
// a chaque niveau reussi, et la moindre erreur termine la partie.
class Simon {
public:
    void reset();                           // nouvelle partie : sequence vide

    void setShowSequence();                 // ajoute une couleur et lance la demo
    PhaseMode showSequence(char pressedKey);

    void setPlaySequence();                 // aux joueurs de repeter
    PhaseMode playSequence(char pressedKey);

    void setGameOver();
    PhaseMode gameOver(char pressedKey);

private:

  uint8_t sequence[SIMON_MAX_LEVEL];
  int level = 0;              // niveaux reussis (= score collectif)
  int length = 0;             // longueur de la sequence du tour en cours
  bool reverse = false;       // vrai en mode GAME_SIMON_REVERSE (repeter a l'envers)

  // Demonstration de la sequence.
  int showIndex = 0;          // couleur en cours de demonstration
  bool showLit = false;       // vrai pendant l'allumage, faux pendant le silence
  unsigned long stepStart = 0;

  // Repetition par les joueurs.
  int inputIndex = 0;         // position attendue dans la sequence
  int litBuzzer = -1;         // LED allumee en echo d'un appui (-1 = aucune)
  unsigned long litStart = 0;
  unsigned long lastInput = 0;
  bool roundDone = false;     // tour reussi : pause "BRAVO" avant le niveau suivant

  const char* overTitle = "";   // raison de la fin, affichee sur l'ecran final
  int failedBuzzer = -1;        // couleur fautive (-1 = abandon / trop lent)

  void showTitle();                 // ligne 0 : "SIMON - Niveau N"
  void showProgress();              // ligne 2 : progression "x / N"
  PhaseMode fail(const char* title);  // termine la partie avec ce titre

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
};

#endif
