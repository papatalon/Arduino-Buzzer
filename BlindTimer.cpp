#include "BlindTimer.h"
#include <EEPROM.h>

// "12,1" ou " 9,4" : toujours 4 colonnes, pour aligner les temps en deux
// colonnes a l'ecran.
static String fmtSeconds(unsigned long ms) {
  unsigned long tenths = (ms + 50) / 100;      // arrondi au dixieme
  String pad = (tenths / 10 < 10) ? " " : "";
  return pad + String(tenths / 10) + "," + String(tenths % 10);
}

// Ecart au centieme ("0,23"), borne a 4 colonnes : au-dela de 10 s l'ecart
// n'a plus d'interet, on le resume par ">10".
static String fmtGap(unsigned int ms) {
  if (ms >= 10000) {
    return ">10";
  }
  unsigned int cs = (ms + 5) / 10;             // centiemes, arrondi
  String dec = String(cs % 100);
  if (cs % 100 < 10) {
    dec = "0" + dec;
  }
  return String(cs / 100) + "," + dec;
}

void BlindTimer::reset() {
  for (int i = 0; i < 4; i++) {
    scores[i] = 0;
    times[i] = 0;
  }
  round = 0;
  totalRounds = buzzer.getGameRounds(GAME_BLIND);
  aborted = false;
  bestGapMs = BLIND_NO_RECORD;
  newRecord = false;
  winner = -1;

  // Scores propres au jeu, distincts de ceux du quiz : voir
  // BleLink::sendGameScores.
  ble.sendGameScores(scores);
  ble.sendGameRound(0, totalRounds);
}

bool BlindTimer::allBuzzed() {
  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i) && times[i] == 0) {
      return false;
    }
  }
  return true;
}

String BlindTimer::scoreLine() {
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

// "R 11,8" (6 colonnes) ou "R ----" si le joueur n'a pas buzze.
String BlindTimer::playerCell(int i) {
  String cell = String(buzzer.colorName(i)[0]) + " ";
  return cell + (times[i] == 0 ? String("----") : fmtSeconds(times[i]));
}

// Deux joueurs par ligne : "R 11,8   J 12,1" (15 colonnes au plus).
void BlindTimer::showTimes() {
  String line = "";
  int shown = 0;
  int row = 1;
  for (int i = 0; i < 4; i++) {
    if (!buzzer.isEnabled(i)) {
      continue;
    }
    if (shown % 2 == 1) {
      line += "   ";
    }
    line += playerCell(i);
    shown++;
    if (shown % 2 == 0) {
      display.setText(line, row++);
      line = "";
    }
  }
  if (line.length() > 0) {
    display.setText(line, row++);
  }
  while (row <= 2) {
    display.setText(F(""), row++);
  }
}

unsigned int BlindTimer::readRecord() {
  return (unsigned int)EEPROM.read(BLIND_EEPROM_RECORD)
       | ((unsigned int)EEPROM.read(BLIND_EEPROM_RECORD + 1) << 8);
}

void BlindTimer::writeRecord(unsigned int ms) {
  EEPROM.update(BLIND_EEPROM_RECORD, (uint8_t)(ms & 0xFF));
  EEPROM.update(BLIND_EEPROM_RECORD + 1, (uint8_t)(ms >> 8));
}

// === Annonce de la cible ===
void BlindTimer::setAnnounce() {
  round++;
  for (int i = 0; i < 4; i++) {
    times[i] = 0;
  }
  winner = -1;

  targetMs = (unsigned long)random(BLIND_TARGET_MIN_S, BLIND_TARGET_MAX_S + 1) * 1000UL;

  buzzer.resetLights();
  display.clear();
  display.setText(String("CHRONO AVEUGLE ") + round + "/" + totalRounds, 0);
  display.setText(String("Cible : ") + (targetMs / 1000) + " secondes", 1);
  display.setText(F("#: depart  C: fin"), 3);

  ble.sendGameRound(round, totalRounds);
  // La cible est annoncee a voix haute et affichee sur le buzzer : rien de
  // secret. Ce qui doit rester invisible, c'est le TEMPS QUI PASSE - d'ou
  // l'absence totale de telemetrie pendant BLIND_RUN.
  ble.send(String("BLND|") + (targetMs / 1000));
}

PhaseMode BlindTimer::announce(char pressedKey) {
  if (pressedKey == 'C') {
    aborted = true;
    return BLIND_OVER;
  }
  if (pressedKey == '#') {
    return BLIND_RUN;
  }
  return BLIND_ANNOUNCE;
}

// === Manche : plus rien ne bouge ===
// Aucun son n'est joue pendant la manche : la duree d'un extrait donnerait une
// reference temporelle aux joueurs, ce qui viderait le jeu de son interet.
// Toutes les LED s'allument au depart, celle d'un joueur s'eteint quand il a
// buzze (seul retour visuel, il ne divulgue aucune duree).
void BlindTimer::setRun() {
  buzzer.armButtons();

  for (int i = 0; i < 4; i++) {
    if (buzzer.isEnabled(i)) {
      buzzer.setLed(i, true);
    }
  }
  startMs = millis();

  display.clear();
  display.setText(F("CHRONO AVEUGLE"), 0);
  display.setText(String("Cible : ") + (targetMs / 1000) + " s", 1);
  display.setText(F("Buzzez au bon moment"), 2);
}

PhaseMode BlindTimer::run(char pressedKey) {
  unsigned long now = millis();

  for (int i = 0; i < 4; i++) {
    if (!buzzer.isEnabled(i) || times[i] != 0) {
      continue;
    }
    if (buzzer.wasPressed(i)) {
      times[i] = now - startMs;
      if (times[i] == 0) {
        times[i] = 1;        // 0 est la valeur "n'a pas buzze"
      }
      buzzer.setLed(i, false);
    }
  }

  if (allBuzzed()) {
    return BLIND_RESULT;
  }

  if (pressedKey == 'C') {
    aborted = true;
    return BLIND_OVER;
  }

  // Manche coupee bien apres la cible : les retardataires sont notes "----".
  if (now - startMs >= targetMs + BLIND_GRACE_MS) {
    return BLIND_RESULT;
  }
  return BLIND_RUN;
}

// === Resultat de la manche ===
void BlindTimer::setResult() {
  buzzer.resetLights();

  // Le plus proche de la cible remporte la manche.
  unsigned long bestGap = 0;
  winner = -1;
  for (int i = 0; i < 4; i++) {
    if (!buzzer.isEnabled(i) || times[i] == 0) {
      continue;
    }
    unsigned long gap = (times[i] > targetMs) ? (times[i] - targetMs) : (targetMs - times[i]);
    if (winner < 0 || gap < bestGap) {
      bestGap = gap;
      winner = i;
    }
  }

  display.clear();
  if (winner >= 0) {
    scores[winner]++;
    if (bestGap < bestGapMs) {
      bestGapMs = (unsigned int)bestGap;
    }
    buzzer.setLed(winner, true);
    mp3.playBuzzer(winner);
    display.setText(String("Cible ") + (targetMs / 1000) + " s  "
                    + buzzer.colorName(winner) + " !", 0);
  } else {
    mp3.playBadAnswer();
    display.setText(String("Cible ") + (targetMs / 1000) + " s  personne", 0);
  }

  showTimes();
  display.setText(scoreLine() + "  #", 3);

  ble.sendGameScores(scores);
  ble.send(String("BLNDR|") + winner + "|" + times[0] + "|" + times[1] + "|"
           + times[2] + "|" + times[3]);
}

PhaseMode BlindTimer::result(char pressedKey) {
  if (pressedKey == 'C') {
    aborted = true;
    return BLIND_OVER;
  }
  if (pressedKey == '#') {
    return (round >= totalRounds) ? BLIND_OVER : BLIND_ANNOUNCE;
  }
  return BLIND_RESULT;
}

// === Fin de partie ===
void BlindTimer::setGameOver() {
  buzzer.resetLights();

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

  // Record persistant du plus petit ecart jamais realise.
  newRecord = false;
  unsigned int record = readRecord();
  if (bestGapMs != BLIND_NO_RECORD
      && (record == BLIND_NO_RECORD || bestGapMs < record)) {
    writeRecord(bestGapMs);
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

  if (bestGapMs == BLIND_NO_RECORD) {
    display.setText(F("Aucun resultat"), 2);
  } else if (newRecord) {
    display.setText(String("RECORD ! ") + fmtGap(bestGapMs) + " s", 2);
  } else {
    display.setText(String("Vous ") + fmtGap(bestGapMs) + "  Rec " + fmtGap(record), 2);
  }

  display.setText(F("#: rejouer  *: menu"), 3);

  const bool decided = !aborted && any && maxScore > 0;
  ble.sendGameScores(scores);
  ble.sendGameOver(decided && leaders == 1 ? who : -1, decided && leaders > 1);

  if (!aborted && maxScore > 0) {
    mp3.playGoodAnswer();
  } else {
    mp3.playBadAnswer();
  }
}

PhaseMode BlindTimer::gameOver(char pressedKey) {
  if (pressedKey == '#') {
    reset();
    return BLIND_ANNOUNCE;      // nouvelle partie
  }
  if (pressedKey == '*') {
    buzzer.resetLights();
    return CONFIGURATION;
  }
  return BLIND_OVER;
}

// Le record, ouvert a l'application (messages RECB et SET_RECB). Le plus
// petit ecart jamais realise, en millisecondes.
unsigned int BlindTimer::record() {
  return readRecord();
}

// N'ecrit QUE si c'est mieux : le garde-fou est ici, chez le proprietaire de
// la donnee, pas dans l'application qui la lui envoie.
void BlindTimer::enregistrerRecord(unsigned int ecartMs) {
  unsigned int actuel = readRecord();
  if (actuel == BLIND_NO_RECORD || actuel == 0 || ecartMs < actuel) {
    writeRecord(ecartMs);
  }
}
