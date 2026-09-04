#include "Reflex.h"
#include <EEPROM.h>

void Reflex::reset() {
  for (int i = 0; i < 4; i++) {
    scores[i] = 0;
    falseStart[i] = false;
  }
  round = 0;
  totalRounds = buzzer.getGameRounds(GAME_REFLEX);
  aborted = false;
  bestMs = 0;
  newRecord = false;
  winner = -1;
  winnerMs = 0;

  // Les scores du Reflexe n'ont rien a voir avec ceux du quiz : sans cette
  // remise a zero annoncee, l'app garderait a l'ecran ceux de la partie
  // precedente.
  ble.sendGameScores(scores);
  ble.sendGameRound(0, totalRounds);
  ble.send("RFLX|-1|0|0");   // efface le resultat de la partie precedente
}

// Buzzers presents qui n'ont pas fait de faux depart dans la manche en cours.
int Reflex::activePlayers() {
  int n = 0;
  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i) && !falseStart[i]) {
      n++;
    }
  }
  return n;
}

// "R2 B1 J0 V1" : initiale de la couleur + score, pour les buzzers presents.
String Reflex::scoreLine() {
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

unsigned int Reflex::readRecord() {
  return (unsigned int)EEPROM.read(REFLEX_EEPROM_RECORD)
       | ((unsigned int)EEPROM.read(REFLEX_EEPROM_RECORD + 1) << 8);
}

void Reflex::writeRecord(unsigned int ms) {
  EEPROM.update(REFLEX_EEPROM_RECORD, (uint8_t)(ms & 0xFF));
  EEPROM.update(REFLEX_EEPROM_RECORD + 1, (uint8_t)(ms >> 8));
}

// === Attente du signal ===
void Reflex::setArm() {
  round++;
  for (int i = 0; i < 4; i++) {
    falseStart[i] = false;
  }
  winner = -1;
  winnerMs = 0;

  buzzer.resetLights();
  buzzer.armButtons();      // un bouton deja maintenu ne compte pas comme faux depart

  waitMs = random(REFLEX_WAIT_MIN_MS, REFLEX_WAIT_MAX_MS);
  armStart = millis();

  display.clear();
  // Une seule espace apres REFLEXE : au pire ("20/20") la ligne fait pile les
  // 20 colonnes du LCD, donc elle ne se met jamais a defiler.
  display.setText(String("REFLEXE Manche ") + round + "/" + totalRounds, 0);
  display.setText(F("Attendez le signal.."), 1);
  display.setText(F("C: terminer"), 3);

  ble.sendGameRound(round, totalRounds);
}

PhaseMode Reflex::arm(char pressedKey) {
  if (pressedKey == 'C') {
    aborted = true;
    return REFLEX_OVER;
  }

  // Faux depart : buzzer avant le signal elimine pour la manche en cours.
  for (int i = 0; i < 4; i++) {
    if (!buzzer.isEnabled(i) || falseStart[i]) {
      continue;
    }
    if (!buzzer.wasPressed(i)) {
      continue;
    }
    falseStart[i] = true;
    mp3.playBadAnswer();
    display.setText(String("Faux depart: ") + buzzer.colorName(i), 2);
    // Un faux depart est deja public (LED + ecran du buzzer) : l'annoncer a
    // la salle ne divulgue rien sur le signal a venir.
    ble.send(String("RFLXF|") + i);
  }

  // Plus personne en lice : manche nulle.
  if (activePlayers() == 0) {
    winner = -1;
    return REFLEX_RESULT;
  }

  if (millis() - armStart >= waitMs) {
    return REFLEX_GO;
  }
  return REFLEX_ARM;
}

// === Le signal ===
// Ordre important : on arme les boutons, on allume, on horodate, et SEULEMENT
// ensuite on ecrit a l'ecran (l'I2C du LCD prend quelques ms, sans commune
// mesure avec un temps de reaction humain, mais autant les sortir du chemin).
void Reflex::setGo() {
  buzzer.armButtons();

  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i) && !falseStart[i]) {
      buzzer.setLed(i, true);
    }
  }
  goStart = millis();

  display.clear();
  display.setText(F("   MAINTENANT !"), 1);
}

PhaseMode Reflex::go(char pressedKey) {
  unsigned long now = millis();

  // Les boutons d'abord : rien ne doit retarder la mesure.
  for (int i = 0; i < 4; i++) {
    if (!buzzer.isEnabled(i) || falseStart[i]) {
      continue;
    }
    if (buzzer.wasPressed(i)) {
      winner = i;
      winnerMs = (unsigned int)(now - goStart);
      return REFLEX_RESULT;
    }
  }

  if (pressedKey == 'C') {
    aborted = true;
    return REFLEX_OVER;
  }

  if (now - goStart >= REFLEX_ANSWER_MS) {
    winner = -1;             // personne n'a buzze a temps
    return REFLEX_RESULT;
  }
  return REFLEX_GO;
}

// === Resultat de la manche ===
void Reflex::setResult() {
  buzzer.resetLights();
  display.clear();

  if (winner >= 0) {
    scores[winner]++;
    if (bestMs == 0 || winnerMs < bestMs) {
      bestMs = winnerMs;
    }
    buzzer.setLed(winner, true);
    mp3.playBuzzer(winner);
    display.setText(String(buzzer.colorName(winner)) + " gagne !", 0);
    display.setText(String("Temps : ") + winnerMs + " ms", 1);
  } else {
    mp3.playBadAnswer();
    // Manche nulle pour deux raisons distinctes : tout le monde elimine avant
    // le signal, ou signal donne mais personne n'a buzze a temps.
    display.setText(activePlayers() == 0 ? F("Tous faux depart !") : F("Personne n'a buzze!"), 0);
    display.setText(F("Manche nulle"), 1);
  }

  display.setText(scoreLine(), 2);
  display.setText(round >= totalRounds ? F("#: resultats") : F("#: manche suivante"), 3);

  ble.sendGameScores(scores);
  // Envoye seulement ICI, jamais pendant l'attente ni au signal : un message
  // qui part au moment du GO ferait changer l'ecran public, que les joueurs
  // pourraient prendre comme signal a la place de la LED. Le BLE est bien
  // trop lent et irregulier pour arbitrer des temps de reaction.
  ble.send(String("RFLX|") + winner + "|" + winnerMs + "|" + bestMs);
}

PhaseMode Reflex::result(char pressedKey) {
  if (pressedKey == 'C') {
    aborted = true;
    return REFLEX_OVER;
  }
  if (pressedKey == '#') {
    return (round >= totalRounds) ? REFLEX_OVER : REFLEX_ARM;
  }
  return REFLEX_RESULT;
}

// === Fin de partie ===
void Reflex::setGameOver() {
  buzzer.resetLights();

  // Gagnant : meilleur score parmi les buzzers presents (egalite possible).
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

  // Record persistant du meilleur temps de reaction.
  newRecord = false;
  unsigned int record = readRecord();
  if (bestMs > 0 && (record == REFLEX_NO_RECORD || record == 0 || bestMs < record)) {
    writeRecord(bestMs);
    newRecord = true;
  }

  display.clear();
  if (aborted) {
    display.setText(F("     ABANDON"), 0);
  } else if (!any || maxScore == 0) {
    display.setText(F("  Aucun vainqueur"), 0);
  } else if (leaders > 1) {
    display.setText(F("     EGALITE !"), 0);
  } else {
    buzzer.setLed(who, true);
    display.setText(String("  ") + buzzer.colorName(who) + " GAGNE !", 0);
  }

  display.setText(scoreLine(), 1);

  if (bestMs == 0) {
    display.setText(F("Aucun temps"), 2);
  } else if (newRecord) {
    display.setText(String("RECORD BATTU ! ") + bestMs, 2);
  } else {
    // Tient en 20 colonnes meme a 4 chiffres : "Vous: 2999 Rec: 2999".
    display.setText(String("Vous: ") + bestMs + " Rec: " + record, 2);
  }

  display.setText(F("#: rejouer  *: menu"), 3);

  const bool decided = !aborted && any && maxScore > 0;
  ble.sendGameScores(scores);
  ble.send(String("RFLXR|") + bestMs + "|" + record + "|" + (newRecord ? 1 : 0));
  ble.sendGameOver(decided && leaders == 1 ? who : -1, decided && leaders > 1);

  if (!aborted && maxScore > 0) {
    mp3.playGoodAnswer();
  } else {
    mp3.playBadAnswer();
  }
}

PhaseMode Reflex::gameOver(char pressedKey) {
  if (pressedKey == '#') {
    reset();
    return REFLEX_ARM;      // nouvelle partie
  }
  if (pressedKey == '*') {
    buzzer.resetLights();
    return CONFIGURATION;
  }
  return REFLEX_OVER;
}

// Le record, ouvert a l'application. Elle mene le Reflexe en mode applicatif,
// mais la valeur reste celle du buzzer : c'est l'objet qui garde la memoire
// des soirees, pas l'ordinateur qui passait par la.
unsigned int Reflex::record() {
  return readRecord();
}

// N'ecrit QUE si c'est mieux : le garde-fou est ici, pas dans l'application.
// Elle pourrait etre d'une version plus ancienne, ou se tromper.
void Reflex::enregistrerRecord(unsigned int ms) {
  if (ms == 0) return;
  unsigned int actuel = readRecord();
  if (actuel == REFLEX_NO_RECORD || actuel == 0 || ms < actuel) {
    writeRecord(ms);
  }
}
