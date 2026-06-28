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

#define INIT_FILE_COUNT 8
#define BUZZER_FILE_COUNT 30
#define GOOD_FILE_COUNT 17
#define BAD_FILE_COUNT 26


class Mp3 {
  public:
    Mp3();

    static Mp3& shared();

    void init(void);
    void playInit();
    void playBuzzer(int buzzerId);
    void playGoodAnswer();
    void playBadAnswer();
    void shuffleBuzzers();

    // Configuration des sons (assistant)
    int getSound(int buzzerId);             // index du son courant (0-based)
    void cycleSound(int buzzerId);          // passe au son suivant non verrouillé
    void lockSound(int buzzerId);           // verrouille le son du buzzer
    void ensureUnlockedSound(int buzzerId); // décale si le son est déjà verrouillé ailleurs
    void resetConfig();                     // déverrouille tous les buzzers

  private:

    bool isSoundLockedByOther(int sound, int buzzerId);
    bool locked[4] = { false, false, false, false };


    struct MP3Array
    {
      int *array = nullptr;
      int size = 0;
      int index = 0;
    };

    void initializeMP3Arrays(void);
    int getFileCount(int folderId);

    // Passe à true automatiquement quand aucun DFPlayer n'est détecté
    // (ex. simulation Wokwi) : les sons sont alors affichés sur le port série.
    bool simulation = false;

    MP3Array mp3Arrays[4];
    int buzzerSound[4];

    DFRobotDFPlayerMini mp3;
    SoftwareSerial softwareSerialMP3;
    Mp3(const Mp3&) = delete;
    Mp3& operator=(const Mp3&) = delete;
};

#endif
