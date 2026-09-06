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
    {List<Facette> themes = const []}) {
  final store = BanqueStore();
  store.banque = Banque(questions: questions, themes: themes);
  return store;
}

void main() {
  // Un petit fonds représentatif : deux thématiques qui viennent d'un
  // fichier, une troisième qui les traverse, et une question qui ne se
  // prononce sur rien.
  //
  // CHAQUE QUESTION PORTE LA THÉMATIQUE DE SON FICHIER, comme dans la vraie
  // banque : c'est le générateur qui l'écrit, et un test de
  // banque_embarquee_test.dart garde qu'aucune n'en est dépourvue. Un fonds
  // qui l'oublierait rendrait ses questions injoignables au tirage.
  BanqueStore fonds() => magasin(
        [
          QuizQuestion(
              category: 'Histoire',
              question: 'H1',
              niveau: 1,
              ages: {Tranche.enfants},
              themes: {'Histoire'}),
          QuizQuestion(
              category: 'Histoire',
              question: 'H2',
              niveau: 3,
              ages: {Tranche.adultes, Tranche.aines},
              themes: {'Histoire'}),
          QuizQuestion(
              category: 'Musique',
              question: 'M1',
              niveau: 2,
              ages: {Tranche.enfants, Tranche.ados},
              themes: {'Musique'}),
          QuizQuestion(
              category: 'Musique',
              question: 'M2',
              niveau: 1,
              ages: {Tranche.aines},
              themes: {'Musique', 'Spécial Noël'}),
          QuizQuestion(
              category: 'Histoire',
              question: 'H3',
              niveau: 2,
              ages: {Tranche.ados},
              themes: {'Histoire', 'Spécial Noël'}),
          // Ni niveau ni tranche : une question écrite à la main, qui ne
          // s'est pas prononcée. Aucun filtre ne doit l'écarter.
          QuizQuestion(
              category: 'Histoire', question: 'X1', themes: {'Histoire'}),
        ],
        themes: const [
          Facette(nom: 'Histoire', emoji: '📜', questions: 4),
          Facette(nom: 'Musique', emoji: '🎵', questions: 2),
          Facette(nom: 'Spécial Noël', emoji: '🎄', questions: 2),
        ],
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
    final q = t.composer(themes: {'Musique'}, nombre: 50)!;
    expect(q.questions.length, 2);
    expect(q.note, contains('2'));
  });

  test('la thématique limite le tirage', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(7));
    final q = t.composer(themes: {'Musique'}, nombre: 5)!;
    for (final question in q.questions) {
      expect(question.question, startsWith('M'));
    }
  });

  test('une thématique transversale traverse les fichiers', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(11));
    final q = t.composer(themes: {'Spécial Noël'}, nombre: 5)!;
    final enonces = q.questions.map((e) => e.question).toSet();
    // C'est tout l'intérêt d'une transversale : M2 vient du fichier Musique
    // et H3 de Histoire. Aucune thématique de fichier ne rassemble les deux.
    expect(enonces, {'M2', 'H3'});
  });

  test('deux thématiques cochées se cumulent en OU, pas en ET', () {
    final t = TirageQuestions(banque: fonds(), hasard: Random(13));
    final q = t.composer(themes: {'Musique', 'Spécial Noël'}, nombre: 9)!;
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
    final attendu = t.compter(themes: {'Histoire'}, niveaux: {2});
    final obtenu =
        t.composer(themes: {'Histoire'}, niveaux: {2}, nombre: 99)!;
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
    expect(t.composer(themes: {'Musique'}, nombre: 1)!.title,
        contains('Musique'));
  });

  test('la clé ignore la casse, les espaces et la ponctuation finale', () {
    expect(
      TirageQuestions.cle(QuizQuestion(question: 'Qui a fondé Québec ?')),
      TirageQuestions.cle(QuizQuestion(question: '  qui a  fondé québec')),
    );
  });

  // ----------------------------------------------- L'équilibre de la manche

  // UN FONDS AUX PROPORTIONS DE LA VRAIE BANQUE, parce que c'est le
  // déséquilibre qui est en cause et qu'il ne se voit pas sur six questions.
  //
  // Mesuré sur la banque publiée : 192 questions écrites pour les enfants
  // contre 1553 pour les adultes, et plus de la moitié qui ne se prononcent
  // pas. Brasser puis couper reproduisait ces proportions telles quelles.
  BanqueStore fondsRealiste() {
    final questions = <QuizQuestion>[];
    var n = 0;
    void lot(String fichier, Set<Tranche> ages, int combien) {
      for (var i = 0; i < combien; i++) {
        questions.add(QuizQuestion(
            category: fichier,
            question: 'Q${n++}',
            answer: 'R',
            niveau: 1 + i % 3,
            ages: ages,
            themes: {fichier}));
      }
    }

    for (final c in ['Musique', 'Histoire', 'Géographie']) {
      lot(c, const {}, 180); // Ne se prononcent pas : pour tout le monde.
      lot(c, {Tranche.adultes, Tranche.aines}, 120);
      lot(c, {Tranche.ados, Tranche.adultes}, 60);
    }
    // Les enfants comme dans la vraie banque : rares, et absents d'une
    // catégorie entière.
    lot('Musique', {Tranche.enfants, Tranche.ados}, 12);
    lot('Histoire', {Tranche.enfants}, 6);
    return magasin(questions,
        themes: const [
          Facette(nom: 'Musique', emoji: '🎵', questions: 372),
          Facette(nom: 'Histoire', emoji: '📜', questions: 366),
          Facette(nom: 'Géographie', emoji: '🌍', questions: 360),
        ]);
  }

  int pour(Questionnaire q, Tranche t) =>
      q.questions.where((e) => e.ages.contains(t)).length;

  test('aucune tranche cochée sert quand même tout le monde', () {
    // C'est l'état par défaut de l'écran, et c'est là que le trou passait
    // inaperçu : une manche sur quatre ne contenait aucune question écrite
    // pour un enfant, et rien ne le disait.
    for (var graine = 0; graine < 40; graine++) {
      final t = TirageQuestions(banque: fondsRealiste(), hasard: Random(graine));
      final manche = t.composer(nombre: 25)!;
      for (final tranche in Tranche.values) {
        expect(pour(manche, tranche), greaterThanOrEqualTo(3),
            reason: 'graine $graine, ${kNomsTranches[tranche]}');
      }
    }
  });

  test('les planchers ne déforment pas le prorata par catégorie', () {
    // LE PIÈGE DES DEUX RÈGLES QUI SE MARCHENT DESSUS. Les questions écrites
    // pour les enfants vivent presque toutes en Musique : aller les chercher
    // pour tenir le plancher pouvait gonfler cette catégorie au détriment de
    // Géographie, et rendre la manche équilibrée par âge mais bancale par
    // sujet.
    //
    // Le plancher pioche donc en priorité dans la catégorie la plus en
    // retard sur sa cible, et la phase suivante rattrape le reste. Chaque
    // catégorie reste dans sa fenêtre d'arrondi : jamais plus loin de sa
    // cible que ce que l'arrondi impose déjà.
    const stocks = {'Musique': 372, 'Histoire': 366, 'Géographie': 360};
    const total = 1098;
    for (var graine = 0; graine < 30; graine++) {
      final t = TirageQuestions(banque: fondsRealiste(), hasard: Random(graine));
      final manche = t.composer(nombre: 24)!;
      for (final e in stocks.entries) {
        final cible = 24 * e.value / total;
        final obtenu = manche.questions.where((q) => q.category == e.key).length;
        expect(obtenu, inInclusiveRange(cible.floor(), cible.ceil()),
            reason: 'graine $graine, ${e.key}, cible $cible');
      }
    }
  });

  test('les catégories se répartissent au prorata de leur stock', () {
    final t = TirageQuestions(
        banque: magasin([
          for (var i = 0; i < 300; i++)
            QuizQuestion(category: 'Grosse', question: 'G$i', answer: 'R'),
          for (var i = 0; i < 100; i++)
            QuizQuestion(category: 'Petite', question: 'P$i', answer: 'R'),
        ]),
        hasard: Random(5));
    final manche = t.composer(nombre: 20)!;
    // Trois fois plus de stock, trois fois plus de questions. Exactement, et
    // non « en moyenne sur beaucoup de manches » : c'est celle de ce soir qui
    // compte.
    expect(manche.questions.where((q) => q.category == 'Grosse').length, 15);
    expect(manche.questions.where((q) => q.category == 'Petite').length, 5);
  });

  test('une seule tranche cochée ne déclenche aucun plancher', () {
    // Cocher « aînés » écarte déjà ce qui ne leur est pas destiné. Leur
    // imposer en plus un quota de questions écrites pour eux déciderait à
    // leur place qu'ils ne veulent rien de général.
    final t = TirageQuestions(banque: fondsRealiste(), hasard: Random(7));
    final manche = t.composer(nombre: 25, tranches: {Tranche.aines})!;
    final generales = manche.questions.where((q) => q.ages.isEmpty).length;
    expect(generales, greaterThan(8),
        reason: 'la moitié du fonds ne se prononce pas, la manche doit le montrer');
  });

  test('le plancher cède quand le stock n\'y est pas, et la note le dit', () {
    // Géographie n'a aucune question écrite pour les enfants. Ce n'est pas
    // une raison pour refuser de composer une manche de géographie, mais
    // l'animateur doit savoir ce qui manque avant de la poser.
    final t = TirageQuestions(banque: fondsRealiste(), hasard: Random(11));
    final manche = t.composer(themes: {'Géographie'}, nombre: 25)!;
    expect(manche.questions.length, 25);
    expect(pour(manche, Tranche.enfants), 0);
    expect(manche.note, contains('enfants'));
    expect(manche.note, isNot(contains('adultes')));
  });

  test('un fonds qui ne cote aucune tranche ne se fait pas sermonner', () {
    // Un questionnaire écrit à la main ne se prononce sur rien. Annoncer
    // « rien pour les enfants, les ados, les adultes et les aînés » serait
    // un avertissement de quatre lignes pour dire que l'axe ne sert pas.
    final t = TirageQuestions(
        banque: magasin([
          for (var i = 0; i < 40; i++)
            QuizQuestion(category: 'Maison', question: 'M$i', answer: 'R'),
        ]),
        hasard: Random(13));
    expect(t.composer(nombre: 10)!.note, isEmpty);
  });

  test('les planchers servent la tranche la plus rare en premier', () {
    // Beaucoup de questions portent deux ou trois tranches. Servir les
    // adultes d'abord viderait le tas commun avant que les enfants, qui n'ont
    // presque rien à eux, aient été rejoints.
    final t = TirageQuestions(banque: fondsRealiste(), hasard: Random(17));
    final manche = t.composer(nombre: 16)!;
    // 16 ÷ 8 = 2 par tranche. Le fonds ne porte que 18 questions enfants sur
    // 1098 : sans l'ordre par rareté, elles ne sortiraient jamais.
    expect(pour(manche, Tranche.enfants), greaterThanOrEqualTo(2));
  });

  test("l'arrondi se compense d'une manche à l'autre au lieu de s'accumuler", () {
    // 300 contre 100, en manches de 7 : les cibles tombent sur 5,25 et 1,75.
    // Il reste une place à donner, et la donner toujours à la même catégorie
    // (le plus fort reste) la ferait sortir 6 fois par manche au lieu de
    // 5,25, tous les soirs. Sur la vraie banque, ce biais faisait sortir
    // Québec 40 % plus souvent qu'Histoire pour 2 % d'écart de stock.
    var grosse = 0, petite = 0;
    const manches = 400;
    for (var graine = 0; graine < manches; graine++) {
      final t = TirageQuestions(
          banque: magasin([
            for (var i = 0; i < 300; i++)
              QuizQuestion(category: 'Grosse', question: 'G$i', answer: 'R'),
            for (var i = 0; i < 100; i++)
              QuizQuestion(category: 'Petite', question: 'P$i', answer: 'R'),
          ]),
          hasard: Random(graine));
      final m = t.composer(nombre: 7)!;
      expect(m.questions.length, 7, reason: 'graine $graine');
      grosse += m.questions.where((q) => q.category == 'Grosse').length;
      petite += m.questions.where((q) => q.category == 'Petite').length;
    }
    expect(grosse / manches, closeTo(5.25, 0.15));
    expect(petite / manches, closeTo(1.75, 0.15));
  });
}
