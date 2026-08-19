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
        // Repond immediatement au heartbeat de l'app : contrairement a la
        // telemetrie de jeu (qui peut rester silencieuse longtemps en
        // attendant un evenement), un heartbeat doit toujours revenir - ca
        // donne a l'app un moyen fiable de detecter un lien mort ("fantome")
        // sans faux positif pendant une attente de buzz legitime.
        send("PONG");
      } else if (_rxBuffer == "CTRL|0") {
        _inControl = false;
      } else if (_rxBuffer.startsWith("SELECT_GAME|")) {
        int idx = _rxBuffer.substring(12).toInt();
        if (idx >= 0 && idx < 11) {  // GAME_MODE_COUNT
          _pendingGameSelect = idx;
        }
      } else if (_rxBuffer.startsWith("SET_CATS|")) {
        int mask = _rxBuffer.substring(9).toInt();
        if (mask >= 0 && mask < 1024) {  // 10 bits (QCAT_COUNT)
          _pendingCategoryMask = mask;
        }
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

int BleLink::consumeGameSelect() {
  int v = _pendingGameSelect;
  _pendingGameSelect = -1;
  return v;
}

int BleLink::consumeCategoryMask() {
  int v = _pendingCategoryMask;
  _pendingCategoryMask = -1;
  return v;
}
