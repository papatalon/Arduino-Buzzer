#include "BleLink.h"

BleLink::BleLink() {
}

BleLink& BleLink::shared() {
  static BleLink instance;
  return instance;
}

void BleLink::init() {
  Serial2.begin(9600);
}

void BleLink::send(const String& message) {
  Serial2.println(message);
}

char BleLink::pollKey() {
  char result = 0;
  while (Serial2.available()) {
    char c = (char)Serial2.read();
    if (c == '\n') {
      _rxBuffer.trim();  // Serial2.println cote app envoie "\r\n"
      if (_rxBuffer.startsWith("KEY|") && _rxBuffer.length() == 5) {
        result = _rxBuffer.charAt(4);
      } else if (_rxBuffer == "CTRL|1") {
        _inControl = true;
        _lastControlMillis = millis();
      } else if (_rxBuffer == "CTRL|0") {
        _inControl = false;
      }
      _rxBuffer = "";
    } else if (_rxBuffer.length() < 32) {  // ligne trop longue : forcement corrompue, on l'ignore
      _rxBuffer += c;
    }
  }
  return result;
}

bool BleLink::appInControl() {
  return _inControl && (millis() - _lastControlMillis <= kControlTimeoutMs);
}
