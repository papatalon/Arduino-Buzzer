import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/protocol.dart';
import 'package:buzzer_companion/questionnaires/active_questionnaire.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';

// L'avancement du questionnaire de l'application est DÉDUIT des transitions
// de phase du buzzer, pas commandé : le Mega quitte l'écran des scores tout
// seul après un délai. C'est donc la pièce la plus facile à casser sans le
// voir, et la seule qui ne se vérifie pas à l'œil sans buzzer branché.
//
// Les phases arrivent par le vrai chemin (des lignes « STATE|<n> » dans le
// flux de messages), pas en écrivant dans les champs : un test qui court-
// circuite le parsing ne prouverait rien sur le comportement réel.

String _state(String nom) => 'STATE|${kPhaseNames.indexOf(nom)}';

void main() {
  late StreamController<String> messages;
  late GameState game;
  late ActiveQuestionnaire actif;

  setUp(() {
    messages = StreamController<String>();
    game = GameState();
    game.listenTo(messages.stream);
    actif = ActiveQuestionnaire(game);
    game.addListener(actif.onGameChanged);
  });

  tearDown(() async {
    await messages.close();
  });

  Future<void> phases(List<String> noms) async {
    for (final nom in noms) {
      messages.add(_state(nom));
      await Future<void>.delayed(Duration.zero);
    }
  }

  Questionnaire troisQuestions() => Questionnaire(
        title: 'Essai',
        questions: [
          QuizQuestion(category: 'Un', question: 'Q1', answer: 'R1'),
          QuizQuestion(category: 'Deux', question: 'Q2', answer: 'R2'),
          QuizQuestion(category: 'Trois', question: 'Q3', answer: 'R3'),
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

  test('une mauvaise réponse ne fait PAS avancer', () async {
    actif.use(troisQuestions(), origine: 'Essai');
    await phases(['INTRO', 'WAITING_BUZZER']);
    expect(actif.index, 0);

    // Un joueur buzze, se trompe, la main repasse aux autres : c'est la même
    // question. C'est le cas que confondrait un « avance à chaque retour en
    // attente de buzz ».
    await phases(['BUZZER_PRESSED', 'WAITING_BUZZER']);
    expect(actif.index, 0);
    expect(game.questionText, 'Q1');
  });

  test('les scores puis la révélation font avancer', () async {
    actif.use(troisQuestions(), origine: 'Essai');
    await phases(['INTRO', 'WAITING_BUZZER']);

    // Quelqu'un a trouvé : scores, puis question suivante.
    await phases(['BUZZER_PRESSED', 'SHOW_SCORES', 'WAITING_BUZZER']);
    expect(actif.index, 1);
    expect(game.questionText, 'Q2');

    // Personne n'a trouvé : la réponse est révélée, puis question suivante.
    await phases(['ANSWER_REVEAL', 'WAITING_BUZZER']);
    expect(actif.index, 2);
    expect(game.questionText, 'Q3');
  });

  test('passé la dernière question, le questionnaire est épuisé', () async {
    actif.use(troisQuestions(), origine: 'Essai');
    await phases(['INTRO', 'WAITING_BUZZER']);
    await phases(['SHOW_SCORES', 'WAITING_BUZZER']);
    await phases(['SHOW_SCORES', 'WAITING_BUZZER']);
    expect(actif.index, 2);

    await phases(['SHOW_SCORES', 'WAITING_BUZZER']);
    expect(actif.exhausted, isTrue);
    // Plus de question à poser : les champs se vident au lieu de garder la
    // dernière question affichée pour toujours.
    expect(game.questionText, isNull);
    expect(game.appQuestion, isFalse);
  });

  test('une nouvelle partie repart de la première question', () async {
    actif.use(troisQuestions(), origine: 'Essai');
    await phases(['INTRO', 'WAITING_BUZZER']);
    await phases(['SHOW_SCORES', 'WAITING_BUZZER']);
    expect(actif.index, 1);

    // Retour au menu, puis nouvelle partie.
    await phases(['SHOW_SCORES', 'END_GAME', 'CONFIGURATION', 'INTRO', 'WAITING_BUZZER']);
    expect(actif.index, 0);
    expect(game.questionText, 'Q1');
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

  test('retirer le questionnaire libère les champs', () async {
    actif.use(troisQuestions(), origine: 'Essai');
    expect(game.questionText, 'Q1');
    actif.clear();
    expect(actif.active, isFalse);
    expect(game.questionText, isNull);
    expect(game.appQuestion, isFalse);

    // Et plus aucune transition ne le réveille.
    await phases(['INTRO', 'WAITING_BUZZER', 'SHOW_SCORES', 'WAITING_BUZZER']);
    expect(game.questionText, isNull);
  });

  test('sans questionnaire actif, une QUESTION du buzzer passe normalement', () async {
    messages.add('QUESTION|Histoire|Qui a fondé Québec ?|Champlain');
    await Future<void>.delayed(Duration.zero);
    expect(game.questionText, 'Qui a fondé Québec ?');
    expect(game.appQuestion, isFalse);
  });
}
