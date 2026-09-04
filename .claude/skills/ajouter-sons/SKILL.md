---
name: ajouter-sons
description: Ajouter, remplacer ou retirer des sons dans la banque du Buzzer, puis les passer à la moulinette de conversion et synchroniser les trois copies. À utiliser quand on parle d'ajouter des sons, de nouveaux sons dans la bibliothèque, de convertir ou normaliser des sons, de la carte SD des sons, ou de mettre à jour les compteurs de fichiers du firmware.
---

# Ajouter des sons à la banque

La banque vit en **trois copies** qui doivent rester identiques. Convertir
sans les resynchroniser laisse le travail à moitié fait, et c'est là qu'une
erreur passe inaperçue : le Mega joue un fichier, l'app en joue un autre.

| Copie | Nommage | Rôle |
|---|---|---|
| `C:\Users\MarcLindsay\OneDrive\...\sons\Bibliothèque\` | `003_bingo-....mp3` | **La source.** C'est là qu'on dépose. |
| `E:\` (carte SD du Mega) | `03/003.mp3` | Ce que joue le firmware seul |
| `app/buzzer_companion/assets/sounds/` | identique à la source | Ce que joue l'app quand elle pilote |

## Ce qui rend cette procédure fragile

Cinq choses se trompent en silence.

**Le rang alphabétique fait le numéro DFPlayer.** Le 4e fichier du dossier
devient `004.mp3`, quel que soit son préfixe. Donc **retirer un fichier au
milieu décale tout ce qui suit** : ce n'est pas un trou dans la
numérotation, c'est une renumérotation complète du dossier et de sa
contrepartie sur la carte. Un ajout en fin de dossier, lui, ne décale rien.

**Les pochettes d'album.** La majorité des fichiers téléchargés en
transportent une (76 sur 98 lors de la standardisation du 3 septembre 2026).
C'est la cause classique d'un refus de lecture sur DFPlayer, bien avant le
VBR : le module bute sur un entête ID3 de plusieurs dizaines de kilo-octets
avant d'atteindre la première trame audio. Sans `-vn`, **ffmpeg échoue** au
lieu de la jeter, avec un message qui parle de codec et non d'image.

**`05_Waiting` vise -20 LUFS, pas -16.** Ce dossier joue en fond pendant que
les équipes réfléchissent. L'aligner sur les bruitages transformerait un tic
d'horloge en buzzer. Le script s'en occupe, mais si on convertit à la main,
c'est l'oubli le plus facile.

**Rogner le silence d'un son minuté.** Un décompte, une musique de durée
voulue : vérifier **d'où vient le rognage** avant de l'accepter. Couper
0,6 s en queue est sans conséquence ; couper 0,6 s en tête décale tout ce
que l'animateur annonce par-dessus.

**Les compteurs du firmware.** `Mp3.h` ne connaît la banque que par ses
`*_FILE_COUNT`. L'app, elle, compte ses assets à l'exécution via le
manifeste : elle n'a besoin que d'un rebuild. Oublier les `#define` fait
tirer au Mega un fichier qui n'existe pas.

## Le standard de la banque

MP3 **CBR 128 kbps, mono, 44,1 kHz**, aucune métadonnée ID3 ni pochette,
silences rognés aux deux bouts avec fondu de 5 ms, normalisation EBU R128 à
**-16 LUFS** — sauf `05_Waiting` à **-20 LUFS**.

Prérequis : `winget install Gyan.FFmpeg`.

## 1. Prendre l'état de départ

```bash
L="/c/Users/MarcLindsay/OneDrive/Developpement/Arduino/Buzzer/sons/Bibliothèque"
for d in 01_Intro 02_Buzzer 03_Good 04_Bad 05_Waiting 06_Divers; do
  n="${d%%_*}"
  printf "%-12s biblio=%2d sd=%2d app=%2d\n" "$d" \
    "$(ls "$L/$d"/*.mp3 2>/dev/null|wc -l)" "$(ls /e/$n/*.mp3 2>/dev/null|wc -l)" \
    "$(ls "D:/dev/Arduino/Buzzer/app/buzzer_companion/assets/sounds/$d"/*.mp3 2>/dev/null|wc -l)"
done
grep -n FILE_COUNT D:/dev/Arduino/Buzzer/Mp3.h
```

**Vérifier d'abord que les fichiers déjà convertis n'ont pas dérivé**, avant
de toucher à quoi que ce soit. Si une copie a bougé toute seule, il faut le
savoir maintenant, pas après avoir empilé de nouveaux changements dessus.

## 2. Décider s'il faut renuméroter

Comparer les noms de la bibliothèque à leur rang.

- **Ajouts en fin de dossier** (le cas normal) : rien à faire, le préfixe
  suit déjà.
- **Suppression ou insertion au milieu** : renuméroter tout le dossier, en
  gardant le suffixe descriptif intact.

```bash
i=1
for f in "$L/03_Good"/*.mp3; do
  b=$(basename "$f"); new="$(printf '%03d' $i)${b:3}"
  [ "$b" != "$new" ] && mv "$f" "$L/03_Good/$new"
  i=$((i+1))
done
```

Sur la carte, le décalage se fait par renommage plutôt que par réécriture,
dans l'ordre croissant après avoir retiré la cible.

## 3. Convertir

```bash
bash D:/dev/Arduino/Buzzer/.claude/skills/ajouter-sons/convertir.sh "$SCRATCH"
```

Le script repère seul ce qui n'est pas au standard, en comparant la
bibliothèque aux assets **au md5** : ça attrape aussi bien un ajout qu'un
remplacement en place, ce qu'une comparaison par nom raterait. Il écrit dans
`$SCRATCH/conv_new/` et **n'écrase rien**.

Il signale au passage les fichiers dont la loudness n'est pas mesurable
(« repli crète »). Ce sont des sons trop courts pour le gating EBU R128 :
alignés sur leur crête faute de mieux, ils méritent une écoute en contexte.

**Ne pas repasser la moulinette sur un fichier déjà traité.** Le seuil de
rognage, -50 dB, est absolu : normaliser un fichier vers le bas fait passer
une plus grande part de sa queue décroissante sous ce seuil, et le passage
suivant la coupe. Un `Game-Waiting` déjà converti reperd ainsi 0,4 s à
chaque tour. La détection au md5 évite le problème toute seule — c'est
`--liste` qui permet de se tirer dans le pied.

## 4. Relire la sortie avant de déployer

Le tableau du script donne durée avant, après, et rognage. Trois choses à y
chercher :

- Un **rognage anormalement gros** sur un son minuté : vérifier d'où il
  vient avec le filtre de rognage appliqué au début seul, et comparer les
  durées.
- Un **buzzer qui dépasse 2 s** : `BUZZ_MAX_MS` le coupera en plein son. Ce
  n'est pas une erreur, mais sa fin ne s'entendra jamais.
- Une **loudness de départ extrême** (au-delà de -8 LUFS) : le fichier
  écrasait tout et va beaucoup descendre. Normal, mais s'en assurer à
  l'oreille.
- Un fichier **qui n'atteint pas sa cible** de plus de 2 dB. Voir juste
  en dessous.

### Quand loudnorm rate sa cible

`linear=true` n'est pas une garantie. Sur un fichier dont les crêtes sont
déjà hautes, atteindre la cible ferait dépasser le plafond de -1,5 dBTP :
loudnorm abandonne alors le mode linéaire et bascule en **Dynamic**, qui
compresse et atterrit où il peut. C'est le bon arbitrage — on ne peut pas
à la fois monter le niveau et garder les crêtes basses — mais le résultat
dévie.

Le vérifier quand un écart dépasse 2 dB :

```bash
"$FF" -hide_banner -i "$W/$d/$b.wav" -af "loudnorm=I=$I:TP=-1.5:LRA=11:measured_I=…:linear=true:print_format=summary" -f null - 2>&1 | grep -E 'Output Integrated|Normalization Type'
```

`Normalization Type: Dynamic` confirme la bascule. La correction, si l'écart
gêne : ajouter un `volume=<delta>dB` **après** le loudnorm et réencoder. Une
réduction ne peut pas écrêter, donc c'est sans risque et ça tombe pile.

Ça compte surtout dans `05_Waiting`, dont l'intérêt est justement d'être en
retrait : un fichier 2,4 dB au-dessus de ses voisins y défait l'intention.
C'est arrivé au `20-sec-countdown` le 4 septembre 2026.

Déposer la sortie à côté de la bibliothèque pour écoute si l'ajout est
important. Retirer ce dossier temporaire ensuite, il fait doublon.

## 5. Déployer sur les trois copies

Sauvegarder les originaux d'abord — le remplacement est irréversible côté
carte SD.

```bash
A="D:/dev/Arduino/Buzzer/app/buzzer_companion/assets/sounds"
for d in 01_Intro 02_Buzzer 03_Good 04_Bad 05_Waiting 06_Divers; do
  [ -d "$SCRATCH/conv_new/$d" ] || continue
  cp "$SCRATCH/conv_new/$d"/*.mp3 "$L/$d/"
  n="${d%%_*}"; i=1
  for f in "$L/$d"/*.mp3; do
    b=$(basename "$f"); cp "$f" "/e/$n/$(printf '%03d' $i).mp3"; cp "$f" "$A/$d/$b"
    i=$((i+1))
  done
done
```

## 6. Monter les compteurs

Dans `Mp3.h`, un `#define` par dossier. Les mettre au nombre réel de
fichiers.

```bash
sed -i 's/^#define INIT_FILE_COUNT .*/#define INIT_FILE_COUNT 18/' D:/dev/Arduino/Buzzer/Mp3.h
```

Attention au cas trompeur : un retrait suivi d'un ajout dans le même dossier
laisse le compteur **inchangé** alors que le contenu a changé. Le diff ne
montrera rien pour ce dossier ; le dire dans le message de commit.

## 7. Vérifier au md5, fichier par fichier

Sans exception, et sur les trois copies. C'est cette étape qui a rattrapé,
le 3 septembre 2026, deux fichiers ajoutés dans des dossiers que personne
n'avait mentionnés.

```bash
ok=1
for d in 01_Intro 02_Buzzer 03_Good 04_Bad 05_Waiting 06_Divers; do
  n="${d%%_*}"; i=1
  for f in "$L/$d"/*.mp3; do
    b=$(basename "$f"); t=$(printf '%03d' $i)
    hL=$(md5sum "$f"|cut -d' ' -f1)
    [ "$hL" = "$(md5sum "/e/$n/$t.mp3" 2>/dev/null|cut -d' ' -f1)" ] || { echo "SD  != $d/$b"; ok=0; }
    [ "$hL" = "$(md5sum "$A/$d/$b" 2>/dev/null|cut -d' ' -f1)" ] || { echo "APP != $d/$b"; ok=0; }
    i=$((i+1))
  done
  cl=$(ls "$L/$d"/*.mp3|wc -l); cs=$(ls /e/$n/*.mp3|wc -l); ca=$(ls "$A/$d"/*.mp3|wc -l)
  [ "$cl" = "$cs" ] && [ "$cl" = "$ca" ] || { echo "COMPTE $d $cl/$cs/$ca"; ok=0; }
done
[ $ok = 1 ] && echo "Les trois copies sont identiques."
```

Contrôler aussi que la banque entière tient sur un seul format : aucun VBR,
aucun stéréo, une seule fréquence.

## 8. Commiter

Style du dépôt : **français sans accents** dans le message, ton narratif,
phrases clés en majuscules, corps qui explique ce que le diff ne montre pas.

Y mettre en priorité ce qui ne se devine pas :

- Un compteur qui ne bouge pas alors que le dossier a changé.
- D'où venait un rognage important, si le son est minuté.
- Les fichiers en « repli crète », à surveiller à l'usage.
- Les buzzers qui passent au-dessus de `BUZZ_MAX_MS`.

Terminer par `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

Ne pas pousser sans qu'on le demande.

## Après coup

Le Mega a besoin d'un **flash** pour les nouveaux compteurs, l'app d'un
**rebuild** pour embarquer les nouveaux assets. Ni l'un ni l'autre ne se
fait tout seul, et les deux sont à la main de l'opérateur.
