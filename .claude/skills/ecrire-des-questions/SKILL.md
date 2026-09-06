---
name: ecrire-des-questions
description: Écrire de nouvelles questions pour la banque du Buzzer, sans doublon, avec chaque fait vérifié à l'extérieur et consigné, et la réponse telle qu'on la dit au Québec. À utiliser quand on demande d'ajouter, d'écrire, de créer ou de compléter des questions, un lot de questions, une catégorie ou une thématique du jeu-questionnaire.
---

# Écrire des questions

La banque compte 3875 questions relues une par une. Une seule affirmation
fausse fait perdre au jeu son autorité : quelqu'un dans le salon va le
savoir, et à partir de là il doute de tout le reste. Cette procédure existe
pour qu'aucun lot n'entre sans avoir passé les mêmes barrières que les 3875.

**Une question qui n'a pas franchi toutes les étapes n'entre pas.** Il n'y a
pas de « presque ».

## Pourquoi c'est fragile, avec les preuves

Cinq choses ratent en silence. Chacune a déjà mordu ici.

**1. Ma mémoire EST la source des erreurs.** Se relire ne détecte rien,
parce que le souvenir que je crois sûr est justement ce qui est faux. Sur
1746 affirmations vérifiables, en filtrant pourtant au fil de l'écriture :
treize faits faux. Passe-Montagne décrit comme barbu, Bluey dite beagle, la
mésange dite bleue, la mouffette qui « fait le mort » (c'est l'opossum),
BIXI qui compterait cinq lettres, Cartier qui remonterait le fleuve en 1534.
**Tous étaient des attributs** collés à une entité réelle. L'entité
existait ; le détail était inventé.

**2. Écrire pour atteindre un nombre fabrique des doublons.** Chaque fois
qu'un lot a été écrit pour compléter une catégorie à 200, il a produit des
redites : 45 variantes de nom en un seul commit. **Le nombre demandé est un
plafond, jamais une cible.** Rendre 22 bonnes questions sur 30 demandées est
un succès ; en rendre 30 dont 8 redites est un échec qui se paiera en soirée.

**3. Le doublon ne se voit pas en se relisant.** Deux questions au texte
différent qui attendent la même réponse passent la relecture et se posent
deux fois dans la même manche. Et le compteur qui les attrape **ne regarde
qu'à l'intérieur d'une catégorie** : « Quel plat québécois combine frites,
fromage et sauce ? » dans Québec et « Quel plat de frites disparaît sous le
fromage et la sauce brune ? » dans Bouffe donnent tous deux *La poutine*, et
il ne le voit pas. Seule la recherche préalable le voit.

**4. Un titre de France passe pour du français.** *Cars* s'appelle **Les
Bagnoles** ici, *Inside Out* **Sens dessus dessous**, *Finding Dory*
**Trouver Doris**. Le titre français qui vient en tête est presque toujours
celui de France.

**5. Ce qui est vrai aujourd'hui.** Une autoroute renumérotée, un commerce
fermé, un record battu. L'autoroute 720 est devenue la route 136 en 2021 et
la question l'affirmait encore.

## Ce qu'est une bonne question

Le jeu se joue dans un salon, à l'oral, entre 7 et 77 ans. Le test : **au
moins une personne dans la pièce sait, et les autres se disent « ah oui ! »
en entendant la réponse.** Pas « qui aurait pu savoir ça », pas « c'est
évident ».

Ce qui n'en est pas, et qu'on appelle ici de la scrap :

- Le détail que personne n'a jamais retenu (le deuxième prénom, l'année
  exacte d'un fait mineur, le nombre d'épisodes).
- La question dont la forme donne la réponse (« Quel insecte à miel fabrique
  le miel ? »).
- La reformulation d'une question qui existe déjà, sous d'autres mots.
- La devinette à réponse ouverte, qu'on ne peut juger ni au son ni au sens.
- La question écrite pour arriver au compte.

## Où ça vit

`app/buzzer_companion/tool/questions/<categorie>.txt`, onze fichiers. Chacun
a deux blocs séparés par `=== hors firmware ===` :

- **Avant le séparateur, le MIROIR de `Questions.cpp`.** Ligne pour ligne,
  dans l'ordre. Le générateur vérifie que retirer les accents redonne la
  source du firmware au caractère près, et s'arrête sinon. **On n'y ajoute
  jamais rien.** Une question du firmware se corrige avec un `>` en dessous,
  jamais en réécrivant sa ligne.
- **Après le séparateur, le bloc LIBRE.** Les nouvelles questions vont
  **à la fin** de ce bloc.

Format d'une ligne, des deux côtés :

```
Question|Réponse|niveau|tranches
> Question|Réponse     retouche la ligne du dessus, servie à sa place
- motif                la retire du catalogue
@ noel creatures       ses thématiques
```

### Niveau, tranches, thématiques : trois jugements, tous écrits

**Rien n'est déduit.** Les thématiques l'ont été par mots-clés, et « neige »
rangeait Blanche-Neige dans Sports d'hiver. Chaque question porte les trois,
écrits par quelqu'un qui a décidé.

- **`tranches`** dit **de quel monde vient la question**, pas qui peut y
  répondre. Minecraft vient du monde des enfants et des ados ; Steinberg du
  monde des aînés ; la capitale du Québec, de tout le monde. Liste parmi
  `enfants ados adultes aines`, séparée par des espaces. **Les quatre est le
  cas courant**, et on ne marque que les exceptions.
- **`niveau`** dit la difficulté **à l'intérieur de ce monde** : 1 si
  quelqu'un qui vit dans ce monde répond sans effort, 2 pour la culture
  générale ordinaire, 3 pour le connaisseur. Les deux axes sont
  indépendants : « Quel petit âne de dessin animé français est très
  curieux ? → Trotro » est coté **enfants, niveau 3** — leur monde à eux,
  et pourtant peu le savent ; « La Vie en rose → Édith Piaf » est coté
  **adultes et aînés, niveau 1**.

Ces quatre exemples viennent de la banque, relus avec `--chercher`. Le
précédent brouillon de ce skill en citait un de mémoire, et il était faux.
- **`@ slug`** pour chaque thématique dont la question relève. Les onze
  qui traversent la banque : `noel regne-animal espace corps-humain
  super-heros creatures mer transports disney nostalgie voyages`. Un slug
  inconnu arrête la génération. Le critère est le SUJET de la question, pas
  un mot qu'elle contient : une question sur Blanche-Neige n'est pas un
  sport d'hiver, et « Quel légume mariné accompagne le burger ? » a pour
  sujet le burger.

  **Les onze catégories sont aussi des thématiques**, sous le nom de leur
  fichier : `bouffe-et-cuisine cinema-et-tele culture-generale culture-pop
  geographie histoire mots-et-langue musique quebec sciences-et-nature
  sports`. Chaque question porte celle de son fichier SANS qu'on l'écrive —
  la catégorie n'est pas devinée, c'est le fichier qui la déclare, et la
  thématique l'absorbe. **Ne jamais écrire le slug de la catégorie sous une
  question de son propre fichier** : ce serait redire ce qui est déjà là. On
  ne l'écrit que sur une question d'un AUTRE fichier qui parle du même
  sujet — « @ quebec » sous une question québécoise rangée dans Culture pop.

### Bonifier une thématique, ou en ouvrir une

**L'étiquette coûte moins cher que la question, et vaut autant.** La
thématique Voyages compte 113 questions : 27 ont été écrites, **86 étaient
déjà dans la banque** sans l'étiquette. Sur un lot de thématique, le premier
travail n'est donc pas d'écrire, c'est de **relire les candidates** :

```bash
cd app/buzzer_companion && dart run tool/generate_questionnaires.dart --proposer <slug>
```

Les mots-clés de la thématique ne servent qu'à ça, et ils ratissent large :
sur 212 candidates proposées à Voyages, 86 ont été retenues. La liste se
relit une par une, comme un lot.

**Une thématique neuve ne refait pas une catégorie.** « Le Québec ailleurs »
a été supprimée pour ça, et Voyages a frôlé le même sort : elle touche
Géographie et ses 360 questions. La frontière s'écrit **dans le code**,
au-dessus du thème, en disant ce qui est dedans ET ce qui est dehors. Pour
Voyages : dedans le départ, le séjour et ce qu'on visite ; dehors les
capitales, les frontières et les superficies, qui sont le cœur de la
catégorie. Sans cette ligne écrite, la thématique dérive vers son voisin au
fil des lots.

**Une seule question par lieu, par œuvre, par personne.** Le Louvre en avait
deux, le Taj Mahal deux, la tour Eiffel trois, Gizeh cinq. Une manche de dix
questions tirées dans la thématique reposait deux fois le même monument.
Quand plusieurs existent, garder celle **dont la réponse EST le sujet** :
« Quelle grande statue verte tient une torche à l'entrée d'un port
américain ? » plutôt que « Quel pays a offert la statue de la Liberté ? ».

**Une question peut porter plusieurs thématiques**, et il faut le faire : 21
des 113 questions de Voyages en portent une autre, le pont de la
Confédération `voyages transports mer`, le canal Rideau `voyages
sports-hiver`. Le critère reste le SUJET : l'île Bonaventure n'a pas pris
`regne-animal` parce que le sujet est l'île, et les fous de Bassan ne sont
qu'un attribut.

**Fusionner deux thématiques, c'est TRANSFÉRER puis retirer.** `Sports
d'hiver` a fondu dans `sports` et `Le règne végétal` dans
`sciences-et-nature`. Les étiquettes posées sur des questions du fichier
absorbeur sont redondantes et disparaissent ; **celles qui vivaient ailleurs
doivent être re-étiquetées AVANT le retrait**, sinon la fusion perd des
questions au lieu d'en gagner : 20 des 69 `sports-hiver` étaient dans
Québec, Géographie et Culture pop. Dans l'ordre :

1. relever où vivent les étiquettes du slug qui part, fichier et rang ;
2. `--etiqueter <cible>` sur celles qui sont hors du fichier absorbeur ;
3. `--retirer <slug qui part>`, qui nettoie tous les fichiers ;
4. sortir la thématique de `kThemes` — **dans cet ordre**, le lecteur refuse
   un slug inconnu et s'arrêterait sur un dépôt qu'on ne peut plus nettoyer ;
5. déplacer ses mots-clés dans la thématique cible, pour que `--proposer`
   continue de trouver le sujet dispersé.

**Une fusion se juge question par question quand les deux thématiques ne se
recouvrent pas exactement.** Un sport d'hiver est un sport : les 69
étiquettes ont suivi sans discussion. Le végétal, non : 28 des 58 étiquettes
hors de Sciences étaient des légumes DE RECETTE rangés dans Bouffe, et une
manche de Sciences qui pose le cornichon du burger se fait reprendre. 34 sont
entrées, 24 sont restées dans Bouffe sans étiquette de plante. C'est une
perte, elle est assumée, et elle est écrite dans le code au-dessus de la
thématique.

**Le slug d'une catégorie ne s'écrit jamais dans son propre fichier.** Le
générateur s'arrête et nomme les fautives. On ne l'écrit que sur une question
d'un AUTRE fichier : `@ quebec` sous « Quel objet orange envahit les rues de
Montréal chaque été ? », rangée dans Culture pop.

### La question s'écrit en français soigné

Elle est lue à voix haute et s'affiche sur l'écran public. Les conventions
ci-dessous ont été **relevées dans la banque**, chiffres à l'appui, pour
qu'on puisse les revérifier au lieu de me croire.

- **Tous les accents, majuscules comprises.** `À`, `Ê`, `Ç`.
- **Espace ORDINAIRE avant le `?`**, pas insécable. `Quelle est la capitale
  du Québec ?` : 3681 questions sur 3684, zéro insécable, zéro `?` collé.
- **Une majuscule au début, un `?` à la fin.** Trois exceptions voulues dans
  toute la banque : `Citez un palindrome de cinq lettres qui flotte.`,
  `Complétez : ...`, et une citation dont le `?` est dans les guillemets.
- **La réponse ne prend pas de point final.** `La poutine`, pas `La
  poutine.` Seule exception : `E.T.`, où le point fait partie du nom.
- **La réponse porte son article** quand on le dirait à l'oral : `Le
  castor`, `Les Patriotes`, `Six`.
- **Guillemets français** « comme ceci ». 41 dans la banque, aucun droit.
- **Apostrophe droite `'`**, jamais `’`. 954 contre 0. L'invariant des
  accents du bloc miroir ne convertit pas `’` et s'arrêterait ; le bloc libre
  suit, pour que les deux se cherchent pareil.
- **Pas de `|` dans le texte** : c'est le séparateur de champs.

Le doute se lève en regardant les voisines : `--chercher` sort les questions
existantes telles qu'elles sont écrites.

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

Deux lignes du contrôle donnent cinq nombres. Les noter tels quels :

```
Contrôle : N réponses déjà dans leur question, N réponses partagées par
plusieurs questions, N quasi-doublons, N variantes de nom.
Sources : N question exigée sans source, N orpheline, N consignée.
```

Ce relevé est la moitié de la preuve de l'étape 8. Les repères historiques
sont dans `tool/questions/INTEGRITE.md`, pas ici : ils changent à chaque lot.

## 3. Reconnaître le terrain

**Le geste qui évite le plus de dégâts**, et le seul qui voie les redites
entre catégories. Avant d'écrire une question, chercher son sujet :

```bash
cd app/buzzer_companion && dart run tool/generate_questionnaires.dart --chercher "coupe stanley"
```

Les mots se tapent comme on veut : `quebecoise` trouve `québécoise`. C'est la
RECHERCHE qui ignore accents et casse ; les questions ressortent telles
qu'écrites, avec catégorie, niveau, tranches et thématiques.

Trois recherches par question, pas une :

1. **La réponse.** Si elle existe déjà, la nouvelle question la partagera,
   et il faut que ce soit voulu.
2. **Le sujet de l'énoncé**, par son nom principal. « rondelle » ne trouve
   pas « puck », « érable » ne trouve pas « acériculteur » : chercher aussi
   le synonyme.
3. **La forme de la réponse.** Si la banque dit `Le pont Jacques-Cartier`,
   ne pas écrire `Jacques-Cartier` : deux noms pour la même chose font
   refuser un joueur qui a raison, et c'est un compteur qui monte.
4. **Le sujet SANS son mot générique.** Chercher `132` et non `route 132`,
   `Bonaventure` et non `île Bonaventure`, `Confédération` et non `pont de
   la Confédération`. C'est la recherche qui manque le plus souvent, et elle
   a coûté sept questions au lot Voyages : écrites, vérifiées, sourcées, puis
   jetées parce que la banque les avait déjà sous un autre habillage.
   « route 132 » ne trouve pas « Quelle route ceinture la péninsule
   gaspésienne ? », dont la réponse est `La 132`.

Une recherche vide ne prouve pas que le terrain est libre. Elle prouve que
ce mot-là n'y est pas.

**Quand la banque l'a déjà, on l'étiquette au lieu de l'écrire.** C'est le
même résultat pour la thématique, zéro ligne ajoutée, et zéro fait de plus à
vérifier.

Sur un gros lot, **lire d'abord le fichier de la catégorie** en entier,
`tool/questions/<categorie>.txt`, les deux blocs. C'est la source, à jour,
retouches comprises.

**Attention au premier résultat.** Le préfixe `Running build hooks...` n'a
pas de saut de ligne et colle la première ligne de sortie. Ne jamais filtrer
avec `grep -v "^Running"` : ça mange un résultat.

## 4. Rédiger le lot, dans la réponse et pas dans le fichier

Dix à quinze questions à la fois. La qualité tombe dans la longueur, et c'est
en fin de lot que naissent les redites.

**Rien ne s'écrit dans le fichier avant la fin de l'étape 6.** On rédige
ici, on vérifie, on adapte, et seulement ensuite on écrit ce qui a survécu.

Les règles de contenu, toutes tirées de remarques du client :

- **La réponse doit s'entendre.** L'animateur lit, le joueur crie. « Pluriel
  de bijou ? Bijoux » ne se juge pas à l'oreille. Une question d'orthographe
  se reformule (« prend un S ou un X ? »).
- **Une seule réponse possible.** « Qui a cofondé Microsoft ? » accepte
  Gates ou Allen : verrouiller l'énoncé plutôt que d'accepter les deux.
- **La réponse n'est pas dans la question**, ni en entier ni par sa racine.
- **Rien de périssable.** Un record qu'on va battre, un joueur qui change
  d'équipe, « l'actuel », « le plus récent ». La question doit être aussi
  vraie dans cinq ans, sans retouche.
- **Pas de politique américaine** ni rien de proche : présidents,
  Maison-Blanche, drapeau, droits civiques, OTAN, 11 septembre. La culture
  américaine reste entière : cinéma, musique, sport.
- **Viser 7 à 77 ans.** Culture générale de jeu de société.

Pour chaque question rédigée, décider et noter niveau, tranches et
thématiques **maintenant**, pendant qu'on sait pourquoi on l'a écrite.

## 5. Vérifier chaque fait, à l'extérieur, et le consigner

**Ce qui porte un nom propre, une date, un nombre, un record, un superlatif
ou un attribut passe par WebSearch. Sans exception, et jamais par ma
mémoire.** Ma mémoire est ce qui a produit les treize faits faux.

### Ce que « vérifié » veut dire

- **La source sait.** Site officiel, encyclopédie, fiche de l'œuvre, organe
  de presse établi, texte de loi ou de règlement. Pas un forum, pas un
  extrait de recherche, pas une page qui cite « certains disent ».
- **La page est ouverte**, pas seulement l'extrait du moteur de recherche.
  Les extraits tronquent et mélangent. Pour tout ce qui compte, `WebFetch`.
- **C'est l'AFFIRMATION qu'on vérifie, pas l'entité.** Trouver que
  Passe-Montagne existe ne vérifie pas qu'il est barbu. Trouver que Bluey
  est une chienne ne vérifie pas sa race. La question affirme un attribut ;
  c'est cet attribut-là qu'il faut lire noir sur blanc.
- **Les superlatifs exigent une source qui dise exactement ça.** « Le plus
  grand », « le premier », « le seul », « le plus long ». Ce sont les
  affirmations les plus souvent fausses de la banque, et les plus
  contestées en soirée.
- **Deux sources qui se contredisent : la question se jette.** On ne
  tranche pas, on ne prend pas la majorité. Il en reste des milliers.

### Les formes qui ont déjà mordu, à chercher activement

1. **L'attribut collé à une entité réelle.** La couleur d'un oiseau, la
   race d'un chien de dessin animé, la barbe d'un personnage. Quand on ne
   peut pas le lire noir sur blanc, changer la question : demander un nom,
   une relation, un usage, jamais une description.
2. **La donnée périmée.** Adresse, nom de commerce, numéro de route, nom
   d'organisme, composition d'une équipe. Vérifier que c'est encore vrai, et
   se demander si ça le sera dans cinq ans.
3. **La date ou le nombre approché.** Cartier atteint le golfe en 1534 et
   remonte le fleuve en 1535. « Environ » ne se joue pas au buzzer.
4. **Le titre d'une œuvre, en version québécoise.** Un titre EST un fait.
   Voir l'étape 6 pour ce qu'il faut chercher.

**Ce qui ne se vérifie pas ne s'écrit pas.**

Le vocabulaire courant et les usages (« Que signifie magasiner ? ») ne
demandent pas de source externe, mais la réponse doit être **le** sens
courant et un seul. Une définition à deux lectures est une ambiguïté, pas un
fait.

### Le journal de vérification : `SOURCES.txt`

**Chaque fait vérifié laisse une entrée dans
`tool/questions/SOURCES.txt`**, et non seulement dans la réponse au client :
la réponse disparaît avec la conversation, le fichier reste, et le générateur
le compte.

```
Quel renne du père Noël a le nez rouge ?
  nez rouge — https://fr.wikipedia.org/wiki/Rudolphe_le_petit_renne_au_nez_rouge
```

La question au ras de la marge, **telle qu'écrite dans son fichier** ; en
dessous, indentée de deux espaces, une ligne par fait : l'attribut vérifié,
un tiret, l'adresse de la page **ouverte** qui le dit. Une question à trois
faits a trois lignes. Une question sans fait vérifiable le dit, pour qu'on
distingue « rien à sourcer » de « oublié » :

```
Que signifie magasiner ?
  vocabulaire
```

Le lien entre la source et la question est le TEXTE de la question,
normalisé comme pour les doublons. Reformuler une question rompt le lien et
le générateur le signale comme source orpheline : c'est voulu, reformuler
peut changer ce qu'elle affirme, et le fait est à revérifier avant de remettre
l'entrée sous le nouveau texte.

Sans entrée, la vérification n'a pas eu lieu. « J'ai vérifié » sans source
nommée ne vaut rien, pour le client comme pour celui qui relira dans un an.

## 6. Adapter au Québec

### Le titre d'une œuvre, c'est celui qu'on crie ici

**La réponse attendue est le nom que le joueur va dire dans le salon**, pas
la traduction la plus correcte. Le doublage québécois et celui de France
diffèrent, et c'est le québécois qui joue.

Déjà dans la banque, tous vérifiés : *Cars* est **Les Bagnoles**,
*Inside Out* est **Sens dessus dessous**, *Finding Dory* est **Trouver
Doris**, *Up* est **Là-haut**, *The Incredibles* est **Les Incroyables**.

- **Ça vaut pour tout ce qui porte un titre** : films, séries, dessins
  animés, livres, jeux vidéo, chansons.
- **Chercher `titre québécois <œuvre>`**, jamais se fier au titre français
  qui vient en tête : c'est presque toujours celui de France.
- **Souvent les deux titres sont identiques**, et il n'y a rien à faire.
  C'est la vérification qui le dit, pas l'intuition.
- **Parfois c'est le titre anglais qui est en usage ici.** Alors c'est lui
  la réponse. « Le bon français » n'est pas le critère ; ce que la salle
  crie l'est.

**Si DEUX noms sont réellement en usage au Québec, la question est
ambiguë** : un joueur qui donne l'autre se fait refuser alors qu'il a
raison. C'est ce que compte le compteur « variantes de nom », qui ne doit
pas augmenter. Deux sorties : verrouiller l'énoncé pour n'en rendre qu'un
possible, ou changer de question.

### Le reste

- **Le vocabulaire est d'ici.** Dîner le midi, souper le soir, magasiner,
  char, tuque, mitaines. Éviter les tournures de France même correctes.
- **Les unités sont métriques**, la monnaie en dollars.
- **Les repères partent d'ici.** « À quelle distance de Montréal » plutôt
  que de Paris.

## 7. Écrire dans les deux fichiers

Seulement ce qui a survécu aux étapes 4, 5 et 6.

**Dans le fichier de la catégorie**, à la fin du bloc libre, **sous la ligne
`# Sources exigées à partir d'ici`** : une ligne par question, ses `@` en
dessous. Tout ce qui est écrit sous ce repère doit avoir sa source, et le
générateur le compte.

```
Quel renne du père Noël a le nez rouge ?|Rudolphe|1|enfants ados adultes aines
@ noel
```

**Dans `SOURCES.txt`**, l'entrée de l'étape 5, avec la question copiée
exactement.

Relire les deux fichiers après écriture : un `|` de trop ou une tranche mal
orthographiée arrête le générateur avec la ligne fautive, et c'est mieux
maintenant que dans le commit.

## 8. Repasser les compteurs, et comparer

```bash
cd app/buzzer_companion && dart run tool/generate_questionnaires.dart
```

**Cinq barrières. Aucune ne se franchit en expliquant.**

| compteur | portée | règle |
|---|---|---|
| le générateur | tout | doit sortir en **code 0**. Un doublon exact, un miroir cassé, un slug inconnu ou le slug d'une catégorie écrit dans son propre fichier l'arrêtent. |
| **questions exigées sans source** | bloc libre, sous le repère | doit rester à **0**. Chacune est nommée dans la sortie. Les **sources orphelines** se corrigent aussi : une question reformulée se revérifie, une question retirée libère son entrée. |
| **quasi-doublons** | même catégorie | doit rester à **0**. Aucun cas légitime : quand il en sort un, une des deux lignes est de trop. Le générateur les affiche en détail. |
| **variantes de nom** | toute la banque | ne doit **pas augmenter**. Deux réponses pour la même chose font refuser un joueur qui a raison. |
| échos et réponses partagées | toute la banque | peuvent monter un peu. Pour **chaque** unité de hausse, nommer la question responsable et dire pourquoi c'est légitime (« Quatre » répond à vingt questions sans rapport). Une hausse non expliquée veut dire qu'un lot est entré sans contrôle. |

Un second avis sur les échos, avec une règle un peu plus large :

```bash
node app/buzzer_companion/tool/antiscrap.js
```

Il ne donne pas le même nombre que le générateur, et c'est normal. C'est le
mouvement des deux qui compte.

Si une barrière tombe, **retirer des lignes**. Ne jamais garder une question
en se disant que le compteur exagère.

## 9. Fermer

```bash
cd app/buzzer_companion && flutter analyze && flutter test
```

Puis mettre à jour les repères dans `tool/questions/INTEGRITE.md` avec les
quatre compteurs d'après et la date.

Le commit et la réponse au client disent, dans cet ordre :

1. combien de questions demandées, combien écrites, et pourquoi l'écart ;
2. les cinq compteurs avant et après, et l'explication de chaque hausse ;
3. le journal de vérification, une ligne par fait, tel qu'écrit dans
   `SOURCES.txt`.

Un lot rendu court est une information, pas une excuse. Un lot rendu sans
ses entrées dans `SOURCES.txt` n'est pas rendu, et le compteur le dira.

## Ce qu'on ne fait jamais

- Toucher `Questions.cpp` ou une ligne du bloc miroir.
- Écrire dans le fichier une question qui n'a pas encore été vérifiée.
- Affirmer un fait vérifiable sans avoir ouvert une source qui le dit.
- Décrire une entité réelle de mémoire : sa couleur, sa race, son aspect.
- Trancher entre deux sources qui se contredisent.
- Écrire une question sans niveau, sans tranches ou sans ses thématiques.
- Écrire une question que la banque a déjà, faute d'avoir cherché son sujet
  sans son mot générique.
- Écrire le slug d'une catégorie sous une question de son propre fichier.
- Compléter un lot pour atteindre le nombre demandé.
- Écrire une question sous le repère des sources sans son entrée dans
  `SOURCES.txt`, ou l'écrire au-dessus du repère pour échapper au compteur.
- Annoncer un lot conforme sans les compteurs avant et après, ni le journal.
