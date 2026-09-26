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
  "Les oreilles d'abord. Les yeux, tantôt.",
  'Tout le monde écoute. Même ceux qui font semblant.',
  "L'animateur a trouvé ses lunettes. Ça avance.",
  'Gardez vos réponses au chaud. Elles serviront.',
  "On ne lit pas par-dessus l'épaule de l'animateur.",
  'Le texte fait la file. Il arrive.',
  'Un peu de patience. Vos neurones vous remercieront.',
  'Silence radio dans la salle. Parfait.',
  "On attend la fin de la phrase. C'est la règle.",
  "L'animateur lit avec émotion. Applaudissez plus tard.",
  'Le suspense est gratuit ce soir. Profitez-en.',
  "Personne ne sait encore rien. C'est le moment idéal.",
  "La question arrive, mais elle prend l'escalier.",
  "Écouter, c'est déjà la moitié de la réponse.",
  'Le texte est timide. Il se montre bientôt.',
  'Vos meilleures réponses sont encore à venir.',
  'Ça mijote. La question sort du four bientôt.',
  "Laissez l'animateur finir. Il a pratiqué.",
  "Pas de précipitation. Juste de l'écoute.",
  "La salle est prête. L'écran, pas encore.",
  'On écoute comme au cinéma : sans parler.',
  'Le savoir arrive par les oreilles ce soir.',
  'Chaque mot compte. Même les petits.',
  'Tenez-vous bien. Ça va être bon.',
  'On lit à voix haute, comme à la petite école.',
  "L'écran fait une petite sieste. Laissez-le dormir.",
  'Écouter, ça ne coûte rien. Et ça rapporte gros.',
  "Retenez vos chevaux. Le texte s'en vient.",
  'Faites confiance à vos oreilles. Pour une fois.',
  "Ce n'est pas le temps de jaser avec son voisin.",
  'Le silence vous va très bien.',
  'Les plus sages attendent la fin. Les autres aussi, là.',
  "Mettez vos lunettes d'écoute.",
  'Du calme et du sang-froid. Ça arrive.',
  "Une bonne écoute vaut mieux qu'une bonne vue.",
  "L'animateur lit. Le reste du monde attend.",
  'La question prend son élan.',
  'On y est presque. Promis, juré, craché.',
  'Vos méninges sont priées de se présenter.',
  "Le texte se fait attendre. C'est sa marque de commerce.",
  'Il paraît que la réponse est facile. Il paraît.',
  'Écoutez la question. Elle a travaillé fort.',
  "Pas besoin de lire dans les pensées. Juste d'écouter.",
  "La question est prête. L'animateur, presque.",
  'On retient son souffle. Ou sa collation.',
  'Rangez vos cellulaires. Sortez vos oreilles.',
  'Les bonnes réponses aiment le silence.',
  "Ça s'en vient, aussi sûr que l'hiver.",
  'On ne souffle pas la réponse à son voisin.',
  "Même les gagnants écoutent jusqu'au bout.",
];

// Tire les phrases SANS REMISE : toutes passent une fois avant qu'une seule
// ne revienne. Une soirée pose facilement une soixantaine de questions, et la
// liste en compte cent : une soirée entière passe sans une redite. Tiré au
// hasard pur, le même gag reviendrait dans la même partie, et c'est la
// deuxième fois qu'on remarque.
//
// Au changement de sac, la première phrase du nouveau n'est jamais la
// dernière de l'ancien : sinon, une fois sur cent, la même phrase
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
