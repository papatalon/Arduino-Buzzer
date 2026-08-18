# Handoff : console Buzzer + écran public

## Overview

Interface de pilotage pour un système de buzzers de jeu-concours à quatre boîtiers
colorés (rouge, bleu, jaune, vert) tournant sur Arduino Mega 2560. Le firmware
existe déjà : quatre boutons, quatre LED, un DFPlayer Mini pour les sons, un LCD
20×4, une banque de 2 000 questions en Flash, un historique anti-répétition en
EEPROM, et un module BLE AT-09 sur `Serial2` à 9600 bauds.

L'app à construire remplace le clavier matriciel et le LCD par une console
d'animateur sur ordinateur portable, plus un **écran public détachable** (modèle
KaraFun) projeté sur téléviseur ou projecteur. Deux surfaces, deux publics :

- **Console (fenêtre principale)** — l'animateur. Voit tout, y compris la réponse.
- **Écran public (fenêtre détachée, 16:9)** — les joueurs et la salle. Ne voit
  jamais la réponse avant révélation explicite, ni la séquence Simon, ni les
  écarts du Chrono aveugle, ni le numéro du son de « Ne buzze pas ».

Cette asymétrie est la règle centrale du produit. Toute donnée sensible doit
transiter par un état « révélée » avant d'atteindre la seconde fenêtre.

## About the Design Files

Les fichiers de ce paquet sont des **références de design réalisées en HTML** :
des maquettes montrant l'apparence et le comportement voulus, **pas du code de
production à copier tel quel**. Le travail consiste à **recréer ces designs dans
l'environnement du codebase cible** (Flutter, React, Vue, natif…) avec ses
patterns et ses bibliothèques établis.

Le projet contient déjà une app Flutter embryonnaire
(`app/buzzer_companion/`) : Material 3, seed `deepPurple`, écran unique de
télémétrie en lecture seule, service BLE ligne par ligne. **Deux chemins
possibles**, à trancher avec le propriétaire du projet :

1. **Continuer en Flutter** — cible desktop (Windows est déjà configuré). Le
   second écran se fait avec une fenêtre secondaire (`desktop_multi_window` ou
   équivalent). Il faudra remplacer entièrement le thème Material par les tokens
   Broadsheet ci-dessous : la maquette n'est pas du Material Design.
2. **Passer au web** (Electron/Tauri + React) — le pop-out devient un
   `window.open` avec `BroadcastChannel` pour la synchronisation, ce qui colle
   exactement au modèle des maquettes. Plus direct à réaliser, mais abandonne le
   travail Flutter existant.

Les maquettes sont agnostiques : elles décrivent la mise en page et les états, pas
la technologie.

## Fidelity

**Haute fidélité (hifi).** Couleurs, typographie, échelles et espacements sont
définitifs et proviennent d'un design system nommé **Broadsheet** (fourni,
voir `_ds/`). L'UI doit être recréée fidèlement, en s'appuyant sur les
composants existants du codebase pour le comportement mais en respectant les
valeurs visuelles listées plus bas.

Ne sont **pas** spécifiés et restent à décider : animations d'entrée/sortie
détaillées, comportement responsive sous 1280 px (la console est prévue pour un
portable 1440 × 900 minimum), et le contenu réel des questions.

## Design Tokens

Tous les tokens viennent de `_ds/broadsheet-.../styles.css`, à lire comme source
de vérité. Extraits utilisés dans les maquettes :

### Couleurs de l'interface

| Token | Valeur | Usage |
| --- | --- | --- |
| `--color-bg` | `#f3f2f2` | Fond de toutes les surfaces (console et pop-out) |
| `--color-surface` | `#eae9e9` | Fond des rares blocs remplis |
| `--color-text` | `#201e1d` | Texte, filets épais, barres de dateline |
| `--color-accent` | `#0088b0` | Cyan — tout ce qui est interactif, l'état « actif » |
| `--color-accent-2` | `#d6006c` | Magenta — réservé au chrono et à la révélation |
| `--color-neutral-200` … `-800` | rampe OKLCH | Fonds atténués, textes secondaires, barres vides |
| `--color-accent-100` / `-700` / `-800` | rampe cyan | Fonds teintés, texte sur teinte |
| `--color-accent-2-100` / `-700` / `-800` | rampe magenta | Bloc de réponse révélée |
| `--color-divider` | (voir styles.css) | Filets 1 px entre colonnes et lignes |

Règle Broadsheet respectée dans toutes les maquettes : **jamais les deux accents
dans le même petit composant**. Le cyan porte l'interaction et l'état actif ; le
magenta ne sort que pour le chrono qui se vide et pour la réponse révélée.

### Couleurs physiques des buzzers (ne sont PAS des tokens du design system)

Ce sont les couleurs des LED réelles, reprises de `protocol.dart`. Elles sont
codées en dur et doivent le rester — elles identifient du matériel, pas un rôle
d'interface :

| Buzzer | Hex | Bouton / LED (firmware) |
| --- | --- | --- |
| Rouge | `#e63946` | bouton 5 · LED 6 |
| Bleu | `#3a86ff` | bouton 7 · LED 8 |
| Jaune | `#ffd60a` | bouton 9 · LED 10 |
| Vert | `#2ecc71` | bouton 11 · LED 12 |

Elles apparaissent **toujours comme des carrés pleins sans rayon**, jamais comme
des pastilles rondes, jamais comme fond d'un grand bloc de texte (sauf les
pastilles de présence 3a et le bandeau pop-out, où le carré reste petit).
Tailles utilisées : 14, 16, 18, 20, 22, 24, 30, 34, 38, 40, 44, 52, 64, 74, 80,
88, 110 px de côté selon le contexte.

### Typographie

Une seule famille : **Source Serif 4**, chargée par `styles.css` via
`--font-heading` et `--font-body` (les deux pointent sur Source Serif 4).
L'italique vraie est chargée au poids du corps — utilisée pour les réponses.

Aucune sans-serif nulle part : « le serif EST le chrome » (règle du design
system). La graisse 600 fait office de titre, la 400 de corps.

Échelle réellement employée :

| Rôle | Style |
| --- | --- |
| Sur-titre de section | `600 12px/1`, `letter-spacing: .16em`, majuscules, `--color-neutral-600` |
| Rail de dateline | `600 12px/1`, `letter-spacing: .15em`, majuscules |
| Corps de texte | `400 15px` à `400 19px`, `line-height: 1.3`–`1.5` |
| Nom de buzzer (console) | `600 21px/1.1` à `600 26px/1` |
| Score (console) | `600 40px/1`, `font-variant-numeric: tabular-nums` |
| Question (console) | `600 54px/1.08`, `letter-spacing: -.02em`, `max-width: 16em` |
| Réponse (console) | `italic 400 34px/1.2`, `--color-accent-2-700` |
| Question (pop-out) | `600 96px/1.06`, `letter-spacing: -.025em` |
| Score (pop-out) | `600 74px/.9`, tabular-nums |
| Nom de buzzer (pop-out) | `600 26px/1`, `letter-spacing: .04em`, majuscules |
| Chiffre héros (pop-out) | `600 128px` à `600 150px`, `letter-spacing: -.035em` |

**Plancher de lisibilité du pop-out : 26 px.** Rien de plus petit ne doit
apparaître sur l'écran projeté — contrainte donnée par le client (projection sur
TV ou projecteur, salle sombre). La console, vue à 60 cm, descend à 14 px pour
les métadonnées.

Tous les nombres qui changent en direct (scores, chronos, millisecondes,
écarts) portent `font-variant-numeric: tabular-nums` pour ne pas gigoter.

### Espacement, rayons, ombres

- Échelle `--space-*` du design system, densité 1.25× — **ne pas resserrer**.
- `--radius-*` existe mais les maquettes n'en utilisent quasiment pas : les
  blocs sont des rectangles nets. Les carrés de couleur des buzzers ont un
  rayon de 0.
- `--shadow-lg` sur les cadres de maquette uniquement (c'est le carton de
  présentation, pas l'UI) ; l'UI elle-même n'a aucune ombre.

### Structure de page — sans boîtes

Règle Broadsheet appliquée partout : **pas de cartes, pas de bordures pour
structurer**. La hiérarchie vient de l'échelle typographique, du blanc, et de
trois seules « meubles d'imprimerie » :

1. Un filet **5 px** `--color-text` en haut de la zone de contenu.
2. Le rail de dateline en petites capitales espacées, sous ce filet.
3. Un filet **1 px** `--color-text` sous le rail.

Puis des filets 1 px `--color-divider` pour séparer colonnes et lignes de
tableau, et un filet **4 px** `--color-text` au-dessus du bandeau de scores du
pop-out. Rien d'autre.

## Icônes

**Phosphor Icons, graisse duotone exclusivement**
(`https://unpkg.com/@phosphor-icons/web@2.1.1/src/duotone/style.css`).

Icônes utilisées : `ph-bluetooth-connected`, `ph-bluetooth`,
`ph-arrow-square-out` (détacher l'écran), `ph-check-circle`, `ph-x-circle`,
`ph-check`, `ph-clock`, `ph-timer`, `ph-music-notes`, `ph-play`,
`ph-skip-forward`, `ph-shuffle`, `ph-lightbulb`, `ph-speaker-high`,
`ph-magnifying-glass`, `ph-plus`, `ph-arrow-counter-clockwise`,
`ph-arrow-right`.

Aucun emoji nulle part.

## Screens / Views

Toutes les maquettes vivent dans un seul canevas (`Buzzer Console.dc.html`),
organisé en trois tours, du plus récent au plus ancien. Chaque option porte un
badge d'identifiant visible (`3a`, `2b`, `1c`…) : ces identifiants sont le
vocabulaire commun avec le client, garde-les dans les tickets.

### Le châssis de la console (invariant)

Toutes les consoles font **1440 × 900**, fond `--color-bg`, et partagent
exactement la même ossature. Ne la fais pas bouger d'un état à l'autre — c'est
une exigence explicite : l'animateur doit pouvoir cliquer sans relire l'écran.

```
┌──────────┬─────────────────────────────────────────────────────┐
│ nav      │ filet 5px  ─────────────────────────────────────────│
│ 196px    │ rail dateline (gauche: rôle · droite: 3-4 méta)     │
│          │ filet 1px  ─────────────────────────────────────────│
│ flex col │ ┌──────────────────────────┬──────────────────────┐ │
│ gap 34   │ │ colonne centrale         │ rail droit 340px     │ │
│ padding  │ │ flex:1, min-width:0      │ border-left 1px      │ │
│ 26/0/20  │ │                          │ padding-left 32px    │ │
│ /28      │ │ (le seul bloc qui change)│ (tableau, aperçu,    │ │
│          │ │                          │  actions de partie)  │ │
│          │ └──────────────────────────┴──────────────────────┘ │
└──────────┴─────────────────────────────────────────────────────┘
   padding zone de contenu : 26px 34px 0 34px ; gap colonnes : 44px
   padding-top sous le filet 1px : 30px
```

**Barre latérale (196 px, `flex: none`)**

- Marque `Buzzer` en `600 22px/1`, le point final en `--color-accent-2`.
- Sur-titre « ÉCRANS » (`600 12px`, `.16em`, majuscules, neutral-500), puis cinq
  entrées en `400 18px` : Partie, Jeu actif, Buzzers, Questions, Appareil.
- L'entrée active porte un filet vertical **4 × 18 px** en `--color-accent` à sa
  gauche (`gap: 9px`) et passe en poids 600 ; les inactives sont en
  `--color-neutral-700` avec `padding-left: 13px` pour aligner le texte.
- En bas (`margin-top: auto`) : nom de l'appareil BLE avec
  `ph-bluetooth-connected` en `--color-accent-700`, puis `Serial2 · 9600 bd` en
  `400 14px` neutral-600.

**Rail de dateline** — à gauche « CONSOLE DE L'ANIMATEUR », à droite trois ou
quatre métadonnées séparées par `gap: 26px` : jeu actif, progression, catégorie,
heure (l'heure en `--color-text`, le reste en neutral-700). Un état particulier
peut y colorer une entrée (« RÉPONSE RÉVÉLÉE » en magenta-700, « BLEU +1 » en
cyan-700).

**Rail droit (340 px)** — trois blocs empilés avec `gap: var(--space-6)` :

1. *Tableau* — une ligne par buzzer : carré 20 px, nom `600 21px/1.1`,
   statut `400 14px` (« son 7 · présent », « a la main », « absent »), score
   `600 40px/1` tabular-nums. Le buzzer absent : `opacity: .45` et un tiret cadratin
   à la place du score.
2. *Écran public* — vignette `aspect-ratio: 16/9` sur fond neutral-200, bordure
   1 px divider, qui **reproduit en miniature ce que la seconde fenêtre affiche
   vraiment** (pas un placeholder). Sous la vignette, le bouton secondaire
   « Détacher · écran 2 » avec `ph-arrow-square-out`, et une phrase de garantie
   en `400 14px` neutral-600.
3. *Partie* (`margin-top: auto`) — deux ou trois boutons fantômes.

**Raccourcis clavier visibles.** Chaque bouton affiche la touche du clavier
matriciel d'origine à sa droite, en `opacity: .6`–`.65` : `A` bonne réponse,
`D` mauvaise / top chrono, `0` passer, `#` action principale du jeu,
`B` corriger / annuler, `C` terminer, `*` action secondaire. Cette
correspondance est un pont vers le firmware, ne l'invente pas ailleurs.

### Le châssis du pop-out (invariant)

**1440 × 810** dans les maquettes = **16:9**, à rendre plein écran sur la vraie
sortie (1920 × 1080 typiquement). Fond `--color-bg` — **jamais de fond sombre**,
le design system ne montre aucune surface foncée.

```
┌─────────────────────────────────────────────────────┐
│ [logo soirée] JEU ACTIF          PROGRESSION        │  padding 30px 52px 0
│ ───────────── filet 4px ─────────────────────────── │  margin 18px 52px 0
│                                                     │
│              zone centrale, centrée verticalement   │  padding 0 52px
│              (question 96px, chrono, buzz)          │  gap 38-52px
│                                                     │
│ ═══════════════ filet 4px ════════════════════════ │
│ ROUGE 4 │ BLEU 6 │ JAUNE 3 │ VERT — │               │  4 colonnes flex:1
└─────────────────────────────────────────────────────┘
```

- **Emplacement de logo** : `118 × 44 px`, fond neutral-200, bordure 1 px
  **tiretée** neutral-400, label « logo soirée ». C'est un emplacement à
  remplir par l'utilisateur — prévoir un import d'image dans les réglages.
- **Bandeau de scores** : quatre colonnes `flex: 1`, chacune avec carré 22 px +
  nom en capitales `600 26px` + score `600 74px/.9`. Le premier padding-left et
  le dernier padding-right valent 52 px (marge de page) ; les intermédiaires
  28 px. La colonne du joueur qui vient de buzzer ou de marquer prend un fond
  `--color-accent-100` ; le joueur absent passe à `opacity: .4`.
- **Barre de chrono** : `height: 20px`, piste `--color-neutral-300`, remplissage
  `--color-accent-2`, largeur = `tempsRestant / tempsTotal × 100 %`. Vide
  (piste seule, sans remplissage) tant que le top n'est pas donné.
- **Buzz** : carré de couleur 52–88 px + nom en très gros, avec l'animation
  `buzzpulse` (voir Interactions).

### Écrans livrés, par tour

#### Tour 3 — états transitoires (les plus importants à implémenter d'abord)

**3a — Démarrage, appel des buzzers.** Avant le début de partie. Titre
« Que chacun buzze une fois pour se déclarer présent ». Grille 2 × 2 de
pastilles de présence : les buzzers confirmés ont un fond `--color-accent-100`,
un carré 38 px, le son attribué et une `ph-check-circle` cyan-700 ; celui qu'on
attend a une **bordure 1 px tiretée** neutral-500, son carré pulse
(`buzzpulse 1.4s`) et porte un bouton fantôme « Déclarer absent ». Rail droit :
la partie à lancer (jeu, nombre de questions, catégories, chronos) et une liste
de vérifications (`ph-check` cyan pour ce qui est bon, `ph-clock` neutre pour ce
qui reste). Bouton principal « Commencer avec 3 joueurs » — le libellé compte le
nombre réel de présents.
Pop-out : titre 104 px « Buzzez une fois pour entrer dans la partie » et quatre
cartes de présence — trois en `--color-accent-100` marquées « PRÊT », celle qui
manque en bordure **2 px tiretée** avec « ON T'ATTEND ».

**3b — Question lue, personne n'a buzzé.** Même position, même taille de
question que l'état de buzz (1a) : rien ne bouge quand quelqu'un buzze, seul le
bloc du milieu change de contenu. Ici le bloc de jugement est remplacé par trois
carrés `26 × 52 px` à `opacity: .3` qui pulsent en décalé (`buzzpulse 2s`, délais
0 / .25s / .5s), le texte « Personne n'a buzzé » en neutral-700, et l'aide
« Lis la question à voix haute, puis donne le top ». Chrono : label « TOP NON
DONNÉ », valeur en neutral-600, **piste vide sans remplissage**. Actions :
« Donner le top » (principal, `ph-timer`, touche D), « Révéler la réponse »
(secondaire, A), Passer (0), Ambiance (#).
Pop-out : question 96 px, « ATTENDEZ LE TOP », durée en neutral-500, barre vide.

**3c — Révélation.** La question rétrécit à `600 44px/1.1` et passe en
neutral-700 : elle n'est plus le sujet. La réponse devient le sujet, dans un bloc
`--color-accent-2-100` avec **bordure gauche 5 px** `--color-accent-2`, réponse
en `italic 400 52px/1.1` magenta-800. Sous un filet, le verdict :
`ph-x-circle` neutral-600 + « Bleu s'est trompé, chrono épuisé » + le détail du
score. Le rail de dateline affiche « RÉPONSE RÉVÉLÉE » en magenta-700.
Pop-out : **le filet de tête passe en `--color-accent-2`** (unique exception au
filet noir), sur-titre « LA RÉPONSE ÉTAIT » en magenta-700, question rétrécie à
40 px neutral-700, réponse en `italic 400 140px/1.02` magenta-800, puis
« PERSONNE N'A TROUVÉ » en 32 px. Le score du joueur pénalisé affiche « −1 » en
magenta-700 à côté de son nom.

**3d — Point marqué, bascule.** Carré 80 px + « Bleu marque » en 56 px, et à
droite la transition de score chiffrée : `5` en neutral-600 → `ph-arrow-right`
→ `6` en `600 72px` cyan-700. Sous un filet : la question suivante en
`600 36px/1.15` neutral-800, sa réponse en italique magenta (animateur
seulement). Une **barre de progression 6 px** avec « bascule automatique dans
2 s » et trois boutons : passer maintenant (#), rester sur l'écran de score (*),
annuler le point (B).
Pop-out : « Bleu marque » en 132 px, la bonne réponse en 40 px espacé, la
transition `5 → 6` avec le 6 en 128 px. **La question suivante n'apparaît au
public qu'après la bascule.**

#### Tour 2 — un écran par jeu (console + pop-out appairés)

**2a — Vol.** La question est étiquetée « QUESTION POSÉE À » + carré + nom, et
cette étiquette existe aussi sur le pop-out (carré 44 px + « QUESTION POUR
JAUNE » en 42 px). Bloc « droit de réplique ouvert » avec le voleur qui pulse.
Jugement à valeur double : « Vol réussi +2 ». Rail droit : ordre de passage avec
état par joueur (en cours / question 8 / question 9).

**2b — Simon.** La séquence est une rangée de carrés 74 px dans les couleurs des
buzzers ; le pas attendu porte un `outline: 4px solid var(--color-accent-2)` avec
`outline-offset: 3px` et pulse ; les pas futurs sont un carré neutral-300 avec
« ? ». Sous elle, la reproduction en cours : six rectangles `44 × 24 px`,
remplis pour les pas réussis, **bordure tiretée** pour les pas restants.
Record de la soirée dans le rail. Le pop-out ne montre **que** « Manche 6 »
en 130 px, six rectangles `120 × 44 px` (noirs = faits, neutral-300 = à venir)
et « À Bleu de jouer » — jamais les couleurs de la séquence.

**2c — Réflexe.** Le seul jeu où le temps *est* le score. Console : classement
numéroté, carré 34 px, nom 34 px, temps `600 52px` tabular-nums avec l'unité
« ms » en 24 px neutral-600 ; le faux départ remplace le temps par « faux
départ » à `opacity: .55`. Pop-out : le gagnant en 92 px avec son temps en
150 px à droite, puis les autres en barres comparatives (piste
neutral-300, remplissage neutral-600, largeur proportionnelle au temps) —
270 px pour le nom, 190 px pour le temps aligné à droite.

**2d — Chrono aveugle.** Cible en `600 96px` avec les boutons −/+ et
« Au hasard » (`ph-shuffle`) à côté. Écarts **réservés à l'animateur** : ligne
par joueur avec l'instant du buzz et l'écart signé (le meilleur en
magenta-700). Bouton principal « Révéler au public ». Pop-out : « DURÉE À
VISER » + « 12 s » en 140 px, puis les écarts en valeur absolue (le gagnant sur
fond `--color-accent-100` débordant de 22 px à gauche et à droite), et le label
« ÉCART AVEC LA CIBLE » en bas.

**2e — Ne buzze pas.** Console : `ph-speaker-high` 66 px + « Son 14 » en 46 px
+ « Appartient à [carré] Bleu ». File des sons en huit rectangles `52 px` de
large — les joués en neutral-400, **celui en cours en `--color-accent` plus haut
(38 px vs 22 px) avec un `outline: 3px`**, les suivants en neutral-300. Bloc de
faute avec le fautif qui pulse. Les leurres (sons des buzzers absents) sont
mentionnés explicitement. Pop-out : « Rouge est éliminé » en 104 px, puis les
joueurs encore en course sur fond `--color-accent-100` et l'éliminé à
`opacity: .35`.

**2f — Duel.** En-tête « Bleu 1 contre 0 Rouge » avec les carrés en miroir.
Question 46 px, chrono, buzz. Le rail liste les duellistes (« en duel » en
cyan-700), le spectateur, l'absent, et le format (meilleur de 3, chrono 8 s).
Pop-out : question 84 px, buzz, et un **bandeau coupé en deux** — une moitié par
duelliste, score en `600 92px/.9`, la moitié du meneur en `--color-accent-100`.

#### Tour 1 — direction retenue et écrans de configuration

**1a — Console « La Une » (RETENUE).** L'état de référence : question 54 px,
réponse animateur en italique magenta, chrono, bloc de buzz (carré 52 px qui
pulse + « Bleu a buzzé » en 38 px + « Chrono arrêté · les autres buzzers sont
neutralisés »), puis cinq boutons de jugement.

**1b — Console « Table de presse » (ÉCARTÉE).** Conservée dans le canevas pour
mémoire ; ne pas implémenter.

**1c — Pop-out question pleine page (RETENU).** L'état de référence du pop-out.

**1d — Pop-out à colonne de scores (ÉCARTÉ).** Ne pas implémenter.

**1e — Buzzers.** Tableau `.table` du design system, quatre lignes : identité
(carré 18 px + nom + « bouton 5 · LED 6 » en 15 px neutral-600), présence (`.tag
.tag-accent` « Présent » / `.tag .tag-neutral` « Absent »), son avec « Écouter »
(`ph-play`) et « Changer », et un bouton « Allumer » qui teste la LED. La ligne
d'un absent passe à `opacity: .55` et son son devient « — devient un leurre ».
Sous le tableau : attribution des sons (« Sons au hasard » avec `ph-shuffle`,
assistant guidé, chenillard de test) et le volume DFPlayer (22 / 30, barre 8 px
cyan, mention EEPROM).

**1f — Choix du jeu.** Les onze modes en grille 2 colonnes, chacun avec un filet
supérieur 2 px `--color-text`, son nom en `600 23px/1.1` et une phrase de règle.
Le mode actif : filet supérieur `--color-accent-2`, fond `--color-accent-2-100`
débordant de 14 px, et un `.tag .tag-accent-2` « Actif ». Un mode indisponible
(Duel avec trois joueurs) passe à `opacity: .5` avec un `.tag .tag-neutral`
« 2 joueurs » et le motif du refus. Rail droit : description du mode
sélectionné, réglages de durées avec −/+, bouton `.btn-block` « Lancer la
partie ».

**1g — Questions.** Segmenté `.seg` (Banque intégrée / Mes questionnaires / Les
deux). Dix catégories en grille 2 colonnes avec cases cochées (carré 17 px
`--color-accent` avec ✓ blanc) ou vides (carré 17 px bordure neutral-500), et le
décompte « 200 · 46 posées ». Tableau des questionnaires personnels. Rail :
nombre de questions avec −/+ et raccourcis (Ouvert / 10 / 30), explication de
l'anti-répétition avec « 157 sur 600 » et une barre de progression, aperçu de la
prochaine question avec sa réponse.

**1h — Appareil / BLE.** Liste d'appareils : icône `ph-bluetooth-connected`
cyan pour le connecté (ligne sur fond `--color-accent-100` débordant de 14 px,
`.tag .tag-accent` « Connecté », bouton Déconnecter), `ph-bluetooth` neutre pour
les autres avec MAC et RSSI. Rail : compteurs de liaison (messages reçus,
lignes rejetées, âge du dernier message) et la **trame brute** telle qu'elle
arrive.

**1i — Fin de partie.** Deux cadres côte à côte (console 820 × 620, pop-out
560 × 315). Cas d'égalité : les ex æquo portent un `.tag .tag-accent-2`, et le
texte explique le bris d'égalité (seuls les ex æquo peuvent buzzer, LED allumées
pour eux). Deux boutons : lancer le bris d'égalité, accepter l'égalité.

**0a — État actuel.** Recréation de la console Flutter existante (Material 3,
`#fef7ff`, Roboto, cartes à rayon 12 px). Sert de point de comparaison
« avant / après » ; ne pas implémenter.

## Interactions & Behavior

### L'animation unique

Une seule keyframe dans tout le système :

```css
@keyframes buzzpulse {
  0%, 100% { opacity: 1 }
  50%      { opacity: .35 }
}
```

Appliquée en `buzzpulse 1.1s ease-in-out infinite` au carré de couleur du joueur
qui vient de buzzer, à 1.4 s pour le buzzer dont on attend la déclaration (3a),
et à 2 s avec des délais de 0 / .25 / .5 s sur les trois carrés atténués de
l'état « personne n'a buzzé » (3b). C'est délibérément la seule animation :
l'attention de la salle est une ressource rare.

### États d'interaction

Ne pas restyler ce que le design system fournit déjà : survol et état pressé
viennent des rampes d'accent, le focus clavier est un anneau
`2px solid var(--color-accent)` avec `outline-offset: 2px`, la sélection de
texte est une teinte d'accent, et les contrôles désactivés tombent à 45 %
d'opacité. Il **faut** un focus visible partout : l'animateur travaille au
clavier, pas à la souris.

### Le flux d'une question (Chrono pénalité)

1. **Question armée** (3b) — question affichée, chrono à sa valeur pleine mais
   piste vide, buzzers armés. L'animateur lit à voix haute.
2. **Top donné** (touche D) — le chrono se vide, la barre magenta décroît.
3. **Buzz** (1a) — le firmware neutralise les autres buzzers, joue le son du
   buzzeur, arrête le chrono. La console montre qui a la main et propose le
   jugement.
4. **Jugement** (A / D) — score modifié.
   - Bonne réponse → **3d**, célébration 2 s, bascule vers la question suivante.
   - Mauvaise réponse → soit le chrono des réponses suivantes redémarre pour les
     autres (5 s), soit plus personne ne trouve → **3c** révélation.
5. **Révélation** (3c) — la réponse part vers le pop-out. « Masquer la réponse »
   la reprend.
6. Retour en 1.

Le firmware possède déjà cette machine à états (`STATE|8` dans la trame). L'app
doit **la refléter, pas la dupliquer** : la source de vérité reste l'Arduino.
Les commandes envoyées depuis l'app sont des équivalents des touches du clavier
matriciel.

### Comportement du pop-out

- Bouton « Détacher · écran 2 » dans le rail droit de la console. Une fois
  détaché, le bouton devient un état (« Écran public actif · réattacher »).
- La vignette du rail droit reste synchronisée et montre exactement le contenu
  de la seconde fenêtre — elle sert de contrôle de sécurité avant de révéler
  quoi que ce soit.
- Le pop-out n'a **aucun contrôle** : ni bouton, ni curseur, ni raccourci. Il ne
  reçoit que de l'état.
- La fenêtre doit se souvenir de l'écran sur lequel elle a été placée et y
  revenir à la session suivante.
- Prévoir une sortie plein écran propre (masquer le curseur après 3 s
  d'inactivité).

### Règles de confidentialité (à tester explicitement)

| Donnée | Console | Pop-out |
| --- | --- | --- |
| Réponse attendue | toujours visible | seulement après « Révéler » |
| Séquence Simon | visible | jamais (longueur seule) |
| Écarts du Chrono aveugle | visibles | seulement après « Révéler » |
| Numéro du son (Ne buzze pas) | visible | jamais |
| Question suivante | visible dès 3d | seulement après la bascule |
| Historique anti-répétition | visible | jamais |

## State Management

État partagé entre les deux fenêtres (source de vérité : l'Arduino, via BLE) :

- `connection` : `{ deviceName, address, connected, rssi, messagesReceived, messagesRejected, lastMessageAt }`
- `buzzers[4]` : `{ color, present, soundId, armed, hasFloor, score }`
- `activeGame` : identifiant parmi les onze modes + ses réglages
  (`firstAnswerSeconds`, `nextAnswerSeconds`, `volume`, `roundsFormat`,
  `targetSeconds`, `soundInterval`, `decoysEnabled`…)
- `question` : `{ index, total, category, text, answer, revealed }`
- `chrono` : `{ totalSeconds, remainingSeconds, running, started }`
- `phase` : `idle | roster | armed | counting | buzzed | judged | revealed | betweenQuestions | tiebreak | finished`
- `buzzEvent` : `{ buzzerId, at }` — qui a la main
- `gameSpecific` : séquence Simon et progression, temps de réflexe par joueur,
  écarts du chrono aveugle, file des sons et éliminés, duellistes et manches
- `questionBank` : catégories cochées, questionnaires personnels, historique
  anti-répétition (miroir de l'EEPROM)
- `log[]` : `{ at, text }` — le journal de la colonne droite en 1b, utile même
  si 1a ne l'affiche pas
- `popout` : `{ attached, displayId, logoImage, partyTheme }`

Transitions déclenchées par : (a) une trame BLE entrante, (b) une action de
l'animateur qui envoie une commande au firmware, (c) l'expiration d'un
minuteur local (bascule 2 s de 3d).

### Protocole BLE

Le firmware envoie des lignes en clair sur `Serial2`, 9600 bauds. Les maquettes
en montrent la forme (écran 1h) :

```
STATE|8
BUZZ|1
SCORE|4|6|3|0
PRESENT|1|1|1|0
GAME|3
CFG_SOUND|1|3
```

Points relevés dans le code existant à conserver : les lignes sont parsées
individuellement ; une ligne tronquée pendant une reconnexion doit être
**ignorée** plutôt que de fausser l'état ; l'app se reconnecte au dernier
appareil connu au démarrage.

Le sens app → firmware n'existe pas encore : le client veut un **pilotage
complet depuis l'app**, il faudra donc étendre le firmware avec des commandes
entrantes correspondant aux touches du clavier matriciel. À cadrer avec le
propriétaire du firmware avant de coder l'UI de pilotage.

## Assets

- **Icônes** : Phosphor duotone via CDN. À vendorer dans le codebase cible.
- **Police** : Source Serif 4, chargée par `styles.css` du design system.
- **Logo de soirée** : emplacement vide (`118 × 44 px`, bordure tiretée) que
  l'utilisateur remplit. Aucun fichier fourni — prévoir l'import.
- **Sons** : sur la carte SD du DFPlayer, six dossiers. L'app les référence par
  numéro, elle ne les héberge pas.
- Aucune photographie dans ces écrans. Le design system propose des traitements
  d'image (`.cmyk`, `.halftone`) non utilisés ici.

## Files

| Fichier | Contenu |
| --- | --- |
| `Buzzer Console.dc.html` | Le canevas complet : tous les écrans des trois tours |
| `support.js` | Runtime nécessaire pour ouvrir le canevas dans un navigateur |
| `_ds/broadsheet-.../styles.css` | **Source de vérité des tokens** — tous les `var(--*)` |
| `_ds/broadsheet-.../_ds_bundle.js` | Composants du design system |
| `_ds/broadsheet-.../readme.md` | Guide du design system : règles à respecter |
| `_ds/broadsheet-.../theme.json` | Paramètres du thème, lisibles par machine |

Ouvre `Buzzer Console.dc.html` dans un navigateur pour voir les écrans. Le
canevas se navigue par ancre : `#3a`, `#2b`, `#1c`… correspondent aux badges
visibles.

Le firmware et l'app Flutter existants ne sont **pas** dans ce paquet : ils sont
dans le dépôt du projet (`Buzzer/`, `Buzzer/app/buzzer_companion/`).

## Ordre d'implémentation suggéré

1. Trancher Flutter desktop vs web (voir *About the Design Files*).
2. Poser les tokens Broadsheet et le châssis de console — barre latérale, rail
   de dateline, colonne centrale, rail droit. Rien d'autre ne fonctionne sans.
3. Le pop-out et sa synchronisation, avec la vignette de contrôle.
4. Le flux d'une question en Chrono pénalité : 3b → 1a → 3d → 3c. C'est 80 % de
   l'usage réel.
5. Les écrans de configuration : 1e buzzers, 1f jeux, 1g questions, 1h appareil.
6. Le démarrage 3a et la fin de partie 1i.
7. Les jeux spécifiques, dans cet ordre de valeur : 2c Réflexe (le plus simple),
   2a Vol, 2f Duel, 2d Chrono aveugle, 2e Ne buzze pas, 2b Simon (le plus
   complexe).

## Questions ouvertes pour le propriétaire du projet

- Flutter desktop ou bascule web ? (bloque tout le reste)
- Le firmware acceptera-t-il des commandes entrantes, et sous quel format ?
- Les questionnaires personnels vivent-ils dans l'app seule, ou doivent-ils
  monter dans le Mega ?
- L'historique anti-répétition doit-il rester en EEPROM, ou l'app en devient-elle
  la gardienne ?
- Le logo de soirée : image seule, ou thème complet (couleurs de la soirée) ?
