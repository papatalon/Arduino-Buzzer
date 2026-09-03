import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_quiz.dart';
import 'package:buzzer_companion/jeu/mots_de_la_fin.dart';
import 'package:buzzer_companion/protocol.dart';
import 'package:buzzer_companion/questionnaires/active_questionnaire.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';

// Les règles de quiz, désormais tenues par l'application et non plus par le
// firmware. Elles sont reprises à l'identique de Buzzer.cpp, parce qu'elles
// ont été jouées et ajustées pendant des soirées : chaque écart serait une
// régression pour quelqu'un qui connaît le jeu.
//
// C'est exactement le genre de code qui se trompe en silence. Un point de
// pénalité oublié, un buzzer réarmé alors qu'il vient de se tromper, un tour
// de Vol qui n'avance pas : rien ne plante, la soirée est juste fausse.

// Enregistre ce que le moteur demande au matériel.
class _Materiel implements CommandesBuzzer {
  final List<int> armements = [];
  final List<int> leds = [];
  final List<int> signaux = [];
  int desarmements = 0;

  int? get dernierArmement => armements.isEmpty ? null : armements.last;

  @override
  void armer(int masque, {bool continu = false}) => armements.add(masque);

  @override
  void desarmer() => desarmements++;

  @override
  void allumerLeds(int masque) => leds.add(masque);
  @override
  void allumerSignal(int masque) => signaux.add(masque);
}

const _rouge = 0, _bleu = 1, _jaune = 2, _vert = 3;
int _bit(int i) => 1 << i;

void main() {
  late _Materiel materiel;
  late MoteurQuiz moteur;

  MoteurQuiz creer({List<bool>? presents}) {
    materiel = _Materiel();
    final actif = ActiveQuestionnaire(GameState())
      ..use(
        Questionnaire(title: 'Essai', questions: [
          QuizQuestion(question: 'Q1', answer: 'R1'),
          QuizQuestion(question: 'Q2', answer: 'R2'),
          QuizQuestion(question: 'Q3', answer: 'R3'),
        ]),
        origine: 'Essai',
      );
    final m = MoteurQuiz(ble: materiel, actif: actif);
    if (presents != null) m.presents = presents;
    return m;
  }

  group('Classique', () {
    setUp(() => moteur = creer());

    test('une bonne réponse marque un point et ferme la question', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      expect(moteur.etape, EtapeQuiz.attente);
      // Les quatre buzzers sont armés d'un coup.
      expect(materiel.dernierArmement, 0x0F);

      moteur.surBuzz(_bleu, 300);
      expect(moteur.etape, EtapeQuiz.buzze);
      expect(moteur.buzzeur, _bleu);

      moteur.bonneReponse();
      expect(moteur.scores[_bleu], 1);
      expect(moteur.etape, EtapeQuiz.scores);
    });

    test('une mauvaise réponse écarte son auteur mais garde la question', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.surBuzz(_bleu, 300);
      moteur.mauvaiseReponse();

      // Toujours la même question : on revient en attente.
      expect(moteur.etape, EtapeQuiz.attente);
      expect(moteur.numeroQuestion, 1);
      // Le fautif n'est plus armé, les trois autres le sont.
      expect(materiel.dernierArmement, 0x0F & ~_bit(_bleu));
      expect(moteur.enLice[_bleu], isFalse);
      // Classique ne pénalise pas.
      expect(moteur.scores[_bleu], 0);
    });

    test('quand tout le monde s\'est trompé, la question se ferme', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      for (final qui in [_rouge, _bleu, _jaune]) {
        moteur.surBuzz(qui, 300);
        moteur.mauvaiseReponse();
        expect(moteur.etape, EtapeQuiz.attente);
      }
      moteur.surBuzz(_vert, 300);
      moteur.mauvaiseReponse();
      // Plus personne en lice : on révèle la réponse.
      expect(moteur.etape, EtapeQuiz.revelee);
    });

    test('la question suivante réarme tout le monde', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.surBuzz(_bleu, 300);
      moteur.mauvaiseReponse();
      moteur.surBuzz(_rouge, 300);
      moteur.bonneReponse();
      moteur.continuer();

      expect(moteur.numeroQuestion, 2);
      expect(materiel.dernierArmement, 0x0F);
      expect(moteur.enLice.every((e) => e), isTrue);
    });

    test('un buzz est ignoré hors de la phase d\'attente', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.surBuzz(_bleu, 300);
      // Un deuxième joueur pianote pendant que l'animateur juge : sans ce
      // garde, il volerait la main au premier.
      moteur.surBuzz(_rouge, 320);
      expect(moteur.buzzeur, _bleu);
    });

    test('un buzzer absent ne peut pas buzzer', () {
      moteur = creer(presents: [true, false, true, true]);
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      expect(materiel.dernierArmement, 0x0F & ~_bit(_bleu));
      moteur.surBuzz(_bleu, 300);
      expect(moteur.buzzeur, isNull);
    });
  });

  group('Pénalité', () {
    setUp(() => moteur = creer());

    test('une mauvaise réponse coûte un point', () {
      moteur.demarrer(jeuChoisi: 1, limite: 0);
      moteur.surBuzz(_bleu, 300);
      moteur.mauvaiseReponse();
      expect(moteur.scores[_bleu], -1);
    });

    test('le score peut devenir négatif, comme sur le buzzer', () {
      moteur.demarrer(jeuChoisi: 1, limite: 0);
      for (var tour = 0; tour < 2; tour++) {
        moteur.surBuzz(_bleu, 300);
        moteur.mauvaiseReponse();
        moteur.passer();
        moteur.continuer();
      }
      expect(moteur.scores[_bleu], -2);
    });
  });

  group('Vol', () {
    setUp(() {
      moteur = creer();
      moteur.demarrer(jeuChoisi: 4, limite: 0);
    });

    test('seul le joueur désigné est armé au départ', () {
      expect(materiel.dernierArmement, _bit(moteur.tourVol));
    });

    test('son échec ouvre la question aux autres', () {
      final designe = moteur.tourVol;
      moteur.surBuzz(designe, 300);
      moteur.mauvaiseReponse();

      // Tous les autres présents entrent, le fautif reste dehors.
      expect(materiel.dernierArmement, 0x0F & ~_bit(designe));
      expect(moteur.enLice[designe], isFalse);
    });

    test('un voleur qui échoue à son tour reste écarté', () {
      final designe = moteur.tourVol;
      moteur.surBuzz(designe, 300);
      moteur.mauvaiseReponse();

      final voleur = [0, 1, 2, 3].firstWhere((i) => i != designe);
      moteur.surBuzz(voleur, 300);
      moteur.mauvaiseReponse();

      expect(moteur.enLice[voleur], isFalse);
      // Le désigné n'est PAS réactivé au passage.
      expect(moteur.enLice[designe], isFalse);
    });

    test('le tour avance après une bonne réponse, même volée', () {
      final designe = moteur.tourVol;
      moteur.surBuzz(designe, 300);
      moteur.bonneReponse();
      expect(moteur.tourVol, isNot(designe));
    });
  });

  group('Correction', () {
    setUp(() => moteur = creer());

    test('annule le point d\'une bonne réponse et rouvre le jugement', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.surBuzz(_bleu, 300);
      moteur.bonneReponse();
      expect(moteur.scores[_bleu], 1);

      moteur.corriger();
      expect(moteur.scores[_bleu], 0);
      expect(moteur.etape, EtapeQuiz.buzze);
      expect(moteur.buzzeur, _bleu);
    });

    test('remet en lice un buzzer écarté, et lui rend sa pénalité', () {
      moteur.demarrer(jeuChoisi: 1, limite: 0);
      moteur.surBuzz(_bleu, 300);
      moteur.mauvaiseReponse();
      expect(moteur.scores[_bleu], -1);
      expect(moteur.enLice[_bleu], isFalse);

      moteur.corriger();
      expect(moteur.scores[_bleu], 0);
      expect(moteur.enLice[_bleu], isTrue);
    });

    test('ne fait rien quand il n\'y a rien à corriger', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.corriger();
      expect(moteur.etape, EtapeQuiz.attente);
    });
  });

  group('Fin de partie', () {
    setUp(() => moteur = creer());

    test('la limite de questions termine la partie', () {
      moteur.demarrer(jeuChoisi: 0, limite: 2);
      moteur.surBuzz(_bleu, 300);
      moteur.bonneReponse();
      moteur.continuer();
      expect(moteur.numeroQuestion, 2);
      expect(moteur.etape, EtapeQuiz.attente);

      moteur.surBuzz(_bleu, 300);
      moteur.bonneReponse();
      moteur.continuer();
      expect(moteur.etape, EtapeQuiz.finie);
    });

    test('sans limite, la partie continue indéfiniment', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      for (var i = 0; i < 8; i++) {
        moteur.surBuzz(_bleu, 300);
        moteur.bonneReponse();
        moteur.continuer();
      }
      expect(moteur.etape, EtapeQuiz.attente);
      expect(moteur.numeroQuestion, 9);
    });

    test('désigne le gagnant, ou l\'égalité', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.surBuzz(_bleu, 300);
      moteur.bonneReponse();
      moteur.terminer();
      expect(moteur.gagnant, _bleu);
      expect(moteur.egalite, isFalse);
    });

    test('égalité quand plusieurs sont au sommet', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.surBuzz(_bleu, 300);
      moteur.bonneReponse();
      moteur.continuer();
      moteur.surBuzz(_rouge, 300);
      moteur.bonneReponse();
      moteur.terminer();
      expect(moteur.egalite, isTrue);
      expect(moteur.gagnant, isNull);
    });

    test('terminer désarme le matériel et éteint les LED', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      final avant = materiel.desarmements;
      moteur.terminer();
      expect(materiel.desarmements, greaterThan(avant));
      expect(materiel.leds.last, 0);
    });
  });

  group('Le mot de la fin', () {
    setUp(() => moteur = creer());

    // Tire UNE SEULE FOIS, a la fin de la partie. L'ecran public le recoit
    // dans l'instantane ; le retirer a chaque reconstruction de la fenetre le
    // ferait clignoter devant la salle.
    test('une victoire et une égalité ne piochent pas dans la même liste', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      moteur.surBuzz(1, 300);
      moteur.bonneReponse();
      moteur.terminer();
      expect(moteur.gagnant, 1);
      expect(motsDeVictoire, contains(moteur.motFinal));

      final autre = creer();
      autre.demarrer(jeuChoisi: 0, limite: 0);
      autre.terminer();       // personne n'a marqué : tout le monde à zéro
      expect(autre.egalite, isTrue);
      expect(motsDEgalite, contains(autre.motFinal));
    });

    test('rien à dire tant que la partie tourne', () {
      moteur.demarrer(jeuChoisi: 0, limite: 0);
      expect(moteur.motFinal, isEmpty);
    });
  });

  group('Vol : le tirage', () {
    // Le bruitage du tirage NE doit PAS jouer pendant l'ouverture : les deux
    // sons se couvraient. Il accompagne l'animation, au depart de la premiere
    // question, et l'ecran public annonce alors ce qui se decide.
    test('le mot du tirage est vide tant que rien ne se tire', () {
      final m = creer();
      m.demarrer(jeuChoisi: 4, limite: 0);
      expect(m.motTirage, isEmpty);
    });

    test("le sort est tire avant l'ouverture, pas pendant l'animation", () {
      final m = creer();
      m.demarrer(jeuChoisi: 4, limite: 0);
      // Un seul joueur est en lice : c'est le designe, et il l'est des le
      // depart. L'animation qui suit ne decide de rien, elle annonce.
      final enLice = [for (var i = 0; i < 4; i++) if (m.enLice[i]) i];
      expect(enLice, [m.tourVol]);
    });
  });
}
