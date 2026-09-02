import 'dart:math';

// LE MOT DE LA FIN, projeté sous le nom du gagnant.
//
// Même registre que les messages de l'écran d'attente : effronté, mais jamais
// dirigé contre une personne. Ici il y a bien un gagnant nommé juste au-dessus,
// donc une pique légère est permise, à condition qu'elle porte sur la victoire
// et non sur celui qui l'a remportée. Les perdants, eux, ne sont jamais visés :
// ils viennent déjà de perdre devant tout le monde.
//
// Deux listes, parce que les deux situations n'ont rien à voir. Une victoire
// se célèbre, une égalité laisse tout le monde sur sa faim, et servir la même
// phrase aux deux sonnerait faux.

const motsDeVictoire = <String>[
  'Le talent, la chance, ou les deux. On ne saura jamais.',
  "Les autres avaient les bonnes réponses. Juste trop tard.",
  'Une victoire, ça ne se discute pas. Ça se raconte.',
  'Le pointage a parlé. Il ne reprend jamais ce qu\'il dit.',
  "On dira que c'était serré. Ça ne l'était pas.",
  'Champions du soir. Le titre expire à minuit.',
  'Savourez. La revanche se prépare déjà.',
  'Il fallait bien que quelqu\'un gagne.',
  'Personne ne conteste. C\'est écrit en gros.',
  'La modestie, maintenant, serait de très mauvais goût.',
];

const motsDEgalite = <String>[
  'Personne ne gagne, personne ne perd. Frustrant, non ?',
  'Deux gagnants, donc aucun. Les règles sont comme ça.',
  "Il aurait fallu une question de plus. Une seule.",
  'Égalité parfaite. Vous vous méritez.',
  'Personne ne pourra se vanter. C\'est peut-être mieux ainsi.',
  "L'histoire ne retiendra aucun nom ce soir.",
  'Tout ce chemin pour finir à égalité.',
  'Bravo à tous, ce qui ne veut rien dire du tout.',
  'On se quitte sans savoir. Ça arrive.',
  'Le pointage refuse de trancher. Débrouillez-vous.',
];

// Tiré une seule fois, à la fin de la partie, et transporté tel quel vers
// l'écran public : le retirer à chaque reconstruction de la fenêtre ferait
// clignoter la phrase devant la salle.
String motDeLaFin({required bool egalite, Random? hasard}) {
  final liste = egalite ? motsDEgalite : motsDeVictoire;
  return liste[(hasard ?? Random()).nextInt(liste.length)];
}

// MANCHE LIBRE : l'animateur pose ses propres questions, à voix haute, et
// l'écran public n'a aucun texte à montrer. Sans ces phrases il reste vide,
// ce qui ressemble à une panne au moment précis où la salle devrait écouter.
//
// Elles ne remplacent pas la question : elles disent où porter attention.
// D'où un ton plus sobre que celui de l'écran d'attente, sans blague à
// chercher, parce qu'elles s'affichent pendant que quelqu'un parle.
const motsDattention = <String>[
  'Écoutez bien la question.',
  "La question se pose à voix haute. Ouvrez grand les oreilles.",
  'Tout se joue à l\'oreille cette fois.',
  'Rien à lire ici. Tout à écouter.',
  'La réponse est dans ce qui vient d\'être dit.',
  'Silence. On écoute.',
  'Pas de texte, pas de relecture. Une seule écoute.',
  'Écoutez jusqu\'au bout : la fin de la question compte.',
  'Ceux qui écoutent vraiment ont déjà une longueur d\'avance.',
  'La question ne sera pas répétée. Enfin, peut-être.',
  'Oreilles ouvertes, main au-dessus du bouton.',
  'Ici, on ne triche pas en relisant.',
];

// Tiré à chaque nouvelle question d'une manche libre, et transporté vers
// l'écran public : le retirer à chaque reconstruction de la fenêtre le ferait
// changer sous les yeux de la salle en pleine question.
String motDattention({Random? hasard}) =>
    motsDattention[(hasard ?? Random()).nextInt(motsDattention.length)];

// PENDANT LE TIRAGE AU SORT du mode Vol : la roue tourne sur les boutons,
// mais l'écran public, lui, n'a rien à annoncer. Il resterait sur son plan
// d'attente ordinaire, sans que la salle comprenne ce qui se joue.
//
// Ces phrases disent ce qui se passe, sur le ton du reste : le sort désigne
// qui ouvrira la question, et personne n'y peut rien.
const motsDeTirage = <String>[
  'Le sort choisit qui ouvre. Personne ne négocie.',
  'La roue tourne. Un seul aura la première chance.',
  'On tire au sort. Les protestations sont notées, puis ignorées.',
  "Quelqu'un va être désigné. Ce n'est pas personnel.",
  'Le hasard travaille. Laissez-le finir.',
  'La roue décide, et elle ne se relit pas.',
  'Un buzzer va être choisi. Les autres attendront leur tour.',
  'Tirage en cours. Croisez ce que vous voulez.',
];

String motDeTirage({Random? hasard}) =>
    motsDeTirage[(hasard ?? Random()).nextInt(motsDeTirage.length)];
