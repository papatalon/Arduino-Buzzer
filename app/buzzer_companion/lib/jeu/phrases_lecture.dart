import 'dart:math';

// Les phrases projetées à la salle PENDANT QUE L'ANIMATEUR LIT la question.
//
// Le réglage « question à l'écran : quand je la montre » garde le texte hors
// de l'écran public jusqu'au clic de l'animateur. Sans rien à la place,
// l'écran resterait vide au moment précis où tout le monde le regarde, ce
// qui ressemble à une panne. Ces phrases disent que la question s'en vient,
// sur un ton taquin.
//
// Elles vivent à part du moteur pour la même raison que les phrases
// d'attente : c'est du contenu, il grossit par lots, souvent tard, et pour
// d'autres raisons que les règles du jeu.
//
// LES RÈGLES DE LA LISTE :
//
// Ton québécois, taquin envers la salle au complet, JAMAIS envers un joueur
// en particulier. L'animateur, lui, peut en prendre pour son rhume : il n'est
// pas en compétition.
//
// AUCUN POINT D'INTERROGATION. La phrase s'affiche en gros, là où la
// question va apparaître : une phrase qui finit par un « ? » se lit comme la
// question elle-même, et quelqu'un buzzera dessus.
//
// NEUTRE SUR LES BUZZERS. Selon le réglage, ils sont armés ou verrouillés
// pendant la lecture. « Ne touchez pas au bouton » serait faux dans un cas,
// « buzzez quand vous voulez » dans l'autre. On parle de la question qui
// s'en vient, de l'écoute, de la patience, jamais de ce que le bouton
// permet.
//
// PAS DE POUCES, pas de manettes : les buzzers sont de gros boutons qu'on
// abat avec la main. AUCUN CHIFFRE. Pas de tiret cadratin.
//
// COURT. Deux lignes dans la zone de la question : au-delà d'une soixantaine
// de caractères, la troisième ligne est coupée. Le test de la liste tient
// ces règles honnêtes.
const phrasesLecture = <String>[
  "La question s'en vient. Faites semblant d'être prêts.",
  "L'animateur lit. Vous, vous écoutez.",
  "Ça s'en vient. Gardez votre calme.",
  "Écoutez d'abord, paniquez ensuite.",
  'La question se fait belle pour vous.',
  'Patience. Les bonnes questions se font attendre.',
  "Ouvrez grand les oreilles. L'écran suivra.",
  'On lit la question. Vos neurones, réchauffez-vous.',
  'La question est en route. Aucun détour prévu.',
  'Respirez. La question ne mord pas. Pas toujours.',
  "L'animateur prend son temps. C'est voulu.",
  'Pendant la lecture, révisez tout ce que vous savez.',
  'Tendez l\'oreille. Le texte suit.',
  'Suspense. La question se fait désirer.',
  'On y arrive. Retenez votre souffle, pas trop longtemps.',
  "Une question approche. Personne n'est à l'abri.",
  'La question se prépare. Votre cerveau aussi, on espère.',
  "L'animateur a la parole. Profitez-en, c'est rare.",
  'Écoutez bien : on ne rembobine pas.',
  'Faites vos plus beaux airs intelligents.',
  'On lit lentement pour ceux qui ont veillé tard.',
  'La question attend poliment son tour.',
  'Le texte arrive quand la lecture finit. Pas avant.',
  "On écoute jusqu'au bout. Le punch est souvent à la fin.",
  'La question se cache encore. Elle est gênée.',
  'La question enfile ses bottes. Minute, là.',
  'Un instant. La question se peigne.',
  'Les meilleures questions arrivent en retard.',
  'Écoutez fort. Oui, ça se peut.',
  'Concentration maximale. Ou presque.',
  "Mettez votre face de quelqu'un qui sait.",
  'Cachez votre inquiétude. Ça paraît.',
  'Pas de panique. Pas encore.',
  "La question s'échauffe avant d'entrer.",
  'On garde le meilleur pour la fin de la phrase.',
  'Écoutez comme si le pointage en dépendait. Il en dépend.',
  'Chut. La question fait son entrée.',
  'Toute la salle retient son souffle. Ou fait semblant.',
  'Oubliez ce que vous pensiez savoir.',
  'Doucement. La question a le droit de finir.',
  'Promis, on ne vous oublie pas. Ça arrive.',
  'Un peu de suspense, ça fait du bien.',
  'La question arrive au galop.',
  'La réponse se cache souvent dans les détails.',
  "L'écran se tait, l'animateur parle. Chacun son tour.",
  'Vos voisins sont aussi perdus que vous. Rassurant.',
  'Préparez votre plus belle réponse. Même la mauvaise.',
  "L'animateur articule. Faites-lui honneur.",
  'Le texte viendra. Pour l\'instant, les oreilles.',
  'Ne regardez pas ici. Écoutez là-bas.',
];

// Tire les phrases SANS REMISE : toutes passent une fois avant qu'une seule
// ne revienne. Une soirée pose facilement une soixantaine de questions ; tiré
// au hasard pur, le même gag reviendrait deux fois dans la même partie, et
// c'est la deuxième fois qu'on remarque.
//
// Au changement de sac, la première phrase du nouveau n'est jamais la
// dernière de l'ancien : sinon, une fois sur cinquante, la même phrase
// s'afficherait deux questions de suite.
class TirageLecture {
  TirageLecture({Random? hasard}) : _hasard = hasard ?? Random();

  final Random _hasard;
  final List<String> _sac = [];
  String? _derniere;

  String suivante() {
    if (_sac.isEmpty) {
      _sac
        ..addAll(phrasesLecture)
        ..shuffle(_hasard);
      // On pige par la fin : c'est donc la derniere du sac qui sortirait.
      if (_sac.length > 1 && _sac.last == _derniere) {
        final premiere = _sac.first;
        _sac.first = _sac.last;
        _sac.last = premiere;
      }
    }
    final phrase = _sac.removeLast();
    _derniere = phrase;
    return phrase;
  }
}
