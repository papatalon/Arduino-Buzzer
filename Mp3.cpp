#include "Mp3.h"

Mp3::Mp3(): softwareSerialMP3(RX_PIN, TX_PIN) {
}

// === Required for Singletons ===
// Define the single instance as a static member
Mp3& Mp3::shared() {
  static Mp3 instance;
  return instance;
}


void Mp3::init(void) {

  randomSeed(analogRead(0));

  pinMode(BUSY_PIN, INPUT);
  softwareSerialMP3.begin(9600);
  Serial.println(F("Initializing MP3Player ..."));

  if (!mp3.begin(softwareSerialMP3, false))
  {
    // Aucun DFPlayer détecté (carte SD absente ou simulation Wokwi).
    // On bascule en mode simulation au lieu de bloquer le programme.
    simulation = true;
    Serial.println(F("DFPlayer introuvable -> mode SIMULATION (sons sur le port serie)."));
  }
  else
  {
    mp3.stop();
    mp3.volume(10);
    Serial.println(F("MP3Player online."));
  }

  initializeMP3Arrays();
  shuffleBuzzers();
}

void Mp3::initializeMP3Arrays(void)
{
  // Init
  for (int i = 0; i < 4; i++)
  {
    mp3Arrays[i].size = getFileCount(i + 1);
    mp3Arrays[i].array = new int[mp3Arrays[i].size];
  }
}

int Mp3::getFileCount(int folderId)
{
  switch(folderId) {
    case INIT_FOLDER:
      return INIT_FILE_COUNT;
    case BUZZER_FOLDER:
      return BUZZER_FILE_COUNT;
    case GOOD_FOLDER:
      return GOOD_FILE_COUNT;
    case BAD_FOLDER:
      return BAD_FILE_COUNT;
    default:
      return 0;
  }
}

void Mp3::shuffleBuzzers() {
  int buzzerCount = mp3Arrays[BUZZER_FOLDER - 1].size;

  if (buzzerCount < 4) {
    Serial.println("Error: Not enough buzzers to shuffle.");
    return;
  }

  int buzzerIds[buzzerCount];

  // Initialize buzzer IDs
  for (int i = 0; i < buzzerCount; i++) {
    buzzerIds[i] = i;
  }

  // Shuffle IDs using Fisher-Yates algorithm
  for (int i = buzzerCount - 1; i > 0; i--) {
    int j = random(0, i + 1);
    int temp = buzzerIds[i];
    buzzerIds[i] = buzzerIds[j];
    buzzerIds[j] = temp;
  }

  // Assign the first 4 shuffled indices to buzzerSound
  for (int i = 0; i < 4; i++) {
    buzzerSound[i] = buzzerIds[i];
    Serial.println(buzzerSound[i]);
  }
}

void Mp3::playInit() {
  int arraySize = mp3Arrays[INIT_FOLDER - 1].size;
  int randomIndex = random(arraySize);

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier INIT, fichier "));
    Serial.println(randomIndex);
    return;
  }

  mp3.playFolder(INIT_FOLDER, randomIndex);
}

void Mp3::playBuzzer(int buzzerId) {

  int mp3Id = buzzerSound[buzzerId];

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier BUZZER, fichier "));
    Serial.println(mp3Id + 1);
    return;
  }

  mp3.playFolder(BUZZER_FOLDER, mp3Id + 1);
}

void Mp3::playGoodAnswer() {
  int arraySize = mp3Arrays[GOOD_FOLDER - 1].size;
  int randomIndex = random(arraySize);

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier GOOD, fichier "));
    Serial.println(randomIndex);
    return;
  }

  mp3.playFolder(GOOD_FOLDER, randomIndex);
}

void Mp3::playBadAnswer() {
  int arraySize = mp3Arrays[BAD_FOLDER - 1].size;
  int randomIndex = random(arraySize);

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier BAD, fichier "));
    Serial.println(randomIndex);
    return;
  }

  mp3.playFolder(BAD_FOLDER, randomIndex);
}
