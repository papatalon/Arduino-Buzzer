#ifndef LCDDISPLAY_H
#define LCDDISPLAY_H

#include <Arduino.h>
#include <LiquidCrystal_I2C.h>

#define SCROLL_DELAY 350
#define PADDING 3

// Largeur du LCD, et longueur maximale d'un message memorise.
//
// 20 colonnes s'affichent, mais un message peut etre plus long : au-dela il
// defile. Buzzer::wrapText depose sur sa DERNIERE ligne tout le reste du
// texte, sans le couper — une question de 77 caracteres peut donc y arriver
// en grande partie. 80 couvre la plus longue question de la banque meme si
// elle atterrissait entiere sur une seule ligne.
#define LCD_COLS 20
#define LCD_MSG_MAX 80

class LcdDisplay {
  public:
    LcdDisplay() : lcd(0x27, 20, 4) {};
    static LcdDisplay& shared();
    bool init();

    // Deux surcharges plutot qu'un String par valeur.
    //
    // Celle qui prend un F("...") copie directement depuis la flash vers le
    // tampon : aucun String n'est construit, donc aucune allocation. C'est
    // le cas de la grande majorite des appels.
    //
    // Celle qui prend un String& sert aux textes assembles a l'execution
    // (scores, noms de couleur, questions). Elle prend une reference, pas
    // une copie : l'ancienne signature par valeur dupliquait chaque message.
    void setText(const __FlashStringHelper* text, int line);
    void setText(const String& text, int line);

    void updateScrolling();
    void clear();

    // Égaliseur graphique (animation de démarrage) : charge 8 caractères
    // personnalisés (barres de 1 à 8 pixels) puis dessine 20 colonnes sur
    // les 4 lignes. heights[i] = hauteur de la colonne i, de 0 à 32 pixels.
    void initBarChars();
    void drawEqualizer(const uint8_t heights[20]);

    // Fige l'écran sur un ecran "controle par l'app" (voir BleLink::
    // appInControl) : tant que actif, setText()/updateScrolling() sont
    // ignores (le jeu reel continue de tourner, seul l'affichage est gele).
    // A appeler une fois par tour de loop().
    void setControlOverride(bool active);

    // Affiche un repere persistant en haut a droite quand le lecteur audio
    // n'a pas ete detecte au demarrage (mode simulation, voir
    // Mp3::isSimulation) : sans ca, "aucun son" est indistinguable d'un
    // simple volume a zero quand on est devant le buzzer. Ne dessine rien
    // en fonctionnement normal, donc aucun risque d'ecraser du contenu.
    void setAudioWarning(bool active);

  private:
    LiquidCrystal_I2C lcd;

    // Tampons fixes plutot que des String : l'affichage ne touche plus au
    // tas. updateScrolling() tournait trois fois par seconde en allouant
    // une copie, une concatenation et deux sous-chaines par ligne qui
    // defile — de quoi fragmenter durablement un tas de quelques kilo-octets.
    char messages[4][LCD_MSG_MAX + 1] = { "", "", "", "" };
    int offsets[4] = { 0, 0, 0, 0 };
    bool _controlOverrideActive = false;
    bool _audioWarning = false;
    void displayText(const char* text, int line);
    unsigned long previousMillis = 0;    // Last time of update

    // Remplace sur place les sequences UTF-8 accentuees par leur equivalent
    // ASCII. Le LCD ne sait pas les afficher, et la convention du projet est
    // d'ecrire les messages ecran sans accents : c'est donc un filet de
    // securite pour le texte assemble a l'execution, pas un passage oblige.
    static void removeAccentsInPlace(char* s);

    // Recopie vers messages[line], tronque a LCD_MSG_MAX, retire les
    // accents, remet le defilement a zero puis peint si l'ecran n'est pas
    // gele. Les deux surcharges publiques n'en different que par la source.
    void storeAndPaint(int line);
    LcdDisplay(const LcdDisplay&) = delete;
    LcdDisplay& operator=(const LcdDisplay&) = delete;
};

#endif