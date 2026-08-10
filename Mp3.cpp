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


void Mp3::waitAnimated(unsigned long ms, void (*onTick)()) {
  unsigned long start = millis();
  while (millis() - start < ms) {
    if (onTick) {
      onTick();
    }
    delay(10);
  }
}

void Mp3::init(void (*onTick)()) {

  // Note : randomSeed() est fait dans setup(), avant le tirage du message de
  // demarrage — surtout ne pas re-amorcer ici (on repartirait a zero).

  // Recharge le volume sauvegardé (EEPROM). Une case non initialisée vaut
  // 255 -> on garde alors la valeur par défaut.
  int storedVolume = EEPROM.read(EEPROM_ADDR_VOLUME);
  if (storedVolume >= 0 && storedVolume <= 30) {
    volume = storedVolume;
  }

  // BUSY est HIGH au repos et LOW quand le module joue. On active le pull-up
  // interne : ainsi, sans module (simulation Wokwi ou broche non câblée), la
  // lecture donne HIGH -> mode simulation.
  pinMode(BUSY_PIN, INPUT_PULLUP);
  softwareSerialMP3.begin(9600);
  Serial.println(F("Initializing MP3Player ..."));

  mp3.begin(softwareSerialMP3, false);

  // Le DFPlayer met ~1,5 à 3 s après la mise sous tension pour lire la carte SD
  // et devenir capable d'accepter des commandes. On anime pendant l'attente.
  waitAnimated(2000, onTick);

  // Détection via la broche BUSY. De nombreux modules DFPlayer « clones »
  // jouent parfaitement mais ne répondent à AUCUNE requête série (readState,
  // readFileCountsInFolder -> toujours -1) : impossible de les détecter en les
  // interrogeant. On lance donc une courte lecture test et on observe BUSY,
  // qui passe à LOW dès que le module joue. Aucun module -> BUSY reste HIGH.
  setVolume(volume);
  mp3.playFolder(INIT_FOLDER, 1);   // le fichier 1 du dossier init existe toujours

  bool detected = false;
  for (int i = 0; i < 10 && !detected; i++) {
    waitAnimated(100, onTick);
    if (digitalRead(BUSY_PIN) == LOW) {
      detected = true;
    }
  }
  mp3.stop();   // on coupe la lecture test ; l'intro sera jouée par playInit()

  if (!detected)
  {
    // Aucun module détecté (BUSY jamais actif) : simulation Wokwi, carte SD
    // absente, ou broche BUSY non câblée. On affiche les sons sur le série.
    simulation = true;
    Serial.println(F("DFPlayer introuvable (BUSY inactif) -> mode SIMULATION."));
  }
  else
  {
    Serial.println(F("MP3Player online (detecte via BUSY)."));
  }

  initializeMP3Arrays();
  shuffleBuzzers();
}

void Mp3::initializeMP3Arrays(void)
{
  for (int i = 0; i < FOLDER_COUNT; i++)
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
    case WAITING_FOLDER:
      return WAITING_FILE_COUNT;
    case SPIN_FOLDER:
      return SPIN_FILE_COUNT;
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
  cycleSoundBy(buzzerId, +1);
}

void Mp3::cyclePrevSound(int buzzerId) {
  cycleSoundBy(buzzerId, -1);
}

void Mp3::cycleSoundBy(int buzzerId, int direction) {
  int poolSize = mp3Arrays[BUZZER_FOLDER - 1].size;
  if (poolSize <= 0) {
    return;
  }

  int candidate = buzzerSound[buzzerId];
  // Cherche le son suivant/précédent non verrouillé par un autre buzzer.
  for (int step = 0; step < poolSize; step++) {
    candidate = (candidate + direction + poolSize) % poolSize;
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

bool Mp3::isBusy() {
  // BUSY est LOW pendant la lecture, HIGH au repos. Sans module (simulation),
  // la broche n'est pas pilotée : on ne peut pas savoir -> on renvoie faux.
  if (simulation) {
    return false;
  }
  return digitalRead(BUSY_PIN) == LOW;
}

bool Mp3::isSimulation() {
  return simulation;
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

// Comme playBuzzer(), mais pour un son designe directement plutot que via le
// buzzer qui le porte (leurres du jeu Ne buzze pas).
void Mp3::playBuzzerSound(int soundIndex) {
  int poolSize = mp3Arrays[BUZZER_FOLDER - 1].size;
  if (soundIndex < 0 || soundIndex >= poolSize) {
    return;
  }

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier BUZZER, fichier "));
    Serial.println(soundIndex + 1);
    return;
  }

  mp3.playFolder(BUZZER_FOLDER, soundIndex + 1);
}

int Mp3::buzzerSoundPoolSize() {
  return mp3Arrays[BUZZER_FOLDER - 1].size;
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

// Son d'ambiance lancé par l'animateur quand la réponse tarde à venir.
void Mp3::playWaiting() {
  int arraySize = mp3Arrays[WAITING_FOLDER - 1].size;
  if (arraySize <= 0) {
    return;
  }

  int fileNumber;
  do {
    fileNumber = random(arraySize) + 1;
  } while (arraySize > 1 && fileNumber == lastWaiting);   // pas 2x le même de suite
  lastWaiting = fileNumber;

  if (simulation) {
    Serial.print(F("[SIM] Lecture dossier WAITING, fichier "));
    Serial.println(fileNumber);
    return;
  }

  mp3.playFolder(WAITING_FOLDER, fileNumber);
}

// Un seul fichier pour l'instant : pas de tirage, on rejoue toujours le même.
void Mp3::playSpin() {
  if (simulation) {
    Serial.println(F("[SIM] Lecture dossier SPIN, fichier 1"));
    return;
  }

  mp3.playFolder(SPIN_FOLDER, 1);
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
