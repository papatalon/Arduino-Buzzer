#ifndef MP3_H
#define MP3_H

#include "SoftwareSerial.h"
#include "DFRobotDFPlayerMini.h"
#include <Arduino.h>
#include "BleLink.h"

#define RX_PIN 15
#define TX_PIN 14
#define BUSY_PIN 2

#define INIT_FOLDER 1
#define BUZZER_FOLDER 2
// Duree maxi d'un son de buzzer. Les fichiers de la carte SD vont de la demi
// seconde a une dizaine de secondes ; laisses entiers, les plus longs
// couvrent la question suivante. L'application applique la meme limite a sa
// propre bibliotheque (voir SoundEngine).
#define BUZZ_MAX_MS 2000
#define GOOD_FOLDER 3
#define BAD_FOLDER 4
#define WAITING_FOLDER 5
#define SPIN_FOLDER 6
#define FOLDER_COUNT 6

#define INIT_FILE_COUNT 17
#define BUZZER_FILE_COUNT 31
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

    // Vrai tant qu'une chanson est en cours de lecture. Lit la broche BUSY
    // en temps normal ; en mode delegue c'est l'app qui rapporte son etat
    // de lecture (voir setAppBusy), sinon le chenillard de l'intro n'aurait
    // plus aucun repere pour se caler sur la musique.
    // Toujours faux en simulation (aucun module -> BUSY indisponible).
    bool isBusy();

    // A appeler a chaque tour de boucle : coupe un son de buzzer qui depasse
    // BUZZ_MAX_MS. Certains fichiers de la carte durent plusieurs secondes,
    // ce qui couvre la question suivante et retarde toute la soiree.
    void tick();

    // Coupe net ce qui joue. Sert quand l'application ecourte l'ouverture :
    // le chenillard s'arrete, la musique doit s'arreter avec lui.
    void stopNow();
    bool isSimulation();

    // Vrai quand l'app joue les sons a notre place : le Mega ne gere plus
    // que les lumieres et se contente d'annoncer les evenements sonores.
    bool isDelegated();

    void playBuzzer(int buzzerId);

    // Joue un son quelconque du dossier des buzzers (index 0-based), même s'il
    // n'est attribué à aucun buzzer : sert aux « leurres » du jeu Ne buzze pas.
    void playBuzzerSound(int soundIndex);

    // Variantes semantiques, necessaires parce qu'en mode delegue l'app
    // detient les assignations : elle seule sait quels sons sont libres.
    void playRandomBuzzerSound();     // Duel : signal de depart, son quelconque
    void playDecoySound(int soundIndex);  // Ne buzze pas : leurre
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

    // Annonce les 4 assignations d'un coup. Necessaire a la (re)connexion :
    // CFG_SOUND n'etait emis que par lockSound(), donc une app qui se
    // connectait sans passer par l'assistant n'apprenait jamais quel son
    // porte chaque buzzer.
    void sendAllSoundAssignments();

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

    // Telemetrie app compagnon (BLE) : un seul point de construction du
    // message SOUND, appele par chaque play*() juste avant (ou a la place
    // de) la lecture DFPlayer.
    void sendSoundEvent(int folder, int file);

    // Annonce l'evenement sonore a l'app et renvoie true si c'est elle qui
    // joue (l'appelant doit alors s'arreter la, sans commander le
    // DFPlayer). Un seul point de decision, plutot que la meme condition
    // repetee dans chaque play*().
    bool delegateToApp(const String& event);

    // Attend ms millisecondes en appelant onTick périodiquement (animation).
    void waitAnimated(unsigned long ms, void (*onTick)());

    // Passe à true automatiquement quand aucun DFPlayer n'est détecté
    // (ex. simulation Wokwi) : les sons sont alors affichés sur le port série.
    bool simulation = false;

    MP3Array mp3Arrays[FOLDER_COUNT];
    int buzzerSound[4];

    DFRobotDFPlayerMini mp3;

    // Depart du son de buzzer en cours, ou 0 si aucun n'est a surveiller.
    unsigned long buzzStartedAt = 0;
    SoftwareSerial softwareSerialMP3;
    BleLink& ble = BleLink::shared();
    Mp3(const Mp3&) = delete;
    Mp3& operator=(const Mp3&) = delete;
};

#endif
