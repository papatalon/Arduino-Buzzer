# Buzzer

Système de **buzzers de jeu-concours** pour Arduino Mega : quatre buzzers colorés (rouge, bleu, jaune, vert), chacun avec sa LED et son bouton, pilotés depuis un clavier matriciel 4×4 et un écran LCD 20×4. Conçu pour animer des quiz : les joueurs appuient sur leur buzzer, le plus rapide est signalé (LED + son), et l'animateur valide une bonne ou mauvaise réponse au clavier. Plusieurs **jeux** sont disponibles (quiz Classique, quiz Pénalité, et **Simon** collaboratif), choisis dans le sous-menu `C`.

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
  - `C` : **choisir le jeu** (`GAME_CHOICE`) — le jeu sélectionné est affiché sur la 1re ligne
  - `D` : régler le **volume** (`VOLUME`)
  - `#` : démarrer la partie (`INTRO`) — **remet les scores à zéro** et joue un son de lancement (dossier `01`)
- **GAME_CHOICE** — Liste déroulante des **jeux** (jusqu'à 3 lignes visibles ; la fenêtre défile automatiquement si la liste s'allonge — voir `GAME_LIST` dans [Configuration.cpp](Configuration.cpp)) : `2` fait monter le curseur `>` (haut du pavé numérique), `8` le fait descendre, `#` confirme la ligne en surbrillance, `*` revient sans rien changer. Confirmer applique le jeu ; les jeux à configurer (`Chrono classique`, `Chrono penalite`) enchaînent en plus sur leur écran de réglage (`CHRONO`) avant de revenir au menu.
- **CHRONO** — Réglage des deux durées du chrono de buzz, en deux étapes (comme la liste des jeux : un seul réglage à la fois, curseur `>`) : `2`/`8` font monter/descendre la valeur affichée (comme sur l'écran Volume), `#` la valide et passe à la suivante (1re réponse, puis autres réponses) ; à la 2e validation, les durées sont sauvegardées et on revient à la liste des jeux. `*` interrompt le réglage.
- **INTRO** — Lancement festif : un **chenillard** allume les LED l'une après l'autre (~4 s) pendant la musique de démarrage, puis passe à la 1re question (ou à la 1re séquence en Simon). N'importe quelle touche passe l'intro.
- **VOLUME** — Réglage du volume du DFPlayer (0–30) : `2` = +, `8` = −, `#` = sauvegarder et retour. Appuyer sur un **buzzer** joue son son au volume courant (aperçu).
- **BUZZER_CONFIG** — Assistant de configuration guidé (voir ci-dessous). `#` quitte à tout moment.
- **SHUFFLE_BUZZER** — Réattribue aléatoirement les sons à tous les buzzers, **après confirmation** (`#` = confirmer, `*` = annuler) pour éviter d'écraser une configuration faite via l'assistant.
- **WAITING_BUZZER** — En attente (le n° de **question** est affiché) : le premier buzzer *présent et actif* pressé allume sa LED, joue son son et passe en `BUZZER_PRESSED`. La détection est sur **front d'appui** (un bouton maintenu ne se redéclenche pas tout seul). `C` demande à terminer la partie, `B` corrige la dernière décision, `0` **passe la question** (personne ne marque), `#` lance un **son d'ambiance**, `D` donne le **top du chrono** (voir ci-dessous).
- **BUZZER_PRESSED** — L'animateur tranche :
  - `A` : bonne réponse → **+1 point**, son de bonne réponse, puis écran des scores (`SHOW_SCORES`) avec clignotement bref de la LED du gagnant.
  - `D` : mauvaise réponse → son d'échec, le buzzer fautif est désactivé pour ce tour (**−1 point en mode Pénalité**), on reste sur la même question.
  - `0` : **passer la question** (personne ne marque, on passe à l'écran des scores).
- **SHOW_SCORES** — Affiche les scores entre les questions (2 colonnes + titre), pendant 15 s ou jusqu'à `#`. `C` demande à terminer la partie, `B` corrige la dernière décision (proposé seulement s'il y a une décision à corriger — pas après une question passée).
- **END_CONFIRM** — Confirmation avant de terminer la partie (`#` = oui, `*` = non / continuer).
- **END_GAME** — Scores finaux. Si un gagnant unique : couleur gagnante + son de victoire, `#` revient au menu. Si **égalité** au sommet : `#` lance un **bris d'égalité**, `*` accepte l'égalité (retour au menu).
- **SIMON_SHOW / SIMON_PLAY / SIMON_OVER** — Les trois états du jeu Simon (voir plus bas).
- **RESET** — Une touche de reset (gérée par [AppKeypad](AppKeypad.h)) éteint les LEDs et revient au menu.

Les sons sont organisés en 5 dossiers sur la carte SD (voir [Mp3.h](Mp3.h)) : init, buzzers, bonnes réponses, mauvaises réponses, ambiance. Le **nombre de fichiers par dossier est détecté automatiquement** au démarrage en interrogeant le DFPlayer (`readFileCountsInFolder`) ; les constantes `*_FILE_COUNT` de [Mp3.h](Mp3.h) ne servent que de **valeurs de repli** (simulation Wokwi, ou si la détection échoue). Les comptes sont affichés sur le port série au démarrage.

Au **démarrage**, l'initialisation du DFPlayer immobilise la carte ~3 s (le module a besoin de ce délai pour lire la carte SD). Pendant cette attente, un **égaliseur audio animé** occupe tout l'écran et les LED des buzzers défilent en chenillard ; le menu ne s'affiche qu'une fois le module prêt — donc dès qu'il apparaît, le clavier répond. Un **son d'intro** (dossier `01`) est ensuite joué.

Le **volume** (0–30) se règle depuis le menu (`D`) et est **sauvegardé en EEPROM** (comme les durées du chrono) : il est conservé après extinction et rechargé au démarrage. Pour les sons de bonne/mauvaise réponse et d'ambiance, le même fichier n'est jamais **rejoué deux fois de suite** (anti-répétition).

### Son d'ambiance (`#` pendant une question)

Quand la réponse se fait attendre, l'animateur peut appuyer sur `#` depuis l'écran d'attente pour lancer un **son d'ambiance** tiré au hasard du dossier `05` (jingle d'attente, tic-tac…). La question **continue** : les buzzers restent armés, et un joueur qui buzze **interrompt** le son d'ambiance pour jouer le sien. La touche peut être pressée plusieurs fois, et fonctionne aussi pendant un bris d'égalité.

## Les jeux (`C` au menu)

La touche `C` du menu ouvre le **sous-menu des jeux**. Le jeu sélectionné s'affiche sur la 1re ligne du menu et se lance avec `#` :

| Jeu | Principe |
|-----|----------|
| **Classique** | Quiz : bonne réponse `+1`, mauvaise sans effet |
| **Pénalité** | Quiz : bonne réponse `+1`, mauvaise `−1` |
| **Chrono classique** | Quiz classique + **chrono de buzz** (configuré à la sélection) |
| **Chrono pénalité** | Quiz pénalité + **chrono de buzz** (configuré à la sélection) |
| **Simon** | Jeu de mémoire **collaboratif**, obligatoirement à 4 |
| **Simon inverse** | Comme Simon, mais la séquence se répète **à l'envers** |

### Chrono de buzz (jeux « Chrono ... »)

Le chrono limite le **temps pour buzzer**, pas le temps de répondre : une fois qu'un joueur a buzzé, c'est l'animateur qui décide quand la réponse est finie, sans compteur qui le contredise. Il n'existe que dans les jeux **Chrono classique** et **Chrono pénalité** ; sélectionner l'un d'eux ouvre directement son écran de réglage. Chacun a ses **deux durées indépendantes** (`2`/`8` pour monter/descendre la valeur, pas de 1 s, comme sur l'écran Volume) :

| Durée | S'applique | Départ | Défaut |
|-------|------------|--------|--------|
| **1re réponse** | question posée, personne n'a encore buzzé | **manuel** : `D` (« top ») une fois la question lue | 10 s |
| **Réponses suivantes** | après une mauvaise réponse, les autres reprennent la main | **automatique** | 5 s |

Le top est manuel sur la première réponse parce que la lecture de la question à voix haute prendrait sinon une partie du temps imparti — et une question longue n'en laisserait plus du tout. Sur les réponses suivantes il n'y a rien à relire, le décompte repart donc tout seul : c'est là que la pression se joue. **Buzzer avant le top reste possible** : le chrono ne verrouille rien, il ne fait que fermer la question.

Pendant le décompte, l'écran affiche les secondes restantes et une **barre qui se vide**, et sur les **3 dernières secondes** les LED des buzzers encore en lice **clignotent**. À l'expiration, un son d'échec est joué et la question est close sans que personne ne marque : l'écran des scores s'affiche avec le titre « TEMPS ECOULE ! ».

Le pas de réglage est de 1 s (jusqu'à 60 s). Régler une durée sur `off` désactive le chrono correspondant — on retrouve alors le comportement sans limite de temps. Les quatre durées (2 par mode chrono) sont **sauvegardées en EEPROM** (adresses 1 à 4 ; l'adresse 0 est le volume) et rechargées au démarrage. Le chrono ne s'applique **pas** au bris d'égalité, ni aux jeux Simon qui ont leur propre délai.

### Score des modes quiz (Classique / Pénalité / Chrono classique / Chrono pénalité)

Chaque buzzer (couleur) a un score. Les scores sont remis à zéro au lancement d'une partie (`#`). Entre chaque question (après une bonne réponse **ou une question passée**), l'écran des scores s'affiche 15 secondes (ou `#` pour enchaîner). En fin de partie (`C`), l'écran affiche les scores finaux et la couleur gagnante avec un son de victoire (en cas d'égalité, « EGALITE » est affiché sans son).

Seuls les **buzzers présents** (déclarés via l'assistant) apparaissent sur les écrans de scores ; les buzzers absents sont masqués, et le gagnant est calculé uniquement parmi les présents.

### Bris d'égalité

Si la partie se termine sur une **égalité** au sommet, l'écran de fin propose un bris (`#`). Pendant le bris (« BRIS D'EGALITE »), **seuls les buzzers ex æquo** peuvent buzzer — leurs **LED s'allument** et leurs **couleurs sont affichées** à l'écran ; les autres sont neutralisés (sans effet à l'appui). L'animateur juge :

- `A` (bonne réponse) → ce buzzer **gagne la partie** (+1, score final unique).
- `D` (mauvaise réponse) → ce buzzer est **éliminé du bris** ; le dernier encore en lice gagne.

On enchaîne ensuite sur l'écran de fin avec le gagnant désigné.

### Corriger une erreur de jugement

Si l'animateur se trompe (coche bonne au lieu de mauvaise, ou l'inverse), la touche `B` **annule la dernière décision** : le score est rétabli comme avant, et on revient sur l'écran de jugement (`BIP / A / D`) du **même buzzer** pour appuyer sur la bonne touche. Disponible depuis l'écran des scores (après une bonne réponse) et depuis l'écran d'attente (après une mauvaise réponse).

### Simon / Simon inverse — jeu collaboratif de mémoire (à 4)

Jeu **coopératif** : il n'y a pas de gagnant individuel, l'équipe joue contre sa propre mémoire. Chaque joueur tient **une couleur** ; la machine joue une séquence de couleurs que l'équipe doit **rejouer**, chacun appuyant quand *sa* couleur passe. Implémenté dans [Simon.cpp](Simon.cpp).

Le jeu exige les **4 buzzers** : si un buzzer a été déclaré absent, `#` affiche « SIMON : 4 JOUEURS » et renvoie vers l'assistant (`A`) au lieu de lancer la partie.

Déroulement d'un niveau :

1. **Démonstration** (`SIMON_SHOW`) — une couleur est ajoutée à la séquence, puis toute la séquence est rejouée **dans l'ordre**, y compris en Simon inverse (seule la répétition change) : chaque étape allume la LED ~0,6 s et joue **le son configuré du buzzer** correspondant (le même que pendant un quiz — donc réglable via `A` ou `B` au menu).
2. **Répétition** (`SIMON_PLAY`) — « A vous de repeter ! » (ou « Repetez a l'envers! » en Simon inverse, où il faut alors rejouer la séquence en partant de la **dernière** couleur montrée) avec la progression `x / N`. Chaque appui rallume brièvement sa LED et rejoue son son. Il faut moins de **10 s** entre deux appuis.
3. **Niveau réussi** → son de bonne réponse, « BRAVO ! », et la séquence s'allonge d'une couleur.

La partie s'arrête à la **première erreur** : l'écran de fin affiche la **couleur fautive** (nommée, LED allumée), le **niveau atteint** et un petit commentaire. `#` relance une partie, `*` revient au menu. `C` permet d'abandonner à tout moment ; si l'équipe atteint le niveau 32 (`SIMON_MAX_LEVEL`), c'est gagné (« PARFAIT !!! »).

Les durées du jeu (démonstration, écho des appuis, délai maxi) sont réglables via les `#define` en tête de [Simon.h](Simon.h).

## Assistant de configuration des buzzers (`A` au menu)

L'assistant fait le tour des 4 buzzers (Rouge → Bleu → Jaune → Vert). Pour chacun :

1. L'écran affiche `<Couleur> : appuyez sur le buzzer`.
   - **Appui sur le buzzer** → son son est joué, on passe au choix.
   - **`*`** → buzzer déclaré *absent* (exclu du pool).
   - **`#`** → quitte l'assistant.
2. Après l'appui :
   - **`B`** → **son suivant**, **`C`** → **son précédent** (parcourt les sons disponibles dans un sens ou dans l'autre, en sautant ceux déjà verrouillés ; peut « voler » le son d'un buzzer pas encore configuré). Le son est joué à chaque changement.
   - **`A`** → valide et **verrouille** le son de ce buzzer.
   - **`*`** → buzzer déclaré absent.

La configuration est **optionnelle** : si on lance directement la partie (`#`), on joue avec les **4 buzzers et des sons aléatoires** (état par défaut). Elle n'est pas sauvegardée entre deux mises sous tension.

## Structure du code

| Fichier | Rôle |
|---------|------|
| [Buzzer.ino](Buzzer.ino) | Point d'entrée, boucle principale et machine à états |
| [PhaseMode.h](PhaseMode.h) | Énumération des états de l'application |
| [GameMode.h](GameMode.h) | Énumération des jeux disponibles (Classique / Pénalité / Simon) |
| [Configuration.cpp](Configuration.cpp) / [.h](Configuration.h) | Menus et écrans de configuration (dont le sous-menu des jeux) |
| [Buzzer.cpp](Buzzer.cpp) / [.h](Buzzer.h) | Gestion des buzzers, LEDs et logique des jeux quiz (singleton) |
| [Simon.cpp](Simon.cpp) / [.h](Simon.h) | Jeu collaboratif de mémoire « Simon » (à 4) |
| [AppKeypad.h](AppKeypad.h) | Lecture du clavier matriciel et détection du reset (singleton) |
| [LcdDisplay.cpp](LcdDisplay.cpp) / [.h](LcdDisplay.h) | Affichage LCD 20×4 (textes calibrés sur 20 colonnes ; défilement en secours), gestion des accents et égaliseur graphique (caractères personnalisés) |
| [Mp3.cpp](Mp3.cpp) / [.h](Mp3.h) | Pilotage du DFPlayer Mini + bascule simulation (singleton) |
| [OledDisplay.cpp](OledDisplay.cpp) / [.h](OledDisplay.h) | Variante d'affichage OLED (non utilisée actuellement) |

## Son : matériel réel et simulation

Les sons sont organisés sur la carte SD du DFPlayer Mini en **5 dossiers** : `01` (init), `02` (buzzers), `03` (bonnes réponses), `04` (mauvaises réponses), `05` (ambiance, lancé manuellement par `#` pendant une question).

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

> ⚠️ Wokwi simule le **dernier binaire compilé** : il faut **recompiler** après chaque modif du code, puis relancer la simulation, sinon on teste un binaire périmé. Une tâche VS Code « Compiler (Arduino Mega) » est fournie ([.vscode/tasks.json](.vscode/tasks.json)) — lance-la avec **Ctrl+Shift+B** avant « Wokwi: Start Simulator ».

### Avec arduino-cli

```sh
arduino-cli compile --fqbn arduino:avr:mega --output-dir build .
arduino-cli upload  --fqbn arduino:avr:mega -p <PORT> .
```

En simulation Wokwi (DFPlayer absent), le moniteur série (9600 bauds) affiche les sons « joués » sous la forme `[SIM] Lecture dossier ...`. Sur l'Arduino réel équipé du DFPlayer et de la carte SD, les sons sont diffusés réellement — sans rien changer au code.

## Auteur

Marc Lindsay
