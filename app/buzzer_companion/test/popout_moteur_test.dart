import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_quiz.dart';
import 'package:buzzer_companion/popout/popout_snapshot.dart';
import 'package:buzzer_companion/protocol.dart';
import 'package:buzzer_companion/questionnaires/active_questionnaire.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';

// Ce que la salle voit quand l'application mène la partie.
//
// L'instantané est le seul chemin vers la fenêtre publique, et c'est là que
// se tient le contrat de confidentialité : une réponse qui n'a pas encore
// été révélée ne doit pas y être sérialisée du tout, pas seulement être
// cachée à l'affichage. Un écran de console ouvert sur le mauvais moniteur
// suffirait sinon à gâcher une question.

class _MaterielMuet implements CommandesBuzzer {
  @override
  void armer(int masque, {ModeArmement mode = ModeArmement.premier}) {}
  @override
  void desarmer() {}
  @override
  void allumerLeds(int masque) {}
  @override
  void allumerSignal(int masque, {bool avecSonDuel = false}) {}
}

void main() {
  late MoteurQuiz moteur;
  late ActiveQuestionnaire actif;

  setUp(() {
    actif = ActiveQuestionnaire(GameState())
      ..use(
        Questionnaire(title: 'Essai', questions: [
          QuizQuestion(themes: {'Histoire'}, question: 'Q1', answer: 'R1'),
          QuizQuestion(themes: {'Histoire'}, question: 'Q2', answer: 'R2'),
        ]),
        origine: 'Essai',
      );
    moteur = MoteurQuiz(ble: _MaterielMuet(), actif: actif);
  });

  PopoutSnapshot vu() => PopoutSnapshot.duMoteur(
        moteur,
        GameState(),
        question: actif.current,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
        vueSons: VueDesSons.aucune,
        pisteEnCours: PisteEnCours.aucune,
      );

  test('la réponse ne part pas tant que la question est ouverte', () {
    moteur.demarrer(jeuChoisi: 0, limite: 0);
    expect(vu().questionText, 'Q1');
    expect(vu().answerText, isNull);

    moteur.surBuzz(1, 300);
    expect(vu().answerText, isNull);
  });

  test('elle part une fois la question tranchée', () {
    moteur.demarrer(jeuChoisi: 0, limite: 0);
    moteur.surBuzz(1, 300);
    moteur.bonneReponse();
    expect(vu().answerText, 'R1');
  });

  test('et quand personne ne trouve', () {
    moteur.demarrer(jeuChoisi: 0, limite: 0);
    moteur.passer();
    expect(vu().answerText, 'R1');
  });

  test('sur un jeu à chrono, la question attend le top de l\'animateur', () {
    moteur.chronoPremiere = 20;
    moteur.chronoSuivantes = 10;
    moteur.demarrer(jeuChoisi: 2, limite: 0);
    // L'animateur la lit encore à voix haute : la salle ne doit pas la lire
    // avant lui.
    expect(vu().questionText, isNull);

    moteur.lancerChronoPremiere();
    expect(vu().questionText, 'Q1');

    moteur.dispose();
  });

  test('sans chrono réglé, la question part tout de suite', () {
    moteur.chronoPremiere = 0;
    moteur.demarrer(jeuChoisi: 2, limite: 0);
    expect(vu().questionText, 'Q1');
  });

  test('les scores et la progression viennent du moteur', () {
    moteur.demarrer(jeuChoisi: 0, limite: 2);
    moteur.surBuzz(2, 300);
    moteur.bonneReponse();

    final s = vu();
    expect(s.appMene, isTrue);
    expect(s.scores[2], 1);
    expect(s.questionsAsked, 1);
    expect(s.qcountValue, 2);
    expect(s.gameMode, 0);
  });

  test('la fin de partie annonce le gagnant', () {
    moteur.demarrer(jeuChoisi: 0, limite: 0);
    moteur.surBuzz(3, 300);
    moteur.bonneReponse();
    moteur.terminer();

    final s = vu();
    expect(s.gameFinished, isTrue);
    expect(s.gameWinner, 3);
    expect(s.gameTie, isFalse);
    // Plus de question en cours : la salle ne doit pas rester sur la
    // dernière posée pendant qu'on annonce le gagnant.
    expect(s.flowState, QuestionFlowState.none);
  });

  test('l\'instantané survit à l\'aller-retour vers la fenêtre publique', () {
    moteur.demarrer(jeuChoisi: 1, limite: 5);
    moteur.surBuzz(0, 300);
    moteur.bonneReponse();

    // La fenêtre du pop-out ne partage pas la mémoire : tout passe par du
    // JSON. Un champ oublié à l'encodage ne se voit qu'ici.
    final aller = vu();
    final retour = PopoutSnapshot.decode(aller.encode());
    expect(retour.appMene, isTrue);
    expect(retour.scores, aller.scores);
    expect(retour.answerText, 'R1');
    expect(retour.gameMode, 1);
    expect(retour.qcountValue, 5);
  });

  // LA QUESTION RETENUE PENDANT LA LECTURE. Même exigence que pour la
  // réponse : la question ne doit pas être sérialisée du tout tant que
  // l'animateur ne l'a pas montrée, pas seulement cachée à l'affichage.
  group('pendant la lecture', () {
    setUp(() => moteur.reglerLecture(surAutorisation: true));

    test('la question ne part pas, une phrase part à sa place', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      final s = vu();
      expect(s.questionText, isNull);
      expect(s.questionCategory, isNull);
      expect(s.motLecture, isNotEmpty);
      expect(s.flowState, QuestionFlowState.arming);
    });

    test('le clic de l\'animateur l\'envoie et retire la phrase', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.montrerQuestion();
      final s = vu();
      expect(s.questionText, 'Q1');
      expect(s.motLecture, isEmpty);
    });

    // Un « Personne ne trouve » en pleine lecture : la question est tranchée,
    // la salle voit la question et sa réponse, pas la phrase d'attente.
    test('une question passée sans être montrée se révèle quand même', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.passer();
      final s = vu();
      expect(s.questionText, 'Q1');
      expect(s.answerText, 'R1');
      expect(s.motLecture, isEmpty);
    });

    test('la phrase survit à l\'aller-retour vers la fenêtre publique', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      final aller = vu();
      final retour = PopoutSnapshot.decode(aller.encode());
      expect(retour.motLecture, aller.motLecture);
      expect(retour.questionText, isNull);
    });
  });

  // MANCHE LIBRE APRÈS UN QUESTIONNAIRE. Le questionnaire reste en réserve,
  // et ses questions sortaient quand même : projetées à la place de la
  // phrase d'attention, puis leur réponse révélée en fin de question, pour
  // une question que personne n'avait posée.
  group('en manche libre, avec un questionnaire en réserve', () {
    setUp(() => actif.utiliserLibre());

    test('la salle voit la phrase d\'attention, pas la question en réserve', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      final s = vu();
      expect(s.questionText, isNull);
      expect(s.motAttention, isNotEmpty);
    });

    test('aucune réponse n\'est révélée en fin de question', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.passer();
      // Sans question à l'écran, on va droit aux scores.
      expect(moteur.etape, EtapeQuiz.scores);
      expect(vu().answerText, isNull);
    });
  });
}
