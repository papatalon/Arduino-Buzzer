#include "Duel.h"

// Repere les deux buzzers presents parmi les 4. Configuration a deja verifie
// qu'il y en a exactement deux avant d'autoriser le lancement (voir
// Buzzer::hasExactlyTwoPlayers()) ; si jamais ce n'etait pas le cas, on garde
// les valeurs precedentes plutot que de planter sur un indice invalide.
void Duel::findPlayers() {
  int found[2];
  int n = 0;
  for (int i = 0; i < 4 && n < 2; i++) {
    if (buzzer.isEnabled(i)) {
      found[n++] = i;
    }
  }
  if (n == 2) {
    playerA = found[0];
    playerB = found[1];
  }
}

void Duel::reset() {
  for (int i = 0; i < 4; i++) {
    scores[i] = 0;
  }
  findPlayers();
  round = 0;
  totalRounds = buzzer.getGameRounds(GAME_DUEL);
  aborted = false;
  winner = -1;
  winnerMs = 0;
  falseStart = false;
  falseStarter = -1;
}

// "Rouge 2   Vert 1" : toujours les deux mêmes duellistes, pas besoin
// d'initiales compactes comme les jeux a 4.
String Duel::scoreLine() {
  return String(buzzer.colorName(playerA)) + " " + scores[playerA]
       + "   " + buzzer.colorName(playerB) + " " + scores[playerB];
}

// === Attente du signal ===
void Duel::setArm() {
  round++;
  winner = -1;
  falseStart = false;
  falseStarter = -1;

  buzzer.resetLights();
  buzzer.armButtons();

  waitMs = random(DUEL_WAIT_MIN_MS, DUEL_WAIT_MAX_MS);
  armStart = millis();

  display.clear();
  display.setText(String("DUEL  Manche ") + round + "/" + totalRounds, 0);
  display.setText(String(buzzer.colorName(playerA)) + " vs " + buzzer.colorName(playerB), 1);
  display.setText("Le son va sonner...", 2);
  display.setText("C: terminer", 3);
}

PhaseMode Duel::arm(char pressedKey) {
  if (pressedKey == 'C') {
    aborted = true;
    return DUEL_OVER;
  }

  // Faux depart : buzzer avant le signal offre directement la manche a
  // l'adversaire, qui n'a rien besoin de faire (ils ne sont que deux).
  if (buzzer.wasPressed(playerA)) {
    falseStart = true;
    falseStarter = playerA;
    winner = playerB;
    return DUEL_RESULT;
  }
  if (buzzer.wasPressed(playerB)) {
    falseStart = true;
    falseStarter = playerB;
    winner = playerA;
    return DUEL_RESULT;
  }

  if (millis() - armStart >= waitMs) {
    return DUEL_GO;
  }
  return DUEL_ARM;
}

// === Le signal : sonore, pas visuel ===
// Un seul haut-parleur pour les deux duellistes : ils entendent le signal au
// meme instant, donc le delai de demarrage reel du DFPlayer (quelques
// dizaines de ms) ne favorise personne — seul l'ecart entre les deux appuis
// compte, pas l'instant absolu du signal.
//
// Le signal est un son de buzzer tire au hasard dans tout le dossier (pas
// forcement celui d'un des deux duellistes) plutot que toujours le meme
// fichier : avec un seul son fixe, les joueurs finiraient par en reconnaitre
// le tout debut et partiraient dessus au lieu d'attendre le signal complet.
void Duel::setGo() {
  buzzer.armButtons();

  int poolSize = mp3.buzzerSoundPoolSize();
  if (poolSize > 0) {
    mp3.playBuzzerSound(random(poolSize));
  } else {
    mp3.playSpin();        // repli improbable : dossier des buzzers vide
  }
  goStart = millis();

  display.clear();
  display.setText("      GO !", 1);
}

PhaseMode Duel::go(char pressedKey) {
  unsigned long now = millis();

  if (buzzer.wasPressed(playerA)) {
    winner = playerA;
    winnerMs = (unsigned int)(now - goStart);
    return DUEL_RESULT;
  }
  if (buzzer.wasPressed(playerB)) {
    winner = playerB;
    winnerMs = (unsigned int)(now - goStart);
    return DUEL_RESULT;
  }

  if (pressedKey == 'C') {
    aborted = true;
    return DUEL_OVER;
  }

  if (now - goStart >= DUEL_ANSWER_MS) {
    winner = -1;             // les deux trop lents
    return DUEL_RESULT;
  }
  return DUEL_GO;
}

// === Resultat de la manche ===
void Duel::setResult() {
  buzzer.resetLights();
  display.clear();

  if (winner >= 0) {
    scores[winner]++;
    buzzer.setLed(winner, true);
    mp3.playBuzzer(winner);
    if (falseStart) {
      display.setText(String(buzzer.colorName(falseStarter)) + " faux depart !", 0);
      display.setText(String(buzzer.colorName(winner)) + " gagne la manche", 1);
    } else {
      display.setText(String(buzzer.colorName(winner)) + " gagne !", 0);
      display.setText(String("Temps : ") + winnerMs + " ms", 1);
    }
  } else {
    mp3.playBadAnswer();
    display.setText("Personne n'a buzze!", 0);
    display.setText("Manche nulle", 1);
  }

  display.setText(scoreLine(), 2);
  display.setText(round >= totalRounds ? "#: resultats" : "#: manche suivante", 3);
}

PhaseMode Duel::result(char pressedKey) {
  if (pressedKey == 'C') {
    aborted = true;
    return DUEL_OVER;
  }
  if (pressedKey == '#') {
    return (round >= totalRounds) ? DUEL_OVER : DUEL_ARM;
  }
  return DUEL_RESULT;
}

// === Fin de partie ===
void Duel::setGameOver() {
  buzzer.resetLights();
  display.clear();

  bool tie = (scores[playerA] == scores[playerB]);
  if (aborted) {
    display.setText("     ABANDON", 0);
  } else if (tie) {
    display.setText("     EGALITE !", 0);
  } else {
    int champ = (scores[playerA] > scores[playerB]) ? playerA : playerB;
    buzzer.setLed(champ, true);
    display.setText(String("  ") + buzzer.colorName(champ) + " GAGNE !", 0);
  }

  display.setText(scoreLine(), 1);
  display.setText("#: rejouer  *: menu", 3);

  if (!aborted && !tie) {
    mp3.playGoodAnswer();
  } else {
    mp3.playBadAnswer();
  }
}

PhaseMode Duel::gameOver(char pressedKey) {
  if (pressedKey == '#') {
    reset();
    return DUEL_ARM;         // nouvelle partie
  }
  if (pressedKey == '*') {
    buzzer.resetLights();
    return CONFIGURATION;
  }
  return DUEL_OVER;
}
