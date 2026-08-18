#ifndef BLELINK_H
#define BLELINK_H

#include <Arduino.h>

// Lien BLE vers l'app compagnon, via l'AT-09 sur Serial2 (pins fixes du Mega :
// TX2 = 16, RX2 = 17 ; TX2 passe par un diviseur de tension vers RXD, voir
// README). Pour l'instant, telemetrie sortante seulement (Mega -> app) ;
// la reception de commandes (app -> Mega) viendra dans une passe suivante.
class BleLink {
  public:
    static BleLink& shared();

    void init();
    void send(const String& message);

  private:
    BleLink();
    BleLink(const BleLink&) = delete;
    BleLink& operator=(const BleLink&) = delete;
};

#endif
