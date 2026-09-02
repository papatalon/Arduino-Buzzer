#ifndef APPCONTROL_H
#define APPCONTROL_H

#include <Arduino.h>
#include "PhaseMode.h"
#include "Buzzer.h"
#include "BleLink.h"

// LE MODE ESCLAVE : quand l'application mene, le buzzer n'est qu'un
// gestionnaire de boutons.
//
// En mode autonome (clavier physique), le firmware mene le spectacle : menus,
// choix du jeu, banque de questions, scores, chronos, ecrans. Rien de tout ca
// ne change.
//
// En mode application, il n'a plus AUCUN etat de jeu. Pas de jeu en memoire,
// pas de score, pas de question, pas de phase de quiz. Il ecoute trois
// primitives et rapporte les appuis. C'est l'application qui decide de tout
// le reste.
//
// POURQUOI CETTE COUPURE NETTE. Tant que le Mega gardait sa machine a etats
// en mode application, l'app devait la suivre : elle miroitait ses ecrans,
// heritait du jeu qu'il avait garde en memoire, et se retrouvait a annoncer
// des choses que personne n'avait choisies. Chaque correctif au cas par cas
// en decouvrait un autre. Le probleme n'etait pas dans l'app, il etait dans
// le partage des roles.
//
// LES PRIMITIVES
//
//   ARM|<masque>   accepte le PREMIER appui parmi ces buzzers, allume sa LED,
//                  ignore les suivants, et repond BUZZ|<n>|<ms>
//   DISARM         n'accepte plus rien
//   LED|<masque>   allume ou eteint directement (gagnant, chenillard, Simon)
//
// LE TEMPS DE REACTION EST MESURE ICI, pas dans l'application. Un aller-retour
// Bluetooth ajoute de 30 a 100 ms de gigue, ce qui rendrait le Reflexe et le
// Duel faux. Mesurer un appui fait partie de la gestion des boutons.
class AppControl {
public:
    // L'application vient de prendre la main : on repart de zero.
    void enter();

    // Appelee a chaque tour de boucle tant que l'app mene. Lit les boutons
    // armes et envoie BUZZ des qu'il y en a un.
    void tick();

    void arm(int mask);
    void disarm();
    void setLeds(int mask);

private:
  // Buzzers qui peuvent encore buzzer. Zero = desarme.
  int armedMask = 0;
  // Depart de la mesure du temps de reaction.
  unsigned long armedAt = 0;
  // Un seul appui est rapporte par armement : c'est l'application qui
  // rearme quand elle veut le suivant. Sans ca, un joueur qui pianote
  // enverrait une rafale de BUZZ pendant que l'animateur juge le premier.
  bool fired = false;

  Buzzer& buzzer = Buzzer::shared();
  BleLink& ble = BleLink::shared();
};

#endif
