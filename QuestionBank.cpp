#include "QuestionBank.h"
#include <EEPROM.h>

// Historique "deja posee" : 1 bit par question, en EEPROM. Les adresses 0-6
// sont prises (volume + chronos, voir Mp3.cpp et Buzzer.cpp) ; le bitmap
// commence a 16. Chaque categorie reserve QB_STRIDE bits (50 octets), que
// ses questions existent ou non : on peut donc ajouter des questions a une
// categorie sans decaler l'historique des autres.
//
// L'adresse 15 contient la version du plan d'occupation : si QB_STRIDE
// change, les adresses du bitmap se decalent et l'ancien historique devient
// du bruit. init() compare la version et remet le bitmap a zero au besoin.
#define QB_EEPROM_VERSION_ADDR 15
#define QB_LAYOUT_VERSION 2                  // incrementer si QB_STRIDE change
#define QB_EEPROM_BASE 16
#define QB_STRIDE 400                        // capacite max par categorie
#define QB_BYTES_PER_CAT (QB_STRIDE / 8)     // 50 octets par categorie

QuestionBank& QuestionBank::shared() {
  static QuestionBank instance;
  return instance;
}

// Compte les entrees de chaque categorie en parcourant sa chaine en Flash
// (un '\n' = une question). Lecture en adressage far (32 bits) : la banque
// est placee au-dela des 64 Ko. Quelques dizaines de ms au demarrage.
void QuestionBank::init() {
  // Bitmap invalide (premier demarrage ou changement de QB_STRIDE) :
  // remise a zero de l'historique de toutes les categories.
  if (EEPROM.read(QB_EEPROM_VERSION_ADDR) != QB_LAYOUT_VERSION) {
    Serial.println(F("Historique des questions : nouveau plan EEPROM, remise a zero."));
    resetHistory((1 << QCAT_COUNT) - 1);
    EEPROM.update(QB_EEPROM_VERSION_ADDR, QB_LAYOUT_VERSION);
  }

  for (int c = 0; c < QCAT_COUNT; c++) {
    uint32_t p = qcatDataFar(c);
    int n = 0;
    char ch;
    while ((ch = (char)pgm_read_byte_far(p++)) != 0) {
      if (ch == '\n') {
        n++;
      }
    }
    counts[c] = (n > QB_STRIDE) ? QB_STRIDE : n;

    Serial.print(F("Categorie "));
    Serial.print(c);
    Serial.print(F(": "));
    Serial.print(counts[c]);
    Serial.println(F(" questions"));
  }
}

String QuestionBank::readFar(uint32_t addr) {
  String s = "";
  char ch;
  while ((ch = (char)pgm_read_byte_far(addr++)) != 0) {
    s += ch;
  }
  return s;
}

String QuestionBank::categoryName(int c) {
  return readFar(qcatNameFar(c));
}

int QuestionBank::categoryCount(int c) {
  return counts[c];
}

void QuestionBank::setSelection(uint16_t mask) {
  selection = mask;
  curQ = "";
  curA = "";
  curCat = -1;
}

bool QuestionBank::isActive() {
  return selection != 0;
}

bool QuestionBank::isAsked(int cat, int idx) {
  int g = cat * QB_STRIDE + idx;
  return EEPROM.read(QB_EEPROM_BASE + g / 8) & (1 << (g % 8));
}

void QuestionBank::markAsked(int cat, int idx) {
  int g = cat * QB_STRIDE + idx;
  int addr = QB_EEPROM_BASE + g / 8;
  EEPROM.update(addr, EEPROM.read(addr) | (1 << (g % 8)));
}

void QuestionBank::resetHistory(uint16_t mask) {
  for (int c = 0; c < QCAT_COUNT; c++) {
    if (!(mask & (1 << c))) {
      continue;
    }
    int base = QB_EEPROM_BASE + c * QB_BYTES_PER_CAT;
    for (int b = 0; b < QB_BYTES_PER_CAT; b++) {
      EEPROM.update(base + b, 0);
    }
  }
}

int QuestionBank::countRemaining() {
  int n = 0;
  for (int c = 0; c < QCAT_COUNT; c++) {
    if (!(selection & (1 << c))) {
      continue;
    }
    for (int i = 0; i < counts[c]; i++) {
      if (!isAsked(c, i)) {
        n++;
      }
    }
  }
  return n;
}

// Lit l'entree idx de la categorie cat : saute idx '\n', puis lit la
// question jusqu'au '|' et la reponse jusqu'au '\n'.
bool QuestionBank::loadEntry(int cat, int idx) {
  uint32_t p = qcatDataFar(cat);
  char ch;
  while (idx > 0) {
    ch = (char)pgm_read_byte_far(p++);
    if (ch == 0) {
      return false;
    }
    if (ch == '\n') {
      idx--;
    }
  }

  curQ = "";
  while ((ch = (char)pgm_read_byte_far(p++)) != 0 && ch != '|' && ch != '\n') {
    curQ += ch;
  }
  curA = "";
  if (ch == '|') {
    while ((ch = (char)pgm_read_byte_far(p++)) != 0 && ch != '\n') {
      curA += ch;
    }
  }
  curCat = cat;
  return curQ.length() > 0;
}

bool QuestionBank::drawQuestion() {
  if (selection == 0) {
    return false;
  }

  int n = countRemaining();
  if (n == 0) {
    // Toute la selection a ete posee : on repart a zero (persistant).
    Serial.println(F("Banque epuisee pour cette selection : remise a zero."));
    resetHistory(selection);
    n = countRemaining();
    if (n == 0) {
      return false;      // selection vide (categories sans questions)
    }
  }

  int r = random(n);
  for (int c = 0; c < QCAT_COUNT; c++) {
    if (!(selection & (1 << c))) {
      continue;
    }
    for (int i = 0; i < counts[c]; i++) {
      if (isAsked(c, i)) {
        continue;
      }
      if (r == 0) {
        markAsked(c, i);
        return loadEntry(c, i);
      }
      r--;
    }
  }
  return false;   // ne devrait jamais arriver
}

String QuestionBank::questionText() {
  return curQ;
}

String QuestionBank::answerText() {
  return curA;
}

String QuestionBank::questionCategory() {
  return (curCat >= 0) ? categoryName(curCat) : "";
}
