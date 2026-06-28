#include "OledDisplay.h"

// === Required for Singletons ===
// Define the single instance as a static member
OledDisplay& OledDisplay::shared() {
  static OledDisplay instance;
  return instance;
}

bool OledDisplay::init() {
    // Initialize the display with the I2C address
    if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
        return false; // Initialization failed
    }

    display.setTextWrap(false);
    // Effacer l'écran pour afficher le logo Adafruit
    display.display();
    delay(2000); // Attendre 2 secondes pour que le logo disparaisse

    // Effacer l'écran après le délai
    display.clearDisplay();
    display.display();
    
    return true; // Initialization succeeded
}

void OledDisplay::clear() {

    for(int i = 1; i <= 4; i++) {
      displayText("", i);
    }
}

void OledDisplay::displayContent() {
    display.display();
}

void OledDisplay::displayText(String text, int line) {

  text = removeAccents(text);
  
  display.setTextSize(TEXT_SIZE); // Draw 2X-scale text
  display.setTextColor(SSD1306_WHITE);

  int x = ((line - 1) * (LINE_HEIGHT + PADDING)) + PADDING;

  display.setCursor(0, x);
  display.print(padRight("", SCREEN_WIDTH / 6 / TEXT_SIZE));

  display.setCursor(0, x);
  display.print(text);

  messages[line] = text;
  offsets[line] = 0;

  display.display();      // Show initial text
}

void OledDisplay::updateScrolling() {
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis < SCROLL_DELAY) {
    return;
  }
    
  previousMillis = currentMillis;
  display.clearDisplay();
  display.setTextSize(TEXT_SIZE); // Draw 2X-scale text
  display.setTextColor(SSD1306_WHITE);

  for(int i = 0; i < 5; i++) {
    String message = messages[i];
    int offset = offsets[i];

    int textWidth = message.length() * 6 * TEXT_SIZE;
    int x = ((i - 1) * (LINE_HEIGHT + PADDING)) + PADDING;
    display.setCursor(0, x);

    if(textWidth <= SCREEN_WIDTH) {
      display.print(message);
      continue;
    }

    message += "  ";

    // Construit la chaîne à afficher pour donner l'effet ticker
    String displayText = message.substring(offset) + 
                          message.substring(0, offset);

    display.print(displayText);
    offsets[i]++;

    if (offsets[i] >= message.length()) {
        offsets[i] = 0;
    }
  }

  display.display();
}

void OledDisplay::testdrawtriangle() {
  display.clearDisplay();

  for(int16_t i=0; i<max(display.width(),display.height())/2; i+=5) {
    display.drawTriangle(
      display.width()/2  , display.height()/2-i,
      display.width()/2-i, display.height()/2+i,
      display.width()/2+i, display.height()/2+i, SSD1306_WHITE);
    display.display();
    delay(1);
  }

  delay(2000);
}

String OledDisplay::padRight(String input, int totalLength) {
  if (input.length() >= totalLength) {
    return input; // Retourne la chaîne d'origine si elle est déjà assez longue
  }
  return input + String(' ', totalLength - input.length());
}

String OledDisplay::removeAccents(String text) {
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