#ifndef BLELINK_H
#define BLELINK_H

#include <Arduino.h>

// Lien BLE vers l'app compagnon, via l'AT-09 sur Serial2 (pins fixes du Mega :
// TX2 = 16, RX2 = 17 ; TX2 passe par un diviseur de tension vers RXD, voir
// README). Telemetrie sortante (Mega -> app) et commandes entrantes
// (app -> Mega, protocole "KEY|<touche>" : l'app simule une touche du
// clavier matriciel, rejouee telle quelle dans la meme machine a etats).
//
// L'AT-09 est un pont UART transparent (4 fils, pas de broche STATE) : le
// Mega ne peut pas savoir directement si un telephone est connecte. Le
// "controle" de l'app est donc deduit d'un signal logiciel ("CTRL|1",
// repete toutes les ~1s tant que l'app est connectee) avec expiration
// automatique (appInControl()) si les messages cessent d'arriver - pour ne
// pas rester verrouille si le lien BLE tombe sans preavis.
class BleLink {
  public:
    static BleLink& shared();

    void init();
    void send(const String& message);

    // A appeler une fois par tour de loop() : draine Serial2 et renvoie la
    // touche demandee par l'app si une ligne "KEY|X" complete est arrivee,
    // sinon 0 (equivalent a NO_KEY). Reconnait aussi au passage les lignes
    // "CTRL|0"/"CTRL|1" (voir appInControl()) et "SELECT_GAME|<n>" (voir
    // consumeGameSelect()). Ne bloque jamais.
    char pollKey();

    // Vrai si l'app a annonce le controle ("CTRL|1") et l'a reconfirme
    // recemment (heartbeat) - expire tout seul si les messages cessent.
    bool appInControl();

    // Retourne l'index de jeu demande par un "SELECT_GAME|<n>" recu depuis
    // le dernier appel (0-10), ou -1 si aucun n'est en attente. Consommee
    // une seule fois (remise a -1 apres lecture) : une vraie commande, pas
    // une simulation de touche - voir Configuration::selectGameIndex().
    int consumeGameSelect();

    // Retourne le masque de categories demande par un "SET_CATS|<n>" recu
    // depuis le dernier appel (0-1023), ou -1 si aucun n'est en attente.
    // Consommee une seule fois - voir Configuration::confirmCategories().
    int consumeCategoryMask();

    // Etat de lecture rapporte par l'app ("SFX_BUSY|0/1") quand elle joue
    // les sons a notre place : remplace la broche BUSY du DFPlayer, qui ne
    // bouge plus dans ce mode. Voir Mp3::isBusy().
    bool appSoundBusy();

    // Faux quand l'operateur a demande que le buzzer joue lui-meme les
    // sons (pas de haut-parleur cote PC, par exemple). Transporte par le
    // heartbeat, voir pollKey().
    bool appHandlesSound();

    // Commande de configuration des sons du DFPlayer demandee par l'app,
    // ou 0 si rien en attente. Consommee une seule fois. Sert a piloter a
    // distance ce que l'assistant du clavier fait localement - sans quoi,
    // en mode "son du buzzer", personne ne pourrait reassigner les sons :
    // l'app n'a pas prise dessus et le clavier est verrouille.
    //   'S' = melanger, 'N' = suivant, 'P' = precedent, 'E' = ecouter
    char consumeSoundCommand();
    int soundCommandBuzzer();   // buzzer vise (0-3), -1 pour "melanger"

  private:
    BleLink();
    BleLink(const BleLink&) = delete;
    BleLink& operator=(const BleLink&) = delete;

    static const unsigned long kControlTimeoutMs = 3000;  // ~3x la cadence du heartbeat app

    String _rxBuffer;
    bool _inControl = false;
    unsigned long _lastControlMillis = 0;
    int _pendingGameSelect = -1;
    int _pendingCategoryMask = -1;
    bool _appSoundBusy = false;
    bool _appHandlesSound = true;
    char _pendingSoundCommand = 0;
    int _pendingSoundBuzzer = -1;
};

#endif
