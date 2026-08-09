#ifndef GAMEMODE_H
#define GAMEMODE_H

// Jeux disponibles, choisis dans le menu deroulant du sous-menu "C" du menu
// principal. Le jeu selectionne est lance par "#" depuis le menu.
//
// Ajouter un jeu : inserer une valeur ICI (avant GAME_MODE_COUNT, qui doit
// rester en dernier) et completer les tableaux GAME_NAMES / GAME_DESCRIPTIONS
// dans Configuration.cpp. Le menu deroulant s'adapte automatiquement.
enum GameMode {
    GAME_CLASSIC,        // quiz : bonne reponse +1, mauvaise sans effet
    GAME_PENALTY,        // quiz : bonne reponse +1, mauvaise -1
    GAME_CHRONO_CLASSIC, // quiz classique + chrono de buzz (duree configuree)
    GAME_CHRONO_PENALTY, // quiz penalite + chrono de buzz (duree configuree)
    GAME_VOL,            // question adressee a un joueur ; les autres peuvent la voler s'il rate (chrono toujours actif)
    GAME_SIMON,          // jeu collaboratif de memoire (obligatoirement a 4)
    GAME_SIMON_REVERSE,  // comme GAME_SIMON, mais la sequence se repete a l'envers
    GAME_MODE_COUNT      // sentinelle : nombre de jeux (doit rester en dernier)
};

#endif
