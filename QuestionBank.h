#ifndef QUESTIONBANK_H
#define QUESTIONBANK_H

#include <Arduino.h>
#include "Questions.h"

// Banque de questions : selection de categories, tirage au sort sans
// repetition (les questions deja posees sont marquees dans un bitmap en
// EEPROM, persistant entre les soirees). Quand toutes les questions de la
// selection ont ete posees, l'historique de ces categories est remis a
// zero automatiquement et le tirage repart.
class QuestionBank {
public:
    static QuestionBank& shared();

    void init();                        // compte les questions par categorie

    String categoryName(int c);         // nom d'une categorie (copie RAM)
    int categoryCount(int c);           // nombre de questions de la categorie

    // Selection des categories en jeu : masque de bits (bit c = categorie c).
    // 0 = banque inactive (l'animateur utilise son propre questionnaire).
    void setSelection(uint16_t mask);
    bool isActive();

    // Tire une question non encore posee parmi la selection et la marque
    // comme posee (EEPROM). Renvoie false si la banque est inactive.
    bool drawQuestion();
    String questionText();
    String answerText();
    String questionCategory();          // nom de la categorie de la question tiree

private:
  int counts[QCAT_COUNT];
  uint16_t selection = 0;
  String curQ = "";
  String curA = "";
  int curCat = -1;

  bool isAsked(int cat, int idx);
  void markAsked(int cat, int idx);
  void resetHistory(uint16_t mask);     // efface l'historique des categories du masque
  int countRemaining();                 // questions non posees dans la selection
  bool loadEntry(int cat, int idx);     // lit "Question|Reponse" depuis la Flash
  String readFar(uint32_t addr);        // copie une chaine Flash (adresse far) en RAM

  QuestionBank() {}
  QuestionBank(const QuestionBank&) = delete;
  QuestionBank& operator=(const QuestionBank&) = delete;
};

#endif
