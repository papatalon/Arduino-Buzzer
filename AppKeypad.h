#ifndef APPKEYPAD_H
#define APPKEYPAD_H

#include <Keypad.h>
#include <Arduino.h>

const byte PAD_ROWS = 4; //four rows
const byte PAD_COLS = 4; //four columns

class AppKeypad {
public:
  static AppKeypad& shared();
  bool isResetActivated(char pressedKey);
  bool isLedTestActivated(char pressedKey);   // sequence cachee *1 -> mode test
  char getKey();

private:

  AppKeypad();

  char previousKey = ' ';
  unsigned long previousMillis = 0;

  char hexaKeys[PAD_ROWS][PAD_COLS] = {
    {'1','2','3','A'},
    {'4','5','6','B'},
    {'7','8','9','C'},
    {'*','0','#','D'}
  };

  byte padRowPins[PAD_ROWS] = {39, 41, 43, 45}; //connect to the row pinouts of the keypad
  byte padColPins[PAD_COLS] = {47, 49, 51, 53}; //connect to the column pinouts of the keypad

  //initialize an instance of class NewKeypad
  Keypad customKeypad = Keypad( makeKeymap(hexaKeys), padRowPins, padColPins, PAD_ROWS, PAD_COLS); 

  // Private copy constructor and assignment operator to prevent cloning
  // === Required for Singletons ===
  AppKeypad(const AppKeypad&) = delete;
  AppKeypad& operator=(const AppKeypad&) = delete;
};

#endif
