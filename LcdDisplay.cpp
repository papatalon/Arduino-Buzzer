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

  setText("", 0);
  setText("", 1);
  setText("", 2);
  setText("", 3);
}

void LcdDisplay::setText(String text, int line) {

  text = removeAccents(text);

  messages[line] = text;
  offsets[line] = 0;

  // Ecran fige sur l'ASCII art "controle par l'app" : on memorise quand
  // meme ce que le jeu veut afficher (messages[] ci-dessus), sans le
  // peindre. Ca permet de repeindre l'ecran reel tel quel des que le
  // controle est relache - sinon il resterait fige jusqu'a la prochaine
  // transition de phase, qui peut ne jamais venir si le jeu est assis
  // dans une phase stable (ex. WAITING_BUZZER).
  if (_controlOverrideActive) return;

  displayText(text, line);

}

void LcdDisplay::displayText(String text, int line) {

  lcd.setCursor(0, line);
  lcd.print("                    ");
  lcd.setCursor(0, line);
  lcd.print(text.substring(0, 20));

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
    String message = messages[i];
    int offset = offsets[i];

    int textWidth = message.length();
    if(textWidth <= 20) {
      continue;
    }

    message += "  ";

    // Construit la chaîne à afficher pour donner l'effet ticker
    String messageDisplay = message.substring(offset) + 
                          message.substring(0, offset);

    displayText(messageDisplay, i);
    offsets[i]++;

    if (offsets[i] >= message.length()) {
        offsets[i] = 0;
    }

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

  String cadre = "";
  for (int i = 0; i < 20; i++) cadre += '#';

  lcd.setCursor(0, 0);
  lcd.print(cadre);
  lcd.setCursor(0, 3);
  lcd.print(cadre);

  // Colonne 0 et 19 : le cadre. Colonne 3 : le cadenas. Colonnes 5 a 18 :
  // quatorze caracteres de texte, la largeur de « CLAVIER BLOQUE ».
  lcd.setCursor(0, 1);
  lcd.print("#  ");
  lcd.write(byte(0));
  lcd.print(" L'APP MENE    #");
  lcd.setCursor(0, 2);
  lcd.print("#  ");
  lcd.write(byte(1));
  lcd.print(" CLAVIER BLOQUE#");
}

// Centre un texte (deja sans accents) sur 20 colonnes, tronque s'il est
// trop long.
String LcdDisplay::centerLine(String text) {
  int len = text.length();
  if (len >= 20) return text.substring(0, 20);
  int left = (20 - len) / 2;
  int right = 20 - len - left;
  String out = "";
  for (int i = 0; i < left; i++) out += ' ';
  out += text;
  for (int i = 0; i < right; i++) out += ' ';
  return out;
}

String LcdDisplay::removeAccents(String text) {
  text.replace("é", "e");
  text.replace("è", "e");
  text.replace("à", "a");
  text.replace("ç", "c");
  text.replace("ê", "e");
  text.replace("â", "a");
  text.replace("î", "i");
  text.replace("ô", "o");
  text.replace("û", "u");
  // Ajoute d'autres remplacements selon tes besoins
  return text;
}