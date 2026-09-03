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
//   ARM|<masque>[|C] accepte les appuis parmi ces buzzers et repond
//                  BUZZ|<n>|<ms>. Sans suffixe : le PREMIER appui seulement,
//                  puis desarmement complet - c'est la regle du quiz, ou le
//                  premier qui pese prend la main. Avec |C : mode CONTINU,
//                  chaque buzzer arme rapporte son appui et sort du masque,
//                  les autres restent en jeu.
//   DISARM         n'accepte plus rien
//   LED|<masque>   allume ou eteint directement (gagnant, chenillard, Simon)
//   GO|<masque>    allume ET remet le chrono de reaction a zero, dans la meme
//                  instruction
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

    void arm(int mask, bool continu = false);
    void disarm();
    void setLeds(int mask);

    // LE SIGNAL DE DEPART du Reflexe et du Duel.
    //
    // Allume les LED et repart le chrono AU MEME INSTANT. Si l'application
    // envoyait LED puis comptait de son cote, la latence Bluetooth de cette
    // commande (30 a 100 ms, inconnue) s'ajouterait a chaque temps de
    // reaction, qui se joue entre 150 et 400 ms : 20 a 50% d'erreur, et des
    // records incomparables d'une manche a l'autre.
    //
    // Aucune regle de jeu ne passe ici pour autant : l'application decide du
    // delai, du moment, des faux departs et des scores. Le Mega garantit
    // seulement que « ca s'allume » et « le chrono part » sont le meme
    // instant, ce qu'elle ne peut pas garantir a distance.
    void go(int mask);

private:
  // Buzzers qui peuvent encore buzzer. Zero = desarme.
  int armedMask = 0;
  // Depart de la mesure du temps de reaction.
  unsigned long armedAt = 0;
  // Un seul appui est rapporte par armement : c'est l'application qui
  // rearme quand elle veut le suivant. Sans ca, un joueur qui pianote
  // enverrait une rafale de BUZZ pendant que l'animateur juge le premier.
  bool fired = false;

  // MODE CONTINU. Le quiz s'arrete au premier appui ; les autres jeux non.
  // Chrono aveugle attend un appui de CHAQUE joueur, Simon une suite du
  // meme, Ne buzze pas des appuis a n'importe quel moment. Dans ce mode,
  // un buzzer qui pese sort du masque et les autres restent armes ; c'est
  // l'application qui decide quand tout s'arrete.
  //
  // La LED n'est PAS allumee automatiquement ici : en Reflexe un appui trop
  // tot est un faux depart, et l'eclairer comme un gagnant serait mentir.
  // C'est l'application qui allume, quand elle a juge.
  bool continu = false;

  Buzzer& buzzer = Buzzer::shared();
  BleLink& ble = BleLink::shared();
};

#endif
