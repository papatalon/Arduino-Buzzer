import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/protocol.dart';
import 'package:buzzer_companion/questionnaires/active_questionnaire.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';

// Le questionnaire en jeu est la réserve de questions de l'application : le
// moteur de jeu lui dit où aller, et lui pousse la question courante dans
// l'état de partie, d'où l'écran public et la console la lisent.
//
// Il n'y a plus rien de déduit ici. L'avancement était autrefois deviné en
// observant les transitions de phase du buzzer, parce que le buzzer menait la
// partie ; c'est le moteur qui décide maintenant, et [moteur_quiz_test.dart]
// couvre ses règles. Ce qui reste à protéger, c'est le bornage (aucun index
// hors du questionnaire) et le fait que les champs se vident au lieu de garder
// éternellement la dernière question affichée.

void main() {
  late StreamController<String> messages;
  late GameState game;
  late ActiveQuestionnaire actif;

  setUp(() {
    messages = StreamController<String>();
    game = GameState();
    game.listenTo(messages.stream);
    actif = ActiveQuestionnaire(game);
  });

  tearDown(() async {
    await messages.close();
  });

  Questionnaire troisQuestions() => Questionnaire(
        title: 'Essai',
        questions: [
          QuizQuestion(themes: {'Un'}, question: 'Q1', answer: 'R1'),
          QuizQuestion(themes: {'Deux'}, question: 'Q2', answer: 'R2'),
          QuizQuestion(themes: {'Trois'}, question: 'Q3', answer: 'R3'),
        ],
      );

  test('la question de l\'app alimente les champs de l\'état de partie', () {
    actif.use(troisQuestions(), origine: 'Essai');
    expect(game.questionText, 'Q1');
    expect(game.answerText, 'R1');
    expect(game.questionCategory, 'Un');
    expect(game.appQuestion, isTrue);
    // Le compteur de l'écran public compte les questions posées.
    expect(game.questionsAsked, 1);
  });

  test('avancer pousse la question suivante', () {
    actif.use(troisQuestions(), origine: 'Essai');
    actif.next();
    expect(actif.index, 1);
    expect(game.questionText, 'Q2');
    expect(game.questionCategory, 'Deux');
  });

  test('passé la dernière question, le questionnaire est épuisé', () {
    actif.use(troisQuestions(), origine: 'Essai');
    actif.next();
    actif.next();
    expect(actif.index, 2);
    expect(actif.exhausted, isFalse);

    actif.next();
    expect(actif.exhausted, isTrue);
    // Plus de question à poser : les champs se vident au lieu de garder la
    // dernière question affichée pour toujours.
    expect(game.questionText, isNull);
    expect(game.appQuestion, isFalse);
  });

  test('le rattrapage manuel reste borné', () {
    actif.use(troisQuestions(), origine: 'Essai');
    actif.previous();
    expect(actif.index, 0);      // pas de question -1
    actif.goTo(99);
    expect(actif.index, 3);      // épuisé, mais pas au-delà
    expect(actif.exhausted, isTrue);
    actif.previous();
    expect(actif.index, 2);
    expect(game.questionText, 'Q3');
  });

  test('revenir à la première question relit bien la première', () {
    actif.use(troisQuestions(), origine: 'Essai');
    actif.goTo(2);
    expect(game.questionText, 'Q3');
    // Ce que fait le moteur au démarrage d'une nouvelle partie, même si le
    // questionnaire avait déjà servi.
    actif.goTo(0);
    expect(game.questionText, 'Q1');
    expect(actif.exhausted, isFalse);
  });

  test('retirer le questionnaire libère les champs', () {
    actif.use(troisQuestions(), origine: 'Essai');
    expect(game.questionText, 'Q1');
    actif.clear();
    expect(actif.active, isFalse);
    expect(game.questionText, isNull);
    expect(game.appQuestion, isFalse);
  });

  test('en manche libre, l\'app ne fournit aucune question', () {
    actif.utiliserLibre(nombre: 5);
    expect(actif.libre, isTrue);
    expect(game.questionText, isNull);
    expect(game.appQuestion, isFalse);
    // Et la faire avancer ne fabrique rien à afficher.
    actif.goTo(3);
    expect(game.questionText, isNull);
  });

  test('sans questionnaire actif, une QUESTION du buzzer passe normalement', () async {
    messages.add('QUESTION|Histoire|Qui a fondé Québec ?|Champlain');
    await Future<void>.delayed(Duration.zero);
    expect(game.questionText, 'Qui a fondé Québec ?');
    expect(game.appQuestion, isFalse);
  });
}
