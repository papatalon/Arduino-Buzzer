#ifndef PHASEMODE_H
#define PHASEMODE_H

// Define the PhaseMode enum here
enum PhaseMode {
    BOOT,           // demarrage : egaliseur anime pendant la chanson d'intro
    CONFIGURATION,
    GAME_CHOICE,    // sous-menu "C" : choix du jeu (Classique/Penalite/Simon)
    SHUFFLE_BUZZER,
    BUZZER_CONFIG,
    RESET,
    INTRO,
    WAITING_BUZZER,
    BUZZER_PRESSED,
    SHOW_SCORES,
    END_CONFIRM,
    END_GAME,
    VOLUME,
    CHRONO,         // reglage des deux durees du chrono de buzz
    SIMON_SHOW,     // Simon : demonstration de la sequence
    SIMON_PLAY,     // Simon : les joueurs repetent la sequence
    SIMON_OVER,     // Simon : fin de partie (niveau atteint)
    LED_TEST        // mode cache de test cablage (LED + boutons), entree *1
};

#endif