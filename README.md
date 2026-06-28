# Buzzer

Système de **buzzers de jeu-concours** pour Arduino Mega : quatre buzzers colorés (rouge, bleu, jaune, vert), chacun avec sa LED et son bouton, pilotés depuis un clavier matriciel 4×4 et un écran LCD 20×4. Conçu pour animer des quiz : les joueurs appuient sur leur buzzer, le plus rapide est signalé (LED + son), et l'animateur valide une bonne ou mauvaise réponse au clavier.

Le projet est développé et simulé sur [Wokwi](https://wokwi.com/projects/420440216092145665).

## Matériel

| Composant | Détail |
|-----------|--------|
| Carte | Arduino Mega 2560 |
| Buzzers | 4 boutons poussoirs (rouge, bleu, jaune, vert) — `INPUT_PULLUP` sur pins 6, 8, 10, 12 |
| LEDs | 4 LEDs (une par buzzer) sur pins 7, 9, 11, 13, via résistances 220 Ω |
| Clavier | Membrane matricielle 4×4 — lignes sur pins 39/41/43/45, colonnes sur 47/49/51/53 |
| Écran | LCD 20×4 en I²C (adresse `0x27`, SDA/SCL sur pins 20/21) |
| Son | Module MP3 (simulé via le moniteur série pour l'instant) |

Le câblage complet est décrit dans [diagram.json](diagram.json).

## Fonctionnement

L'application est une machine à états ([PhaseMode.h](PhaseMode.h)) pilotée dans [Buzzer.ino](Buzzer.ino) :

- **CONFIGURATION** — Menu principal sur l'écran LCD :
  - `A` : configurer les sons des buzzers (`BUZZER_CONFIG`)
  - `B` : attribuer des sons aléatoires (`SHUFFLE_BUZZER`)
  - `#` : démarrer la partie (`WAITING_BUZZER`)
- **BUZZER_CONFIG** — Appuyer sur un buzzer pour lui assigner un son ; `#` retourne au menu. Les buzzers non configurés reçoivent un son aléatoire unique à la fin.
- **SHUFFLE_BUZZER** — Réattribue aléatoirement les sons à tous les buzzers.
- **WAITING_BUZZER** — En attente : le premier buzzer actif pressé allume sa LED, joue son son et passe en `BUZZER_PRESSED`.
- **BUZZER_PRESSED** — L'animateur tranche :
  - `A` : bonne réponse → son de bonne réponse, clignotement, tous les buzzers réactivés, retour en attente.
  - `D` : mauvaise réponse → son d'échec, le buzzer fautif est désactivé pour ce tour, retour en attente.
- **RESET** — Une touche de reset (gérée par [AppKeypad](AppKeypad.h)) éteint les LEDs et revient au menu.

Les sons sont répartis par plages d'identifiants dans [Mp3.h](Mp3.h) (init, bonnes réponses, mauvaises réponses, buzzers).

## Structure du code

| Fichier | Rôle |
|---------|------|
| [Buzzer.ino](Buzzer.ino) | Point d'entrée, boucle principale et machine à états |
| [PhaseMode.h](PhaseMode.h) | Énumération des états de l'application |
| [Configuration.cpp](Configuration.cpp) / [.h](Configuration.h) | Menus et écrans de configuration |
| [Buzzer.cpp](Buzzer.cpp) / [.h](Buzzer.h) | Gestion des buzzers, LEDs et logique de jeu (singleton) |
| [AppKeypad.h](AppKeypad.h) | Lecture du clavier matriciel et détection du reset (singleton) |
| [LcdDisplay.cpp](LcdDisplay.cpp) / [.h](LcdDisplay.h) | Affichage LCD 20×4 avec défilement de texte et gestion des accents |
| [Mp3.cpp](Mp3.cpp) / [.h](Mp3.h) | Sélection et lecture des sons (singleton) |
| [OledDisplay.cpp](OledDisplay.cpp) / [.h](OledDisplay.h) | Variante d'affichage OLED (non utilisée actuellement) |

## Dépendances

Bibliothèques Arduino requises (voir [libraries.txt](libraries.txt)) :

- `Keypad`
- `LiquidCrystal I2C`
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

Le moniteur série (9600 bauds) affiche les identifiants de sons « joués » tant que le module MP3 réel n'est pas branché.

## Auteur

Marc Lindsay
