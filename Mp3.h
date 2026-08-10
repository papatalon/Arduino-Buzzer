#ifndef MP3_H
#define MP3_H

#include "SoftwareSerial.h"
#include "DFRobotDFPlayerMini.h"
#include <Arduino.h>

#define RX_PIN 15
#define TX_PIN 14
#define BUSY_PIN 2

#define INIT_FOLDER 1
#define BUZZER_FOLDER 2
#define GOOD_FOLDER 3
#define BAD_FOLDER 4
#define WAITING_FOLDER 5
#define SPIN_FOLDER 6
#define FOLDER_COUNT 6

#define INIT_FILE_COUNT 8
#define BUZZER_FILE_COUNT 30
#define GOOD_FILE_COUNT 17
#define BAD_FILE_COUNT 26
#define WAITING_FILE_COUNT 6
#define SPIN_FILE_COUNT 1


class Mp3 {
  public:
    Mp3();

    static Mp3& shared();

    // onTick (optionnel) est appelé régulièrement pendant les attentes de
    // démarrage du DFPlayer : permet d'animer l'écran / les LED sans figer.
    void init(void (*onTick)() = nullptr);
    void playInit();

    // Vrai tant qu'une chanson est en cours de lecture (broche BUSY LOW).
    // Toujours faux en simulation (aucun module -> BUSY indisponible).
    bool isBusy();
    bool isSimulation();

    void playBuzzer(int buzzerId);

    // Joue un son quelconque du dossier des buzzers (index 0-based), même s'il
    // n'est attribué à aucun buzzer : sert aux « leurres » du jeu Ne buzze pas.
    void playBuzzerSound(int soundIndex);
    int buzzerSoundPoolSize();              // nombre de sons disponibles
    void playGoodAnswer();
    void playBadAnswer();
    void playWaiting();     // son d'ambiance quand la réponse se fait attendre
    void playSpin();        // son du tirage au sort (dossier 06, mode Vol)
    void shuffleBuzzers();

    // Volume (0..30)
    void setVolume(int v);
    int getVolume();
    void volumeUp();
    void volumeDown();
    void saveVolume();      // sauvegarde le volume en EEPROM (persistant)

    // Configuration des sons (assistant)
    int getSound(int buzzerId);             // index du son courant (0-based)
    void cycleSound(int buzzerId);          // passe au son suivant non verrouillé
    void cyclePrevSound(int buzzerId);      // passe au son précédent non verrouillé
    void lockSound(int buzzerId);           // verrouille le son du buzzer
    void ensureUnlockedSound(int buzzerId); // décale si le son est déjà verrouillé ailleurs
    void resetConfig();                     // déverrouille tous les buzzers

  private:

    bool isSoundLockedByOther(int sound, int buzzerId);
    void cycleSoundBy(int buzzerId, int direction);  // +1 suivant, -1 précédent
    bool locked[4] = { false, false, false, false };

    int volume = 10;        // volume courant (0..30)
    int lastGood = -1;      // dernier fichier GOOD joué (anti-répétition)
    int lastBad = -1;       // dernier fichier BAD joué (anti-répétition)
    int lastWaiting = -1;   // dernier fichier WAITING joué (anti-répétition)


    struct MP3Array
    {
      int size = 0;
    };

    void initializeMP3Arrays(void);
    int getFileCount(int folderId);

    // Attend ms millisecondes en appelant onTick périodiquement (animation).
    void waitAnimated(unsigned long ms, void (*onTick)());

    // Passe à true automatiquement quand aucun DFPlayer n'est détecté
    // (ex. simulation Wokwi) : les sons sont alors affichés sur le port série.
    bool simulation = false;

    MP3Array mp3Arrays[FOLDER_COUNT];
    int buzzerSound[4];

    DFRobotDFPlayerMini mp3;
    SoftwareSerial softwareSerialMP3;
    Mp3(const Mp3&) = delete;
    Mp3& operator=(const Mp3&) = delete;
};

#endif
