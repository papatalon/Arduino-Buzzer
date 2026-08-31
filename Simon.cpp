#include "Simon.h"

void Simon::reset() {
  level = 0;
  length = 0;
  overTitle = "";
  failedBuzzer = -1;
  reverse = (buzzer.getGameMode() == GAME_SIMON_REVERSE);
  inputIndex = 0;

  // Les couleurs de la partie sont celles des buzzers presents. Sans ca, a
  // deux joueurs, la machine demanderait des couleurs que personne ne tient.
  playerCount = 0;
  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i)) {
      players[playerCount++] = (uint8_t)i;
    }
  }
  // Filet de securite : Configuration refuse deja de lancer a moins de deux,
  // mais random(0) n'aurait aucun sens si on arrivait ici autrement.
  if (playerCount == 0) {
    for (int i = 0; i < 4; i++) {
      players[i] = (uint8_t)i;
    }
    playerCount = 4;
  }

  sendTelemetry();
  // Simon n'a ni score ni manche, mais "GROUND|0" reste le signal generique
  // de nouvelle partie cote app : sans lui, l'ecran public garderait le
  // "partie terminee" du Simon precedent.
  ble.sendGameRound(0, 0);
}

void Simon::showTitle() {
  display.setText(String("SIMON - Niveau ") + (level + 1), 0);
}

void Simon::showProgress() {
  display.setText(String("      ") + inputIndex + " / " + length, 2);
  sendTelemetry();
}

// Simon est le seul jeu sans score : ce qu'il y a a montrer, c'est le niveau
// atteint et l'avancement dans la sequence en cours. D'ou un message a lui
// plutot qu'un GSCORE vide qui ferait afficher un tableau de zeros.
void Simon::sendTelemetry() {
  ble.send(String("SIMON|") + level + "|" + inputIndex + "|" + length);
}

PhaseMode Simon::fail(const char* title) {
  overTitle = title;
  return SIMON_OVER;
}

// === Demonstration de la sequence ===
// Une couleur est ajoutee a chaque entree : le niveau N joue N couleurs.
void Simon::setShowSequence() {
  failedBuzzer = -1;

  if (length < SIMON_MAX_LEVEL) {
    sequence[length] = players[random(playerCount)];
    length++;
  }

  showIndex = 0;
  showLit = false;          // on commence par la pause de lecture (SIMON_START_MS)
  stepStart = millis();
  inputIndex = 0;           // rien de saisi tant que la demo tourne

  buzzer.resetLights();
  display.clear();
  showTitle();
  display.setText("Observez la sequence", 1);
  display.setText("Chacun sa couleur !", 3);
  sendTelemetry();
}

PhaseMode Simon::showSequence(char pressedKey) {
  if (pressedKey == 'C') {
    return fail("      ABANDON");
  }

  unsigned long now = millis();

  // Couleur allumee : on l'eteint au bout de SIMON_ON_MS.
  if (showLit) {
    if (now - stepStart >= SIMON_ON_MS) {
      buzzer.setLed(sequence[showIndex], false);
      showIndex++;
      showLit = false;
      stepStart = now;
    }
    return SIMON_SHOW;
  }

  // Silence entre deux couleurs (plus long avant la premiere, pour laisser
  // le temps de lire l'ecran).
  unsigned long gap = (showIndex == 0) ? SIMON_START_MS : SIMON_GAP_MS;
  if (now - stepStart < gap) {
    return SIMON_SHOW;
  }

  if (showIndex >= length) {
    return SIMON_PLAY;      // sequence entierement jouee : a l'equipe !
  }

  buzzer.setLed(sequence[showIndex], true);
  mp3.playBuzzer(sequence[showIndex]);   // le son configure du buzzer
  showLit = true;
  stepStart = now;
  return SIMON_SHOW;
}

// === Repetition par les joueurs ===
void Simon::setPlaySequence() {
  inputIndex = 0;
  litBuzzer = -1;
  roundDone = false;
  lastInput = millis();

  buzzer.resetLights();
  buzzer.armButtons();      // ignore les appuis en cours pendant la demo

  display.clear();
  showTitle();
  display.setText(reverse ? "Repetez a l'envers!" : "A vous de repeter !", 1);
  showProgress();
  display.setText("C: abandon", 3);
}

PhaseMode Simon::playSequence(char pressedKey) {
  unsigned long now = millis();

  // Echo lumineux du dernier appui : la LED s'eteint toute seule.
  if (litBuzzer >= 0 && now - litStart >= SIMON_ECHO_MS) {
    buzzer.setLed(litBuzzer, false);
    litBuzzer = -1;
  }

  // Tour reussi : courte pause "BRAVO" avant d'allonger la sequence.
  if (roundDone) {
    if (now - stepStart >= SIMON_ROUND_MS) {
      return SIMON_SHOW;
    }
    return SIMON_PLAY;
  }

  if (pressedKey == 'C') {
    return fail("      ABANDON");
  }

  if (now - lastInput >= SIMON_TIMEOUT_MS) {
    return fail("    TROP LENT !");
  }

  for (int i = 0; i < 4; i++) {
    // Un buzzer declare absent reste branche : sans ce filtre, un appui
    // dessus ferait echouer une partie a laquelle il ne participe pas.
    if (!buzzer.isEnabled(i) || !buzzer.wasPressed(i)) {
      continue;
    }

    lastInput = now;
    buzzer.setLed(i, true);     // on montre la couleur appuyee, juste ou fausse
    litBuzzer = i;
    litStart = now;

    // La demo est toujours montree du debut a la fin ; en mode inverse, c'est
    // la fin de la sequence qui doit etre rejouee en premier.
    int expected = reverse ? (length - 1 - inputIndex) : inputIndex;
    if (sequence[expected] != i) {
      failedBuzzer = i;              // sa LED reste allumee sur l'ecran de fin
      return fail("      RATE !");   // le son d'echec est joue par setGameOver
    }

    inputIndex++;
    if (inputIndex < length) {
      mp3.playBuzzer(i);        // bonne couleur : son du buzzer
      showProgress();
      return SIMON_PLAY;
    }

    // Sequence complete : niveau reussi.
    level++;
    if (level >= SIMON_MAX_LEVEL) {
      return fail("    PARFAIT !!!");   // sequence maxi atteinte
    }

    roundDone = true;
    stepStart = now;
    mp3.playGoodAnswer();
    display.setText("      BRAVO !", 1);
    display.setText(String("  Niveau ") + level + " reussi", 2);
    display.setText("", 3);
    return SIMON_PLAY;
  }

  return SIMON_PLAY;
}

// === Fin de partie ===
void Simon::setGameOver() {
  buzzer.resetLights();

  const char* comment;
  if (level >= SIMON_MAX_LEVEL) {
    comment = "Memoire d'elephant !";
  } else if (level >= 12) {
    comment = "Impressionnant !";
  } else if (level >= 8) {
    comment = "Belle memoire !";
  } else if (level >= 4) {
    comment = "Pas mal du tout !";
  } else if (level >= 1) {
    comment = "Peut mieux faire !";
  } else {
    comment = "Meme pas un niveau !";
  }

  display.clear();
  if (failedBuzzer >= 0) {
    // On montre la couleur fautive, LED allumee et nommee a l'ecran.
    buzzer.setLed(failedBuzzer, true);
    display.setText(String("  RATE ! -> ") + buzzer.colorName(failedBuzzer), 0);
  } else {
    display.setText(overTitle, 0);
  }
  display.setText(String("Niveau atteint : ") + level, 1);
  display.setText(comment, 2);
  display.setText("#: rejouer   *: menu", 3);
  sendTelemetry();
  // Jeu collaboratif : jamais de gagnant individuel, mais l'app doit savoir
  // que la partie est finie pour afficher le niveau atteint plutot que le
  // niveau en cours.
  ble.sendGameOver(-1, false);

  if (level >= SIMON_MAX_LEVEL) {
    mp3.playGoodAnswer();
  } else {
    mp3.playBadAnswer();
  }
}

PhaseMode Simon::gameOver(char pressedKey) {
  if (pressedKey == '#') {
    reset();
    return SIMON_SHOW;      // on rejoue une partie
  }
  if (pressedKey == '*') {
    buzzer.resetLights();
    return CONFIGURATION;
  }
  return SIMON_OVER;
}
