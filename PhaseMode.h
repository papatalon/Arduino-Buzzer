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
    ROUNDS_SETUP,   // reglage du nombre de manches (Reflexe, Chrono aveugle)
    REFLEX_ARM,     // Reflexe : attente du signal (buzzer = faux depart)
    REFLEX_GO,      // Reflexe : signal donne, course au buzz
    REFLEX_RESULT,  // Reflexe : resultat de la manche (temps de reaction)
    REFLEX_OVER,    // Reflexe : fin de partie (scores + record)
    BLIND_ANNOUNCE, // Chrono aveugle : cible annoncee, attente du depart
    BLIND_RUN,      // Chrono aveugle : chrono en cours, ecran fige
    BLIND_RESULT,   // Chrono aveugle : temps de chacun et gagnant de la manche
    BLIND_OVER,     // Chrono aveugle : fin de partie (scores + record)
    SOUND_SETUP,    // Ne buzze pas : reglage (nb de sons, puis leurres)
    SOUND_LEARN,    // Ne buzze pas : apprentissage des 4 sons
    SOUND_PLAY,     // Ne buzze pas : flux continu de sons
    SOUND_OVER,     // Ne buzze pas : fin de partie (scores)
    DUEL_ARM,       // Duel : attente du signal (buzzer = faux depart)
    DUEL_GO,        // Duel : signal sonore donne, course au buzz
    DUEL_RESULT,    // Duel : resultat de la manche
    DUEL_OVER,      // Duel : fin de partie (scores)
    LED_TEST,       // mode cache de test cablage (LED + boutons), entree *1
    APP_CONTROL     // l'application mene : le buzzer n'est qu'un gestionnaire de boutons
};

#endif