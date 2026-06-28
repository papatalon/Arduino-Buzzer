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