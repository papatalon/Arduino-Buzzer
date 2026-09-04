#include "LcdDisplay.h"

// === Required for Singletons ===
// Define the single instance as a static member
LcdDisplay& LcdDisplay::shared() {
  static LcdDisplay instance;
  return instance;
}

bool LcdDisplay::init() {

  lcd.init(); // initialize the lcd
  lcd.backlight();

  return true;
}

void LcdDisplay::clear() {

  setText(F(""), 0);
  setText(F(""), 1);
  setText(F(""), 2);
  setText(F(""), 3);
}

// Texte en flash : recopie directe vers le tampon, sans construire de String.
void LcdDisplay::setText(const __FlashStringHelper* text, int line) {
  if (line < 0 || line > 3) return;
  strncpy_P(messages[line], (PGM_P)text, LCD_MSG_MAX);
  messages[line][LCD_MSG_MAX] = '\0';
  storeAndPaint(line);
}

// Texte assemble a l'execution.
void LcdDisplay::setText(const String& text, int line) {
  if (line < 0 || line > 3) return;
  strncpy(messages[line], text.c_str(), LCD_MSG_MAX);
  messages[line][LCD_MSG_MAX] = '\0';
  storeAndPaint(line);
}

void LcdDisplay::storeAndPaint(int line) {

  removeAccentsInPlace(messages[line]);
  offsets[line] = 0;

  // Ecran fige sur l'ASCII art "controle par l'app" : on memorise quand
  // meme ce que le jeu veut afficher (messages[] ci-dessus), sans le
  // peindre. Ca permet de repeindre l'ecran reel tel quel des que le
  // controle est relache - sinon il resterait fige jusqu'a la prochaine
  // transition de phase, qui peut ne jamais venir si le jeu est assis
  // dans une phase stable (ex. WAITING_BUZZER).
  if (_controlOverrideActive) return;

  displayText(messages[line], line);

}

void LcdDisplay::displayText(const char* text, int line) {

  lcd.setCursor(0, line);
  lcd.print(F("                    "));
  lcd.setCursor(0, line);
  for (int i = 0; i < LCD_COLS && text[i]; i++) lcd.write(text[i]);

  // Repere "pas de lecteur audio" : repeint apres le texte pour survivre
  // a n'importe quel ecran de jeu (chacun redessine ses 4 lignes de zero,
  // il n'y a aucune zone reservee sur ce LCD 20x4). Uniquement en mode
  // simulation, donc l'affichage normal n'est jamais ampute.
  if (_audioWarning && line == 0) {
    lcd.setCursor(19, 0);
    lcd.print("X");
  }

}

void LcdDisplay::setAudioWarning(bool active) {
  if (active == _audioWarning) return;
  _audioWarning = active;
  displayText(messages[0], 0);   // applique (ou efface) le repere tout de suite
}

void LcdDisplay::updateScrolling() {

  if (_controlOverrideActive) return;  // ecran fige sur l'ASCII art "controle par l'app"

  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis < SCROLL_DELAY) {
    return;
  }

  previousMillis = currentMillis;

  for(int i = 0; i < 4; i++) {
    int len = strlen(messages[i]);
    if (len <= LCD_COLS) {
      continue;
    }

    // Deux espaces separent la fin du message de son debut, sinon le texte
    // se recolle a lui-meme et devient illisible au raccord.
    const int total = len + 2;

    // La fenetre de 20 colonnes est composee caractere par caractere depuis
    // le tampon, en enroulant l'index. L'ancienne version construisait la
    // meme chose avec une copie, une concatenation et deux sous-chaines,
    // soit quatre allocations par ligne et par tour — trois fois par
    // seconde, indefiniment.
    char window[LCD_COLS + 1];
    for (int c = 0; c < LCD_COLS; c++) {
      int idx = (offsets[i] + c) % total;
      window[c] = (idx < len) ? messages[i][idx] : ' ';
    }
    window[LCD_COLS] = '\0';

    displayText(window, i);
    offsets[i] = (offsets[i] + 1) % total;

  }
}

// Définit les caractères personnalisés 0..7 : une barre remplie depuis le
// bas, de 1 pixel (char 0) à 8 pixels = cellule pleine (char 7).
void LcdDisplay::initBarChars() {
  byte pattern[8];
  for (int c = 0; c < 8; c++) {
    for (int row = 0; row < 8; row++) {
      // row 0 = haut de la cellule ; on remplit les (c+1) rangées du bas.
      pattern[row] = (row >= 7 - c) ? 0b11111 : 0b00000;
    }
    lcd.createChar(c, pattern);
  }
}

// Dessine l'égaliseur : chaque colonne est une barre verticale de 0 à 32
// pixels répartie sur les 4 lignes du LCD (4 x 8 pixels).
void LcdDisplay::drawEqualizer(const uint8_t heights[20]) {
  for (int row = 0; row < 4; row++) {
    lcd.setCursor(0, row);
    int base = (3 - row) * 8;   // pixels sous cette ligne
    for (int col = 0; col < 20; col++) {
      int v = (int)heights[col] - base;
      if (v <= 0) {
        lcd.write(' ');
      } else if (v >= 8) {
        lcd.write((uint8_t)7);          // cellule pleine
      } else {
        lcd.write((uint8_t)(v - 1));    // barre partielle (1..7 pixels)
      }
    }
  }
}

// Ecran plein format annoncant que l'app a pris le controle (voir
// BleLink::appInControl) - dessine directement via lcd, en contournant
// setText()/clear() (qui sont eux-memes bloques tant que ce verrou est
// actif, pour figer l'affichage meme si le jeu reel continue d'appeler
// setText() en arriere-plan). Contenu ajustable ici sans toucher au reste
// du firmware.
void LcdDisplay::setControlOverride(bool active) {
  if (active == _controlOverrideActive) return;
  _controlOverrideActive = active;

  if (!active) {
    // Les caracteres 0 et 1 ont servi au cadenas : ils appartiennent a
    // l'egaliseur, qui dessinerait des morceaux de cadenas a la place de ses
    // barres si on ne les lui rendait pas.
    initBarChars();

    // Controle relache : repeint immediatement ce que le jeu voulait
    // afficher pendant le gel (memorise par setText()). Ne pas compter
    // sur le prochain setText() du jeu : il n'arrive qu'a la prochaine
    // transition de phase, donc jamais si le jeu attend un buzz.
    for (int i = 0; i < 4; i++) {
      displayText(messages[i], i);
    }
    return;
  }

  // Un cadenas dessine sur deux cellules empilees, plus un cadre complet.
  // L'ancien ecran (une ligne de # et trois lignes centrees) disait la meme
  // chose, mais avait l'air d'un message d'erreur : ce n'en est pas un,
  // c'est l'etat normal quand l'app anime la soiree.
  //
  // Les caracteres 0 et 1 sont empruntes a l'egaliseur (initBarChars) et lui
  // sont rendus des que le controle est relache, plus bas.
  byte anseCadenas[8] = {
    0b00000,
    0b00000,
    0b01110,
    0b10001,
    0b10001,
    0b10001,
    0b11111,
    0b11111,
  };
  byte corpsCadenas[8] = {
    0b11111,
    0b11011,
    0b11011,
    0b11111,
    0b11111,
    0b00000,
    0b00000,
    0b00000,
  };
  lcd.createChar(0, anseCadenas);
  lcd.createChar(1, corpsCadenas);

  lcd.clear();

  lcd.setCursor(0, 0);
  lcd.print(F("####################"));
  lcd.setCursor(0, 3);
  lcd.print(F("####################"));

  // Colonne 0 et 19 : le cadre. Colonne 3 : le cadenas. Colonnes 5 a 18 :
  // quatorze caracteres de texte, la largeur de « CLAVIER BLOQUE ».
  lcd.setCursor(0, 1);
  lcd.print(F("#  "));
  lcd.write(byte(0));
  lcd.print(F(" L'APP MENE    #"));
  lcd.setCursor(0, 2);
  lcd.print(F("#  "));
  lcd.write(byte(1));
  lcd.print(F(" CLAVIER BLOQUE#"));
}

// Remplace sur place les lettres accentuees par leur equivalent ASCII.
//
// Les accents arrivent en UTF-8, donc sur DEUX octets : 0xC3 suivi d'un
// second octet qui designe la lettre. On ecrit un seul octet a la place, ce
// qui raccourcit la chaine — d'ou le curseur d'ecriture w distinct du
// curseur de lecture r.
//
// L'ancienne version enchainait neuf String::replace, chacun reconstruisant
// la chaine entiere sur le tas.
void LcdDisplay::removeAccentsInPlace(char* s) {
  char* w = s;
  for (char* r = s; *r; ) {
    if ((unsigned char)*r == 0xC3 && r[1]) {
      char rep = 0;
      switch ((unsigned char)r[1]) {
        case 0xA0: case 0xA2: case 0xA4: rep = 'a'; break;   // a a a
        case 0xA7:                       rep = 'c'; break;   // c
        case 0xA8: case 0xA9: case 0xAA: case 0xAB: rep = 'e'; break;
        case 0xAE: case 0xAF:            rep = 'i'; break;   // i i
        case 0xB4: case 0xB6:            rep = 'o'; break;   // o o
        case 0xB9: case 0xBB: case 0xBC: rep = 'u'; break;   // u u u
      }
      if (rep) { *w++ = rep; r += 2; continue; }
    }
    *w++ = *r++;
  }
  *w = '\0';
}