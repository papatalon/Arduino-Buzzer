#ifndef CONFIGURATION_H
#define CONFIGURATION_H

#include "LcdDisplay.h"
#include "PhaseMode.h"
#include "Mp3.h"
#include "Buzzer.h"
#include "QuestionBank.h"
#include "BleLink.h"

class Configuration {
public:
    void init();
    PhaseMode manageConfiguration(char pressedKey);
    void setGameChoice();                    // sous-menu "C" : choix du jeu
    PhaseMode gameChoice(char pressedKey);
    // Selectionne directement le jeu d'index [index] (meme ordre que
    // GameMode/kGameModeNames cote app) et le confirme, sans passer par la
    // navigation haut/bas du clavier - utilise par la commande App->Mega
    // SELECT_GAME|<n> (voir BleLink::consumeGameSelect()). Fonctionne peu
    // importe la phase courante : l'app n'est pas soumise a la contrainte
    // sequentielle du clavier physique.
    PhaseMode selectGameIndex(int index);
    void setChronoScreen();                  // reglage des durees du chrono
    PhaseMode chronoScreen(char pressedKey);
    void setRoundsScreen();                  // reglage du nb de manches d'un jeu
    PhaseMode roundsScreen(char pressedKey);
    void setSoundSetup();                    // Ne buzze pas : nb de sons + leurres
    PhaseMode soundSetup(char pressedKey);
    void setQuizCats();                      // lancement quiz : categories
    PhaseMode quizCats(char pressedKey);
    // Applique directement le masque de categories [mask] et passe a
    // QUIZ_COUNT, sans passer par les raccourcis dependants du curseur
    // physique (qui n'ont de sens que pour une seule frappe a la fois) -
    // utilise par la commande App->Mega SET_CATS|<mask> (voir
    // BleLink::consumeCategoryMask()).
    PhaseMode confirmCategories(int mask);
    void setQuizCount();                     // lancement quiz : nb de questions
    PhaseMode quizCount(char pressedKey);
    // Fixe le nombre de questions [n] (0 = Ouvert) et lance la partie -
    // utilise par la commande App->Mega SET_COUNT|<n> (voir
    // BleLink::consumeQuestionCount()). Le mode ouvert est ce que l'app
    // impose quand c'est elle qui fournit les questions : c'est alors elle
    // qui decide de la fin, pas le buzzer qui compte jusqu'a N.
    PhaseMode confirmQuestionCount(int n);
    // Depart demande par l'application, depuis n'importe quelle phase : banque
    // du Mega en retrait et compteur ouvert, l'app fournissant les questions.
    // Voir BleLink::consumeStartGame().
    PhaseMode startFromApp(int nbQuestions);
    void setShuffleBuzzers();
    PhaseMode shuffleBuzzer(char pressedKey);
    void setBuzzerConfig();
    PhaseMode buzzerConfig(char pressedKey);
    void setVolumeScreen();
    PhaseMode volumeScreen(char pressedKey);

private:

  // Le lancement reel de la partie, partage par le '#' du compteur de
  // questions et par la commande SET_COUNT de l'app.
  PhaseMode startMatch();

  // Étapes de l'assistant de configuration d'un buzzer.
  enum CfgStep { CFG_PROMPT, CFG_CHOOSING };

  // Étapes de l'écran "Sons aléatoires" : confirmation avant d'écraser, puis
  // animation de tirage (chenillard + son, comme le mode Vol) pendant le
  // mélange, puis résultat.
  enum ShufStep { SHUF_CONFIRM, SHUF_SPINNING, SHUF_DONE };

  // Liste déroulante du sous-menu "C" (jeux + réglages, ex. Chrono) : tout
  // tient sur 3 lignes visibles ; curseur ">" déplacé par 2/8, la fenêtre
  // défile automatiquement si la liste dépasse ces 3 lignes. Le contenu de
  // la liste (GAME_LIST) est défini dans Configuration.cpp.
  int gameCursor = 0;        // ligne en surbrillance (index dans GAME_LIST)
  int gameWindowTop = 0;     // première ligne affichée (haut de la fenêtre visible)
  void showGameChoice();
  void scrollGameWindow();               // recale gameWindowTop sur gameCursor
  PhaseMode confirmGameSelection();       // applique GAME_LIST[gameCursor] (utilise par '#' et selectGameIndex)

  int cfgIndex = 0;          // buzzer en cours de configuration (0..3)
  CfgStep cfgStep = CFG_PROMPT;
  ShufStep shufStep = SHUF_CONFIRM;

  // Vrai quand l'avertissement "Simon = 4 joueurs" occupe l'écran à la place
  // du menu : la touche suivante redessine le menu avant d'être traitée.
  bool warningShown = false;
  void showFourPlayersWarning();
  void showTwoPlayersWarning();

  // Réglage du chrono en deux étapes (1re réponse, puis autres réponses),
  // ouvert depuis une ligne "Chrono ..." de la liste déroulante ;
  // chronoTargetMode retient pour quel mode (Classique ou Pénalité).
  enum ChronoStep { CHRONO_FIRST, CHRONO_NEXT };
  ChronoStep chronoStep = CHRONO_FIRST;
  GameMode chronoTargetMode = GAME_CLASSIC;
  int chronoCursor = 0;      // valeur (secondes) en cours de réglage
  void showChronoStep();

  // Réglage du nombre de manches, ouvert depuis la ligne du jeu concerné dans
  // la liste déroulante (qui sélectionne aussi le jeu, comme le Chrono) ;
  // roundsTargetMode retient de quel jeu il s'agit.
  int roundsCursor = GAME_ROUNDS_DEFAULT;
  GameMode roundsTargetMode = GAME_REFLEX;
  void showRoundsValue();

  // Réglage de « Ne buzze pas » en deux étapes (nombre de sons, puis leurres),
  // comme l'écran du chrono : un seul réglage à la fois, `#` valide et enchaîne.
  enum SoundStep { SOUND_CFG_COUNT, SOUND_CFG_DECOYS };
  SoundStep soundStep = SOUND_CFG_COUNT;
  bool soundDecoysCursor = true;
  void showSoundStep();

  // Lancement d'un quiz : écran des catégories de questions (liste
  // déroulante multi-sélection : "Toutes", "Aucune" = questionnaire perso,
  // puis les catégories cochables), puis écran du nombre de questions
  // ("Ouvert" = l'animateur arrête quand il veut, comme avant).
  // qcatMask/qcountIdx persistent : mêmes choix proposés au prochain match.
  int qcatCursor = 0;
  int qcatTop = 0;
  uint16_t qcatMask = 0;
  int qcountIdx = 0;         // nombre de questions choisi (0 = Ouvert)
  void showQuizCats();
  String qcatLabel(int row);
  void showQuizCount();

  void showConfigPrompt();
  void showConfigChoice();
  PhaseMode advanceConfig();
  const char* colorName(int i);

  LcdDisplay& display = LcdDisplay::shared();
  Mp3& mp3 = Mp3::shared();
  Buzzer& buzzer = Buzzer::shared();
  BleLink& ble = BleLink::shared();
};

#endif
