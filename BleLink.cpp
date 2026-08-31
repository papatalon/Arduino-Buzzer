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

void BleLink::sendGameScores(const int scores[4]) {
  send(String("GSCORE|") + scores[0] + "|" + scores[1] + "|" + scores[2] + "|" + scores[3]);
}

void BleLink::sendGameRound(int round, int total) {
  send(String("GROUND|") + round + "|" + total);
}

void BleLink::sendGameOver(int winner, bool tie) {
  send(String("GOVER|") + winner + "|" + (tie ? 1 : 0));
}

char BleLink::pollKey() {
  char result = 0;
  while (Serial2.available()) {
    char c = (char)Serial2.read();
    if (c == '\n') {
      _rxBuffer.trim();  // Serial2.println cote app envoie "\r\n"
      if (_rxBuffer.startsWith("KEY|") && _rxBuffer.length() == 5) {
        result = _rxBuffer.charAt(4);
      } else if (_rxBuffer.startsWith("CTRL|1")) {
        _inControl = true;
        _lastControlMillis = millis();
        // Le mode audio voyage dans le heartbeat ("CTRL|1|<0/1>") plutot
        // que dans un message ponctuel : s'il etait envoye une seule fois,
        // un redemarrage du Mega en pleine soiree le perdrait et le son
        // basculerait sans prevenir. Un ancien "CTRL|1" nu garde le
        // defaut (l'app joue).
        if (_rxBuffer.length() >= 8) {
          _appHandlesSound = (_rxBuffer.charAt(7) != '0');
        }
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
      } else if (_rxBuffer == "SFX_BUSY|1") {
        _appSoundBusy = true;
      } else if (_rxBuffer == "SFX_BUSY|0") {
        _appSoundBusy = false;
      } else if (_rxBuffer.startsWith("SND|")) {
        // "SND|<action>|<buzzer>" : melanger (S) ignore le buzzer, les
        // autres actions le visent (0-3).
        char action = _rxBuffer.charAt(4);
        int who = -1;
        int sep = _rxBuffer.indexOf('|', 4);
        if (sep > 0) {
          who = _rxBuffer.substring(sep + 1).toInt();
        }
        if (action == 'S' || (who >= 0 && who < 4)) {
          _pendingSoundCommand = action;
          _pendingSoundBuzzer = who;
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

bool BleLink::appSoundBusy() {
  return _appSoundBusy;
}

bool BleLink::appHandlesSound() {
  return _appHandlesSound;
}

char BleLink::consumeSoundCommand() {
  char c = _pendingSoundCommand;
  _pendingSoundCommand = 0;
  return c;
}

int BleLink::soundCommandBuzzer() {
  return _pendingSoundBuzzer;
}

int BleLink::consumeCategoryMask() {
  int v = _pendingCategoryMask;
  _pendingCategoryMask = -1;
  return v;
}
