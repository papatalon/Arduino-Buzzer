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

  displayText(text, line);

}

void LcdDisplay::displayText(String text, int line) {

  lcd.setCursor(0, line);
  lcd.print("                    ");
  lcd.setCursor(0, line);
  lcd.print(text.substring(0, 20));

}

void LcdDisplay::updateScrolling() {

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