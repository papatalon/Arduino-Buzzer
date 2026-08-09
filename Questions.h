#ifndef QUESTIONS_H
#define QUESTIONS_H

#include <Arduino.h>
#include <avr/pgmspace.h>

// Banque de questions en memoire programme (PROGMEM) : le texte reste en
// Flash et n'occupe aucune SRAM. Chaque categorie est une longue chaine
// d'entrees "Question|Reponse\n" mises bout a bout ; le nombre d'entrees est
// compte au demarrage (QuestionBank::init), donc on peut ajouter des
// questions librement dans Questions.cpp sans rien changer d'autre.
//
// Regles d'ecriture des questions (voir Questions.cpp) :
//  - pas d'accents (le LCD ne les affiche pas) ;
//  - pas de '|' ni de retour a la ligne dans les textes ;
//  - question courte (ideal <= 60 caracteres, l'ecran defile au-dela de 20) ;
//  - reponse courte (ideal <= 20 caracteres).

#define QCAT_COUNT 10

// La banque depasse la barriere des 64 Ko de Flash adressables par les
// pointeurs PROGMEM classiques (16 bits). Les donnees sont donc placees en
// FIN de Flash (section .fini1, jamais executee sur Arduino) et lues via
// des adresses "far" 32 bits (pgm_read_byte_far). Les petites chaines du
// reste du programme (F(), PROGMEM) restent en debut de Flash, sous 64 Ko.
uint32_t qcatNameFar(int c);   // adresse far du nom de la categorie c
uint32_t qcatDataFar(int c);   // adresse far des donnees de la categorie c

#endif
