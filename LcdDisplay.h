#ifndef LCDDISPLAY_H
#define LCDDISPLAY_H

#include <Arduino.h>
#include <LiquidCrystal_I2C.h>

#define SCROLL_DELAY 350
#define PADDING 3

class LcdDisplay {
  public:
    LcdDisplay() : lcd(0x27, 20, 4) {};
    static LcdDisplay& shared();
    bool init();
    void setText(String text, int line);
    void updateScrolling();
    void clear();
  
  private:
    LiquidCrystal_I2C lcd;
    String messages[4] = { "", "", "", ""};
    int offsets[4] = { 0, 0, 0, 0 };
    void displayText(String text, int line);
    unsigned long previousMillis = 0;    // Last time of update
    String removeAccents(String text);
    LcdDisplay(const LcdDisplay&) = delete;
    LcdDisplay& operator=(const LcdDisplay&) = delete;
};

#endif