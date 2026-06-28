#ifndef OLEDDISPLAY_H
#define OLEDDISPLAY_H

#include <SPI.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#define SCREEN_WIDTH 128 // OLED display width, in pixels
#define SCREEN_HEIGHT 64 // OLED display height, in pixels

// Declaration for an SSD1306 display connected to I2C (SDA, SCL pins)
// The pins for I2C are defined by the Wire-library. 
// On an Arduino UNO:       A4(SDA), A5(SCL)
// On an Arduino MEGA 2560: 20(SDA), 21(SCL)
// On an Arduino LEONARDO:   2(SDA),  3(SCL), ...
#define OLED_RESET -1       // Reset pin # (or -1 if sharing Arduino reset pin)
#define SCREEN_ADDRESS 0x3D // See datasheet for Address; 0x3D for 128x64, 0x3C for 128x32
#define LINE_HEIGHT 11
#define TEXT_SIZE 1
#define SCROLL_DELAY 100
#define PADDING 3

class OledDisplay {
  public:
    OledDisplay() : display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET) {} // Constructor to initialize the display
    static OledDisplay& shared();
    void testdrawtriangle();
    bool init();
    void clear();
    void displayContent();  
    void displayText(String text, int line);
    void updateScrolling();


  private:
    Adafruit_SSD1306 display;
    String messages[5] = { "", "", "", "", ""};
    int offsets[5] = { 0, 0, 0, 0, 0 };
    unsigned long previousMillis = 0;    // Last time of update
    String padRight(String input, int totalLength);
    String removeAccents(String text);
    OledDisplay(const OledDisplay&) = delete;
    OledDisplay& operator=(const OledDisplay&) = delete;
};

#endif
