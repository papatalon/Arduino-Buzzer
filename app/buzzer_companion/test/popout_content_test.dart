import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_quiz.dart';
import 'package:buzzer_companion/popout/popout_content.dart';
import 'package:buzzer_companion/popout/popout_snapshot.dart';
import 'package:buzzer_companion/protocol.dart';
import 'package:buzzer_companion/questionnaires/active_questionnaire.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';

// L'ECRAN PUBLIC DOIT TOUJOURS MONTRER QUELQUE CHOSE.
//
// C'est le plan le plus longtemps affiche de la soiree, et une fenetre vide
// devant la salle ressemble a une panne. Ces tests le rendent pour de vrai :
// une exception de mise en page ne se voit d'aucune autre facon, et elle
// laisse justement un ecran vide au lieu de planter bruyamment.

class _MaterielMuet implements CommandesBuzzer {
  @override
  void armer(int masque) {}
  @override
  void desarmer() {}
  @override
  void allumerLeds(int masque) {}
}

void main() {
  Future<void> rendre(WidgetTester tester, PopoutSnapshot snap) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: FittedBox(child: PopoutContent(snapshot: snap)),
        ),
      ),
    ));
  }

  testWidgets('au demarrage, sans buzzer connecte', (tester) async {
    await rendre(tester, PopoutSnapshot.empty);
    // L'ecran d'attente, avec son chapeau : la salle voit quelque chose.
    expect(find.text("LE JEU S'EN VIENT"), findsOneWidget);
  });

  testWidgets("connecte, mais aucune partie lancee", (tester) async {
    final actif = ActiveQuestionnaire(GameState());
    final moteur = MoteurQuiz(ble: _MaterielMuet(), actif: actif);
    final game = GameState()..listenTo(const Stream<String>.empty());

    await rendre(
      tester,
      PopoutSnapshot.duMoteur(
        moteur,
        game,
        question: null,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
        recallIndex: null,
      ),
    );
    expect(find.text("LE JEU S'EN VIENT"), findsOneWidget);
  });

  testWidgets('une question en cours', (tester) async {
    final actif = ActiveQuestionnaire(GameState())
      ..use(
        Questionnaire(title: 'Essai', questions: [
          QuizQuestion(category: 'Histoire', question: 'Qui donc ?', answer: 'Lui'),
        ]),
        origine: 'Essai',
      );
    final moteur = MoteurQuiz(ble: _MaterielMuet(), actif: actif)
      ..demarrer(jeuChoisi: 0, limite: 1);

    await rendre(
      tester,
      PopoutSnapshot.duMoteur(
        moteur,
        GameState(),
        question: actif.current,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
        recallIndex: null,
      ),
    );
    expect(find.text('Qui donc ?'), findsOneWidget);
    // La reponse n'est pas encore revelee : elle ne doit pas etre a l'ecran.
    expect(find.text('Lui'), findsNothing);
  });

  testWidgets('la fin de partie annonce le gagnant', (tester) async {
    final actif = ActiveQuestionnaire(GameState())
      ..use(
        Questionnaire(title: 'Essai', questions: [
          QuizQuestion(question: 'Q1', answer: 'R1'),
        ]),
        origine: 'Essai',
      );
    final moteur = MoteurQuiz(ble: _MaterielMuet(), actif: actif)
      ..demarrer(jeuChoisi: 0, limite: 1);
    moteur.surBuzz(2, 300);
    moteur.bonneReponse();
    moteur.terminer();

    await rendre(
      tester,
      PopoutSnapshot.duMoteur(
        moteur,
        GameState(),
        question: actif.current,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
        recallIndex: null,
      ),
    );
    expect(find.text('JAUNE GAGNE'), findsOneWidget);
  });

  // LE BUG DU 2 SEPTEMBRE 2026 : ecran public vide, buzzer connecte.
  //
  // Le buzzer connecte reste en APP_CONTROL toute la soiree. Cette phase
  // n'etait pas comptee comme une phase de repos, donc l'ecran public se
  // croyait en pleine partie et basculait sur sa mise en page de jeu, sans
  // jeu ni question a montrer : rien du tout, devant la salle.
  //
  // Il ne se voyait qu'avec un buzzer allume. Debranche, la phase valait
  // null et tout paraissait normal, ce qui a fait passer le bug pour une
  // intermittence pendant une demi-douzaine d'essais.
  testWidgets('buzzer connecte au repos : ecran d\'attente, pas de vide',
      (tester) async {
    final appControl = kPhaseNames.indexOf('APP_CONTROL');
    expect(appControl, isNonNegative, reason: 'la phase doit exister');
    // Le buzzer en mode esclave ne joue rien de son cote.
    expect(isGameRunning(appControl), isFalse);

    await rendre(
      tester,
      PopoutSnapshot(
        scores: const [0, 0, 0, 0],
        present: const [true, true, true, true],
        flowState: QuestionFlowState.none,
        phase: appControl,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
      ),
    );
    expect(find.text("LE JEU S'EN VIENT"), findsOneWidget);
  });
}
