# Buzzer

Système de **buzzers de jeu-concours** pour Arduino Mega : quatre buzzers colorés (rouge, bleu, jaune, vert), chacun avec sa LED et son bouton, pilotés depuis un clavier matriciel 4×4 et un écran LCD 20×4. Conçu pour animer des quiz : les joueurs appuient sur leur buzzer, le plus rapide est signalé (LED + son), et l'animateur valide une bonne ou mauvaise réponse au clavier.

Le projet est développé et simulé sur [Wokwi](https://wokwi.com/projects/420440216092145665).

## Matériel

| Composant | Détail |
|-----------|--------|
| Carte | Arduino Mega 2560 |
| Buzzers | 4 boutons poussoirs (rouge, bleu, jaune, vert) — `INPUT_PULLUP` sur pins 5, 7, 9, 11 |
| LEDs | 4 LEDs (une par buzzer) sur pins 6, 8, 10, 12, via résistances 220 Ω |
| Clavier | Membrane matricielle 4×4 — lignes sur pins 39/41/43/45, colonnes sur 47/49/51/53 |
| Écran | LCD 20×4 en I²C (adresse `0x27`, SDA/SCL sur pins 20/21) |
| Son | Module DFPlayer Mini (carte SD) — RX 15, TX 14, BUSY 2 |

Le câblage complet est décrit dans [diagram.json](diagram.json).

## Fonctionnement

L'application est une machine à états ([PhaseMode.h](PhaseMode.h)) pilotée dans [Buzzer.ino](Buzzer.ino) :

- **CONFIGURATION** — Menu principal sur l'écran LCD :
  - `A` : configurer les sons des buzzers (`BUZZER_CONFIG`)
  - `B` : attribuer des sons aléatoires (`SHUFFLE_BUZZER`)
  - `C` : changer de mode de jeu (Classique ⇄ Pénalité ; le mode est affiché)
  - `#` : démarrer la partie (`WAITING_BUZZER`) — **remet les scores à zéro**
- **BUZZER_CONFIG** — Assistant de configuration guidé (voir ci-dessous). `#` quitte à tout moment.
- **SHUFFLE_BUZZER** — Réattribue aléatoirement les sons à tous les buzzers, **après confirmation** (`#` = confirmer, `*` = annuler) pour éviter d'écraser une configuration faite via l'assistant.
- **WAITING_BUZZER** — En attente : le premier buzzer *présent et actif* pressé allume sa LED, joue son son et passe en `BUZZER_PRESSED`. `C` termine la partie (`END_GAME`).
- **BUZZER_PRESSED** — L'animateur tranche :
  - `A` : bonne réponse → **+1 point**, son de bonne réponse, clignotement, buzzers réactivés, puis écran des scores (`SHOW_SCORES`).
  - `D` : mauvaise réponse → son d'échec, le buzzer fautif est désactivé pour ce tour (**−1 point en mode Pénalité**), on reste sur la même question.
- **SHOW_SCORES** — Affiche les scores entre les questions (2 colonnes + titre), pendant 15 s ou jusqu'à `#`. `C` termine la partie.
- **END_GAME** — Scores finaux + couleur gagnante (+ son de victoire) ; `#` revient au menu.
- **RESET** — Une touche de reset (gérée par [AppKeypad](AppKeypad.h)) éteint les LEDs et revient au menu.

Les sons sont organisés en 4 dossiers sur la carte SD (voir [Mp3.h](Mp3.h)) : init, buzzers, bonnes réponses, mauvaises réponses.

### Score et modes de jeu

Chaque buzzer (couleur) a un score. Deux modes, choisis au menu via `C` :

- **Classique** : bonne réponse `+1`, mauvaise réponse sans effet sur le score.
- **Pénalité** : bonne réponse `+1`, mauvaise réponse `−1` (le score peut devenir négatif).

Les scores sont remis à zéro au lancement d'une partie (`#`). Entre chaque question (après une bonne réponse), l'écran des scores s'affiche 15 secondes (ou `#` pour enchaîner). En fin de partie (`C`), l'écran affiche les scores finaux et la couleur gagnante avec un son de victoire (en cas d'égalité, « EGALITE » est affiché sans son).

### Assistant de configuration des buzzers (`A` au menu)

L'assistant fait le tour des 4 buzzers (Rouge → Bleu → Jaune → Vert). Pour chacun :

1. L'écran affiche `<Couleur> : appuyez sur le buzzer`.
   - **Appui sur le buzzer** → son son est joué, on passe au choix.
   - **`*`** → buzzer déclaré *absent* (exclu du pool).
   - **`#`** → quitte l'assistant.
2. Après l'appui :
   - **`B`** → essaie un autre son (parcourt les sons disponibles, en sautant ceux déjà verrouillés ; peut « voler » le son d'un buzzer pas encore configuré).
   - **`A`** → valide et **verrouille** le son de ce buzzer.
   - **`*`** → buzzer déclaré absent.

La configuration est **optionnelle** : si on lance directement la partie (`#`), on joue avec les **4 buzzers et des sons aléatoires** (état par défaut). Elle n'est pas sauvegardée entre deux mises sous tension.

## Structure du code

| Fichier | Rôle |
|---------|------|
| [Buzzer.ino](Buzzer.ino) | Point d'entrée, boucle principale et machine à états |
| [PhaseMode.h](PhaseMode.h) | Énumération des états de l'application |
| [Configuration.cpp](Configuration.cpp) / [.h](Configuration.h) | Menus et écrans de configuration |
| [Buzzer.cpp](Buzzer.cpp) / [.h](Buzzer.h) | Gestion des buzzers, LEDs et logique de jeu (singleton) |
| [AppKeypad.h](AppKeypad.h) | Lecture du clavier matriciel et détection du reset (singleton) |
| [LcdDisplay.cpp](LcdDisplay.cpp) / [.h](LcdDisplay.h) | Affichage LCD 20×4 avec défilement de texte et gestion des accents |
| [Mp3.cpp](Mp3.cpp) / [.h](Mp3.h) | Pilotage du DFPlayer Mini + bascule simulation (singleton) |
| [OledDisplay.cpp](OledDisplay.cpp) / [.h](OledDisplay.h) | Variante d'affichage OLED (non utilisée actuellement) |

## Son : matériel réel et simulation

Les sons sont organisés sur la carte SD du DFPlayer Mini en **4 dossiers** : `01` (init), `02` (buzzers), `03` (bonnes réponses), `04` (mauvaises réponses).

Le module [Mp3](Mp3.cpp) **détecte automatiquement** la présence du DFPlayer au démarrage (`mp3.begin`) :

- **DFPlayer détecté** (Arduino réel) → les sons sont joués normalement.
- **DFPlayer absent** (simulation Wokwi, ou carte SD manquante) → bascule automatique en **mode simulation** : au lieu de bloquer, le programme affiche sur le moniteur série le dossier et le fichier qui *auraient* été joués (`[SIM] Lecture dossier ...`).

Aucun réglage à modifier entre la simulation et le téléversement réel : **le même code fonctionne dans les deux cas**.

## Dépendances

Bibliothèques Arduino requises (voir [libraries.txt](libraries.txt)) :

- `Keypad`
- `LiquidCrystal I2C`
- `DFRobotDFPlayerMini` *(pilotage du module son ; `SoftwareSerial` est fourni par le core AVR)*
- `Adafruit SSD1306` *(pour la variante OLED)*
- `Adafruit GFX Library` *(pour la variante OLED)*

## Compilation et simulation

### Avec Wokwi

1. Ouvrir le projet sur [Wokwi](https://wokwi.com/projects/420440216092145665), ou
2. Utiliser l'extension Wokwi pour VS Code : compiler le sketch (génère `build/Buzzer.ino.hex` et `.elf`), puis lancer la simulation via [wokwi.toml](wokwi.toml).

### Avec arduino-cli

```sh
arduino-cli compile --fqbn arduino:avr:mega --output-dir build .
arduino-cli upload  --fqbn arduino:avr:mega -p <PORT> .
```

En simulation Wokwi (DFPlayer absent), le moniteur série (9600 bauds) affiche les sons « joués » sous la forme `[SIM] Lecture dossier ...`. Sur l'Arduino réel équipé du DFPlayer et de la carte SD, les sons sont diffusés réellement — sans rien changer au code.

## Auteur

Marc Lindsay
