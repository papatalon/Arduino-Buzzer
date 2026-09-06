import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_quiz.dart';
import 'dart:math';

import 'package:buzzer_companion/jeu/mots_de_la_fin.dart';
import 'package:buzzer_companion/jeu/moteur_reflexe.dart';
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
  void armer(int masque, {ModeArmement mode = ModeArmement.premier}) {}
  @override
  void desarmer() {}
  @override
  void allumerLeds(int masque) {}
  @override
  void allumerSignal(int masque, {bool avecSonDuel = false}) {}
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
        vueSons: VueDesSons.aucune,
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
        vueSons: VueDesSons.aucune,
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
        vueSons: VueDesSons.aucune,
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

  // ECARTE POUR CETTE QUESTION. Une mauvaise reponse met son auteur hors jeu
  // jusqu'a la suivante. Sans mention, la salle regarde quelqu'un attendre
  // sans comprendre qu'il ne joue plus ce tour-ci.
  testWidgets('un buzzer ecarte est marque, puis ne l\'est plus', (tester) async {
    final actif = ActiveQuestionnaire(GameState())
      ..use(
        Questionnaire(title: 'Essai', questions: [
          QuizQuestion(question: 'Q1', answer: 'R1'),
          QuizQuestion(question: 'Q2', answer: 'R2'),
        ]),
        origine: 'Essai',
      );
    final moteur = MoteurQuiz(ble: _MaterielMuet(), actif: actif)
      ..demarrer(jeuChoisi: 0, limite: 2);

    PopoutSnapshot vu() => PopoutSnapshot.duMoteur(
          moteur,
          GameState(),
          question: actif.current,
          teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
          logoPath: null,
          vueSons: VueDesSons.aucune,
        );

    moteur.surBuzz(1, 300);
    moteur.mauvaiseReponse();
    await rendre(tester, vu());
    expect(find.text('ÉCARTÉ'), findsOneWidget);

    // Question tranchee : plus personne n'est ecarte, la mention disparait
    // au lieu de rester affichee a tort.
    moteur.surBuzz(0, 300);
    moteur.bonneReponse();
    await rendre(tester, vu());
    expect(find.text('ÉCARTÉ'), findsNothing);
  });

  // MANCHE LIBRE : l'animateur pose ses propres questions. L'ecran public
  // n'a aucun texte a projeter, et rester vide au moment ou la salle doit
  // ecouter ressemble a une panne.
  testWidgets('manche libre : une phrase remplace la question', (tester) async {
    final actif = ActiveQuestionnaire(GameState())..utiliserLibre(nombre: 3);
    final moteur = MoteurQuiz(ble: _MaterielMuet(), actif: actif)
      ..demarrer(jeuChoisi: 0, limite: 3);

    expect(moteur.motAttention, isNotEmpty);
    expect(motsDattention, contains(moteur.motAttention));

    await rendre(
      tester,
      PopoutSnapshot.duMoteur(
        moteur,
        GameState(),
        question: actif.current,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
        vueSons: VueDesSons.aucune,
      ),
    );
    expect(find.text(moteur.motAttention), findsOneWidget);
  });

  testWidgets('avec un questionnaire, aucune phrase de remplacement',
      (tester) async {
    final actif = ActiveQuestionnaire(GameState())
      ..use(
        Questionnaire(title: 'Essai', questions: [
          QuizQuestion(question: 'Qui donc ?', answer: 'Lui'),
        ]),
        origine: 'Essai',
      );
    final moteur = MoteurQuiz(ble: _MaterielMuet(), actif: actif)
      ..demarrer(jeuChoisi: 0, limite: 1);
    expect(moteur.motAttention, isEmpty);
  });

  // LE CHRONO DOIT SE VOIR DE LA SALLE. Il ne servait qu'a l'animateur : le
  // public voyait « CHRONO NON LANCE » et une barre grise figee, meme pendant
  // le decompte. C'est pourtant lui qui pousse les joueurs a se decider.
  testWidgets('le decompte s\'affiche sur l\'ecran public', (tester) async {
    final actif = ActiveQuestionnaire(GameState())
      ..use(
        Questionnaire(title: 'Essai', questions: [
          QuizQuestion(question: 'Qui donc ?', answer: 'Lui'),
        ]),
        origine: 'Essai',
      );
    final moteur = MoteurQuiz(ble: _MaterielMuet(), actif: actif)
      ..chronoPremiere = 20
      ..chronoSuivantes = 10;
    moteur.demarrer(jeuChoisi: 2, limite: 1);   // Chrono classique
    moteur.lancerChronoPremiere();

    await rendre(
      tester,
      PopoutSnapshot.duMoteur(
        moteur,
        GameState(),
        question: actif.current,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
        vueSons: VueDesSons.aucune,
      ),
    );
    expect(find.text('20 s'), findsOneWidget);
    expect(find.text('CHRONO NON LANCÉ'), findsNothing);
    moteur.dispose();
  });

  // RÉFLEXE : un faux départ écarte son auteur de la manche, et la salle doit
  // le voir dans le bandeau, exactement comme une mauvaise réponse au quiz.
  // Sans ça, on regarde quelqu'un attendre le signal alors qu'il ne joue plus.
  testWidgets('reflexe : un faux depart se voit dans le bandeau',
      (tester) async {
    final moteur = MoteurReflexe(ble: _MaterielMuet(), hasard: Random(1))
      ..manchesPrevues = 3
      ..regleFauxDepart = FauxDepart.ecarte;
    moteur.demarrer();
    moteur.surBuzz(1, 800);   // avant le signal
    expect(moteur.enLice[1], isFalse);

    PopoutSnapshot vu() => PopoutSnapshot.duReflexe(
          moteur,
          teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
          logoPath: null,
        );

    await rendre(tester, vu());
    expect(find.text('ÉCARTÉ'), findsOneWidget);

    // Manche tranchee : tout le monde revient, la mention disparait.
    moteur.donnerLeSignal();
    moteur.surBuzz(0, 250);
    await rendre(tester, vu());
    expect(find.text('ÉCARTÉ'), findsNothing);
    moteur.dispose();
  });

  // Le mode « penalite » garde le fautif en lice : rien ne doit apparaitre
  // dans le bandeau, sinon on annoncerait une exclusion qui n'existe pas.
  testWidgets('reflexe : en mode penalite, personne n\'est marque ecarte',
      (tester) async {
    final moteur = MoteurReflexe(ble: _MaterielMuet(), hasard: Random(1))
      ..manchesPrevues = 3
      ..regleFauxDepart = FauxDepart.penalite;
    moteur.demarrer();
    moteur.surBuzz(1, 800);

    await rendre(
      tester,
      PopoutSnapshot.duReflexe(
        moteur,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
      ),
    );
    expect(find.text('ÉCARTÉ'), findsNothing);
    moteur.dispose();
  });

  // Un bris se joue EN PLUS des manches prevues : la progression annoncerait
  // « manche 3 sur 2 ». Le nom de ce qui se joue vaut mieux qu'un compte faux.
  testWidgets('bris d\'egalite : la progression laisse sa place',
      (tester) async {
    final moteur = MoteurReflexe(ble: _MaterielMuet(), hasard: Random(1))
      ..manchesPrevues = 2;
    moteur.demarrer();
    moteur.donnerLeSignal();
    moteur.personneNaPese();
    moteur.continuer();
    moteur.donnerLeSignal();
    moteur.personneNaPese();
    moteur.continuer();
    expect(moteur.egalite, isTrue);

    moteur.lancerBrisDegalite();
    expect(moteur.manche, greaterThan(moteur.manchesPrevues));

    await rendre(
      tester,
      PopoutSnapshot.duReflexe(
        moteur,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
      ),
    );
    expect(find.text("BRIS D'ÉGALITÉ"), findsOneWidget);
    expect(find.textContaining('SUR 2'), findsNothing);
    moteur.dispose();
  });
}
