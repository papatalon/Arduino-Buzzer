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

### 1. Les faits jamais relus — FAIT (septembre 2026)

Les 1746 affirmations vérifiables de la banque ont toutes été relues, et les
plus exposées vérifiées à l'extérieur plutôt qu'en se relisant.

Résultat : **treize faits faux**, deux données périmées, une quarantaine
d'ambiguïtés et de fuites, et 37 quasi-doublons. La mésange n'est pas bleue,
la mouffette ne fait pas le mort, Toupie est une souris, Gabby est une
fillette, le cipaille vient de la Gaspésie et non du Lac-Saint-Jean,
Mont-Sainte-Anne ne domine pas Stoneham, BIXI compte quatre lettres, Cartier
ne remonte pas le fleuve en 1534, La Presse a cessé le papier en 2017, le
parc Maisonneuve borde le Parc olympique sans l'entourer, la Boîte à surprise
n'ouvrait sur aucun coffre, le chapeau de Toad est blanc taché de rouge, et
c'est Isabelle Pierre qui a popularisé Évangéline.

Méthode qui a marché, à reprendre pour tout nouveau lot : trier par forme de
risque (détail descriptif sur une entité réelle, date, record, mesure, nom
propre), puis vérifier à l'extérieur. Les questions de vocabulaire et de
définitions ne peuvent pas être fausses et ne demandent rien. **Se relire ne
sert à rien** : les treize faits faux étaient tous des souvenirs qui
paraissaient sûrs.

Ce qui n'est toujours pas couvert ici : les titres localisés. Le même film
porte un nom au Québec et un autre en France (Moana / Vaiana, Sens dessus
dessous / Vice-versa), et rien ne le signale.

### 2. L'ambiguïté

Aucun outil. Une question comme « Dans quel pays trouve-t-on la savane, les
lions et les girafes ? » a dix bonnes réponses, et rien ne la signale. La
vingtaine trouvée en septembre l'a été à l'œil, sur un dixième de la banque.

### 3. La péremption — FAIT (septembre 2026)

Une ligne `~ raison` sous une question la marque comme périssable, à côté des
marqueurs `>` (retouche) et `-` (retrait). Le générateur les compte à chaque
passage, et

    dart run tool/generate_questionnaires.dart --perissables

les liste avec leur raison. **C'est la commande de la revue annuelle.**

Le critère est étroit, et c'est voulu : on marque une question dont la
réponse peut devenir **fausse** alors que l'énoncé reste valable. Un record
qu'on bat, un joueur qui change d'équipe, un compte qui bouge, un
amphithéâtre qui change de commanditaire. « Qui a fondé Québec ? » sera vrai
dans vingt ans et ne se marque pas. Une marque qui disparaîtrait rendrait sa
question caduque, pas fausse : elle ne se marque pas non plus.

23 questions marquées au départ, surtout dans Sports et Québec. Une était
déjà périmée quand on l'a trouvée : « Quel Espagnol règne sur Roland-Garros ? »
au présent, alors que Nadal a pris sa retraite en novembre 2024.

### 4. Les niveaux et les tranches

Le niveau (1 à 3) et les tranches d'âge sont du jugement, jamais confrontés à
une vraie soirée. Une partie jouée avec des enfants et une autre avec des
aînés en diraient plus que n'importe quelle relecture.
