import 'package:flutter/foundation.dart';

import '../protocol.dart';
import 'questionnaire.dart';

// Le questionnaire en jeu, quand c'est l'application qui fournit les
// questions plutôt que la banque compilée dans le firmware.
//
// LE PARTAGE DES RÔLES. En mode applicatif, le buzzer ne s'occupe que des
// boutons : qui a sonné le premier, les lumières, le verrouillage entre deux
// questions. Les questions, elles, viennent d'ici. Le firmware a déjà tout
// ce qu'il faut pour s'effacer : un masque de catégories à zéro met sa banque
// en retrait (« l'animateur utilise son propre questionnaire ») et le reste
// de la partie continue de tourner sans rien savoir des questions.
//
// COMMENT ON SAIT QU'IL FAUT AVANCER. Pas en supposant que l'application
// provoque chaque avancement : le Mega quitte l'écran des scores tout seul
// après un délai (SCORES_DISPLAY_MS), sans que personne ait cliqué. On
// observe donc les transitions de phase, qui sont annoncées : entrer en
// attente de buzz EN VENANT des scores ou de la révélation de réponse, c'est
// une nouvelle question. Y entrer en venant d'un buzz, c'est la même question
// qu'un autre joueur peut encore tenter après une mauvaise réponse.
//
// Ça reste une déduction, alors les flèches « précédente » et « suivante » de
// la console existent : si un jour ça décale, l'animateur rattrape en un clic
// au lieu de finir la soirée décalé d'un cran.
class ActiveQuestionnaire extends ChangeNotifier {
  ActiveQuestionnaire(this._game);

  final GameState _game;

  Questionnaire? _questionnaire;
  String _origine = '';
  int _index = 0;

  // QUESTIONNAIRE LIBRE : l'animateur pose ses propres questions, l'app ne
  // fait que compter les points. Le questionnaire choisi n'est PAS oublié
  // pour autant : on peut jouer une manche libre entre deux manches d'un
  // questionnaire sans avoir à le rechoisir après.
  bool libre = false;

  // Nombre de questions d'une manche libre, ou null pour « sans limite »,
  // où l'animateur arrête quand il veut. Sans objet quand un questionnaire
  // fournit les questions : c'est sa longueur qui décide.
  int? nombreLibre;

  bool get active => _questionnaire != null && _questionnaire!.questions.isNotEmpty;

  // Vrai quand une partie peut démarrer : soit un questionnaire fournit les
  // questions, soit l'animateur a dit qu'il posait les siennes.
  bool get pretAJouer => libre || active;

  // Ce que « Lancer la partie » envoie au buzzer (START_GAME|<n>).
  //
  // Zéro veut dire « ouvert » : le buzzer ne compte pas. C'est le cas avec un
  // questionnaire, puisque c'est l'app qui sait quand il est épuisé, et le
  // cas d'une manche libre sans limite.
  int get nombreALancer => libre ? (nombreLibre ?? 0) : 0;

  void utiliserLibre({int? nombre}) {
    libre = true;
    nombreLibre = nombre;
    // Les questions ne viennent plus de l'app : elle ne doit pas continuer
    // d'en afficher une.
    _game.setAppQuestion(null, null, null);
    notifyListeners();
  }

  // Revenir au questionnaire deja choisi apres une manche libre.
  void reprendreQuestionnaire() {
    if (!active) return;
    libre = false;
    _push();
    notifyListeners();
  }

  void reglerNombreLibre(int? nombre) {
    if (nombreLibre == nombre) return;
    nombreLibre = nombre;
    notifyListeners();
  }

  String get title => _questionnaire?.title ?? '';
  String get origine => _origine;
  int get index => _index;
  int get total => _questionnaire?.questions.length ?? 0;

  // Vrai quand on a dépassé la dernière question. La partie continue côté
  // buzzer (scores, chrono) mais il n'y a plus rien à poser : mieux vaut le
  // dire que d'afficher un vide inexpliqué.
  bool get exhausted => active && _index >= total;

  QuizQuestion? get current =>
      active && _index >= 0 && _index < total ? _questionnaire!.questions[_index] : null;

  void use(Questionnaire questionnaire, {required String origine}) {
    _questionnaire = questionnaire;
    _origine = origine;
    _index = 0;
    // Choisir un questionnaire sort du mode libre : c'est lui qui fournit les
    // questions maintenant.
    libre = false;
    _push();
    notifyListeners();
  }

  void clear() {
    _questionnaire = null;
    _origine = '';
    _index = 0;
    libre = false;
    nombreLibre = null;
    _game.setAppQuestion(null, null, null);
    notifyListeners();
  }

  void next() => goTo(_index + 1);
  void previous() => goTo(_index - 1);

  void goTo(int i) {
    if (!active) return;
    // Borné à total, et non à total - 1 : dépasser la dernière question est
    // un état légitime (le questionnaire est épuisé), pas une erreur.
    final borne = i.clamp(0, total);
    if (borne == _index) return;
    _index = borne;
    _push();
    notifyListeners();
  }

  // Écrit la question courante dans l'état de partie, aux mêmes champs que la
  // banque du firmware remplirait. Tout l'aval suit sans le savoir : la
  // console, l'écran public, et la règle qui garde la réponse cachée jusqu'à
  // la fin de la question.
  void _push() {
    final q = current;
    _game.setAppQuestion(
      q?.category.isEmpty ?? true ? null : q!.category,
      q?.question,
      q?.answer,
      numero: q == null ? null : _index + 1,
    );
  }

  // L'AVANCEMENT N'EST PLUS DEDUIT. Il l'etait, en observant les transitions
  // de phase du buzzer, parce que c'etait le buzzer qui menait la partie. En
  // mode application, c'est le moteur de jeu qui decide quand on passe a la
  // question suivante, et il le dit : il appelle goTo(). Deduire ce qu'on
  // decide soi-meme etait le symptome d'un mauvais partage des roles.
}
