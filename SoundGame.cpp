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
  buildCourse();            // apres decoys : les leurres en dependent
  interval = SOUND_INTERVAL_START;
  owner = -1;
  claimed = false;
  learnIndex = -1;
  learnDone = false;

  // Scores propres au jeu, distincts de ceux du quiz : voir
  // BleLink::sendGameScores.
  ble.sendGameScores(scores);
  ble.sendGameRound(0, totalSounds);
  ble.send("SNDO|-2|0");   // -2 = rien a reveler encore (nouvelle partie)
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
  // Ici les "manches" sont des sons : meme forme, meme message que les
  // autres jeux a manches.
  ble.sendGameRound(played, totalSounds);
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
    ble.send("SNDL|-1");     // apprentissage termine
    return SOUND_LEARN;
  }

  learnIndex = next;
  buzzer.setLed(next, true);
  mp3.playBuzzer(next);
  display.setText(String("Son de ") + buzzer.colorName(next), 2);
  // Pendant l'apprentissage, dire a qui appartient le son est le BUT : la
  // LED s'allume et la couleur est nommee. Rien a cacher a ce stade.
  ble.send(String("SNDL|") + next);
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

// MONTER LE PARCOURS : chaque buzzer present obtient EXACTEMENT le meme
// nombre de tours.
//
// Le menu demande un nombre total de sons ; on le repartit ici. Ce qui ne
// tombe pas juste sur le nombre de joueurs devient des leurres, ce qui laisse
// le total conforme a ce que l'animateur a regle. Sans leurres, le total est
// arrondi vers le bas : mieux vaut deux sons de moins qu'un joueur lese.
void SoundGame::buildCourse() {
  int players[4];
  int n = 0;
  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i)) {
      players[n++] = i;
    }
  }
  if (n == 0) {
    totalSounds = 0;
    return;
  }

  int total = totalSounds;
  if (total > GAME_ROUNDS_MAX) {
    total = GAME_ROUNDS_MAX;
  }

  // Part de leurres tiree au sort pour que deux parties ne se ressemblent
  // pas, mais bornee par le total : vingt tours ne peuvent pas porter cent
  // leurres.
  int wanted = 0;
  bool canDecoy = decoys && pickDecoySound() >= 0;
  if (canDecoy) {
    int lo = (total * SOUND_DECOY_MIN_PCT) / 100;
    int hi = (total * SOUND_DECOY_MAX_PCT) / 100;
    wanted = lo + ((hi > lo) ? (int)random(hi - lo + 1) : 0);
  }

  int chances = (total - wanted) / n;
  if (chances < 1) {
    chances = 1;              // au moins un tour chacun, meme sur une partie courte
  }
  int playerRounds = chances * n;
  int decoyCount = canDecoy ? (total - playerRounds) : 0;
  if (decoyCount < 0) {
    decoyCount = 0;
  }
  int len = playerRounds + decoyCount;
  if (len > SOUND_COURSE_MAX) {
    len = SOUND_COURSE_MAX;
  }

  // Combien il reste a placer. L'index 4 porte les leurres : un compteur a
  // part plutot qu'une valeur -1 melee aux joueurs, sinon "leurre choisi" et
  // "rien trouve" se confondent et le tri se trompe en silence.
  int8_t left[5] = { 0, 0, 0, 0, 0 };
  for (int k = 0; k < n; k++) {
    left[players[k]] = (int8_t)chances;
  }
  left[4] = (int8_t)decoyCount;

  // ETALER LES TOURS D'UN MEME BUZZER : deux tours de suite pour la meme
  // personne se jouent mal, elle vient de peser et son son revient une
  // seconde et demie plus tard. On place toujours celui a qui il reste le
  // plus de tours parmi ceux qui ne viennent pas de jouer, ce qui donne
  // toujours un ordre valide quand il en existe un. Les leurres ont le droit
  // de se suivre : ce sont des sons differents a chaque fois.
  int prev = -2;
  int pos = 0;
  while (pos < len) {
    int best = -1;
    int bestLeft = 0;
    int start = (int)random(5);      // depart tournant : sinon le rouge passe toujours en premier a egalite
    for (int t = 0; t < 5; t++) {
      int c = (start + t) % 5;
      if (left[c] <= 0) {
        continue;
      }
      if (c != 4 && c == prev) {
        continue;
      }
      if (left[c] > bestLeft) {
        bestLeft = left[c];
        best = c;
      }
    }
    if (best < 0) {
      for (int c = 0; c < 5; c++) {  // dernier recours : il ne reste que celui qu'on vient de jouer
        if (left[c] > 0) {
          best = c;
          break;
        }
      }
    }
    if (best < 0) {
      break;
    }
    left[best]--;
    course[pos++] = (best == 4) ? -1 : (int8_t)best;
    prev = (best == 4) ? -2 : best;
  }

  totalSounds = pos;
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

  // Le parcours est monte d'avance : on lit la case du tour, on ne tire plus.
  owner = (played >= 1 && played <= totalSounds) ? course[played - 1] : -1;
  if (owner >= 0) {
    mp3.playBuzzer(owner);
  } else {
    int decoy = pickDecoySound();
    if (decoy >= 0 || mp3.isDelegated()) {
      // Delegue : l'app choisit elle-meme un leurre qu'aucun buzzer
      // present ne possede (elle seule connait les assignations), donc
      // l'index calcule ici est ignore de son cote.
      mp3.playDecoySound(decoy);
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
  // Le proprietaire n'est revele qu'ICI, jamais pendant que le son joue :
  // c'est toute la question du jeu, et l'ecran public y repondrait avant
  // les joueurs. A cet instant la fenetre pour buzzer est deja fermee.
  ble.send(String("SNDO|") + owner + "|" + (claimed ? 1 : 0));

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
    ble.sendGameScores(scores);

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

  const bool decided = !aborted && any;
  ble.sendGameScores(scores);
  ble.sendGameOver(decided && leaders == 1 ? who : -1, decided && leaders > 1);

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
