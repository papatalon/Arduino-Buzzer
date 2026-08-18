#include "Buzzer.h"
#include "QuestionBank.h"
#include <EEPROM.h>
#include <math.h>

// Plan d'occupation de l'EEPROM : l'adresse 0 est le volume (voir Mp3.cpp).
// Chrono par mode : Chrono classique, Chrono pénalité, Vol — chacun (1re
// réponse, suivantes).
#define EEPROM_ADDR_CLASSIC_FIRST 1
#define EEPROM_ADDR_CLASSIC_NEXT 2
#define EEPROM_ADDR_PENALTY_FIRST 3
#define EEPROM_ADDR_PENALTY_NEXT 4
#define EEPROM_ADDR_VOL_FIRST 5
#define EEPROM_ADDR_VOL_NEXT 6
// Manches par jeu : 7 = Réflexe, 8 = Chrono aveugle, 9 = Ne buzze pas.
// 10 = leurres de Ne buzze pas (0/1). 11 = manches du Duel.
#define EEPROM_ADDR_ROUNDS_REFLEX 7
#define EEPROM_ADDR_ROUNDS_BLIND 8
#define EEPROM_ADDR_ROUNDS_SOUND 9
#define EEPROM_ADDR_SOUND_DECOYS 10
#define EEPROM_ADDR_ROUNDS_DUEL 11

Buzzer::Buzzer() {}

// === Required for Singletons ===
// Define the single instance as a static member
Buzzer& Buzzer::shared() {
  static Buzzer instance;
  return instance;
}

void Buzzer::init() {
  for (int buzzerId = 0; buzzerId < 4; buzzerId++) {
    pinMode(buzzers[buzzerId][0],OUTPUT);
    pinMode(buzzers[buzzerId][1],INPUT_PULLUP);
  }
  loadBuzzTimes();
  loadGameRounds();
  loadSoundDecoys();
}

void Buzzer::resetLights() {
  for (int buzzerId = 0; buzzerId < 4; buzzerId++) {
    digitalWrite(buzzers[buzzerId][0], LOW);
  }
}

// Messages de démarrage tirés au hasard : la 2e ligne reçoit les points
// animés, donc on la garde courte (max ~16 colonnes sur les 20 du LCD).
static const char* const BOOT_MESSAGES[BOOT_MESSAGE_COUNT][2] = {
  { "Chauffage des",       "pouces"          },
  { "Reveil des lutins",   "du son"          },
  { "sudo demarrer quiz",  "Acces autorise"  },
  { "Temps restant :",     "environ 3 jours" },
  { "Compilation de",      "l'ambiance"      },
};

// === Phase 1 : pendant l'initialisation (bloquante) du DFPlayer ===
// Un message rigolo tiré au hasard, dont les points s'animent (voir bootTick).
void Buzzer::showBootScreen() {
  bootMessage = random(BOOT_MESSAGE_COUNT);
  lastDots = -1;
  display.clear();
  display.setText(BOOT_MESSAGES[bootMessage][0], 1);
  display.setText(BOOT_MESSAGES[bootMessage][1], 2);
}

// Chenillard : les 4 LED s'allument l'une après l'autre.
void Buzzer::ledChase(unsigned long elapsed) {
  int step = (elapsed / INTRO_STEP_MS) % 4;
  for (int i = 0; i < 4; i++) {
    setLed(i, i == step);
  }
}

// Appelé en boucle par mp3.init() pendant les attentes de démarrage : chenillard
// des LED + points animés derrière le message, sans bloquer.
void Buzzer::bootTick() {
  ledChase(millis());

  // Points de 0 à 3, redessinés seulement quand leur nombre change (le bus
  // I2C de l'afficheur est lent).
  int dots = (millis() / BOOT_DOT_MS) % 4;
  if (dots == lastDots) {
    return;
  }
  lastDots = dots;

  String line = BOOT_MESSAGES[bootMessage][1];
  for (int i = 0; i < dots; i++) {
    line += ".";
  }
  display.setText(line, 2);
}

// === Phase 2 : pendant la chanson d'intro ===
// L'écran bascule sur un égaliseur audio plein écran, dessiné avec les
// caractères personnalisés du LCD.
void Buzzer::setBoot() {
  bootStart = millis();
  lastEqFrame = bootStart;
  display.clear();
  display.initBarChars();
  for (int i = 0; i < 20; i++) {
    eqHeights[i] = random(4, 29);
  }
  display.drawEqualizer(eqHeights);
}

// Marche aléatoire : chaque barre monte/descend un peu, comme un VU-mètre.
void Buzzer::updateEqualizer() {
  for (int i = 0; i < 20; i++) {
    int h = (int)eqHeights[i] + random(-7, 8);
    if (h < 1) h = 1;
    if (h > 32) h = 32;
    eqHeights[i] = h;
  }
  display.drawEqualizer(eqHeights);
}

PhaseMode Buzzer::boot(char pressedKey) {
  unsigned long elapsed = millis() - bootStart;

  // N'importe quelle touche, ou la fin de la chanson, ouvre le menu.
  if (pressedKey || songFinished(elapsed)) {
    resetLights();
    return CONFIGURATION;
  }

  ledChase(elapsed);

  unsigned long now = millis();
  if (now - lastEqFrame >= EQ_FRAME_MS) {
    lastEqFrame = now;
    updateEqualizer();
  }
  return BOOT;
}

// Le chenillard accompagne la chanson : il tourne tant que le DFPlayer joue
// (broche BUSY à LOW). INTRO_START_MS laisse au module le temps de démarrer la
// lecture avant de tester la fin ; INTRO_MAX_MS borne la durée par sécurité.
// En simulation (pas de BUSY), on garde un minuteur fixe.
bool Buzzer::songFinished(unsigned long elapsed, unsigned long simDurationMs) {
  if (mp3.isSimulation()) {
    return elapsed >= simDurationMs;
  }
  if (elapsed < INTRO_START_MS) {
    return false;                    // on laisse la lecture démarrer
  }
  return !mp3.isBusy() || elapsed >= INTRO_MAX_MS;
}

// === Mode cache de test cablage (LED_TEST), entree via *1 ===
// A l'entree, les 4 LED s'allument. Ensuite :
//  - une touche du clavier bascule TOUTES les LED (test des sorties LED) ;
//  - un appui sur un bouton de buzzer bascule SA propre LED et affiche la
//    couleur (test conjoint du bouton et de la LED, couleur par couleur).
// Sortie : ** (reset) -> retour a la configuration.
void Buzzer::setLedTest() {
  ledTestMaster = true;
  armButtons();
  for (int i = 0; i < 4; i++) {
    ledTestOn[i] = true;
    setLed(i, true);
  }
  display.clear();
  display.setText("Test LED + boutons", 0);
  display.setText("Touche: tout on/off", 1);
  display.setText("Bouton: sa LED", 2);
  display.setText("**  = retour config", 3);
}

PhaseMode Buzzer::ledTest(char pressedKey) {
  // Touche du clavier : bascule globale de toutes les LED.
  if (pressedKey) {
    ledTestMaster = !ledTestMaster;
    for (int i = 0; i < 4; i++) {
      ledTestOn[i] = ledTestMaster;
      setLed(i, ledTestMaster);
    }
    display.setText(ledTestMaster ? "Tout: ON" : "Tout: OFF", 3);

    Serial.print(F("[LED_TEST] Touche '"));
    Serial.print(pressedKey);
    Serial.print(F("' -> Tout: "));
    Serial.println(ledTestMaster ? F("ON") : F("OFF"));
  }

  // Boutons des buzzers : bascule la LED du buzzer appuye (front anti-rebondi).
  for (int i = 0; i < 4; i++) {
    if (buttonPressed(i)) {
      ledTestOn[i] = !ledTestOn[i];
      setLed(i, ledTestOn[i]);
      display.setText(String(colorName(i)) + ": " + (ledTestOn[i] ? "ON" : "OFF"), 3);

      Serial.print(F("[LED_TEST] Bouton "));
      Serial.print(colorName(i));
      Serial.print(F(" (pin "));
      Serial.print(buzzers[i][1]);
      Serial.print(F(") -> LED pin "));
      Serial.print(buzzers[i][0]);
      Serial.print(F(" : "));
      Serial.println(ledTestOn[i] ? F("ON") : F("OFF"));
    }
  }

  return LED_TEST;
}

PhaseMode Buzzer::waitingBuzzerIsPressed(PhaseMode currentMode) {
  PhaseMode result = currentMode;

  for (int i = 0; i < 4; i++) {
    // Front descendant anti-rebondi : un bouton maintenu ne se redéclenche pas.
    bool edge = buttonPressed(i);

    if (result == currentMode && enabled[i] && actives[i] && edge) {
      currentBuzzerId = i;
      digitalWrite(buzzers[i][0], HIGH);
      mp3.playBuzzer(i);
      result = BUZZER_PRESSED;
    }
  }

  if (result != currentMode) {
    timerRunning = false;      // quelqu'un a buzzé : le chrono s'arrête
    return result;
  }

  return tickBuzzTimer();      // sinon on fait tourner le décompte
}

void Buzzer::setWaitingForBuzzer() {
  armButtons();   // un bouton maintenu en entrant ne buzze pas tout seul

  // Chrono : pas de limite pendant un bris d'égalité. Sur les réponses
  // secondaires la question est déjà connue, le décompte part tout seul ;
  // sur la première, il attend le « top » de l'animateur (touche D).
  // Le chrono n'existe que dans les jeux "Chrono ..." (et jamais en bris).
  timerLimit = (tiebreak || !isChronoMode())
                 ? 0
                 : (secondaryRound ? getNextBuzzTime(gameMode) : getFirstBuzzTime(gameMode));
  timerRunning = false;
  lastShownSecs = -1;
  if (timerLimit > 0 && secondaryRound) {
    startBuzzTimer();
  }

  // Vol, nouvelle question : seul le joueur désigné (volTurn) peut buzzer.
  // Uniquement à l'entrée de la question (pas à chaque ré-appel pendant la
  // phase de vol, sinon un voleur qui vient d'échouer serait réactivé) —
  // c'est badAnswer() qui ouvre le vol aux autres, une seule fois.
  if (gameMode == GAME_VOL && !tiebreak && !secondaryRound) {
    for (int i = 0; i < 4; i++) {
      actives[i] = enabled[i] && (i == volTurn);
    }
  }

  display.clear();

  if (tiebreak) {
    // LED allumées pour les ex æquo (seuls buzzers en lice).
    for (int i = 0; i < 4; i++) {
      setLed(i, enabled[i] && actives[i]);
    }

    // Banque de questions active : le bris d'égalité pioche lui aussi une
    // question (une seule pour tout le bris, voir enterTiebreak() qui avance
    // questionNumber pour forcer ce tirage). Sinon, comme avant : l'animateur
    // pose sa propre question à l'oral.
    QuestionBank& bank = QuestionBank::shared();
    bool bankOn = bank.isActive();
    if (bankOn && lastDrawnQuestion != questionNumber) {
      if (bank.drawQuestion()) {
        lastDrawnQuestion = questionNumber;
      } else {
        bankOn = false;
      }
    }

    if (bankOn) {
      display.setText("EGALITE - Buzzez !", 0);
      wrapText(bank.questionText(), 1, 3);
      return;
    }

    // Pas de banque : liste des couleurs encore en lice, question à l'oral.
    String parts = "";
    for (int i = 0; i < 4; i++) {
      if (enabled[i] && actives[i]) {
        if (parts.length() > 0) {
          parts += " ";
        }
        parts += colorName(i);
      }
    }
    display.setText("  BRIS D'EGALITE", 0);
    display.setText("   Buzzez vite !", 1);
    display.setText(parts, 2);
    display.setText("#:son d'ambiance", 3);
    return;
  }

  // Banque de questions : une nouvelle question est tirée à chaque nouveau
  // numéro (pas à chaque retour ici pendant la même question, par ex. après
  // une mauvaise réponse).
  QuestionBank& bank = QuestionBank::shared();
  bool bankOn = bank.isActive();
  if (bankOn && lastDrawnQuestion != questionNumber) {
    if (bank.drawQuestion()) {
      lastDrawnQuestion = questionNumber;
    } else {
      bankOn = false;
    }
  }

  // Vol, 1re réponse : la LED du joueur désigné reste allumée.
  if (gameMode == GAME_VOL) {
    setLed(volTurn, !secondaryRound);
  }

  if (timerRunning) {
    // Décompte en cours (réponses secondaires) : titre + barre occupent les
    // lignes 0-1 ; la question, déjà lue, se replie sur les lignes 2-3.
    drawBuzzTimer((unsigned long)timerLimit * 1000UL);
    if (bankOn) {
      wrapText(bank.questionText(), 2, 3);
    } else {
      display.setText("#:son d'ambiance", 2);
      display.setText("0:passer    C:fin", 3);
    }
    return;
  }

  if (bankOn) {
    // La question a besoin de place : elle occupe les lignes 1 à 3 (60
    // colonnes), de quoi l'afficher d'un bloc dans la quasi-totalité des
    // cas. Le titre est donc réduit, et porte aussi les rappels de touches
    // (plus de place pour eux ailleurs) : « 0:passer » et « C:fin » sont
    // sinon invisibles en mode banque. Si ça dépasse 20 colonnes (Vol +
    // chrono + tour affiché), le titre défile — l'affichage gère ça tout seul.
    String head = String("Q") + questionNumber;
    if (gameMode == GAME_VOL && !secondaryRound) {
      head += " Tour:" + String(colorName(volTurn));
    }
    if (timerLimit > 0) {
      head += "  D:top";
    }
    head += "  0:pass C:fin";
    display.setText(head, 0);
    wrapText(bank.questionText(), 1, 3);
    return;
  }

  // Sans la banque : l'animateur a son propre questionnaire, l'écran garde
  // donc les rappels de touches.
  display.setText(String("Question ") + questionNumber, 0);
  // Chrono armé : il attend le « top » de l'animateur (question à lire).
  display.setText(timerLimit > 0 ? "  D = top chrono" : "   EN ATTENTE...", 1);
  if (gameMode == GAME_VOL && !secondaryRound) {
    display.setText(String("Tour: ") + colorName(volTurn), 2);
  } else if (lastJudgedBuzzer >= 0) {
    // "B:corriger" n'a de sens que si une décision a déjà été prise.
    display.setText("#:son   B:corriger", 2);
  } else {
    display.setText("#:son d'ambiance", 2);
  }
  display.setText("0:passer    C:fin", 3);
}

// Répartit `text` sur les lignes `from` à `to` de l'écran, en coupant aux
// espaces. Ce qui dépasse reste sur la dernière ligne, qui défile alors.
void Buzzer::wrapText(String text, int from, int to) {
  for (int line = from; line <= to; line++) {
    if (text.length() == 0) {
      display.setText("", line);
      continue;
    }
    if (text.length() <= 20 || line == to) {
      display.setText(text, line);   // dernière ligne : défile si trop long
      text = "";
      continue;
    }
    int cut = text.lastIndexOf(' ', 20);
    if (cut <= 0) {
      cut = 20;                      // mot unique trop long : coupe sèche
    }
    display.setText(text.substring(0, cut), line);
    text = text.substring(cut + 1);
  }
}

void Buzzer::setBuzzerPressed() {
    resetLights();   // coupe un éventuel clignotement de fin de chrono
    display.clear();
    display.setText(String("BIP ! -> ") + colorName(currentBuzzerId), 0);
    QuestionBank& bank = QuestionBank::shared();
    if (bank.isActive()) {
      // La bonne réponse occupe toute la ligne 1 (20 colonnes) : sans
      // préfixe « Rep: », la quasi-totalité des réponses tient sans
      // défilement, donc l'animateur la lit d'un coup d'oeil.
      display.setText(bank.answerText(), 1);
      display.setText("A:Bonne  D:Mauvaise", 2);
    } else {
      display.setText("A: Bonne reponse", 1);
      display.setText("D: Mauvaise reponse", 2);
    }
    display.setText("0 = passer", 3);
    ble.send("BUZZ|" + String(currentBuzzerId));
    int ledPin = buzzers[currentBuzzerId][0];
    digitalWrite(ledPin, HIGH);
}

PhaseMode Buzzer::buzzerIsPressed(PhaseMode currentMode, char pressedKey) {

  // Bris d'égalité : règles particulières.
  if (tiebreak) {
    if (pressedKey == 'A') {                 // bonne réponse -> gagne la partie
      scores[currentBuzzerId]++;
      mp3.playGoodAnswer();
      setLed(currentBuzzerId, false);
      tiebreak = false;
      return END_GAME;
    }
    if (pressedKey == 'D') {                  // éliminé du bris
      mp3.playBadAnswer();
      actives[currentBuzzerId] = false;
      setLed(currentBuzzerId, false);

      int remaining = 0;
      int last = -1;
      for (int i = 0; i < 4; i++) {
        if (enabled[i] && actives[i]) {
          remaining++;
          last = i;
        }
      }
      if (remaining <= 1) {                   // dernier en lice -> gagnant
        if (remaining == 1) {
          scores[last]++;
        }
        tiebreak = false;
        return END_GAME;
      }
      return WAITING_BUZZER;                   // le bris continue
    }
    return currentMode;
  }

  switch (pressedKey) {
    case 'A':
      Buzzer::goodAnswer();
      return SHOW_SCORES;       // fin de question -> écran des scores
    case 'D':
      Buzzer::badAnswer();
      return WAITING_BUZZER;    // même question, les autres peuvent répondre
      break;
    case '0':
      return Buzzer::skipQuestion();   // question abandonnée -> écran des scores (ou réponse d'abord)
    default:
      return currentMode;
  };


  return currentMode;
}

void Buzzer::setIntro() {
  introStart = millis();
  display.clear();
  display.setText("   C'EST PARTI !", 0);
  if (gameMode == GAME_SIMON_REVERSE) {
    display.setText("   Memoire a 4 :", 1);
    display.setText(" a l'envers, gare !", 2);
  } else if (gameMode == GAME_SIMON) {
    display.setText("   Memoire a 4 :", 1);
    display.setText("  tous ensemble !", 2);
  } else if (gameMode == GAME_REFLEX) {
    display.setText("     Reflexes :", 1);
    display.setText("  le plus rapide !", 2);
  } else if (gameMode == GAME_BLIND) {
    display.setText("  Chrono aveugle :", 1);
    display.setText("  fiez-vous a vous", 2);
  } else if (gameMode == GAME_SOUND) {
    display.setText("   Ne buzze pas :", 1);
    display.setText("  ouvrez l'oreille", 2);
  } else if (gameMode == GAME_DUEL) {
    display.setText("     Duel au son :", 1);
    display.setText("  fermez les yeux !", 2);
  } else {
    display.setText("  Que le meilleur", 1);
    display.setText("     gagne !", 2);
  }
}

PhaseMode Buzzer::intro(char pressedKey) {
  unsigned long elapsed = millis() - introStart;

  // N'importe quelle touche, ou la fin de la chanson, lance le jeu choisi.
  // (Vol n'a pas d'intro : il passe directement de CONFIGURATION à VOL_SPIN.)
  if (pressedKey || songFinished(elapsed)) {
    resetLights();
    if (gameMode == GAME_REFLEX) {
      return REFLEX_ARM;
    }
    if (gameMode == GAME_BLIND) {
      return BLIND_ANNOUNCE;
    }
    if (gameMode == GAME_SOUND) {
      return SOUND_LEARN;      // on apprend les sons avant que ca compte
    }
    if (gameMode == GAME_DUEL) {
      return DUEL_ARM;
    }
    bool isSimon = (gameMode == GAME_SIMON || gameMode == GAME_SIMON_REVERSE);
    return isSimon ? SIMON_SHOW : WAITING_BUZZER;
  }

  ledChase(elapsed);   // chenillard festif pendant la musique
  return INTRO;
}

// === Vol : tirage au sort anime du 1er joueur ===
// Chenillard limite aux buzzers presents + son du dossier 06, pendant toute
// la duree reelle du son (songFinished, comme l'intro) ; le joueur tire au
// sort est determine des l'entree (pour ne pas dependre du minutage de
// l'animation) et revele en fin d'animation par setWaitingForBuzzer(), qui
// allume sa LED et affiche "Tour: <couleur>".
void Buzzer::setVolSpin() {
  volTurn = randomEnabledBuzzer();
  startSpinAnimation();
  display.clear();
  display.setText("  TIRAGE AU SORT", 0);
  display.setText(" Qui va repondre ?", 1);
}

PhaseMode Buzzer::volSpin(char pressedKey) {
  // N'importe quelle touche, ou la fin reelle du son, revele le joueur.
  if (pressedKey || tickSpinAnimation()) {
    resetLights();
    return WAITING_BUZZER;
  }

  return VOL_SPIN;
}

void Buzzer::startSpinAnimation() {
  volSpinStart = millis();
  mp3.playSpin();
  volSpinStepIndex = 0;
  volSpinIntervalMs = VOL_SPIN_STEP_MS_INITIAL;
  volSpinNextStepAt = volSpinIntervalMs;
}

bool Buzzer::tickSpinAnimation() {
  unsigned long elapsed = millis() - volSpinStart;
  if (songFinished(elapsed, VOL_SPIN_SIM_MS)) {
    return true;
  }
  ledChaseEnabled(elapsed);
  return false;
}

// Chenillard limite aux buzzers presents (contrairement a ledChase(), qui
// parcourt les 4 sans distinction) : n'allume jamais un buzzer absent.
// La cadence suit celle du son du tirage (dossier 06), qui demarre par des
// clics rapides et ralentit progressivement, comme une roue qui tourne : on
// recalcule l'intervalle courant a chaque pas avec une croissance
// exponentielle (constante VOL_SPIN_STEP_TAU_MS), plafonnee a
// VOL_SPIN_STEP_MS_MAX.
void Buzzer::ledChaseEnabled(unsigned long elapsed) {
  int pool[4];
  int count = 0;
  for (int i = 0; i < 4; i++) {
    if (enabled[i]) {
      pool[count++] = i;
    }
  }
  if (count == 0) {
    return;
  }

  if (elapsed >= volSpinNextStepAt) {
    volSpinStepIndex++;
    float grown = VOL_SPIN_STEP_MS_INITIAL * exp(elapsed / VOL_SPIN_STEP_TAU_MS);
    volSpinIntervalMs = (unsigned int)min((float)VOL_SPIN_STEP_MS_MAX, grown);
    volSpinNextStepAt = elapsed + volSpinIntervalMs;
  }

  for (int i = 0; i < 4; i++) {
    setLed(i, false);
  }
  setLed(pool[volSpinStepIndex % count], true);
}

PhaseMode Buzzer::skipQuestion() {
  if (tiebreak) {
    return SHOW_SCORES;      // pas de "passer" pendant un bris d'égalité
  }
  bool bankOn = QuestionBank::shared().isActive();
  resetLights();
  resetAllBuzzers();         // tous les buzzers présents redeviennent actifs
  lastJudgedBuzzer = -1;     // plus de décision à corriger
  lastWasGood = false;
  secondaryRound = false;    // la prochaine question repart sur le chrono long
  questionNumber++;          // on passe à la question suivante
  if (gameMode == GAME_VOL) {
    volTurn = nextEnabledBuzzer(volTurn);   // au suivant, même sans réponse
  }
  // Banque active : personne n'a répondu, donc personne ne connaît la
  // réponse — on la montre avant l'écran des scores.
  return bankOn ? ANSWER_REVEAL : SHOW_SCORES;
}

// === Question passée sans réponse : révèle la réponse (banque) ===
void Buzzer::setAnswerReveal() {
  display.clear();
  display.setText("Personne n'a repondu", 0);
  wrapText(String("Rep: ") + QuestionBank::shared().answerText(), 1, 2);
  display.setText("        # : suite", 3);
}

PhaseMode Buzzer::answerReveal(char pressedKey) {
  if (pressedKey == '#') {
    return SHOW_SCORES;
  }
  return ANSWER_REVEAL;
}

void Buzzer::goodAnswer() {
  int ledPin = buzzers[currentBuzzerId][0];

  scores[currentBuzzerId]++;        // bonne réponse : +1
  lastJudgedBuzzer = currentBuzzerId;
  lastWasGood = true;
  secondaryRound = false;           // question suivante : chrono long
  questionNumber++;                 // question résolue -> on passe à la suivante
  if (gameMode == GAME_VOL) {
    volTurn = nextEnabledBuzzer(volTurn);   // au suivant, qu'il ait gagné ou volé
  }

  mp3.playGoodAnswer();
  digitalWrite(ledPin, LOW);
  sendScoreTelemetry();

  // Le clignotement de la LED se fait sans blocage pendant l'écran des
  // scores (voir showScores), pour ne pas figer le clavier ni l'afficheur.
  resetAllBuzzers();
}

void Buzzer::badAnswer() {
  int ledPin = buzzers[currentBuzzerId][0];

  if (isPenaltyMode()) {
    scores[currentBuzzerId]--;      // mode Pénalité : -1 (peut être négatif)
  }
  lastJudgedBuzzer = currentBuzzerId;
  lastWasGood = false;
  bool wasFirstAttempt = !secondaryRound;
  secondaryRound = true;            // les autres reprennent sur le chrono court

  mp3.playBadAnswer();

  actives[currentBuzzerId] = false;
  digitalWrite(ledPin, LOW);
  sendScoreTelemetry();

  // Vol : le joueur désigné vient d'échouer (1er échec de la question) —
  // on ouvre le vol aux autres présents. Un voleur qui échoue à son tour
  // reste éliminé (juste la ligne au-dessus, sans repasser ici).
  if (gameMode == GAME_VOL && wasFirstAttempt && currentBuzzerId == volTurn) {
    for (int i = 0; i < 4; i++) {
      if (i != volTurn) {
        actives[i] = enabled[i];
      }
    }
  }
}

PhaseMode Buzzer::correctLastDecision(PhaseMode fallback) {
  if (lastJudgedBuzzer < 0) {
    return fallback;                // rien à corriger
  }

  int id = lastJudgedBuzzer;
  if (lastWasGood) {
    scores[id]--;                  // annule le +1 d'une bonne réponse
    if (questionNumber > 1) {
      questionNumber--;            // on rouvre la question
    }
  } else {
    actives[id] = true;            // ré-active le buzzer écarté
    if (isPenaltyMode()) {
      scores[id]++;                // annule le -1 de la pénalité
    }
  }
  sendScoreTelemetry();

  currentBuzzerId = id;            // on revient juger ce même buzzer
  return BUZZER_PRESSED;
}

void Buzzer::resetAllBuzzers() {
  for(int i = 0; i < 4; i++) {
    actives[i] = true;
  }
}

const char* Buzzer::colorName(int i) {
  switch (i) {
    case 0: return "Rouge";
    case 1: return "Bleu";
    case 2: return "Jaune";
    case 3: return "Vert";
    default: return "?";
  }
}

void Buzzer::setGameMode(GameMode value) {
  gameMode = value;
  ble.send("GAME|" + String((int)value));
}

GameMode Buzzer::getGameMode() {
  return gameMode;
}

const char* Buzzer::gameModeName() {
  return gameModeName(gameMode);
}

const char* Buzzer::gameModeName(GameMode mode) {
  switch (mode) {
    case GAME_PENALTY:        return "Penalite";
    case GAME_CHRONO_CLASSIC: return "Chrono classique";
    case GAME_CHRONO_PENALTY: return "Chrono penalite";
    case GAME_VOL:            return "Vol";
    case GAME_SIMON:          return "Simon";
    case GAME_SIMON_REVERSE:  return "Simon inverse";
    case GAME_REFLEX:         return "Reflexe";
    case GAME_BLIND:          return "Chrono aveugle";
    case GAME_SOUND:          return "Ne buzze pas";
    case GAME_DUEL:           return "Duel";
    default:                  return "Classique";
  }
}

bool Buzzer::isPenaltyMode() {
  return gameMode == GAME_PENALTY || gameMode == GAME_CHRONO_PENALTY;
}

bool Buzzer::isChronoMode() {
  return gameMode == GAME_CHRONO_CLASSIC || gameMode == GAME_CHRONO_PENALTY || gameMode == GAME_VOL;
}

// === Chrono de buzz ===
// Trois jeux de durées : slot 0 pour Chrono classique, slot 1 pour Chrono
// pénalité, slot 2 pour Vol (les autres jeux n'utilisent pas ces durées).
static int buzzTimeSlot(GameMode mode) {
  switch (mode) {
    case GAME_CHRONO_PENALTY: return 1;
    case GAME_VOL:            return 2;
    default:                  return 0;
  }
}

// Les durées sont conservées en EEPROM, comme le volume. Une case jamais
// écrite vaut 255 : hors plage, on garde alors la valeur par défaut.
void Buzzer::loadBuzzTimes() {
  int stored = EEPROM.read(EEPROM_ADDR_CLASSIC_FIRST);
  if (stored >= 0 && stored <= BUZZ_TIME_MAX) {
    firstBuzzTime[0] = stored;
  }
  stored = EEPROM.read(EEPROM_ADDR_CLASSIC_NEXT);
  if (stored >= 0 && stored <= BUZZ_TIME_MAX) {
    nextBuzzTime[0] = stored;
  }
  stored = EEPROM.read(EEPROM_ADDR_PENALTY_FIRST);
  if (stored >= 0 && stored <= BUZZ_TIME_MAX) {
    firstBuzzTime[1] = stored;
  }
  stored = EEPROM.read(EEPROM_ADDR_PENALTY_NEXT);
  if (stored >= 0 && stored <= BUZZ_TIME_MAX) {
    nextBuzzTime[1] = stored;
  }
  stored = EEPROM.read(EEPROM_ADDR_VOL_FIRST);
  if (stored >= 0 && stored <= BUZZ_TIME_MAX) {
    firstBuzzTime[2] = stored;
  }
  stored = EEPROM.read(EEPROM_ADDR_VOL_NEXT);
  if (stored >= 0 && stored <= BUZZ_TIME_MAX) {
    nextBuzzTime[2] = stored;
  }
}

void Buzzer::saveBuzzTimes() {
  // update n'écrit que si la valeur a changé (ménage l'EEPROM).
  EEPROM.update(EEPROM_ADDR_CLASSIC_FIRST, (uint8_t)firstBuzzTime[0]);
  EEPROM.update(EEPROM_ADDR_CLASSIC_NEXT, (uint8_t)nextBuzzTime[0]);
  EEPROM.update(EEPROM_ADDR_PENALTY_FIRST, (uint8_t)firstBuzzTime[1]);
  EEPROM.update(EEPROM_ADDR_PENALTY_NEXT, (uint8_t)nextBuzzTime[1]);
  EEPROM.update(EEPROM_ADDR_VOL_FIRST, (uint8_t)firstBuzzTime[2]);
  EEPROM.update(EEPROM_ADDR_VOL_NEXT, (uint8_t)nextBuzzTime[2]);
}

// === Nombre de manches (jeux qui se jouent en manches) ===
// Quatre jeux de valeurs : slot 0 pour le Réflexe, 1 pour le Chrono aveugle,
// 2 pour Ne buzze pas, 3 pour le Duel. Les autres jeux n'utilisent pas ce
// réglage.
static int gameRoundsSlot(GameMode mode) {
  switch (mode) {
    case GAME_BLIND: return 1;
    case GAME_SOUND: return 2;
    case GAME_DUEL:  return 3;
    default:         return 0;
  }
}

// Même principe que les durées de chrono : une case jamais écrite vaut 255,
// hors plage, et on garde alors la valeur par défaut.
void Buzzer::loadGameRounds() {
  int stored = EEPROM.read(EEPROM_ADDR_ROUNDS_REFLEX);
  if (stored >= GAME_ROUNDS_MIN && stored <= GAME_ROUNDS_MAX) {
    gameRounds[0] = stored;
  }
  stored = EEPROM.read(EEPROM_ADDR_ROUNDS_BLIND);
  if (stored >= GAME_ROUNDS_MIN && stored <= GAME_ROUNDS_MAX) {
    gameRounds[1] = stored;
  }
  stored = EEPROM.read(EEPROM_ADDR_ROUNDS_SOUND);
  if (stored >= GAME_ROUNDS_MIN && stored <= GAME_ROUNDS_MAX) {
    gameRounds[2] = stored;
  }
  stored = EEPROM.read(EEPROM_ADDR_ROUNDS_DUEL);
  if (stored >= GAME_ROUNDS_MIN && stored <= GAME_ROUNDS_MAX) {
    gameRounds[3] = stored;
  }
}

void Buzzer::saveGameRounds() {
  EEPROM.update(EEPROM_ADDR_ROUNDS_REFLEX, (uint8_t)gameRounds[0]);
  EEPROM.update(EEPROM_ADDR_ROUNDS_BLIND, (uint8_t)gameRounds[1]);
  EEPROM.update(EEPROM_ADDR_ROUNDS_SOUND, (uint8_t)gameRounds[2]);
  EEPROM.update(EEPROM_ADDR_ROUNDS_DUEL, (uint8_t)gameRounds[3]);
}

// Une case jamais écrite vaut 255 : on garde alors le défaut (leurres actifs).
void Buzzer::loadSoundDecoys() {
  int stored = EEPROM.read(EEPROM_ADDR_SOUND_DECOYS);
  if (stored == 0 || stored == 1) {
    soundDecoys = (stored == 1);
  }
}

void Buzzer::saveSoundDecoys() {
  EEPROM.update(EEPROM_ADDR_SOUND_DECOYS, soundDecoys ? 1 : 0);
}

bool Buzzer::getSoundDecoys() {
  return soundDecoys;
}

void Buzzer::setSoundDecoys(bool value) {
  soundDecoys = value;
}

int Buzzer::getGameRounds(GameMode mode) {
  return gameRounds[gameRoundsSlot(mode)];
}

void Buzzer::setGameRounds(GameMode mode, int n) {
  gameRounds[gameRoundsSlot(mode)] = constrain(n, GAME_ROUNDS_MIN, GAME_ROUNDS_MAX);
}

int Buzzer::getFirstBuzzTime(GameMode mode) {
  return firstBuzzTime[buzzTimeSlot(mode)];
}

int Buzzer::getNextBuzzTime(GameMode mode) {
  return nextBuzzTime[buzzTimeSlot(mode)];
}

void Buzzer::setFirstBuzzTime(GameMode mode, int seconds) {
  firstBuzzTime[buzzTimeSlot(mode)] = constrain(seconds, 0, BUZZ_TIME_MAX);
}

void Buzzer::setNextBuzzTime(GameMode mode, int seconds) {
  nextBuzzTime[buzzTimeSlot(mode)] = constrain(seconds, 0, BUZZ_TIME_MAX);
}

// « Top » donné par l'animateur (touche D) une fois la question lue.
void Buzzer::startBuzzTimer() {
  if (timerRunning || timerLimit <= 0) {
    return;
  }
  timerRunning = true;
  timerEnd = millis() + (unsigned long)timerLimit * 1000UL;
  lastShownSecs = -1;
}

// Barre dégressive sur la ligne 1 + secondes restantes à droite du titre.
// Redessinée seulement quand la seconde affichée change (bus I2C lent).
void Buzzer::drawBuzzTimer(unsigned long remaining) {
  int secs = (int)((remaining + 999) / 1000);   // arrondi haut : 10..1 puis 0
  if (secs == lastShownSecs) {
    return;
  }
  lastShownSecs = secs;

  String head = String("Question ") + questionNumber;
  String tail = String(secs) + "s";
  while (head.length() + tail.length() < 20) {
    head += " ";
  }
  display.setText(head + tail, 0);

  int filled = (int)((20L * (long)remaining) / (1000L * (long)timerLimit));
  String bar = "";
  for (int i = 0; i < filled && i < 20; i++) {
    bar += "=";
  }
  display.setText(bar, 1);
}

// Décompte appelé à chaque tick de l'écran d'attente. Renvoie SHOW_SCORES
// quand le temps est écoulé (personne ne marque), WAITING_BUZZER sinon.
PhaseMode Buzzer::tickBuzzTimer() {
  if (!timerRunning) {
    return WAITING_BUZZER;
  }

  unsigned long now = millis();
  long remaining = (long)(timerEnd - now);

  if (remaining <= 0) {
    timerRunning = false;
    mp3.playBadAnswer();

    // Vol, 1re réponse : le joueur désigné n'a pas répondu à temps -> on
    // ouvre le vol aux autres (comme une mauvaise réponse), la question ne
    // se ferme pas. Le droit de réplique (phase de vol, secondaryRound)
    // suit la règle normale ci-dessous : personne ne vole à temps -> fermée.
    if (gameMode == GAME_VOL && !secondaryRound) {
      lastJudgedBuzzer = volTurn;
      lastWasGood = false;
      actives[volTurn] = false;
      for (int i = 0; i < 4; i++) {
        if (i != volTurn) {
          actives[i] = enabled[i];
        }
      }
      secondaryRound = true;
      setWaitingForBuzzer();  // même mode : personne ne réarme l'écran pour nous
      return WAITING_BUZZER;
    }

    timeUp = true;
    return skipQuestion();     // personne ne marque, on passe à la suivante (ou réponse d'abord)
  }

  drawBuzzTimer((unsigned long)remaining);

  // Dernières secondes : les LED des buzzers encore en lice clignotent.
  if (remaining <= BUZZ_WARN_MS) {
    bool on = ((now / BUZZ_WARN_BLINK_MS) % 2) == 0;
    for (int i = 0; i < 4; i++) {
      if (enabled[i] && actives[i]) {
        setLed(i, on);
      }
    }
  }

  return WAITING_BUZZER;
}

void Buzzer::resetScores() {
  for (int i = 0; i < 4; i++) {
    scores[i] = 0;
  }
  lastJudgedBuzzer = -1;
  lastWasGood = false;
  questionNumber = 1;
  tiebreak = false;
  endTie = false;
  secondaryRound = false;
  timerRunning = false;
  timeUp = false;
  lastDrawnQuestion = 0;   // banque : la 1re question sera tirée à l'attente
  // volTurn (mode Vol) est tiré au sort par setVolSpin(), juste avant la
  // 1re question — inutile de le faire ici aussi.
  // Nouvelle partie : tous les buzzers présents redeviennent actifs.
  for (int i = 0; i < 4; i++) {
    actives[i] = true;
  }
  sendScoreTelemetry();
}

void Buzzer::sendScoreTelemetry() {
  ble.send("SCORE|" + String(scores[0]) + "|" + String(scores[1]) + "|" +
           String(scores[2]) + "|" + String(scores[3]));
}

void Buzzer::setQuestionLimit(int n) {
  questionLimit = (n < 0) ? 0 : n;
}

// Prochain buzzer présent après 'from' (boucle sur les 4) ; s'il n'y en a
// qu'un seul, le renvoie tel quel (rien à faire tourner).
int Buzzer::nextEnabledBuzzer(int from) {
  for (int step = 1; step <= 4; step++) {
    int i = (from + step) % 4;
    if (enabled[i]) {
      return i;
    }
  }
  return from;
}

// Un buzzer présent tiré au hasard (tirage équitable, quel que soit le
// nombre de buzzers présents).
int Buzzer::randomEnabledBuzzer() {
  int pool[4];
  int count = 0;
  for (int i = 0; i < 4; i++) {
    if (enabled[i]) {
      pool[count++] = i;
    }
  }
  return (count > 0) ? pool[random(count)] : 0;
}

void Buzzer::displayScores(const char* title, const char* prompt) {
  display.clear();
  display.setText(title, 0);

  // N'affiche que les buzzers présents, jusqu'à 2 par ligne.
  String line1 = "";
  String line2 = "";
  int shown = 0;
  for (int i = 0; i < 4; i++) {
    if (!enabled[i]) {
      continue;
    }
    String entry = String(colorName(i)) + ":" + scores[i];
    if (shown == 0) {
      line1 = entry;
    } else if (shown == 1) {
      line1 += "   " + entry;
    } else if (shown == 2) {
      line2 = entry;
    } else {
      line2 += "   " + entry;
    }
    shown++;
  }

  display.setText(line1, 1);
  display.setText(line2, 2);
  display.setText(prompt, 3);
}

void Buzzer::setShowScores() {
  scoresShownAt = millis();

  // Le titre rappelle si la question s'est terminée sur le chrono.
  const char* title = timeUp ? "   TEMPS ECOULE !" : "      SCORES";
  timeUp = false;

  // "B=corr" n'a de sens que si une décision vient d'être prise
  // (après un "passer", il n'y a rien à corriger).
  if (lastJudgedBuzzer >= 0) {
    displayScores(title, "#=suite B=corr C=fin");
  } else {
    displayScores(title, "#=suite      C=fin");
  }
}

PhaseMode Buzzer::showScores(char pressedKey) {
  // Nombre de questions choisi au lancement atteint : la partie se termine
  // d'elle-même au lieu d'enchaîner sur une question de plus.
  bool limitReached = (questionLimit > 0 && questionNumber > questionLimit);

  if (pressedKey == 'C') {
    setLed(currentBuzzerId, false);
    return END_CONFIRM;              // demander confirmation avant de terminer
  }
  if (pressedKey == 'B') {
    setLed(currentBuzzerId, false);
    return correctLastDecision(SHOW_SCORES);  // corriger la dernière décision
  }
  if (pressedKey == '#') {
    setLed(currentBuzzerId, false);
    return limitReached ? END_GAME : WAITING_BUZZER;
  }
  if (millis() - scoresShownAt >= SCORES_DISPLAY_MS) {
    setLed(currentBuzzerId, false);
    return limitReached ? END_GAME : WAITING_BUZZER;
  }

  // Courte célébration : la LED du gagnant clignote ~1,5 s puis s'éteint.
  // Uniquement si la question vient d'être gagnée (pas après un "passer").
  if (lastJudgedBuzzer >= 0 && lastWasGood) {
    unsigned long elapsed = millis() - scoresShownAt;
    if (elapsed < WIN_BLINK_MS) {
      setLed(lastJudgedBuzzer, ((millis() / 250) % 2) == 0);
    } else {
      setLed(lastJudgedBuzzer, false);
    }
  }
  return SHOW_SCORES;
}

void Buzzer::setEndConfirm() {
  display.clear();
  display.setText("TERMINER LA PARTIE ?", 0);
  display.setText("# = oui", 2);
  display.setText("* = non (continuer)", 3);
}

PhaseMode Buzzer::endConfirm(char pressedKey) {
  if (pressedKey == '#') {
    return END_GAME;
  }
  if (pressedKey == '*') {
    return WAITING_BUZZER;   // on reprend la partie
  }
  return END_CONFIRM;
}

void Buzzer::setEndGame() {
  resetLights();   // éteint d'éventuelles LED restées allumées (bris d'égalité)

  // Détermine le meilleur score parmi les buzzers présents.
  int best = 0;
  bool any = false;
  for (int i = 0; i < 4; i++) {
    if (enabled[i] && (!any || scores[i] > best)) {
      best = scores[i];
      any = true;
    }
  }

  int count = 0;
  int winner = -1;
  for (int i = 0; i < 4; i++) {
    if (enabled[i] && scores[i] == best) {
      count++;
      winner = i;
    }
  }

  endTie = (any && count > 1);

  String prompt;
  if (!any) {
    prompt = "Aucun buzzer #menu";
  } else if (endTie) {
    prompt = "#=bris   *=menu";    // égalité : proposer un bris d'égalité
  } else {
    prompt = String("Gagne:") + colorName(winner) + " #menu";
  }

  displayScores(endTie ? "EGALITE !" : "FIN DE PARTIE", prompt.c_str());

  if (any && count == 1) {
    mp3.playGoodAnswer();            // son de victoire
  }
}

PhaseMode Buzzer::endGame(char pressedKey) {
  if (endTie) {
    if (pressedKey == '#') {         // lancer le bris d'égalité
      enterTiebreak();
      return WAITING_BUZZER;
    }
    if (pressedKey == '*') {         // accepter l'égalité
      resetLights();
      return CONFIGURATION;
    }
    return END_GAME;
  }

  if (pressedKey == '#') {
    resetLights();
    return CONFIGURATION;
  }
  return END_GAME;
}

void Buzzer::enterTiebreak() {
  // Meilleur score parmi les présents.
  int best = 0;
  bool any = false;
  for (int i = 0; i < 4; i++) {
    if (enabled[i] && (!any || scores[i] > best)) {
      best = scores[i];
      any = true;
    }
  }
  // Seuls les ex æquo peuvent buzzer (les autres restent présents mais neutralisés).
  for (int i = 0; i < 4; i++) {
    actives[i] = (enabled[i] && scores[i] == best);
  }
  tiebreak = true;
  questionNumber++;   // force un nouveau tirage dans la banque (voir setWaitingForBuzzer)
}

void Buzzer::resetConfigState() {
  for (int i = 0; i < 4; i++) {
    enabled[i] = true;
    prevPressed[i] = false;
    releasing[i] = false;
  }
}

void Buzzer::setEnabled(int buzzerId, bool value) {
  enabled[buzzerId] = value;
  ble.send("PRESENT|" + String(enabled[0]) + "|" + String(enabled[1]) + "|" +
           String(enabled[2]) + "|" + String(enabled[3]));
}

bool Buzzer::isEnabled(int buzzerId) {
  return enabled[buzzerId];
}

// Vrai si les 4 buzzers sont déclarés présents (requis par le jeu Simon).
bool Buzzer::hasFourPlayers() {
  for (int i = 0; i < 4; i++) {
    if (!enabled[i]) {
      return false;
    }
  }
  return true;
}

// Vrai si exactement 2 buzzers sont déclarés présents (requis par le jeu
// Duel) : peu importe lesquels, un duel se joue à deux, pas à trois ou quatre.
bool Buzzer::hasExactlyTwoPlayers() {
  int n = 0;
  for (int i = 0; i < 4; i++) {
    if (enabled[i]) {
      n++;
    }
  }
  return n == 2;
}

// Mémorise l'état courant des boutons : un bouton déjà maintenu en entrant dans
// un écran devra être relâché avant de produire un front. Évite qu'un appui
// parasite (ou tardif) soit compté dès l'arrivée sur l'écran.
void Buzzer::armButtons() {
  for (int i = 0; i < 4; i++) {
    prevPressed[i] = (digitalRead(buzzers[i][1]) == LOW);
    releasing[i] = false;
  }
}

// Lecture centralisée d'un bouton de buzzer : renvoie true une seule fois par
// appui (front descendant). Le front est accepté immédiatement (aucune
// latence pour le buzz en jeu) : dès que la broche passe à LOW alors qu'on
// n'était pas déjà en appui, c'est gagné.
//
// Le nouvel appui n'est réarmé qu'après un relâchement stable pendant
// BUTTON_DEBOUNCE_MS. Sans ça, le rebond mécanique du contact au relâchement
// (la broche qui repasse brièvement à LOW juste après avoir relâché) était
// lu comme un second appui — c'est ce qui produisait les "doubles clics
// fantômes" en Simon, où plusieurs appuis rapprochés du même joueur sont
// courants. Toute retombée à LOW pendant la confirmation du relâchement
// annule le compte à rebours, sans redéclencher d'appui (on est toujours
// considéré comme pressé).
bool Buzzer::buttonPressed(int buzzerId) {
  bool pressedNow = (digitalRead(buzzers[buzzerId][1]) == LOW);
  unsigned long now = millis();

  if (pressedNow) {
    releasing[buzzerId] = false;   // un retour a LOW annule un relachement en cours
    if (!prevPressed[buzzerId]) {
      prevPressed[buzzerId] = true;
      return true;
    }
    return false;
  }

  if (prevPressed[buzzerId]) {
    if (!releasing[buzzerId]) {
      releasing[buzzerId] = true;
      releaseStartMs[buzzerId] = now;
    } else if (now - releaseStartMs[buzzerId] >= BUTTON_DEBOUNCE_MS) {
      prevPressed[buzzerId] = false;   // relachement confirme : pret pour un nouvel appui
      releasing[buzzerId] = false;
    }
  }
  return false;
}

bool Buzzer::wasPressed(int buzzerId) {
  return buttonPressed(buzzerId);
}

void Buzzer::setLed(int buzzerId, bool on) {
  digitalWrite(buzzers[buzzerId][0], on ? HIGH : LOW);
}

