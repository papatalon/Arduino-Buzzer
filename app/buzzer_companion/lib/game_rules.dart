// Règles des onze jeux, telles que l'animateur les expliquera à voix haute
// avant de lancer une partie.
//
// [pitch] est la phrase courte des cartes de l'écran « Jeu actif ».
// [howTo] est le vrai contenu : des phrases prêtes à être lues au micro,
// dans l'ordre où on les dit, et volontairement plus longues que des
// mots-clés. Un maître de cérémonie qui doit reformuler un mot-clé en
// pleine soirée hésite ; une phrase entière se lit d'un trait.
// [setup] rappelle à l'opérateur ce que le jeu exige avant de partir
// (nombre de buzzers, réglage préalable) : vide quand il n'y a rien à
// préparer.
//
// Source : les commentaires de tête de chaque fichier du firmware
// (Simon.h, Reflex.h, BlindTimer.h, SoundGame.h, Duel.h) et le barème réel
// de Buzzer::goodAnswer/badAnswer. À resynchroniser si une règle change
// dans le firmware.
class GameRules {
  const GameRules({required this.pitch, required this.howTo, this.setup = ''});

  final String pitch;
  final List<String> howTo;
  final String setup;
}

// Même ordre que kGameModeNames et GameMode.h.
const kGameRules = <GameRules>[
  // 0 Classique
  GameRules(
    pitch: 'Le premier à buzzer répond. Bonne réponse, un point.',
    howTo: [
      'Je lis la question. Vous pouvez buzzer dès que vous pensez avoir la réponse, même avant la fin.',
      'Le premier buzzer allumé a la parole. Les autres se taisent.',
      'Bonne réponse : un point. Mauvaise réponse : aucun point retiré, mais vous êtes écartés de cette question.',
      'Les autres équipes peuvent alors se reprendre sur la même question.',
    ],
  ),
  // 1 Pénalité
  GameRules(
    pitch: 'Comme Classique, mais une mauvaise réponse coûte un point.',
    howTo: [
      'Même chose que le Classique : je lis, vous buzzez, le premier répond.',
      'La différence est le prix de l\'erreur. Une mauvaise réponse retire un point.',
      'Un pointage peut donc descendre sous zéro. Buzzez seulement si vous êtes sûrs.',
    ],
  ),
  // 2 Chrono classique
  GameRules(
    pitch: 'Classique, avec un temps limité pour buzzer.',
    howTo: [
      'Je lis la question, puis je donne le départ du chrono.',
      'À partir de là, vous avez un temps limité pour buzzer. Passé le délai, la question est perdue pour tout le monde.',
      'Bonne réponse : un point. Mauvaise réponse : aucun point retiré, mais le chrono repart, plus court, pour les autres.',
    ],
    setup: 'Durées à régler à la sélection du jeu.',
  ),
  // 3 Chrono pénalité
  GameRules(
    pitch: 'Chrono et pénalité ensemble. Le plus exigeant des quiz.',
    howTo: [
      'Je lis la question, puis je donne le départ du chrono.',
      'Vous avez un temps limité pour buzzer, et une mauvaise réponse retire un point.',
      'C\'est le plus sévère des quiz. Prendre son temps coûte la question, se tromper coûte un point.',
    ],
    setup: 'Durées à régler à la sélection du jeu.',
  ),
  // 4 Vol
  GameRules(
    pitch: 'Chacun son tour, mais les autres peuvent voler la question.',
    howTo: [
      'Les questions passent d\'une équipe à l\'autre, chacune son tour. Je nomme celle qui est désignée.',
      'Elle seule peut répondre en premier. Son buzzer est allumé.',
      'Si elle se trompe, la question s\'ouvre aux autres : c\'est le vol. Le premier à buzzer prend le point.',
      'Le tour passe ensuite à l\'équipe suivante, qu\'elle ait marqué ou non.',
    ],
    setup: 'Le premier joueur est tiré au sort avant la première question.',
  ),
  // 5 Simon
  GameRules(
    pitch: 'La machine joue une séquence de couleurs, vous la rejouez.',
    howTo: [
      'Chaque équipe tient une couleur. Une seule. Retenez bien laquelle.',
      'La machine joue une séquence : des couleurs qui s\'allument une à une, avec leur son.',
      'Ensuite, vous la rejouez dans le même ordre. Chacun appuie quand SA couleur passe.',
      'Réussi ? La séquence s\'allonge d\'une couleur. Une seule erreur, et la partie s\'arrête.',
      'Vous jouez ensemble contre la machine, pas les uns contre les autres. Il n\'y a pas de pointage : ce qui compte est le niveau atteint.',
    ],
    setup: 'De 2 à 4 buzzers. La séquence n\'utilise que les couleurs en jeu.',
  ),
  // 6 Simon inverse
  GameRules(
    pitch: 'Simon, mais la séquence se rejoue à l\'envers.',
    howTo: [
      'Chaque équipe tient une couleur, comme au Simon ordinaire.',
      'La machine joue la séquence du début à la fin, normalement.',
      'Mais vous, vous la rejouez À L\'ENVERS. La dernière couleur montrée est la première à appuyer.',
      'C\'est beaucoup plus dur qu\'il en a l\'air. Une seule erreur termine la partie.',
    ],
    setup: 'De 2 à 4 buzzers. La séquence n\'utilise que les couleurs en jeu.',
  ),
  // 7 Réflexe
  GameRules(
    pitch: 'Aucune question. Le plus rapide sur le signal gagne.',
    howTo: [
      'Pas de question ici, juste des réflexes.',
      'Les lumières s\'éteignent. Un moment plus tard, elles s\'allument toutes d\'un coup : c\'est le signal.',
      'Le premier à buzzer après le signal remporte la manche, et je vous annonce son temps de réaction.',
      'Attention : buzzer AVANT le signal est un faux départ. Vous êtes éliminés de la manche, les autres continuent.',
      'Le délai avant le signal change à chaque fois. Impossible de le deviner.',
    ],
    setup: 'Nombre de manches à régler à la sélection du jeu.',
  ),
  // 8 Chrono aveugle
  GameRules(
    pitch: 'Estimez une durée sans aucun repère. Le plus proche gagne.',
    howTo: [
      'Je vous annonce une durée cible, par exemple huit secondes.',
      'Je donne le départ, et à partir de là plus rien ne bouge. Aucun compteur, aucune aiguille, rien.',
      'Chacun buzze quand il pense que la durée est écoulée. Le plus proche de la cible remporte la manche.',
      'La lumière de votre buzzer s\'éteint quand vous avez joué. C\'est le seul retour, et il ne vous dit rien sur le temps.',
      'Aucune connaissance n\'est requise : petits et grands sont à égalité.',
    ],
    setup: 'Nombre de manches à régler à la sélection du jeu.',
  ),
  // 9 Ne buzze pas
  GameRules(
    pitch: 'Buzzez sur VOTRE son, surtout pas sur celui des autres.',
    howTo: [
      'Chaque équipe a son propre son de buzz. On commence par les écouter une fois, tranquillement.',
      'Ensuite les sons s\'enchaînent, sans arrêt. Buzzez quand c\'est le vôtre.',
      'Le vôtre reconnu : un point, et deux points si vous êtes rapides.',
      'Buzzer sur le son de quelqu\'un d\'autre : moins un point. Laisser passer le vôtre : moins un point aussi.',
      'Il n\'y a pas de délai de réponse : la limite, c\'est le son suivant. Et les sons se resserrent au fil de la partie.',
    ],
    setup: 'Nombre de sons et leurres à régler à la sélection du jeu.',
  ),
  // 10 Duel
  GameRules(
    pitch: 'Deux joueurs, un signal sonore, le plus rapide l\'emporte.',
    howTo: [
      'Ce jeu se joue à deux, l\'un contre l\'autre.',
      'Le signal n\'est pas une lumière, c\'est un son. Vous pouvez fermer les yeux, ou vous tourner le dos.',
      'Dès que le son part, le premier à buzzer remporte la manche.',
      'Buzzer avant le son offre la manche à l\'adversaire, qui n\'a même pas besoin d\'appuyer.',
      'Le son change à chaque manche, pour que personne ne parte sur les premières notes.',
    ],
    setup: 'Exactement 2 buzzers en jeu.',
  ),
];

GameRules? rulesFor(int? gameMode) {
  if (gameMode == null || gameMode < 0 || gameMode >= kGameRules.length) return null;
  return kGameRules[gameMode];
}
