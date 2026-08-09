#include "Configuration.h"

void Configuration::init() {
  warningShown = false;
  display.clear();
  display.setText(String("= MENU =  ") + buzzer.gameModeName(), 0);
  display.setText("A: Config Buzzers", 1);
  display.setText("B: Sons au hasard", 2);
  display.setText("C:Jeu D:Volu #:Jouer", 3);
}

// Le jeu Simon exige les 4 buzzers : on refuse le lancement et on renvoie
// vers l'assistant de configuration.
void Configuration::showFourPlayersWarning() {
  warningShown = true;
  display.clear();
  display.setText("  SIMON : 4 JOUEURS", 0);
  display.setText("Buzzers manquants", 1);
  display.setText("A: config buzzers", 2);
  display.setText("Autre touche: menu", 3);
}

PhaseMode Configuration::manageConfiguration(char pressedKey) {

  if(!pressedKey) {
    return CONFIGURATION;
  }

  // L'avertissement occupe l'écran : la touche remet d'abord le menu en place,
  // puis elle est traitée normalement.
  if (warningShown) {
    init();
  }

  switch(pressedKey) {
    case 'A':
      return BUZZER_CONFIG;
    case 'B':
      return SHUFFLE_BUZZER;
    case 'C':
      return GAME_CHOICE;           // sous-menu : choix du jeu
    case 'D':
      return VOLUME;                // écran de réglage du volume
    case '#': {
      GameMode mode = buzzer.getGameMode();
      bool isSimon = (mode == GAME_SIMON || mode == GAME_SIMON_REVERSE);
      if (isSimon) {
        if (!buzzer.hasFourPlayers()) {
          showFourPlayersWarning(); // Simon (endroit ou envers) ne se joue qu'à 4
          return CONFIGURATION;
        }
        buzzer.resetScores();       // nouvelle partie : scores remis à zéro
        mp3.playInit();             // son de lancement (dossier 01)
        return INTRO;               // chenillard festif pendant la musique
      }
      // Tous les quiz (Classique, Pénalité, Chronos, Vol) : on choisit
      // d'abord les questions (catégories puis nombre) ; le lancement réel
      // se fait à la fin de quizCount().
      return QUIZ_CATS;
    }
  }

  return CONFIGURATION;
}

// Liste déroulante du sous-menu "C" : mélange des jeux (choisis directement)
// et des réglages (qui ouvrent un écran dédié, ex. le chrono d'un mode donné).
// Ajouter une ligne : l'insérer ici, à la position voulue — l'affichage et le
// défilement s'adaptent tout seuls (rien d'autre à changer).
enum GameListKind { GLK_GAME, GLK_CHRONO };
struct GameListItem {
  const char* label;
  GameListKind kind;
  GameMode target;   // GLK_GAME : jeu à activer ; GLK_CHRONO : mode dont on règle le chrono
};

static const GameListItem GAME_LIST[] = {
  { "Classique",        GLK_GAME,   GAME_CLASSIC },
  { "Penalite (-1)",    GLK_GAME,   GAME_PENALTY },
  { "Chrono classique", GLK_CHRONO, GAME_CHRONO_CLASSIC },
  { "Chrono penalite",  GLK_CHRONO, GAME_CHRONO_PENALTY },
  { "Vol",              GLK_CHRONO, GAME_VOL },
  { "Simon (a 4)",      GLK_GAME,   GAME_SIMON },
  { "Simon inverse",    GLK_GAME,   GAME_SIMON_REVERSE },
};
#define GAME_LIST_COUNT (sizeof(GAME_LIST) / sizeof(GAME_LIST[0]))

// Lignes 0-2 pour la liste (pas de titre : le menu principal a déjà annoncé
// "Jeu" en appuyant sur C) ; la ligne 3 est réservée à l'aide de navigation.
#define GAME_LIST_VISIBLE 3

// Recale la fenêtre visible pour que gameCursor y reste toujours : ne fait
// rien tant que la liste tient déjà sur l'écran, et fait défiler la fenêtre
// (l'élément du haut disparaît, le suivant apparaît en bas) dès qu'on ajoute
// une ligne de plus que GAME_LIST_VISIBLE.
void Configuration::scrollGameWindow() {
  if (gameCursor < gameWindowTop) {
    gameWindowTop = gameCursor;
  } else if (gameCursor > gameWindowTop + GAME_LIST_VISIBLE - 1) {
    gameWindowTop = gameCursor - GAME_LIST_VISIBLE + 1;
  }
  int maxTop = (int)GAME_LIST_COUNT - GAME_LIST_VISIBLE;
  if (maxTop < 0) {
    maxTop = 0;
  }
  gameWindowTop = constrain(gameWindowTop, 0, maxTop);
}

// Curseur ">" sur la ligne en surbrillance. 2/8 le déplacent (et font défiler
// la fenêtre si besoin), # confirme. "2" est physiquement en haut du pavé
// numérique et "8" en bas (comme "2=+ 8=-" sur l'écran Volume).
void Configuration::showGameChoice() {
  for (int row = 0; row < GAME_LIST_VISIBLE; row++) {
    int index = gameWindowTop + row;
    if (index >= (int)GAME_LIST_COUNT) {
      display.setText("", row);
      continue;
    }
    String prefix = (index == gameCursor) ? "> " : "  ";
    display.setText(prefix + GAME_LIST[index].label, row);
  }
  display.setText("2:haut  8:bas  #:OK", 3);
}

void Configuration::setGameChoice() {
  // gameCursor est un membre persistant : on rouvre là où l'animateur a
  // laissé le curseur (ex. sur "Chrono classique" après l'avoir réglé), pas
  // forcément sur le jeu actif — choisir une ligne de réglage ne change pas
  // le jeu en cours. scrollGameWindow() s'assure juste que ce curseur reste
  // visible (utile si la liste a changé de taille entre-temps).
  scrollGameWindow();
  display.clear();
  showGameChoice();
}

PhaseMode Configuration::gameChoice(char pressedKey) {
  switch (pressedKey) {
    case '2':
      gameCursor = (gameCursor - 1 + GAME_LIST_COUNT) % GAME_LIST_COUNT;
      scrollGameWindow();
      showGameChoice();
      break;
    case '8':
      gameCursor = (gameCursor + 1) % GAME_LIST_COUNT;
      scrollGameWindow();
      showGameChoice();
      break;
    case '#': {
      const GameListItem& item = GAME_LIST[gameCursor];
      buzzer.setGameMode(item.target);   // applique le jeu, réglage ou non
      if (item.kind == GLK_CHRONO) {
        chronoTargetMode = item.target;   // quel mode régler (Classique/Pénalité)
        return CHRONO;
      }
      return CONFIGURATION;
    }
    case '*':
      return CONFIGURATION;         // annule : le jeu en cours ne change pas
  }
  return GAME_CHOICE;
}

// Pas de réglage : 1 s à chaque appui.
static int stepBuzzTime(int value, int direction) {
  return value + direction;
}

// Durée alignée sur 3 colonnes : "off", " 5s", "10s".
static String buzzTimeLabel(int seconds) {
  if (seconds <= 0) {
    return "off";
  }
  return String(seconds < 10 ? " " : "") + seconds + "s";
}

// Réglage du chrono en deux étapes, pour le mode visé par chronoTargetMode
// (Classique ou Pénalité, choisi depuis la liste) : un seul réglage à la
// fois, valeur en surbrillance avec "> ", # pour valider et passer à la
// suite. Les touches reprennent le réglage déjà en place sur l'écran Volume
// ("2=+  8=-").
void Configuration::showChronoStep() {
  display.setText(buzzer.gameModeName(chronoTargetMode), 0);   // "Chrono classique"...
  display.setText(chronoStep == CHRONO_FIRST ? "1re reponse" : "Autres reponses", 1);
  display.setText(String("> ") + buzzTimeLabel(chronoCursor), 2);
}

void Configuration::setChronoScreen() {
  chronoStep = CHRONO_FIRST;
  chronoCursor = buzzer.getFirstBuzzTime(chronoTargetMode);
  display.clear();
  showChronoStep();
  display.setText("2=+  8=-  #OK *:ann", 3);
}

PhaseMode Configuration::chronoScreen(char pressedKey) {
  switch (pressedKey) {
    case '2':
      chronoCursor = stepBuzzTime(chronoCursor, +1);
      showChronoStep();
      break;
    case '8':
      chronoCursor = stepBuzzTime(chronoCursor, -1);
      showChronoStep();
      break;
    case '#':
      if (chronoStep == CHRONO_FIRST) {
        buzzer.setFirstBuzzTime(chronoTargetMode, chronoCursor);
        chronoStep = CHRONO_NEXT;
        chronoCursor = buzzer.getNextBuzzTime(chronoTargetMode);
        showChronoStep();
      } else {
        buzzer.setNextBuzzTime(chronoTargetMode, chronoCursor);
        buzzer.saveBuzzTimes();     // durées conservées après extinction
        return CONFIGURATION;       // réglage terminé : retour au menu principal
      }
      break;
    case '*':
      return CONFIGURATION;         // annule : retour au menu principal
  }
  return CHRONO;
}

// ============================================================
// Lancement d'un quiz : choix des questions de la banque
// ============================================================

// Lignes de l'écran des catégories : 0 = Toutes, 1 = Aucune (questionnaire
// perso), puis les catégories cochables.
#define QCAT_ROWS (2 + QCAT_COUNT)
#define QCAT_VISIBLE 3

// Nombre de questions : valeur libre au pas de 1. 0 = Ouvert (l'animateur
// termine avec C, comme avant).
#define QCOUNT_MAX 99

String Configuration::qcatLabel(int row) {
  if (row == 0) {
    return "Toutes";
  }
  if (row == 1) {
    return "Aucune (perso)";
  }
  int c = row - 2;
  String box = (qcatMask & (1 << c)) ? "[x] " : "[ ] ";
  return box + QuestionBank::shared().categoryName(c);
}

void Configuration::showQuizCats() {
  for (int rowOnScreen = 0; rowOnScreen < QCAT_VISIBLE; rowOnScreen++) {
    int row = qcatTop + rowOnScreen;
    if (row >= QCAT_ROWS) {
      display.setText("", rowOnScreen);
      continue;
    }
    String prefix = (row == qcatCursor) ? "> " : "  ";
    display.setText(prefix + qcatLabel(row), rowOnScreen);
  }
  display.setText("2/8 5:cocher #:OK", 3);
}

void Configuration::setQuizCats() {
  // Le masque persiste : on rouvre avec la sélection du match précédent.
  display.clear();
  showQuizCats();
}

PhaseMode Configuration::quizCats(char pressedKey) {
  switch (pressedKey) {
    case '2':
      qcatCursor = (qcatCursor - 1 + QCAT_ROWS) % QCAT_ROWS;
      break;
    case '8':
      qcatCursor = (qcatCursor + 1) % QCAT_ROWS;
      break;
    case '5':
      if (qcatCursor >= 2) {
        qcatMask ^= (1 << (qcatCursor - 2));   // coche/décoche la catégorie
      }
      break;
    case '#':
      if (qcatCursor == 0) {
        qcatMask = (uint16_t)((1 << QCAT_COUNT) - 1);   // Toutes
      } else if (qcatCursor == 1) {
        qcatMask = 0;                                   // Aucune : perso
      } else if (qcatMask == 0) {
        qcatMask = (1 << (qcatCursor - 2));   // rien de coché : celle du curseur
      }
      return QUIZ_COUNT;
    case '*':
      return CONFIGURATION;       // annule le lancement
    default:
      return QUIZ_CATS;
  }

  // Recale la fenêtre visible sur le curseur puis redessine.
  if (qcatCursor < qcatTop) {
    qcatTop = qcatCursor;
  } else if (qcatCursor > qcatTop + QCAT_VISIBLE - 1) {
    qcatTop = qcatCursor - QCAT_VISIBLE + 1;
  }
  showQuizCats();
  return QUIZ_CATS;
}

void Configuration::showQuizCount() {
  display.setText(String("> ") + (qcountIdx == 0 ? String("Ouvert") : String(qcountIdx)), 1);
}

void Configuration::setQuizCount() {
  display.clear();
  display.setText("NB DE QUESTIONS", 0);
  showQuizCount();
  display.setText("Ouvert = C pour finir", 2);
  display.setText("2=+  8=-  #:OK *:ret", 3);
}

PhaseMode Configuration::quizCount(char pressedKey) {
  switch (pressedKey) {
    case '2':
      if (qcountIdx < QCOUNT_MAX) {
        qcountIdx++;
      }
      showQuizCount();
      break;
    case '8':
      if (qcountIdx > 0) {
        qcountIdx--;
      }
      showQuizCount();
      break;
    case '#': {
      // Lancement réel de la partie (remplace l'ancien '#' du menu).
      buzzer.setQuestionLimit(qcountIdx);
      QuestionBank::shared().setSelection(qcatMask);
      buzzer.resetScores();
      if (buzzer.getGameMode() == GAME_VOL) {
        return VOL_SPIN;          // Vol : pas d'intro, tirage au sort direct
      }
      mp3.playInit();             // son de lancement (dossier 01)
      return INTRO;
    }
    case '*':
      return QUIZ_CATS;           // revenir au choix des catégories
  }
  return QUIZ_COUNT;
}

void Configuration::setShuffleBuzzers() {
  // On NE mélange pas encore : on demande confirmation pour éviter
  // d'écraser une configuration faite via l'assistant.
  shufStep = SHUF_CONFIRM;
  display.clear();
  display.setText("SONS AU HASARD", 0);
  display.setText("Ecrase la config !", 1);
  display.setText("# confirmer", 2);
  display.setText("* annuler", 3);
}

PhaseMode Configuration::shuffleBuzzer(char pressedKey) {
  if (shufStep == SHUF_CONFIRM) {
    if (pressedKey == '*') {
      return CONFIGURATION;          // annulé : aucun son modifié
    }
    if (pressedKey == '#') {
      // Confirmé : anime le tirage (chenillard + son, comme le mode Vol)
      // pendant que les sons sont mélangés.
      buzzer.startSpinAnimation();
      shufStep = SHUF_SPINNING;
      display.clear();
      display.setText("  MELANGE DES SONS", 0);
      display.setText("   Ecoute bien...", 1);
    }
    return SHUFFLE_BUZZER;
  }

  if (shufStep == SHUF_SPINNING) {
    // N'importe quelle touche, ou la fin réelle du son, révèle le résultat.
    if (pressedKey || buzzer.tickSpinAnimation()) {
      buzzer.resetLights();
      mp3.shuffleBuzzers();          // on re-tire les sons
      shufStep = SHUF_DONE;
      display.clear();
      display.setText("Nouveaux sons OK", 0);
      display.setText("# retour au menu", 3);
    }
    return SHUFFLE_BUZZER;
  }

  // SHUF_DONE
  if (pressedKey == '#') {
    return CONFIGURATION;
  }
  return SHUFFLE_BUZZER;
}

void Configuration::setVolumeScreen() {
  // Arme l'anti-rebond des buzzers pour éviter un aperçu parasite à l'entrée.
  for (int i = 0; i < 4; i++) {
    buzzer.wasPressed(i);
  }
  display.clear();
  display.setText("      VOLUME", 0);
  display.setText(String("    Vol: ") + mp3.getVolume() + " / 30", 1);
  display.setText("2=+  8=-  Buzz=test", 2);
  display.setText("# : retour", 3);
}

PhaseMode Configuration::volumeScreen(char pressedKey) {
  // Aperçu : appuyer sur un buzzer joue son son au volume courant.
  for (int i = 0; i < 4; i++) {
    if (buzzer.wasPressed(i)) {
      mp3.playBuzzer(i);
    }
  }

  if (pressedKey == '#') {
    mp3.saveVolume();        // mémorise le volume (persistant après extinction)
    return CONFIGURATION;
  }
  if (pressedKey == '2') {
    mp3.volumeUp();
    setVolumeScreen();
  } else if (pressedKey == '8') {
    mp3.volumeDown();
    setVolumeScreen();
  }
  return VOLUME;
}

const char* Configuration::colorName(int i) {
  switch (i) {
    case 0: return "Rouge";
    case 1: return "Bleu";
    case 2: return "Jaune";
    case 3: return "Vert";
    default: return "?";
  }
}

void Configuration::showConfigPrompt() {
  display.clear();
  display.setText(String("CONFIG ") + colorName(cfgIndex), 0);
  display.setText("Appuie sur le buzzer", 1);
  display.setText("* = absent", 2);
  display.setText("# = terminer", 3);
}

void Configuration::showConfigChoice() {
  display.clear();
  display.setText(String(colorName(cfgIndex)) + " - son " + String(mp3.getSound(cfgIndex) + 1), 0);
  display.setText("A=valider  *=absent", 1);
  display.setText("B = son suivant", 2);
  display.setText("C = son precedent", 3);
}

PhaseMode Configuration::advanceConfig() {
  cfgIndex++;
  if (cfgIndex >= 4) {
    buzzer.resetLights();
    return CONFIGURATION; // tous les buzzers traités -> retour au menu
  }
  cfgStep = CFG_PROMPT;
  showConfigPrompt();
  return BUZZER_CONFIG;
}

void Configuration::setBuzzerConfig() {
  mp3.resetConfig();         // déverrouille tous les sons
  buzzer.resetConfigState(); // ré-active tous les buzzers + anti-rebond
  buzzer.resetLights();
  cfgIndex = 0;
  cfgStep = CFG_PROMPT;
  showConfigPrompt();
}

PhaseMode Configuration::buzzerConfig(char pressedKey) {
  // Lecture du bouton physique à chaque tick (front montant anti-rebond).
  bool pressed = buzzer.wasPressed(cfgIndex);

  // Sortie de l'assistant à tout moment.
  if (pressedKey == '#') {
    buzzer.resetLights();
    return CONFIGURATION;
  }

  if (cfgStep == CFG_PROMPT) {
    if (pressedKey == '*') {            // buzzer absent
      buzzer.setEnabled(cfgIndex, false);
      return advanceConfig();
    }
    if (pressed) {                      // buzzer présent : on joue son son
      buzzer.setEnabled(cfgIndex, true);
      mp3.ensureUnlockedSound(cfgIndex);
      buzzer.setLed(cfgIndex, true);
      mp3.playBuzzer(cfgIndex);
      cfgStep = CFG_CHOOSING;
      showConfigChoice();
    }
    return BUZZER_CONFIG;
  }

  // CFG_CHOOSING
  if (pressedKey == 'B') {              // son suivant
    mp3.cycleSound(cfgIndex);
    mp3.playBuzzer(cfgIndex);
    showConfigChoice();
  } else if (pressedKey == 'C') {       // son précédent
    mp3.cyclePrevSound(cfgIndex);
    mp3.playBuzzer(cfgIndex);
    showConfigChoice();
  } else if (pressedKey == 'A') {       // valider et verrouiller
    mp3.lockSound(cfgIndex);
    buzzer.setLed(cfgIndex, false);
    return advanceConfig();
  } else if (pressedKey == '*') {       // finalement absent
    buzzer.setEnabled(cfgIndex, false);
    buzzer.setLed(cfgIndex, false);
    return advanceConfig();
  } else if (pressed) {                 // ré-appui : rejoue le son courant
    mp3.playBuzzer(cfgIndex);
  }

  return BUZZER_CONFIG;
}