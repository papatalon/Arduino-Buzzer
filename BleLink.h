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

    // Telemetrie commune aux jeux non-quiz (Reflexe, Chrono aveugle, Duel,
    // Ne buzze pas). Chacun garde SES propres scores, distincts de ceux du
    // quiz (Buzzer::scores) : sans ces messages, l'app affichait les scores
    // du quiz pendant un jeu qui n'y touche pas.
    //   GSCORE|s0|s1|s2|s3   scores propres au jeu
    //   GROUND|<manche>|<total>
    //   GOVER|<gagnant>|<egalite>   gagnant -1 = aucun (personne ou abandon)
    void sendGameScores(const int scores[4]);
    void sendGameRound(int round, int total);
    void sendGameOver(int winner, bool tie);

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

    // Retourne le nombre de questions demande par un "SET_COUNT|<n>" recu
    // depuis le dernier appel (0-99, 0 = Ouvert), ou -1 si aucun n'est en
    // attente. Consommee une seule fois - voir
    // Configuration::confirmQuestionCount(). Une vraie commande plutot que
    // des appuis rejoues : le compteur ne reboucle pas, donc atteindre 0
    // depuis 99 demanderait 99 pressions de touche.
    int consumeQuestionCount();

    // Nombre de questions demande par un "START_GAME|<n>" recu depuis le
    // dernier appel (0 = ouvert, l'app decide de la fin), ou -1 si aucun
    // depart n'est en attente. Consommee une seule fois.
    //
    // En mode application, l'app ne fait pas naviguer le firmware dans ses
    // menus : elle demande le depart, et le firmware demarre - voir
    // Configuration::startFromApp().
    int consumeStartGame();

    // --- Primitives du mode esclave (voir AppControl) ---------------------
    //
    // Masque de buzzers a armer demande par "ARM|<masque>" ou 0 pour un
    // "DISARM", ou -1 si rien n'est en attente. Consommee une seule fois.
    int consumeArm();
    // Vrai quand le dernier ARM consomme demandait le mode continu.
    bool armWasContinu();
    // Masque de LED demande par "LED|<masque>", ou -1 si rien n'est en
    // attente. Consommee une seule fois.
    int consumeLeds();
    int consumeGo();

    // Retourne le masque de presence demande par un "SET_PRESENT|<n>" recu
    // depuis le dernier appel (bit 0 = rouge ... bit 3 = vert), ou -1 si
    // aucun n'est en attente. Consommee une seule fois. Sert a jouer a deux
    // (ou a trois) depuis l'app : l'assistant du clavier exige d'appuyer
    // physiquement sur chaque buzzer present, ce qui est impossible a
    // piloter a distance - et le clavier est de toute facon verrouille.
    int consumePresenceMask();

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
    int _pendingQuestionCount = -1;
    int _pendingStartGame = -1;
    int _pendingArm = -1;
    bool _pendingArmContinu = false;
    int _pendingLeds = -1;
    int _pendingGo = -1;
    int _pendingPresenceMask = -1;
    bool _appSoundBusy = false;
    bool _appHandlesSound = true;
    char _pendingSoundCommand = 0;
    int _pendingSoundBuzzer = -1;
};

#endif
