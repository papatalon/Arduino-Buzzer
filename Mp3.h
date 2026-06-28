#ifndef MP3_H
#define MP3_H

#include <Arduino.h>

#define START_INIT 1
#define END_INIT 2
#define START_GOOD 3
#define END_GOOD 25
#define START_BAD 26
#define END_BAD 50
#define START_BUZZER 51
#define END_BUZZER 65

class Mp3 {
  public:
    Mp3();

    static Mp3& shared();
    
    void init(void);
    void playBuzzer(int mp3Id);
    void playGoodAnswer();
    void playBadAnswer();
    void shuffleBuzzers();

    int getBuzzerSoundCount();


  private:  
    Mp3(const Mp3&) = delete;
    Mp3& operator=(const Mp3&) = delete;
    int buzzerIds[END_BUZZER - START_BUZZER + 1];
};

#endif