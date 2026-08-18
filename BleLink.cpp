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
