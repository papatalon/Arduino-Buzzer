#ifndef PHASEMODE_H
#define PHASEMODE_H

// Define the PhaseMode enum here
enum PhaseMode {
    BOOT,           // demarrage : egaliseur anime pendant la chanson d'intro
    CONFIGURATION,
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
    LED_TEST        // mode cache de test cablage (LED + boutons), entree *1
};

#endif