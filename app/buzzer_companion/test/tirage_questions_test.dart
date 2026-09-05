import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/questionnaires/catalogue.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';
import 'package:buzzer_companion/questionnaires/tirage_questions.dart';

// LE TIRAGE D'UNE MANCHE AU HASARD.
//
// Ce qui doit être juste ici ne se voit pas à l'écran : une question posée
// deux fois dans la soirée, c'est un blanc gêné et un point donné pour rien,
// et l'animateur ne le découvre qu'en la relisant à voix haute.
//
// Le catalogue est simulé : ces tests portent sur les règles du tirage, pas
// sur le réseau.

class _CatalogueSimule extends CatalogueStore {
  _CatalogueSimule(this._contenus) {
    catalogue = Catalogue(
      entries: [
        for (final e in _contenus.entries)
          CatalogueEntry(
            id: e.key,
            title: e.key,
            note: '',
            collection: e.key.split('-').first,
            emoji: '',
            questionCount: e.value.length,
            bytes: 0,
            fingerprint: e.key,
          ),
      ],
      collections: const [],
    );
  }

  final Map<String, List<String>> _contenus;

  /// Combien de fichiers ont réellement été lus : c'est tout l'enjeu du
  /// tirage par questionnaires plutôt que par chargement complet.
  int lectures = 0;

  /// Ce que l'appelant a demandé de garder en cache. Le tirage doit le
  /// demander, sinon une soirée jouée en ligne ne laisse rien pour la
  /// suivante et on rejoue les questions du build.
  final List<bool> gardes = [];

  @override
  Future<Questionnaire?> load(CatalogueEntry entry, {bool garder = false}) async {
    lectures++;
    gardes.add(garder);
    final enonces = _contenus[entry.id];
    if (enonces == null) return null;
    return Questionnaire(
      title: entry.title,
      collection: entry.collection,
      questions: [
        for (final e in enonces) QuizQuestion(question: e, answer: 'R'),
      ],
    );
  }
}

void main() {
  // Trois collections, et des doublons VOLONTAIRES entre elles : les
  // mélanges du vrai catalogue reprennent les questions des collections
  // thématiques, c'est exactement le cas à ne pas rater.
  _CatalogueSimule creerCatalogue() => _CatalogueSimule({
        'histoire-1': ['H1', 'H2', 'H3', 'H4', 'H5'],
        'histoire-2': ['H6', 'H7', 'H8', 'H9', 'H10'],
        'melanges-1': ['H1', 'G1', 'G2', 'H6', 'M1'],
        'geo-1': ['G1', 'G2', 'G3', 'G4', 'G5'],
      });

  test('compose le nombre demandé', () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(1));
    final q = await tirage.composer(nombre: 8);
    expect(q, isNotNull);
    expect(q!.questions.length, 8);
  });

  test('jamais deux fois la même question dans une manche', () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(3));
    // Vingt demandées pour seize distinctes : le tirage DOIT traverser les
    // doublons entre « mélanges » et les collections thématiques.
    final q = await tirage.composer(nombre: 20);
    expect(q, isNotNull);

    final cles = q!.questions.map(TirageQuestions.cle).toList();
    expect(cles.toSet().length, cles.length, reason: 'doublon dans la manche');
    // Seize enonces distincts existent : on ne peut pas en avoir plus.
    expect(q.questions.length, 16);
  });

  test('deux manches de suite ne se recoupent pas', () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(5));
    final a = await tirage.composer(nombre: 6);
    final b = await tirage.composer(nombre: 6);

    final clesA = a!.questions.map(TirageQuestions.cle).toSet();
    final clesB = b!.questions.map(TirageQuestions.cle).toSet();
    expect(clesA.intersection(clesB), isEmpty);
  });

  test('le périmètre limite bien le tirage', () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(7));
    final q = await tirage.composer(collection: 'geo', nombre: 5);
    expect(q, isNotNull);
    for (final question in q!.questions) {
      expect(question.question, startsWith('G'));
    }
  });

  test('un périmètre trop petit donne une manche plus courte, pas une erreur',
      () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(9));
    final q = await tirage.composer(collection: 'geo', nombre: 50);
    expect(q, isNotNull);
    expect(q!.questions.length, 5);
    // La note le dit, plutot que de laisser l'animateur compter.
    expect(q.note, contains('5'));
  });

  test('ON NE LIT PAS TOUT LE CATALOGUE pour quelques questions', () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(11));
    await tirage.composer(nombre: 3);
    // Trois questions tiennent dans un seul fichier : en lire quatre serait
    // trois requetes de trop dans une salle sans wifi.
    expect(cat.lectures, 1);
  });

  test('ce qui sert à jouer est gardé pour la prochaine fois', () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(23));
    await tirage.composer(nombre: 8);
    // Sans ce drapeau, une soirée jouée avec du réseau ne laisse rien : au
    // redémarrage sans wifi, on retombe sur les questions du build.
    expect(cat.gardes, isNotEmpty);
    expect(cat.gardes.every((g) => g), isTrue);
  });

  test('un périmètre inconnu ne fait pas planter', () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(13));
    final q = await tirage.composer(collection: 'inexistante', nombre: 5);
    expect(q, isNull);
    expect(tirage.derniereErreur, isNotNull);
  });

  test('la question de bris évite celles déjà posées', () async {
    final cat = creerCatalogue();
    final tirage = TirageQuestions(catalogue: cat, hasard: Random(17));
    final manche = await tirage.composer(nombre: 14);
    final posees = manche!.questions.map(TirageQuestions.cle).toSet();

    final bris = await tirage.questionDeBris();
    expect(bris, isNotNull);
    expect(posees.contains(TirageQuestions.cle(bris!)), isFalse);
  });

  test('la clé ignore la casse, les espaces et la ponctuation finale', () {
    expect(
      TirageQuestions.cle(QuizQuestion(question: 'Qui a fondé Québec ?')),
      TirageQuestions.cle(QuizQuestion(question: '  qui a  fondé québec')),
    );
  });

  // LES DEUX FILTRES DE LA COMPOSITION À LA DEMANDE.
  //
  // Le classement des questions par niveau et par tranche d'âge n'a de valeur
  // que s'il sert au moment de jouer. Ce qui se joue ici : un filtre qui
  // écarte trop est pire qu'un filtre absent, parce que l'animateur ne voit
  // pas ce qui manque.
  _CatalogueCote creerCote() => _CatalogueCote([
        QuizQuestion(question: 'E1', niveau: 1, ages: {Tranche.enfants}),
        QuizQuestion(question: 'E2', niveau: 2, ages: {Tranche.enfants, Tranche.ados}),
        QuizQuestion(question: 'A1', niveau: 3, ages: {Tranche.adultes, Tranche.aines}),
        QuizQuestion(question: 'A2', niveau: 1, ages: {Tranche.aines}),
        // Ni niveau ni tranche : une question écrite à la main, qui ne s'est
        // pas prononcée. Aucun filtre ne doit l'écarter.
        QuizQuestion(question: 'X1'),
      ]);

  test('le filtre de niveau ne garde que les niveaux cochés', () async {
    final tirage = TirageQuestions(catalogue: creerCote(), hasard: Random(5));
    final q = await tirage.composer(nombre: 10, niveaux: {1});
    expect(q, isNotNull);
    final enonces = q!.questions.map((e) => e.question).toSet();
    expect(enonces, containsAll(['E1', 'A2']));
    expect(enonces, isNot(contains('E2')));
    expect(enonces, isNot(contains('A1')));
  });

  test('une question vaut pour chacune de ses tranches, pas seulement la première',
      () async {
    final tirage = TirageQuestions(catalogue: creerCote(), hasard: Random(7));
    final q = await tirage.composer(nombre: 10, tranches: {Tranche.ados});
    // E2 vise enfants ET ados : demander les ados doit la ramener.
    expect(q!.questions.map((e) => e.question), contains('E2'));
    expect(q.questions.map((e) => e.question), isNot(contains('A1')));
  });

  test('une question qui ne se prononce pas passe tous les filtres', () async {
    final tirage = TirageQuestions(catalogue: creerCote(), hasard: Random(11));
    final q = await tirage.composer(
        nombre: 10, niveaux: {3}, tranches: {Tranche.enfants});
    // Le filtre est contradictoire pour les questions cotées, mais X1 n'a
    // rien déclaré : la punir de son silence n'aurait pas de sens.
    expect(q!.questions.map((e) => e.question), contains('X1'));
  });

  test('les deux filtres se combinent', () async {
    final tirage = TirageQuestions(catalogue: creerCote(), hasard: Random(13));
    final q = await tirage.composer(
        nombre: 10, niveaux: {1}, tranches: {Tranche.aines});
    final enonces = q!.questions.map((e) => e.question).toSet();
    expect(enonces, contains('A2')); // niveau 1 ET aînés
    expect(enonces, isNot(contains('E1'))); // niveau 1, mais enfants
    expect(enonces, isNot(contains('A1'))); // aînés, mais niveau 3
  });

  test('un filtre sans réponse le dit, au lieu de rendre une manche vide',
      () async {
    final tirage = TirageQuestions(
        catalogue: _CatalogueCote([
          QuizQuestion(question: 'A1', niveau: 3, ages: {Tranche.aines}),
        ]),
        hasard: Random(19));
    final q = await tirage.composer(nombre: 5, niveaux: {1});
    expect(q, isNull);
    expect(tirage.derniereErreur, contains('critères'));
  });
}

// Un catalogue d'un seul fichier, dont les questions portent leur niveau et
// leurs tranches : ce que le vrai catalogue publie depuis que les deux axes
// sont dans le JSON.
class _CatalogueCote extends CatalogueStore {
  _CatalogueCote(this._questions) {
    catalogue = Catalogue(
      entries: const [
        CatalogueEntry(
          id: 'cote-1',
          title: 'cote-1',
          note: '',
          collection: 'cote',
          emoji: '',
          questionCount: 5,
          bytes: 0,
          fingerprint: 'cote-1',
        ),
      ],
      collections: const [],
    );
  }

  final List<QuizQuestion> _questions;

  @override
  Future<Questionnaire?> load(CatalogueEntry entry, {bool garder = false}) async => Questionnaire(
        title: entry.title,
        collection: entry.collection,
        questions: [for (final q in _questions) q.copy()],
      );
}
