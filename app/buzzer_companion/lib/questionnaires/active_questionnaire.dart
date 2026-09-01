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
  int? _lastPhase;

  bool get active => _questionnaire != null && _questionnaire!.questions.isNotEmpty;
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
    _push();
    notifyListeners();
  }

  void clear() {
    _questionnaire = null;
    _origine = '';
    _index = 0;
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

  // Appelée à chaque notification de l'état de partie.
  void onGameChanged() {
    final phase = _game.phase;
    final avant = _lastPhase;
    if (phase == avant) return;
    _lastPhase = phase;
    if (!active || phase == null) return;

    if (!isPhase(phase, 'WAITING_BUZZER')) return;

    if (avant != null && (isPhase(avant, 'SHOW_SCORES') || isPhase(avant, 'ANSWER_REVEAL'))) {
      next();
    } else if (avant != null && isPhase(avant, 'INTRO')) {
      // Début de partie : on repart de la première question, même si le
      // questionnaire avait déjà servi.
      _index = 0;
      _push();
      notifyListeners();
    }
  }
}
