---
name: ecrire-des-questions
description: Écrire de nouvelles questions pour la banque du Buzzer, sans doublon, avec les faits vérifiés à l'extérieur et l'adaptation québécoise. À utiliser quand on demande d'ajouter, d'écrire, de créer ou de compléter des questions, un lot de questions, une catégorie ou une thématique du jeu-questionnaire.
---

# Écrire des questions

La banque compte 3684 questions relues une par une. Un lot écrit vite y
laisse des traces qui ne se voient qu'en soirée, devant du monde. Cette
procédure existe pour que ça n'arrive pas.

## Pourquoi c'est fragile, avec les preuves

Quatre choses ratent en silence. Chacune a déjà mordu ici.

**1. Ma mémoire EST la source des erreurs.** Se relire ne détecte rien,
parce que le souvenir que je crois sûr est justement ce qui est faux. Sur
1746 affirmations vérifiables, en filtrant pourtant au fil de l'écriture :
treize faits faux. Passe-Montagne décrit comme barbu, Bluey dite beagle, la
mésange dite bleue, la mouffette qui « fait le mort » (c'est l'opossum),
BIXI qui compterait cinq lettres, Cartier qui remonterait le fleuve en 1534.

**2. Écrire pour atteindre un nombre fabrique des doublons.** Chaque fois
qu'un lot a été écrit pour compléter une catégorie à 200, il a produit des
quasi-doublons : 45 variantes de nom en un seul commit. **Le nombre demandé
est un plafond, jamais une cible.** Rendre 22 bonnes questions sur 30
demandées est un succès ; en rendre 30 dont 8 redites est un échec qui se
paiera en soirée.

**3. Le doublon ne se voit pas en se relisant.** Deux questions au texte
différent qui attendent la même réponse passent la relecture sans broncher
et se posent deux fois dans la même manche. Seul le générateur les voit.

**4. Un titre de France passe pour du français.** *Cars* s'appelle **Les
Bagnoles** ici, *Inside Out* **Sens dessus dessous**, *Finding Dory*
**Trouver Doris**. Écrire le titre français de France dans un jeu québécois,
c'est poser une question dont personne dans le salon ne connaît la réponse.

## Où ça vit

`app/buzzer_companion/tool/questions/<categorie>.txt`, onze fichiers. Chacun
a deux blocs séparés par `=== hors firmware ===` :

- **Avant le séparateur, le MIROIR de `Questions.cpp`.** Ligne pour ligne,
  dans l'ordre. Le générateur vérifie que retirer les accents redonne la
  source du firmware au caractère près, et s'arrête sinon. **On n'y ajoute
  jamais rien.** Une question du firmware se corrige avec un `>` en dessous,
  jamais en réécrivant sa ligne.
- **Après le séparateur, le bloc LIBRE.** C'est là que vont les nouvelles
  questions.

Format d'une ligne, des deux côtés :

```
Question|Réponse|niveau|tranches
> Question|Réponse     retouche la ligne du dessus, servie à sa place
- motif                la retire du catalogue
@ noel creatures       ses thématiques
```

`niveau` vaut 1 (facile), 2 (moyen) ou 3 (difficile), **lu à l'intérieur de
la tranche** : un enfant niveau 3 existe, un aîné niveau 1 aussi.
`tranches` est une liste parmi `enfants ados adultes aines`, séparée par des
espaces. Les quatre veulent dire « tout le monde », et c'est le cas courant.

Les douze slugs de thématique : `noel regne-animal espace corps-humain
super-heros creatures sports-hiver regne-vegetal mer transports disney
nostalgie`. Un slug inconnu arrête la génération.

**Rien n'est déduit.** Le niveau, les tranches et les thématiques s'écrivent
sur chaque question. Les thématiques l'ont été par mots-clés, et « neige »
rangeait Blanche-Neige dans Sports d'hiver.

### La question s'écrit en français soigné

Elle est lue à voix haute et s'affiche sur l'écran public : elle se compose
comme une phrase de journal, pas comme une note.

Les conventions ci-dessous ne sont pas des préférences : elles ont été
relevées dans les 3684 questions de la banque, et les chiffres sont là pour
qu'on puisse les revérifier au lieu de me croire.

- **Tous les accents, majuscules comprises.** `À`, `Ê`, `Ç`. Le seul endroit
  du projet qui s'en passe est le firmware, et le bloc miroir le reflète
  déjà : le générateur vérifie que la version accentuée redonne la source
  une fois dépouillée, et s'arrête sinon.
- **Espace ORDINAIRE avant le `?`**, pas insécable. `Quelle est la capitale
  du Québec ?` — 3681 questions sur 3684, zéro insécable. Un `?` collé au
  mot n'existe nulle part.
- **Une majuscule au début, un `?` à la fin.** Trois exceptions dans toute
  la banque, toutes voulues : `Citez un palindrome de cinq lettres qui
  flotte.`, `Complétez : ...`, et une citation dont le `?` est dans les
  guillemets.
- **La réponse ne prend pas de point final.** `La poutine`, pas `La
  poutine.` La seule qui en porte est `E.T.`, où le point fait partie du nom.
- **La réponse porte son article** quand on le dirait à l'oral : `Le
  castor`, `Les Patriotes`, `Six`.
- **Guillemets français** « comme ceci », 41 fois dans la banque. Aucun
  guillemet droit.
- **Apostrophe droite `'`**, jamais la typographique `’`. 954 contre 0. Le
  bloc miroir l'exige — l'invariant des accents ne convertit pas `’` en `'`
  et s'arrêterait — et le bloc libre suit, pour que les deux se cherchent
  pareil.
- **Pas de barre verticale dans le texte** : `|` sépare les champs et
  couperait la ligne en deux.

Le doute se lève en regardant les voisines : `--chercher` sort les questions
existantes telles qu'elles sont écrites, et elles ont toutes été relues.

## 1. Cadrer, et le dire

Avant d'écrire une ligne, fixer et annoncer : **quelle catégorie**, **combien
au maximum**, **quel niveau**, **quelles tranches**, **quelles thématiques**.

Si la demande est vague (« des questions de cinéma »), choisir des valeurs
et les annoncer plutôt que de demander. Si elle est contradictoire (« 40
questions faciles pour les aînés en Sciences »), le dire avant d'écrire, pas
après.

## 2. Relever les compteurs AVANT

```bash
cd app/buzzer_companion && dart run tool/generate_questionnaires.dart
```

La dernière ligne du contrôle donne quatre nombres. Les noter :

```
Contrôle : N réponses déjà dans leur question, N réponses partagées par
plusieurs questions, N quasi-doublons, N variantes de nom.
```

Repère au 5 septembre 2026 : **54, 215, 0, 14**. Ce sont eux qui serviront
de preuve à l'étape 7. Sans le relevé d'avant, l'après ne prouve rien.

## 3. Reconnaître le terrain

**Le geste qui évite le plus de dégâts.** Avant d'écrire une question,
chercher son sujet dans la banque :

```bash
cd app/buzzer_companion && dart run tool/generate_questionnaires.dart --chercher "coupe stanley"
```

Les mots cherchés se tapent comme on veut : `quebecoise` trouve
`québécoise`. C'est la RECHERCHE qui ignore les accents et la casse, pas les
questions, qui ressortent telles qu'elles sont écrites. Chaque résultat
donne la catégorie, le niveau, les tranches et les thématiques.

Chercher **au moins deux mots par question** : la réponse, et le nom
principal de l'énoncé. « rondelle » ne trouve pas « puck », « érable » ne
trouve pas « acériculteur ». Une recherche qui ne rend rien ne prouve pas
que le terrain est libre, elle prouve que ce mot-là n'y est pas.

Sur un gros lot, commencer par balayer la catégorie entière : la revue
publiée (`site/revue.html`) montre les 3684 questions par catégorie sur une
page, filtrables.

**Attention au premier résultat.** Le préfixe `Running build hooks...` n'a
pas de saut de ligne et colle la première ligne de sortie. Ne jamais filtrer
avec `grep -v "^Running"` : ça mange un résultat.

## 4. Écrire, par lots courts

Dix à quinze questions à la fois, pas davantage. La qualité tombe dans la
longueur, et c'est en fin de lot que naissent les redites.

Les règles de contenu, toutes tirées de remarques du client :

- **La réponse doit s'entendre.** Le jeu se joue à l'oral : l'animateur lit,
  le joueur crie. « Pluriel de bijou ? Bijoux » ne se juge pas à l'oreille.
  Une question d'orthographe se reformule (« prend un S ou un X ? »).
- **Une seule réponse possible.** « Qui a cofondé Microsoft ? » accepte
  Gates ou Allen : verrouiller l'énoncé plutôt que d'accepter les deux.
- **La réponse n'est pas dans la question.** « Quel insecte à miel fabrique
  le miel ? » se répond sans savoir.
- **Rien de périssable.** Un record qu'on va battre, un joueur qui change
  d'équipe, « l'actuel premier ministre », « le plus récent film de ». La
  question doit être aussi vraie dans cinq ans.
- **Pas de politique américaine** ni rien de proche : présidents,
  Maison-Blanche, drapeau, droits civiques, OTAN, 11 septembre. La culture
  américaine reste entière (cinéma, musique, sport).
- **Viser 7 à 77 ans.** Culture générale de jeu de société.

## 5. Vérifier les faits, à l'extérieur

**Ce qui porte un nom propre, une date, un record ou une mesure passe par
WebSearch. Sans exception, et jamais par ma mémoire.**

Trois formes ont déjà mordu, à chercher activement :

1. **Le détail attribué à une entité réelle.** La couleur d'un oiseau, la
   race d'un chien de dessin animé, la barbe d'un personnage. Ne jamais
   décrire de mémoire : demander plutôt un nom, une relation, un usage.
2. **La donnée périmée.** Adresse, nom de commerce, numéro de route, nom
   d'organisme. L'autoroute 720 est devenue la route 136 en 2021.
3. **La date approchée.** Cartier atteint le golfe en 1534 et remonte le
   fleuve en 1535. « Environ » ne se joue pas au buzzer.
4. **Le titre d'une œuvre, en version québécoise.** Un titre EST un fait, et
   il se vérifie ici comme les autres, pas dans une passe de finition à la
   fin. Voir l'étape 6 pour ce qu'il faut chercher.

**Ce qui ne se vérifie pas ne s'écrit pas.** Une bonne question qu'on
n'arrive pas à confirmer se jette ; il en reste des milliers d'autres.

Le vocabulaire, les définitions et les usages ne peuvent pas être faux et ne
demandent rien : « Que signifie magasiner ? » n'a pas besoin de source.

## 6. Adapter au Québec

### Le titre d'une œuvre, c'est celui qu'on crie ici

**La réponse attendue est le nom que le joueur va dire dans le salon**, pas
la traduction la plus correcte. Le doublage québécois et celui de France
diffèrent, et c'est le québécois qui joue.

Déjà dans la banque, tous vérifiés : *Cars* est **Les Bagnoles**,
*Inside Out* est **Sens dessus dessous**, *Finding Dory* est **Trouver
Doris**, *Up* est **Là-haut**, *The Incredibles* est **Les Incroyables**.

- **Ça vaut pour tout ce qui porte un titre** : films, séries, dessins
  animés, livres, jeux vidéo, chansons. Pas seulement le cinéma.
- **Chercher `titre québécois <œuvre>`**, jamais se fier au titre français
  qui vient en tête : c'est presque toujours celui de France.
- **Souvent les deux titres sont identiques**, et il n'y a rien à faire.
  C'est la vérification qui le dit, pas l'intuition.
- **Parfois c'est le titre anglais qui est en usage ici.** Alors c'est lui
  la réponse. « Le bon français » n'est pas le critère ; ce que la salle va
  crier l'est.

**Si DEUX noms sont réellement en usage au Québec, la question est
ambiguë** : un joueur qui donne l'autre se fait refuser alors qu'il a
raison. C'est exactement ce que compte le compteur « variantes de nom » de
l'étape 7, et il ne doit pas augmenter. Deux sorties : verrouiller l'énoncé
pour n'en rendre qu'un possible, ou changer de question.
- **Le vocabulaire est d'ici.** Dîner le midi, souper le soir, magasiner,
  char, tuque, mitaines. Éviter les tournures de France même correctes.
- **Les unités sont métriques**, la monnaie en dollars.
- **Les distances et les repères partent d'ici.** « À quelle distance de
  Montréal » plutôt que de Paris.

## 7. Repasser les compteurs, et comparer

```bash
cd app/buzzer_companion && dart run tool/generate_questionnaires.dart
```

**Quatre barrières. Aucune ne se franchit en expliquant.**

| compteur | règle |
|---|---|
| le générateur | doit sortir en **code 0**. Un doublon exact ou un miroir cassé l'arrête. |
| **quasi-doublons** | doit rester à **0**. Il n'a aucun cas légitime : quand il en sort un, une des deux lignes est de trop. Le générateur les affiche en détail. |
| **variantes de nom** | ne doit **pas augmenter**. Deux réponses qui désignent la même chose font refuser un joueur qui a raison. |
| échos et réponses partagées | peuvent monter un peu. Pour **chaque** unité de hausse, nommer la question responsable et dire pourquoi elle est légitime. Une hausse non expliquée veut dire qu'un lot est entré sans contrôle. |

Sur les échos, un second avis :

```bash
node app/buzzer_companion/tool/antiscrap.js
```

Il compte la même chose que le premier compteur du générateur, avec une
règle un peu plus large : **55 contre 54** au 5 septembre 2026. L'écart est
normal ; c'est le mouvement des deux qui compte, pas leur égalité.

Si une barrière tombe, **retirer des lignes**. Ne jamais garder une question
en se disant que le compteur exagère.

## 8. Fermer

```bash
cd app/buzzer_companion && flutter analyze && flutter test
```

Puis, si le lot touche à ce que suit `tool/questions/INTEGRITE.md` (les
repères de compteurs, l'état des chantiers), le mettre à jour.

Le commit dit **combien de questions demandées, combien écrites, et
pourquoi l'écart**. Un lot rendu court est une information, pas une excuse.

## Ce qu'on ne fait jamais

- Toucher `Questions.cpp` ou une ligne du bloc miroir.
- Écrire une question sans niveau ni tranches explicites.
- Compléter un lot avec du remplissage pour atteindre le nombre demandé.
- Affirmer un fait vérifiable sans l'avoir vérifié à l'extérieur.
- Annoncer un lot conforme sans montrer les quatre compteurs avant et après.
