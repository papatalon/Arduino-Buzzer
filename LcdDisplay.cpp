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

  if (_controlOverrideActive) return;  // ecran fige sur l'ASCII art "controle par l'app"

  text = removeAccents(text);

  messages[line] = text;
  offsets[line] = 0;

  displayText(text, line);

}

void LcdDisplay::displayText(String text, int line) {

  lcd.setCursor(0, line);
  lcd.print("                    ");
  lcd.setCursor(0, line);
  lcd.print(text.substring(0, 20));

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
  if (!active) return;  // le prochain setText() du jeu reel redessine normalement

  lcd.clear();

  String border = "";
  for (int i = 0; i < 20; i++) border += '#';

  lcd.setCursor(0, 0);
  lcd.print(border);
  lcd.setCursor(0, 1);
  lcd.print(centerLine("CONTROLE A DISTANCE"));
  lcd.setCursor(0, 2);
  lcd.print(centerLine("PAR L'APPLICATION"));
  lcd.setCursor(0, 3);
  lcd.print(centerLine("CLAVIER VERROUILLE"));
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