#include "Mp3.h"
#include <EEPROM.h>

#define EEPROM_ADDR_VOLUME 0   // adresse EEPROM du volume sauvegardé

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

  // Recharge le volume sauvegardé (EEPROM). Une case non initialisée vaut
  // 255 -> on garde alors la valeur par défaut.
  int storedVolume = EEPROM.read(EEPROM_ADDR_VOLUME);
  if (storedVolume >= 0 && storedVolume <= 30) {
    volume = storedVolume;
  }

  pinMode(BUSY_PIN, INPUT);
  softwareSerialMP3.begin(9600);
  Serial.println(F("Initializing MP3Player ..."));

  mp3.begin(softwareSerialMP3, false);

  // Le DFPlayer met ~1,5 à 3 s après la mise sous tension pour lire la carte SD
  // et devenir capable de répondre aux requêtes. Sans cette pause, readState()
  // peut renvoyer -1 alors que le module est bien présent (faux négatif).
  delay(2000);

  // begin() renvoie toujours true quand l'ACK est désactivé : on ne peut pas
  // s'y fier. On interroge donc réellement le module (readState envoie une
  // requête et attend une réponse). Aucune réponse (DFPlayer absent /
  // simulation Wokwi) -> -1. On tente plusieurs fois, en laissant du temps
  // entre les essais, pour éviter un faux négatif sur le vrai matériel.
  bool detected = false;
  for (int i = 0; i < 5 && !detected; i++) {
    int state = mp3.readState();
    Serial.print(F("  readState() essai "));
    Serial.print(i + 1);
    Serial.print(F(" -> "));
    Serial.println(state);
    if (state != -1) {
      detected = true;
    } else {
      delay(500);
    }
  }

  if (!detected)
  {
    // Aucun DFPlayer détecté (carte SD absente ou simulation Wokwi).
    // On bascule en mode simulation au lieu de jouer dans le vide.
    simulation = true;
    Serial.println(F("DFPlayer introuvable -> mode SIMULATION (sons sur le port serie)."));
  }
  else
  {
    mp3.stop();
    setVolume(volume);
    Serial.println(F("MP3Player online."));
  }

  initializeMP3Arrays();
  shuffleBuzzers();
}

void Mp3::initializeMP3Arrays(void)
{
  for (int i = 0; i < 4; i++)
  {
    int folderId = i + 1;
    int count = getFileCount(folderId);   // valeur de repli (#define)

    // Sur le vrai matériel, on demande au DFPlayer le nombre réel de
    // fichiers présents dans le dossier de la carte SD.
    if (!simulation) {
      int detected = mp3.readFileCountsInFolder(folderId);
      if (detected > 0) {
        count = detected;
      } else {
        Serial.print(F("Dossier "));
        Serial.print(folderId);
        Serial.println(F(": comptage indisponible, repli sur la valeur par defaut."));
      }
    }

    mp3Arrays[i].size = count;

    Serial.print(F("Dossier "));
    Serial.print(folderId);
    Serial.print(F(": "));
    Serial.print(count);
    Serial.println(F(" fichiers"));
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
  const char* couleurs[4] = { "Rouge", "Bleu", "Jaune", "Vert" };
  for (int i = 0; i < 4; i++) {
    buzzerSound[i] = buzzerIds[i];
    Serial.print(F("Buzzer "));
    Serial.print(i);
    Serial.print(F(" ("));
    Serial.print(couleurs[i]);
    Serial.print(F(") -> son "));
    Serial.println(buzzerSound[i] + 1);
  }
}

int Mp3::getSound(int buzzerId) {
  return buzzerSound[buzzerId];
}

bool Mp3::isSoundLockedByOther(int sound, int buzzerId) {
  for (int j = 0; j < 4; j++) {
    if (j != buzzerId && locked[j] && buzzerSound[j] == sound) {
      return true;
    }
  }
  return false;
}

void Mp3::cycleSound(int buzzerId) {
  int poolSize = mp3Arrays[BUZZER_FOLDER - 1].size;
  if (poolSize <= 0) {
    return;
  }

  int candidate = buzzerSound[buzzerId];
  // Cherche le prochain son non verrouillé par un autre buzzer.
  for (int step = 0; step < poolSize; step++) {
    candidate = (candidate + 1) % poolSize;
    if (!isSoundLockedByOther(candidate, buzzerId)) {
      buzzerSound[buzzerId] = candidate;
      return;
    }
  }
  // Tous les autres sons sont verrouillés : on garde le son courant.
}

void Mp3::ensureUnlockedSound(int buzzerId) {
  // Si le son a été "volé" puis verrouillé par un autre buzzer, on en prend un libre.
  if (isSoundLockedByOther(buzzerSound[buzzerId], buzzerId)) {
    cycleSound(buzzerId);
  }
}

void Mp3::lockSound(int buzzerId) {
  locked[buzzerId] = true;
}

void Mp3::resetConfig() {
  for (int i = 0; i < 4; i++) {
    locked[i] = false;
  }
}

void Mp3::playInit() {
  int arraySize = mp3Arrays[INIT_FOLDER - 1].size;
  int fileNumber = random(arraySize) + 1;   // fichiers DFPlayer numérotés à partir de 1

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier INIT, fichier "));
    Serial.println(fileNumber);
    return;
  }

  mp3.playFolder(INIT_FOLDER, fileNumber);
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
  int fileNumber;
  do {
    fileNumber = random(arraySize) + 1;     // fichiers DFPlayer numérotés à partir de 1
  } while (arraySize > 1 && fileNumber == lastGood);  // pas 2x le même de suite
  lastGood = fileNumber;

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier GOOD, fichier "));
    Serial.println(fileNumber);
    return;
  }

  mp3.playFolder(GOOD_FOLDER, fileNumber);
}

void Mp3::playBadAnswer() {
  int arraySize = mp3Arrays[BAD_FOLDER - 1].size;
  int fileNumber;
  do {
    fileNumber = random(arraySize) + 1;
  } while (arraySize > 1 && fileNumber == lastBad);
  lastBad = fileNumber;

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier BAD, fichier "));
    Serial.println(fileNumber);
    return;
  }

  mp3.playFolder(BAD_FOLDER, fileNumber);
}

void Mp3::setVolume(int v) {
  if (v < 0) v = 0;
  if (v > 30) v = 30;
  volume = v;
  if (!simulation) {
    mp3.volume(volume);
  }
}

int Mp3::getVolume() {
  return volume;
}

void Mp3::volumeUp() {
  setVolume(volume + 1);
}

void Mp3::volumeDown() {
  setVolume(volume - 1);
}

void Mp3::saveVolume() {
  // update n'écrit que si la valeur a changé (ménage l'EEPROM).
  EEPROM.update(EEPROM_ADDR_VOLUME, (uint8_t)volume);
}
