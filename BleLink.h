#ifndef BLELINK_H
#define BLELINK_H

#include <Arduino.h>

// Lien BLE vers l'app compagnon, via l'AT-09 sur Serial2 (pins fixes du Mega :
// TX2 = 16, RX2 = 17 ; TX2 passe par un diviseur de tension vers RXD, voir
// README). Telemetrie sortante (Mega -> app) et commandes entrantes
// (app -> Mega, protocole "KEY|<touche>" : l'app simule une touche du
// clavier matriciel, rejouee telle quelle dans la meme machine a etats).
class BleLink {
  public:
    static BleLink& shared();

    void init();
    void send(const String& message);

    // A appeler une fois par tour de loop() : draine Serial2 et renvoie la
    // touche demandee par l'app si une ligne "KEY|X" complete est arrivee,
    // sinon 0 (equivalent a NO_KEY). Ne bloque jamais.
    char pollKey();

  private:
    BleLink();
    BleLink(const BleLink&) = delete;
    BleLink& operator=(const BleLink&) = delete;

    String _rxBuffer;
};

#endif
