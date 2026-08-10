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
- **QUIZ_CATS / QUIZ_COUNT** — Au lancement d'un quiz (`#` au menu, tous les jeux sauf Simon), deux écrans se suivent : le **choix des catégories** de la banque de questions (voir plus bas), puis le **nombre de questions** à poser. C'est la validation du second écran qui démarre réellement la partie.
- **INTRO** — Lancement festif : un **chenillard** allume les LED l'une après l'autre (~4 s) pendant la musique de démarrage, puis passe à la 1re question (ou à la 1re séquence en Simon). N'importe quelle touche passe l'intro. Absent en **Vol**, qui va directement à son propre tirage au sort (`VOL_SPIN`, voir plus bas).
- **VOLUME** — Réglage du volume du DFPlayer (0–30) : `2` = +, `8` = −, `#` = sauvegarder et retour. Appuyer sur un **buzzer** joue son son au volume courant (aperçu).
- **BUZZER_CONFIG** — Assistant de configuration guidé (voir ci-dessous). `#` quitte à tout moment.
- **SHUFFLE_BUZZER** — Réattribue aléatoirement les sons à tous les buzzers, **après confirmation** (`#` = confirmer, `*` = annuler) pour éviter d'écraser une configuration faite via l'assistant. La confirmation lance la même **animation de tirage** que `VOL_SPIN` (chenillard + son du dossier `06`, voir plus bas) avant d'afficher le résultat.
- **WAITING_BUZZER** — En attente (le n° de **question** est affiché) : le premier buzzer *présent et actif* pressé allume sa LED, joue son son et passe en `BUZZER_PRESSED`. La détection est sur **front d'appui** (un bouton maintenu ne se redéclenche pas tout seul). `C` demande à terminer la partie, `B` corrige la dernière décision, `0` **passe la question** (personne ne marque), `#` lance un **son d'ambiance**, `D` donne le **top du chrono** (voir ci-dessous).
- **BUZZER_PRESSED** — L'animateur tranche :
  - `A` : bonne réponse → **+1 point**, son de bonne réponse, puis écran des scores (`SHOW_SCORES`) avec clignotement bref de la LED du gagnant.
  - `D` : mauvaise réponse → son d'échec, le buzzer fautif est désactivé pour ce tour (**−1 point en mode Pénalité**), on reste sur la même question.
  - `0` : **passer la question** (personne ne marque, on passe à l'écran des scores).
- **ANSWER_REVEAL** — Uniquement quand la banque de questions est active et que personne n'a répondu (`0` ou chrono écoulé) : affiche la réponse avant de passer aux scores (`#` pour continuer), pour que l'animateur la découvre aussi.
- **SHOW_SCORES** — Affiche les scores entre les questions (2 colonnes + titre), pendant 15 s ou jusqu'à `#`. `C` demande à terminer la partie, `B` corrige la dernière décision (proposé seulement s'il y a une décision à corriger — pas après une question passée).
- **END_CONFIRM** — Confirmation avant de terminer la partie (`#` = oui, `*` = non / continuer).
- **END_GAME** — Scores finaux. Si un gagnant unique : couleur gagnante + son de victoire, `#` revient au menu. Si **égalité** au sommet : `#` lance un **bris d'égalité**, `*` accepte l'égalité (retour au menu).
- **SIMON_SHOW / SIMON_PLAY / SIMON_OVER** — Les trois états du jeu Simon (voir plus bas).
- **RESET** — Une touche de reset (gérée par [AppKeypad](AppKeypad.h)) éteint les LEDs et revient au menu.

Les sons sont organisés en 6 dossiers sur la carte SD (voir [Mp3.h](Mp3.h)) : init, buzzers, bonnes réponses, mauvaises réponses, ambiance, tirage au sort. Le **nombre de fichiers par dossier est détecté automatiquement** au démarrage en interrogeant le DFPlayer (`readFileCountsInFolder`) ; les constantes `*_FILE_COUNT` de [Mp3.h](Mp3.h) ne servent que de **valeurs de repli** (simulation Wokwi, ou si la détection échoue). Les comptes sont affichés sur le port série au démarrage.

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
| **Vol** | Question adressée à un joueur ; les autres peuvent la **voler** s'il rate — **chrono toujours actif** |
| **Simon** | Jeu de mémoire **collaboratif**, obligatoirement à 4 |
| **Simon inverse** | Comme Simon, mais la séquence se répète **à l'envers** |

### Chrono de buzz (jeux « Chrono ... » et « Vol »)

Le chrono limite le **temps pour buzzer**, pas le temps de répondre : une fois qu'un joueur a buzzé, c'est l'animateur qui décide quand la réponse est finie, sans compteur qui le contredise. Il n'existe que dans les jeux **Chrono classique**, **Chrono pénalité** et **Vol** ; sélectionner l'un d'eux ouvre directement son écran de réglage. Chacun a ses **deux durées indépendantes** (`2`/`8` pour monter/descendre la valeur, pas de 1 s, comme sur l'écran Volume) :

| Durée | S'applique | Départ | Défaut |
|-------|------------|--------|--------|
| **1re réponse** | question posée, personne n'a encore buzzé | **manuel** : `D` (« top ») une fois la question lue | 10 s |
| **Réponses suivantes** | après une mauvaise réponse, les autres reprennent la main | **automatique** | 5 s |

Le top est manuel sur la première réponse parce que la lecture de la question à voix haute prendrait sinon une partie du temps imparti — et une question longue n'en laisserait plus du tout. Sur les réponses suivantes il n'y a rien à relire, le décompte repart donc tout seul : c'est là que la pression se joue. **Buzzer avant le top reste possible** : le chrono ne verrouille rien, il ne fait que fermer la question.

Pendant le décompte, l'écran affiche les secondes restantes et une **barre qui se vide**, et sur les **3 dernières secondes** les LED des buzzers encore en lice **clignotent**. À l'expiration, un son d'échec est joué et la question est close sans que personne ne marque : l'écran des scores s'affiche avec le titre « TEMPS ECOULE ! ».

Le pas de réglage est de 1 s (jusqu'à 60 s). Régler une durée sur `off` désactive le chrono correspondant — on retrouve alors le comportement sans limite de temps. Les six durées (2 par mode chrono) sont **sauvegardées en EEPROM** (adresses 1 à 6 ; l'adresse 0 est le volume) et rechargées au démarrage. Le chrono ne s'applique **pas** au bris d'égalité, ni aux jeux Simon qui ont leur propre délai.

### Vol — question adressée, avec possibilité de voler

Contrairement aux autres quiz (où le premier à buzzer répond), en **Vol** chaque question est adressée à **un seul joueur à la fois** : sa LED s'allume, lui seul peut buzzer (`Tour: <couleur>` à l'écran). Le tour tourne ensuite dans l'ordre des couleurs, une place à chaque question.

Le **premier joueur** est désigné par un **tirage au sort animé** (`VOL_SPIN`) : un chenillard parcourt les buzzers présents (jamais un absent) pendant que le son du tirage (dossier `06`, fichier `1`) joue, puis s'arrête sur le joueur tiré au sort — sa LED reste allumée et l'écran d'attente qui suit affiche aussitôt `Tour: <couleur>`, pour que l'animateur voie clairement qui doit répondre. N'importe quelle touche passe l'animation. **Vol n'a pas d'intro musicale** : `#` au menu enchaîne directement sur ce tirage au sort (l'intro + le tirage auraient fait deux animations à la suite, trop long).

L'animation dure exactement le temps réel du son (détection `BUSY` du DFPlayer, comme l'intro), et le chenillard ralentit progressivement pour suivre le son, qui démarre avec des clics rapprochés et se termine avec des clics espacés (effet « roue qui ralentit »). Cette même animation (`Buzzer::startSpinAnimation` / `tickSpinAnimation`) est réutilisée par le menu **B : Sons au hasard** (`SHUFFLE_BUZZER`) pendant le mélange des sons de buzz.

- S'il **répond juste** (`A`) → il marque le point, et le tour passe au joueur suivant.
- S'il **répond faux** (`D`) **ou n'appuie pas à temps** (chrono écoulé) → il est écarté pour cette question, et la question **s'ouvre aussitôt aux autres présents** (« droit de réplique ») : le chrono court repart tout seul, et le premier d'entre eux à buzzer tente de la « voler ». Comme dans un quiz classique, une nouvelle mauvaise réponse écarte le voleur à son tour et laisse la main aux suivants.
- Si **personne ne vole à temps** pendant le droit de réplique (chrono écoulé) → là, la question se ferme : personne ne marque, comme en Classique/Pénalité.

Dans tous les cas, le tour passe au joueur présent suivant à la question d'après.

Le joueur désigné doit appuyer sur son propre buzzer pour répondre (comme dans les autres modes) — c'est cet appui qui arrête le chrono. Le chrono de Vol se règle comme celui des jeux Chrono (`2`/`8`, `D` = top sur la 1re réponse, automatique ensuite).

### Banque de questions intégrée

Une **banque de 1765 questions-réponses** (10 catégories de 170 à 180 : Culture generale, Histoire, Geographie, Sciences et nature, Sports, Musique, Cinema et tele, Quebec, Bouffe et cuisine, Mots et langue) est stockée en Flash — aucune SRAM consommée. La banque dépasse la barrière des 64 Ko adressables par les pointeurs `PROGMEM` classiques : elle est placée en **fin de Flash** (section `.fini1`) et lue en **adressage far 32 bits** (`pgm_read_byte_far`), ce qui laisse les petites chaînes du programme (`F()`) sous les 64 Ko. Les questions vivent dans [Questions.cpp](Questions.cpp) au format `"Question|Reponse\n"` : pour en ajouter, il suffit d'insérer des lignes (sans accents, sans `|`), le comptage est automatique au démarrage — jusqu'à **200 par catégorie** (limite de l'historique EEPROM, soit ~20 places libres par catégorie).

Au lancement d'un quiz (`#` au menu — tous les jeux sauf Simon), deux écrans se présentent :

1. **Catégories** (`QUIZ_CATS`) — liste déroulante : `Toutes`, `Aucune (perso)` — pour jouer avec **son propre questionnaire** papier, comme avant —, puis les 10 catégories cochables. `2`/`8` déplacent le curseur, `5` coche/décoche `[x]`, `#` confirme (sur `Toutes`/`Aucune`, `#` applique directement ; sur une catégorie sans rien de coché, `#` sélectionne celle-là seule), `*` annule le lancement. La sélection est **mémorisée** d'une partie à l'autre.
2. **Nombre de questions** (`QUIZ_COUNT`) — `Ouvert` (l'animateur termine avec `C`, comportement historique) ou une valeur de 1 à 99 (`2` = +1, `8` = −1). Quand le compte est atteint, la partie se termine d'elle-même sur l'écran des scores finaux. La limite s'applique aussi avec `Aucune` (questionnaire perso).

En jeu avec la banque, l'écran d'attente est entièrement consacré à la question : le titre se réduit à `Q5` (plus `D:top` si le chrono est actif) et la question occupe les **lignes 1 à 3, soit 60 colonnes**, découpée aux espaces — **85 % des questions s'affichent ainsi d'un bloc**, sans défilement. Les 15 % restantes voient seulement leur fin défiler sur la dernière ligne. Pendant le décompte, la question se replie sur deux lignes (elle a déjà été lue). Le titre porte aussi les rappels `0:pass` et `C:fin` (sinon invisibles, la question prenant toute la place) ; si tout ne tient pas sur 20 colonnes (Vol + chrono + tour affiché), le titre défile.

La **réponse s'affiche pour l'animateur** sur l'écran de jugement, seule sur sa ligne (20 colonnes, sans préfixe) : une seule réponse de toute la banque dépasse cette largeur (`Anticonstitutionnellement`, forcément). C'est l'animateur qui lit la question à voix haute et juge `A`/`D`. Si personne n'a répondu (`0` = passer, ou chrono écoulé), un écran **ANSWER_REVEAL** affiche quand même la réponse (`# = suite`) avant les scores, pour que l'animateur (et la table) la découvre.

Les questions sont validées automatiquement (aucun doublon, aucun accent, format `Question|Reponse` respecté, réponse tenant sur une ligne, réponse jamais contenue dans sa propre question).

**Anti-répétition** : chaque question posée est marquée dans un **bitmap en EEPROM** (persistant entre les soirées — adresses 16 à 265, 1 bit par question). Une question déjà posée ne ressort jamais, même des semaines plus tard, jusqu'à épuisement des catégories sélectionnées : l'historique de ces catégories est alors remis à zéro automatiquement et le tirage repart.

### Score des modes quiz (Classique / Pénalité / Chrono classique / Chrono pénalité / Vol)

Chaque buzzer (couleur) a un score. Les scores sont remis à zéro au lancement d'une partie (`#`). Entre chaque question (après une bonne réponse **ou une question passée**), l'écran des scores s'affiche 15 secondes (ou `#` pour enchaîner). En fin de partie (`C`), l'écran affiche les scores finaux et la couleur gagnante avec un son de victoire (en cas d'égalité, « EGALITE » est affiché sans son).

Seuls les **buzzers présents** (déclarés via l'assistant) apparaissent sur les écrans de scores ; les buzzers absents sont masqués, et le gagnant est calculé uniquement parmi les présents.

### Bris d'égalité

Si la partie se termine sur une **égalité** au sommet, l'écran de fin propose un bris (`#`). Pendant le bris, **seuls les buzzers ex æquo** peuvent buzzer — leurs **LED s'allument** ; les autres sont neutralisés (sans effet à l'appui). Si la banque de questions est active, une question y est aussi tirée pour le bris (comme pour une question normale) ; sinon l'écran affiche les couleurs en lice et l'animateur pose sa question à l'oral. L'animateur juge :

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
| [Questions.cpp](Questions.cpp) / [.h](Questions.h) | Banque de questions-réponses par catégorie (PROGMEM) |
| [QuestionBank.cpp](QuestionBank.cpp) / [.h](QuestionBank.h) | Tirage sans répétition (historique en EEPROM), sélection de catégories |
| [AppKeypad.h](AppKeypad.h) | Lecture du clavier matriciel et détection du reset (singleton) |
| [LcdDisplay.cpp](LcdDisplay.cpp) / [.h](LcdDisplay.h) | Affichage LCD 20×4 (textes calibrés sur 20 colonnes ; défilement en secours), gestion des accents et égaliseur graphique (caractères personnalisés) |
| [Mp3.cpp](Mp3.cpp) / [.h](Mp3.h) | Pilotage du DFPlayer Mini + bascule simulation (singleton) |
| [OledDisplay.cpp](OledDisplay.cpp) / [.h](OledDisplay.h) | Variante d'affichage OLED (non utilisée actuellement) |

## Son : matériel réel et simulation

Les sons sont organisés sur la carte SD du DFPlayer Mini en **6 dossiers** : `01` (init), `02` (buzzers), `03` (bonnes réponses), `04` (mauvaises réponses), `05` (ambiance, lancé manuellement par `#` pendant une question), `06` (tirage au sort du mode Vol, un seul fichier).

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
