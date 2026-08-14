#include "SoundGame.h"

void SoundGame::reset() {
  for (int i = 0; i < 4; i++) {
    scores[i] = 0;
    buzzed[i] = false;
  }
  aborted = false;
  played = 0;
  totalSounds = buzzer.getGameRounds(GAME_SOUND);
  decoys = buzzer.getSoundDecoys();
  interval = SOUND_INTERVAL_START;
  owner = -1;
  claimed = false;
  learnIndex = -1;
  learnDone = false;
}

String SoundGame::scoreLine() {
  String s = "";
  for (int i = 0; i < 4; i++) {
    if (!buzzer.isEnabled(i)) {
      continue;
    }
    if (s.length() > 0) {
      s += " ";
    }
    s += String(buzzer.colorName(i)[0]) + String(scores[i]);
  }
  return s;
}

void SoundGame::showProgress() {
  display.setText(String("NE BUZZE PAS  ") + played + "/" + totalSounds, 0);
}

// === Apprentissage des sons ===
// Chaque son est joue une fois, LED allumee et couleur nommee : l'assistant
// garantit 4 fichiers differents, pas 4 sons reconnaissables a l'oreille.
// C'est ici que l'animateur s'en apercoit, avant que ca compte.
void SoundGame::setLearn() {
  learnIndex = -1;
  learnDone = false;
  learnStart = millis();

  buzzer.resetLights();
  display.clear();
  display.setText("NE BUZZE PAS", 0);
  display.setText("Apprenez les sons", 1);
  display.setText("C: retour au menu", 3);
}

PhaseMode SoundGame::learn(char pressedKey) {
  if (pressedKey == 'C') {
    buzzer.resetLights();
    return CONFIGURATION;
  }

  if (learnDone) {
    return (pressedKey == '#') ? SOUND_PLAY : SOUND_LEARN;
  }

  if (millis() - learnStart < SOUND_LEARN_MS) {
    return SOUND_LEARN;
  }

  if (learnIndex >= 0) {
    buzzer.setLed(learnIndex, false);
  }

  int next = -1;
  for (int i = learnIndex + 1; i < 4; i++) {
    if (buzzer.isEnabled(i)) {
      next = i;
      break;
    }
  }

  if (next < 0) {
    learnDone = true;
    display.setText("", 2);
    display.setText("#: c'est parti", 3);
    return SOUND_LEARN;
  }

  learnIndex = next;
  buzzer.setLed(next, true);
  mp3.playBuzzer(next);
  display.setText(String("Son de ") + buzzer.colorName(next), 2);
  learnStart = millis();
  return SOUND_LEARN;
}

// === Flux continu ===
int SoundGame::pickPlayer() {
  int pool[4];
  int n = 0;
  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i)) {
      pool[n++] = i;
    }
  }
  return (n > 0) ? pool[random(n)] : -1;
}

int SoundGame::pickOwner() {
  if (decoys && (int)random(100) < SOUND_DECOY_PERCENT) {
    return -1;               // leurre
  }
  return pickPlayer();
}

// Un son du dossier des buzzers qui n'appartient a aucun joueur PRESENT : le
// son d'un buzzer declare absent fait un leurre parfaitement valable, puisque
// personne ne l'a appris.
int SoundGame::pickDecoySound() {
  int poolSize = mp3.buzzerSoundPoolSize();
  if (poolSize <= 0) {
    return -1;
  }

  for (int tries = 0; tries < 20; tries++) {
    int idx = random(poolSize);
    bool owned = false;
    for (int i = 0; i < 4; i++) {
      if (buzzer.isEnabled(i) && mp3.getSound(i) == idx) {
        owned = true;
      }
    }
    if (!owned) {
      return idx;
    }
  }
  return -1;                 // pas assez de sons libres
}

void SoundGame::playNext() {
  played++;
  claimed = false;
  for (int i = 0; i < 4; i++) {
    buzzed[i] = false;
  }

  owner = pickOwner();
  if (owner >= 0) {
    mp3.playBuzzer(owner);
  } else {
    int decoy = pickDecoySound();
    if (decoy >= 0) {
      mp3.playBuzzerSound(decoy);
    } else {
      owner = pickPlayer();          // aucun son libre : on retombe sur un joueur
      if (owner >= 0) {
        mp3.playBuzzer(owner);
      }
    }
  }

  soundStart = millis();
  showProgress();
}

void SoundGame::handleBuzz(int i, unsigned long now) {
  if (buzzed[i]) {
    return;                  // un seul verdict par son et par joueur
  }
  buzzed[i] = true;

  if (i == owner) {
    claimed = true;
    // Buzzer dans la PREMIERE MOITIE de l'ecart courant rapporte +2 au lieu
    // de +1 : sans ce bonus, ecouter le son en entier avant de se decider
    // est une strategie sans risque (l'ecart laisse largement le temps de
    // reconnaitre n'importe quel son avant la fin). Se tromper reste -1
    // quelle que soit la vitesse : la rapidite n'est recompensee que si
    // c'est le bon son, pour ne pas inciter a buzzer au hasard.
    unsigned long elapsed = now - soundStart;
    if (elapsed <= interval / 2) {
      scores[i] += 2;
      display.setText(String(buzzer.colorName(i)) + " +2 rapide !", 1);
    } else {
      scores[i]++;
      display.setText(String(buzzer.colorName(i)) + " +1", 1);
    }
  } else {
    scores[i]--;
    display.setText(String(buzzer.colorName(i)) + " se trompe !", 1);
  }
}

// Verdict du son qui vient de s'ecouler, au moment ou le suivant demarre.
void SoundGame::judgeCurrent() {
  if (owner >= 0) {
    if (!claimed) {
      scores[owner]--;       // laisser passer son propre son coute un point
      display.setText(String(buzzer.colorName(owner)) + " a rate", 1);
    }
    return;
  }

  // Leurre : personne n'aurait du buzzer. Si un joueur s'est fait prendre,
  // handleBuzz a deja affiche son erreur.
  for (int i = 0; i < 4; i++) {
    if (buzzed[i]) {
      return;
    }
  }
  display.setText("Leurre evite !", 1);
}

void SoundGame::setPlay() {
  buzzer.armButtons();
  buzzer.resetLights();      // aucune LED pendant le flux : elle trahirait le son

  played = 0;
  interval = SOUND_INTERVAL_START;

  display.clear();
  display.setText(scoreLine(), 3);
  playNext();
}

PhaseMode SoundGame::play(char pressedKey) {
  unsigned long now = millis();

  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i) && buzzer.wasPressed(i)) {
      handleBuzz(i, now);
    }
  }

  if (pressedKey == 'C') {
    aborted = true;
    return SOUND_OVER;
  }

  // La limite pour buzzer n'est pas une fenetre arbitraire : c'est le son
  // suivant. On solde donc le son courant juste avant d'enchainer.
  if (now - soundStart >= interval) {
    judgeCurrent();
    display.setText(scoreLine(), 3);

    if (played >= totalSounds) {
      return SOUND_OVER;
    }

    if (interval >= SOUND_INTERVAL_MIN + SOUND_INTERVAL_STEP) {
      interval -= SOUND_INTERVAL_STEP;   // ca se resserre au fil de la partie
    } else {
      interval = SOUND_INTERVAL_MIN;
    }
    playNext();
  }

  return SOUND_PLAY;
}

// === Fin de partie ===
void SoundGame::setGameOver() {
  buzzer.resetLights();

  // Les scores peuvent etre negatifs : le meilleur n'est pas forcement > 0.
  int maxScore = 0;
  bool any = false;
  for (int i = 0; i < 4; i++) {
    if (!buzzer.isEnabled(i)) {
      continue;
    }
    if (!any || scores[i] > maxScore) {
      maxScore = scores[i];
      any = true;
    }
  }

  int leaders = 0;
  int who = -1;
  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i) && scores[i] == maxScore) {
      leaders++;
      who = i;
    }
  }

  display.clear();
  if (aborted) {
    display.setText("     ABANDON", 0);
  } else if (!any) {
    display.setText("  Aucun joueur", 0);
  } else if (leaders > 1) {
    display.setText("     EGALITE !", 0);
  } else {
    buzzer.setLed(who, true);
    display.setText(String("  ") + buzzer.colorName(who) + " GAGNE !", 0);
  }

  display.setText(scoreLine(), 1);
  display.setText(String(played) + " sons" + (decoys ? ", leurres" : ""), 2);
  display.setText("#: rejouer  *: menu", 3);

  if (!aborted && any && leaders == 1) {
    mp3.playGoodAnswer();
  } else {
    mp3.playBadAnswer();
  }
}

PhaseMode SoundGame::gameOver(char pressedKey) {
  if (pressedKey == '#') {
    reset();
    return SOUND_LEARN;       // nouvelle partie : on re-ecoute les sons
  }
  if (pressedKey == '*') {
    buzzer.resetLights();
    return CONFIGURATION;
  }
  return SOUND_OVER;
}
