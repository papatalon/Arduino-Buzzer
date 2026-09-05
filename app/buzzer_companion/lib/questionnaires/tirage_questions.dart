import 'dart:math';

import 'banque.dart';
import 'questionnaire.dart';

// UNE MANCHE COMPOSÉE SUR PLACE, pour une partie et une seule.
//
// C'est devenu la façon normale de jouer. L'animateur dit ce qu'il a devant
// lui — des enfants, un mélange, des connaisseurs — et la manche se compose.
// Elle n'existera qu'une fois.
//
// CE QUI A DISPARU ET POURQUOI. Le tirage piochait dans 283 questionnaires
// prédécoupés, en évitant de tous les charger : quelques fichiers plutôt que
// cent vingt-cinq requêtes. La banque tient maintenant dans un seul fichier
// de 570 ko, lu une fois au démarrage, et cette gymnastique n'a plus lieu
// d'être. Le tirage voit toutes les questions à la fois, ce qui lui permet de
// filtrer sur n'importe quelle combinaison de critères — chose impossible
// quand il fallait deviner quel fichier contenait des questions faciles pour
// enfants en histoire.
//
// LES DOUBLONS RESTENT LE VRAI PIÈGE, même si la banque ne contient plus
// qu'un exemplaire de chaque question : deux manches de suite dans le même
// périmètre ne doivent pas se recouper. Deux fois la même question dans une
// soirée, c'est un blanc gêné et un point donné pour rien.
class TirageQuestions {
  TirageQuestions({required this.banque, Random? hasard})
      : _hasard = hasard ?? Random();

  final BanqueStore banque;
  final Random _hasard;

  /// Ce qu'on a déjà posé ce soir. Conservé entre deux tirages.
  final Set<String> _dejaPosees = {};

  /// Message quand le tirage n'a pas pu aboutir. Null si tout va bien.
  String? derniereErreur;

  /// La clé d'unicité : l'énoncé, débarrassé de sa casse, de ses espaces et
  /// de sa ponctuation de fin.
  static String cle(QuizQuestion q) => q.question
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[?!.…\s]+$'), '')
      .trim();

  void oublierCeQuiAEtePose() => _dejaPosees.clear();

  List<Facette> get categories => banque.banque.categories;
  List<Facette> get themes => banque.banque.themes;

  /// Combien de questions répondent à ces critères, avant même de tirer.
  /// Affiché à côté des cases : un filtre qui ne laisse que huit questions
  /// doit se voir AVANT de composer, pas après.
  int compter({
    Set<String> categories = const {},
    Set<String> themes = const {},
    Set<int> niveaux = const {},
    Set<Tranche> tranches = const {},
  }) =>
      banque.banque.questions
          .where((q) => _retenue(q, categories, themes, niveaux, tranches))
          .length;

  /// Un filtre vide veut dire « sans filtre ». Une question qui ne porte pas
  /// de niveau, ou pas de tranche, passe toujours : un questionnaire écrit à
  /// la main ne se prononce pas, et l'écarter reviendrait à le punir de son
  /// silence.
  bool _retenue(
    QuizQuestion q,
    Set<String> categories,
    Set<String> themes,
    Set<int> niveaux,
    Set<Tranche> tranches,
  ) {
    if (!q.isUsable) return false;
    // Catégories et thématiques se cumulent en OU : cocher « Québec » et
    // « Spécial Noël » demande les questions de l'un OU de l'autre, pas leur
    // intersection, qui serait presque toujours vide.
    if (categories.isNotEmpty || themes.isNotEmpty) {
      final parCategorie = categories.contains(q.category);
      final parTheme = q.themes.any(themes.contains);
      if (!parCategorie && !parTheme) return false;
    }
    if (niveaux.isNotEmpty && q.niveau != null && !niveaux.contains(q.niveau)) {
      return false;
    }
    if (tranches.isNotEmpty &&
        q.ages.isNotEmpty &&
        q.ages.intersection(tranches).isEmpty) {
      return false;
    }
    return true;
  }

  /// Compose une manche de [nombre] questions.
  ///
  /// Retourne une manche plus courte que demandé si les critères ne laissent
  /// pas assez de questions, plutôt que d'échouer : mieux vaut douze
  /// questions qu'aucune, et la note le dit.
  Questionnaire? composer({
    Set<String> categories = const {},
    Set<String> themes = const {},
    Set<int> niveaux = const {},
    Set<Tranche> tranches = const {},
    required int nombre,
  }) {
    derniereErreur = null;

    if (banque.banque.isEmpty) {
      derniereErreur = banque.lastError ?? "La banque de questions est vide.";
      return null;
    }

    final candidates = banque.banque.questions
        .where((q) => _retenue(q, categories, themes, niveaux, tranches))
        .where((q) => !_dejaPosees.contains(cle(q)))
        .toList()
      ..shuffle(_hasard);

    if (candidates.isEmpty) {
      final filtre = categories.isNotEmpty ||
          themes.isNotEmpty ||
          niveaux.isNotEmpty ||
          tranches.isNotEmpty;
      // Distinguer les deux échecs : « tout a déjà été posé » et « ces
      // critères ne donnent rien » n'appellent pas le même geste.
      derniereErreur = _dejaPosees.isNotEmpty && !filtre
          ? "Toutes les questions ont déjà été posées ce soir."
          : filtre
              ? 'Aucune question ne répond à ces critères. Élargissez la '
                  "sélection, ou le niveau et la tranche d'âge."
              : "Aucune question à poser.";
      return null;
    }

    final retenues = candidates.take(nombre).map((q) => q.copy()).toList();
    _dejaPosees.addAll(retenues.map(cle));

    return Questionnaire(
      title: _titre(categories, themes),
      note: retenues.length < nombre
          ? 'Seulement ${retenues.length} questions répondaient aux critères.'
          : '',
      questions: retenues,
    );
  }

  /// Une seule question, pour départager. Jamais une de celles déjà posées.
  QuizQuestion? questionDeBris({
    Set<String> categories = const {},
    Set<String> themes = const {},
  }) {
    final compose =
        composer(categories: categories, themes: themes, nombre: 1);
    if (compose == null || compose.questions.isEmpty) return null;
    return compose.questions.first;
  }

  // Le titre dit le périmètre, parce qu'il s'affiche sur l'écran public et
  // que la salle doit comprendre ce qu'on lui pose.
  String _titre(Set<String> categories, Set<String> themes) {
    final noms = [...categories, ...themes];
    if (noms.isEmpty) return 'Questions au hasard';
    if (noms.length == 1) return 'Au hasard : ${noms.first}';
    return 'Au hasard : ${noms.length} sélections';
  }
}
