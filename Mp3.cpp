#include "Mp3.h"

Mp3::Mp3() {}

// === Required for Singletons ===
// Define the single instance as a static member
Mp3& Mp3::shared() {
  static Mp3 instance;
  return instance;
}


void Mp3::init(void) {
  randomSeed(analogRead(0));
  Mp3::shuffleBuzzers();
}

void Mp3::shuffleBuzzers() {
  int buzzerCount = END_BUZZER - START_BUZZER + 1;

  //Init buzzer ids
  for (int i = 0; i < buzzerCount; i++) {
    buzzerIds[i] = START_BUZZER + i;
  }


  //Shuffle ids
  for (int i = buzzerCount - 1; i > 0; i--) {
    int j = random(0, i + 1); // Get a random index from 0 to i
    // Swap numbers[i] with numbers[j]
    int temp = buzzerIds[i];
    buzzerIds[i] = buzzerIds[j];
    buzzerIds[j] = temp;
  }
}
  
void Mp3::playBuzzer(int mp3Index) {

  int mp3Id = buzzerIds[mp3Index];

  Serial.print("Playing mp3 id ");
  Serial.println(mp3Id);
}

void Mp3::playGoodAnswer() {
  int rand = random(START_GOOD, END_GOOD + 1);

  Serial.print("Playing mp3 id ");
  Serial.println(rand);
}

void Mp3::playBadAnswer() {
  int rand = random(START_BAD, END_BAD + 1);

  Serial.print("Playing mp3 id ");
  Serial.println(rand);
}

int Mp3::getBuzzerSoundCount() {
  return END_BUZZER - START_BUZZER + 1;
}