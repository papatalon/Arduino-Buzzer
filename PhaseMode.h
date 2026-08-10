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
    ANSWER_REVEAL,  // question passee (personne n'a repondu) : affiche la reponse (banque)
    SHOW_SCORES,
    END_CONFIRM,
    END_GAME,
    VOLUME,
    CHRONO,         // reglage des deux durees du chrono de buzz
    QUIZ_CATS,      // lancement d'un quiz : choix des categories de questions
    QUIZ_COUNT,     // lancement d'un quiz : nombre de questions a poser
    VOL_SPIN,       // Vol : tirage au sort anime (chenillard + son) du 1er joueur
    SIMON_SHOW,     // Simon : demonstration de la sequence
    SIMON_PLAY,     // Simon : les joueurs repetent la sequence
    SIMON_OVER,     // Simon : fin de partie (niveau atteint)
    REFLEX_ARM,     // Reflexe : attente du signal (buzzer = faux depart)
    REFLEX_GO,      // Reflexe : signal donne, course au buzz
    REFLEX_RESULT,  // Reflexe : resultat de la manche (temps de reaction)
    REFLEX_OVER,    // Reflexe : fin de partie (scores + record)
    LED_TEST        // mode cache de test cablage (LED + boutons), entree *1
};

#endif