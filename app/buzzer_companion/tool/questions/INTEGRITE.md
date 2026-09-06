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
- une ligne n'a pas ses quatre champs, ou un niveau et des tranches valides ;
- une thématique `@` porte un slug qui n'existe pas ;
- une question porte le slug de sa PROPRE catégorie, qui la prend déjà sans
  marqueur : les onze catégories sont aussi des thématiques, et `@ quebec`
  ne s'écrit que sur une question québécoise rangée dans un autre fichier.

Il affiche aussi, sans bloquer, quatre comptes sur les versions servies :

| compteur | portée | ce qu'il doit faire |
|---|---|---|
| réponses déjà dans leur question | toute la banque | monter peu, et chaque hausse s'explique |
| réponses partagées par plusieurs questions | toute la banque | idem |
| quasi-doublons | même catégorie seulement | **rester à 0**, aucun cas légitime |
| variantes de nom | toute la banque | **ne pas augmenter** |
| questions exigées sans source | bloc libre, sous le repère | **rester à 0** |

Le cinquième compte vient de `SOURCES.txt` : toute question libre écrite sous
le repère `# Sources exigées à partir d'ici` de son fichier doit y avoir son
entrée, question et source. Une vérification sans trace n'est pas
distinguable d'une vérification qui n'a pas eu lieu. Le générateur signale
aussi les sources orphelines, dont la question n'existe plus sous ce texte :
une reformulation est à revérifier, un retrait libère l'entrée.

Les deux premiers ne bloquent pas parce que les cas légitimes existent : « la
vitamine C » quand la question dit vitamine, « Quatre » qui répond à vingt
questions sans rapport. **Une hausse non expliquée veut dire qu'un lot est
entré sans contrôle.**

Le quasi-doublon ne regarde qu'à l'intérieur d'une catégorie : une redite
entre Québec et Bouffe lui échappe, et seule la recherche préalable
(`--chercher`) la voit. La procédure complète est dans le skill
`ecrire-des-questions`.

Repères, à mettre à jour après chaque lot :

| date | échos | partagées | quasi-doublons | variantes | sans source |
|---|---:|---:|---:|---:|---:|
| 4 septembre 2026 | 53 | 258 | — | — | — |
| 5 septembre 2026 | 54 | 215 | 0 | 14 | 0 |
| 5 septembre 2026, musique par décennies (+57) | 54 | 215 | 0 | 14 | 0 |
| 5 septembre 2026, musique par décennies, 2e passe (+82) | 54 | 216 | 0 | 14 | 0 |
| 5 septembre 2026, musique 2010-2020 pour les enfants (+7, 4 recotées) | 54 | 216 | 0 | 14 | 0 |
| 5 septembre 2026, thématique Disney et les parcs (+18, 24 étiquetées) | 54 | 217 | 0 | 14 | 0 |
| 5 septembre 2026, thématique Voyages (+27, 86 étiquetées) | 54 | 217 | 0 | 14 | 0 |
| 5 septembre 2026, les 11 catégories deviennent des thématiques (0 neuve) | 54 | 217 | 0 | 14 | 0 |
| 5 septembre 2026, les 221 étiquettes « quebec » récupérées (0 neuve) | 54 | 217 | 0 | 14 | 0 |
| 5 septembre 2026, sports-hiver et regne-vegetal fusionnés (0 neuve) | 54 | 217 | 0 | 14 | 0 |
| 6 septembre 2026, 5 étiquettes Sports reprises, 3 questions molles retirées | 54 | 217 | 0 | 14 | 0 |
| 6 septembre 2026, les villes des grandes équipes (+35) | 54 | 225 | 0 | 14 | 0 |
| 6 septembre 2026, les figures du sport d'ici (+8) | 54 | 225 | 0 | 14 | 0 |
| 6 septembre 2026, creatures et mer absorbées (0 neuve, 114 transférées) | 54 | 225 | 0 | 14 | 0 |
| 6 septembre 2026, Cinéma et télé bonifié (+99) | 54 | 225 | 0 | 14 | 0 |

Ce dernier passage n'a touché aucune question : les onze catégories sont
devenues des thématiques qui absorbent leur catégorie, ce qui donne une
étiquette aux 2795 questions qui n'en portaient aucune. **Zéro question sans
thématique**, et un test de `banque_embarquee_test.dart` le garde : depuis que
les grilles de filtres n'affichent plus qu'un seul axe, une question qui
perdrait la thématique de sa catégorie deviendrait injoignable au tirage sans
qu'aucun écran ne le dise.

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

### 2. L'ambiguïté — EN PARTIE (septembre 2026)

Une question ambiguë accepte plus d'une bonne réponse. Rien ne le prouve
mécaniquement, mais une de ses formes se détecte, et c'est la plus injuste :
**deux réponses de la banque nomment la même chose**, et le joueur qui donne
l'autre nom se fait refuser alors qu'il a raison. « La tire » et « la tire
d'érable », « L'Ère de glace » et « L'Âge de glace », « le casque » et « le
casque de vélo », « Trudeau » pour deux premiers ministres.

Le générateur affiche maintenant ce compte à côté des trois autres, avec le
détail. Le signal : deux réponses dont l'une contient l'autre, et deux
énoncés qui partagent au moins deux mots porteurs. 45 vraies variantes
trouvées et corrigées. **Repère : 14 restantes, toutes vérifiées comme
fausses alertes** (« Six » dans « Vingt-six », le ski et le ski nautique, la
flûte et la flûte de Pan). Si le compte monte, c'est du nouveau.

Ce qui n'est toujours pas détecté, et qui demande de lire : la question dont
plusieurs entités remplissent les conditions. « Dans quel pays trouve-t-on la
savane, les lions et les girafes ? » a dix bonnes réponses. « Quel chanteur
aveugle joue du piano ? » en a deux. Une quarantaine de celles-là ont été
trouvées à l'œil en relisant la banque, aucune par une machine.

Un signal faible existe pour un troisième cas, l'énoncé qui ne tient que par
un « célèbre » ou un « connu » : 35 candidats, dont deux seulement étaient de
vraies ambiguïtés. Le mot sert le plus souvent d'ornement, pas de critère.

### 3. La péremption — FAIT (septembre 2026)

**Les questions doivent être pérennes.** Une banque de party n'a pas de
mainteneur : ce qui demande une revue annuelle ne sera jamais revu, et
vieillira en silence jusqu'à ce que quelqu'un, dans le salon, corrige le jeu.

Une question n'est pas pérenne quand sa réponse peut devenir **fausse** alors
que l'énoncé reste valable : un record qu'on bat, un joueur qui change
d'équipe, un compte qui bouge, un amphithéâtre qui change de commanditaire.
23 ont été trouvées et traitées, aucune n'a été gardée telle quelle :

- **neuf reformulées** pour viser un fait figé. Le record du 100 m devient
  « qui a couru en 9 secondes 58 », le gardien aux plus de victoires devient
  « qui a gagné 691 matchs », le numéro 97 des Oilers devient « repêché
  premier par Edmonton en 2015 ». La performance ne bougera plus ;
- **sept retirées**, faute de reformulation honnête : le nombre de coupes
  Stanley des Canadiens, le nombre d'équipes de la LNH, le pays le plus
  médaillé, le club de Haaland, le nom du Centre Vidéotron ;
- **sept démarquées** : les dominations structurelles que rien ne conteste,
  le café brésilien, le sirop d'érable canadien, le pétrole albertain, le 311
  et l'autoroute 40. Ce ne sont pas des classements disputés.

Une était déjà périmée quand on l'a trouvée : « Quel Espagnol règne sur
Roland-Garros ? » se posait au présent alors que Nadal a pris sa retraite en
novembre 2024.

Le marqueur `~ raison` reste dans le format, à côté de `>` et `-`, et le
générateur en affiche le compte à chaque passage. **Ce compte doit rester à
zéro.** S'il monte, une question qui pourrit est entrée dans la banque.
`--perissables` les liste.

### 4. Les niveaux et les tranches

Le niveau (1 à 3) et les tranches d'âge sont du jugement, jamais confrontés à
une vraie soirée. Une partie jouée avec des enfants et une autre avec des
aînés en diraient plus que n'importe quelle relecture.
