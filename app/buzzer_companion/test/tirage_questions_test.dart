import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/questionnaires/banque.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';
import 'package:buzzer_companion/questionnaires/tirage_questions.dart';

// LA MANCHE COMPOSÉE SUR PLACE.
//
// Ce qui doit être juste ici ne se voit pas à l'écran : une question posée
// deux fois dans la soirée, c'est un blanc gêné et un point donné pour rien,
// et l'animateur ne le découvre qu'en la relisant à voix haute. Un filtre qui
// écarte trop est pire encore, parce que rien ne le signale.

// Un magasin qu'on remplit à la main : ces tests portent sur les règles du
// tirage, pas sur la lecture du fichier.
BanqueStore magasin(List<QuizQuestion> questions,
    {List<Facette> categories = const [], List<Facette> themes = const []}) {
  final store = BanqueStore();
  store.banque = Banque(
    questions: questions,
    categories: categories,
    themes: themes,
  );
  return store;
}

void main() {
  // Un petit fonds représentatif : deux catégories, une thématique qui les
  // traverse, les deux axes de classement, et une question qui ne se
  // prononce sur rien.
  BanqueStore fonds() => magasin(
        [
          QuizQuestion(
              category: 'Histoire',
              question: 'H1',
              niveau: 1,
              ages: {Tranche.enfants}),
          QuizQuestion(
              category: 'Histoire',
              question: 'H2',
              niveau: 3,
              ages: {Tranche.adultes, Tranche.aines}),
          QuizQuestion(
              category: 'Musique',
              question: 'M1',
              niveau: 2,
              ages: {Tranche.enfants, Tranche.ados}),
          QuizQuestion(
              category: 'Musique',
              question: 'M2',
              niveau: 1,
              ages: {Tranche.aines},
              themes: {'Spécial Noël'}),
          QuizQuestion(
              category: 'Histoire',
              question: 'H3',
              niveau: 2,
              ages: {Tranche.ados},
              themes: {'Spécial Noël'}),
          // Ni niveau ni tranche : une question écrite à la main, qui ne
          // s'est pas prononcée. Aucun filtre ne doit l'écarter.
          QuizQuestion(category: 'Histoire', question: 'X1'),
        ],
        categories: const [
          Facette(nom: 'Histoire', emoji: '📜', questions: 4),
          Facette(nom: 'Musique', emoji: '🎵', questions: 2),
        ],
        themes: const [Facette(nom: 'Spécial Noël', emoji: '🎄', questions: 2)],
      );

  test('compose le nombre demandé', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(1));
    expect(t.composer(nombre: 4)!.questions.length, 4);
  });

  test('jamais deux fois la même question dans une manche', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(3));
    final q = t.composer(nombre: 6)!;
    final cles = q.questions.map(TirageQuestions.cle).toList();
    expect(cles.toSet().length, cles.length, reason: 'doublon dans la manche');
  });

  test('deux manches de suite ne se recoupent pas', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(5));
    final a = t.composer(nombre: 3)!;
    final b = t.composer(nombre: 3)!;
    final clesA = a.questions.map(TirageQuestions.cle).toSet();
    final clesB = b.questions.map(TirageQuestions.cle).toSet();
    expect(clesA.intersection(clesB), isEmpty);
  });

  test('une manche plus courte plutôt qu\'une erreur, et la note le dit', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(9));
    final q = t.composer(categories: {'Musique'}, nombre: 50)!;
    expect(q.questions.length, 2);
    expect(q.note, contains('2'));
  });

  test('la catégorie limite le tirage', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(7));
    final q = t.composer(categories: {'Musique'}, nombre: 5)!;
    for (final question in q.questions) {
      expect(question.question, startsWith('M'));
    }
  });

  test('une thématique traverse les catégories', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(11));
    final q = t.composer(themes: {'Spécial Noël'}, nombre: 5)!;
    final enonces = q.questions.map((e) => e.question).toSet();
    // C'est tout l'intérêt d'une thématique : M2 vient de Musique et H3 de
    // Histoire. Aucune catégorie ne sait rassembler les deux.
    expect(enonces, {'M2', 'H3'});
  });

  test('catégories et thématiques se cumulent en OU, pas en ET', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(13));
    final q = t.composer(
        categories: {'Musique'}, themes: {'Spécial Noël'}, nombre: 9)!;
    final enonces = q.questions.map((e) => e.question).toSet();
    // L'intersection serait le seul M2. L'union ramène aussi M1 et H3.
    expect(enonces, containsAll(['M1', 'M2', 'H3']));
  });

  test('le filtre de niveau ne garde que les niveaux cochés', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(5));
    final enonces =
        t.composer(nombre: 9, niveaux: {1})!.questions.map((e) => e.question).toSet();
    expect(enonces, containsAll(['H1', 'M2']));
    expect(enonces, isNot(contains('H2')));
  });

  test('une question vaut pour chacune de ses tranches', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(7));
    final enonces = t
        .composer(nombre: 9, tranches: {Tranche.ados})!
        .questions
        .map((e) => e.question)
        .toSet();
    // M1 vise enfants ET ados : demander les ados doit la ramener.
    expect(enonces, containsAll(['M1', 'H3']));
    expect(enonces, isNot(contains('H1')));
  });

  test('une question qui ne se prononce pas passe tous les filtres', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(11));
    final q = t.composer(nombre: 9, niveaux: {3}, tranches: {Tranche.enfants})!;
    // Le filtre est contradictoire pour les questions cotées, mais X1 n'a
    // rien déclaré : la punir de son silence n'aurait pas de sens.
    expect(q.questions.map((e) => e.question), contains('X1'));
  });

  test('le compte annonce ce que le tirage trouvera', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(17));
    // Ce compte s'affiche pendant qu'on coche : s'il mentait, l'animateur
    // découvrirait sa manche tronquée une fois la partie lancée.
    final attendu = t.compter(categories: {'Histoire'}, niveaux: {2});
    final obtenu =
        t.composer(categories: {'Histoire'}, niveaux: {2}, nombre: 99)!;
    expect(obtenu.questions.length, attendu);
  });

  test('un filtre sans réponse le dit, au lieu de rendre une manche vide', () {
    final t = TirageQuestions(
        banque: magasin([
          QuizQuestion(
              category: 'Histoire', question: 'H2', niveau: 3, ages: {Tranche.aines}),
        ]),
        hasard: Random(19));
    expect(t.composer(nombre: 5, niveaux: {1}), isNull);
    expect(t.derniereErreur, contains('critères'));
  });

  test('une banque vide le dit aussi, et autrement', () {
    final t = TirageQuestions(banque: magasin(const []), hasard: Random(23));
    expect(t.composer(nombre: 5), isNull);
    expect(t.derniereErreur, contains('vide'));
  });

  test('la question de bris évite celles déjà posées', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(17));
    final manche = t.composer(nombre: 4)!;
    final posees = manche.questions.map(TirageQuestions.cle).toSet();
    final bris = t.questionDeBris();
    expect(bris, isNotNull);
    expect(posees.contains(TirageQuestions.cle(bris!)), isFalse);
  });

  test('le titre dit le périmètre, parce que la salle le lit', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(29));
    expect(t.composer(nombre: 2)!.title, 'Questions au hasard');
    expect(t.composer(categories: {'Musique'}, nombre: 1)!.title,
        contains('Musique'));
  });

  test('la clé ignore la casse, les espaces et la ponctuation finale', () {
    expect(
      TirageQuestions.cle(QuizQuestion(question: 'Qui a fondé Québec ?')),
      TirageQuestions.cle(QuizQuestion(question: '  qui a  fondé québec')),
    );
  });
}
