# Intégrité de la banque de questions

Un fait faux discrédite tout le jeu : quelqu'un dans le salon va le savoir.
Ce fichier suit ce qui est contrôlé, ce qui ne l'est pas, et ce qui reste à
faire. Les règles de contenu elles-mêmes sont dans l'en-tête de chaque
fichier `.txt`.

## Ce qui est contrôlé automatiquement

Le générateur refuse de produire le site si :

- une question est posée deux fois, d'où qu'elle vienne ;
- une ligne miroir ne redonne pas `Questions.cpp` au caractère près une fois
  ses accents retirés ;
- une ligne n'a pas ses quatre champs, ou un niveau et des tranches valides.

Il affiche aussi, sans bloquer, deux comptes sur les versions servies :

- les réponses déjà contenues dans leur énoncé ;
- les réponses partagées par plusieurs questions.

Ces deux-là ne bloquent pas parce que les cas légitimes existent : « la
vitamine C » quand la question dit vitamine, « Quatre » qui répond à vingt
questions sans rapport. **Une hausse du compte veut dire qu'un lot est entré
sans contrôle.** Repères au 4 septembre 2026 : 53 et 258.

## Ce qui n'est pas contrôlé

### 1. Les faits jamais relus

Sur 1746 affirmations vérifiables de la banque, 503 ont été relues et
vérifiées à l'extérieur en septembre 2026. **1243 ne l'ont jamais été**,
surtout dans la moitié miroir du firmware.

Ce que la relecture de septembre a trouvé sur les 503 : sept faits faux, deux
données périmées, une vingtaine d'ambiguïtés. Rien ne laisse croire que les
1243 autres soient plus propres.

Méthode qui a marché : trier par forme de risque (détail descriptif sur une
entité réelle, date, record, mesure, nom propre), puis vérifier à l'extérieur
au lieu de se relire. Les questions de vocabulaire et de définitions ne
peuvent pas être fausses et ne demandent rien.

### 2. L'ambiguïté

Aucun outil. Une question comme « Dans quel pays trouve-t-on la savane, les
lions et les girafes ? » a dix bonnes réponses, et rien ne la signale. La
vingtaine trouvée en septembre l'a été à l'œil, sur un dixième de la banque.

### 3. La péremption

Rien ne marque les questions qui vieillissent toutes seules : Haaland à
Manchester City, Cineplex, Sports Experts, le Rocket à Laval, le Centre
Vidéotron. Piste : un marqueur `# périssable` sur ces lignes, revues une fois
l'an.

### 4. Les niveaux et les tranches

Le niveau (1 à 3) et les tranches d'âge sont du jugement, jamais confrontés à
une vraie soirée. Une partie jouée avec des enfants et une autre avec des
aînés en diraient plus que n'importe quelle relecture.
