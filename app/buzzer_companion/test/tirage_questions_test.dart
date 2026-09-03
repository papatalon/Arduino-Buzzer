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

  @override
  Future<Questionnaire?> load(CatalogueEntry entry) async {
    lectures++;
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
}
