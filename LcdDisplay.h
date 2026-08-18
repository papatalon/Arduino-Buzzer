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

    // Égaliseur graphique (animation de démarrage) : charge 8 caractères
    // personnalisés (barres de 1 à 8 pixels) puis dessine 20 colonnes sur
    // les 4 lignes. heights[i] = hauteur de la colonne i, de 0 à 32 pixels.
    void initBarChars();
    void drawEqualizer(const uint8_t heights[20]);

    // Fige l'écran sur un ecran "controle par l'app" (voir BleLink::
    // appInControl) : tant que actif, setText()/updateScrolling() sont
    // ignores (le jeu reel continue de tourner, seul l'affichage est gele).
    // A appeler une fois par tour de loop().
    void setControlOverride(bool active);

  private:
    LiquidCrystal_I2C lcd;
    String messages[4] = { "", "", "", ""};
    int offsets[4] = { 0, 0, 0, 0 };
    bool _controlOverrideActive = false;
    void displayText(String text, int line);
    unsigned long previousMillis = 0;    // Last time of update
    String removeAccents(String text);
    String centerLine(String text);
    LcdDisplay(const LcdDisplay&) = delete;
    LcdDisplay& operator=(const LcdDisplay&) = delete;
};

#endif