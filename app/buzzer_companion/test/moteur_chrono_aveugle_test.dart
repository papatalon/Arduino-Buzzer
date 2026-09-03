import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_chrono_aveugle.dart';
import 'package:buzzer_companion/jeu/moteur_quiz.dart' show CommandesBuzzer, ModeArmement;
import 'package:buzzer_companion/jeu/mots_de_la_fin.dart';
import 'package:buzzer_companion/popout/popout_snapshot.dart';

// LES RÈGLES DU CHRONO AVEUGLE.
//
// Le plus proche de la cible gagne, et « le plus proche » se trompe facilement
// en silence : un écart calculé dans le mauvais sens donne la manche à celui
// qui s'est le plus trompé, et personne ne s'en apercevrait avant la fin de
// la soirée.
//
// Les temps arrivent mesurés par le Mega, comme le matériel le fait.

class _Materiel implements CommandesBuzzer {
  final List<int> armements = [];
  final List<int> signaux = [];
  final List<int> leds = [];
  int desarmements = 0;
  bool dernierContinu = false;

  /// L'ORDRE DES COMMANDES, et pas seulement leur contenu.
  ///
  /// ARM remet AUSSI le chrono a zero cote Mega (AppControl::arm). Si le
  /// signal partait avant l'armement, le chrono repartirait APRES l'allumage
  /// et tous les temps seraient courts de la latence Bluetooth qui les
  /// separe. Rien dans le contenu des messages ne le dirait.
  final List<String> trace = [];

  int? get dernierArmement => armements.isEmpty ? null : armements.last;

  @override
  void armer(int masque, {ModeArmement mode = ModeArmement.premier}) {
    armements.add(masque);
    dernierContinu = (mode == ModeArmement.continu);
    trace.add('ARM');
  }

  @override
  void desarmer() => desarmements++;

  @override
  void allumerLeds(int masque) => leds.add(masque);

  @override
  void allumerSignal(int masque, {bool avecSonDuel = false}) {
    signaux.add(masque);
    trace.add('GO');
  }
}

const _rouge = 0, _bleu = 1, _jaune = 2, _vert = 3;
int _bit(int i) => 1 << i;

void main() {
  late _Materiel materiel;
  late MoteurChronoAveugle moteur;

  MoteurChronoAveugle creer({int manches = 3}) {
    materiel = _Materiel();
    return MoteurChronoAveugle(ble: materiel, hasard: Random(1))
      ..manchesPrevues = manches;
  }

  group('Le déroulement', () {
    setUp(() => moteur = creer());

    test('la cible est annoncée avant le départ, rien n\'est armé', () {
      moteur.demarrer();
      expect(moteur.etape, EtapeChronoAveugle.annonce);
      expect(moteur.cibleSecondes,
          inInclusiveRange(
              MoteurChronoAveugle.cibleMinS, MoteurChronoAveugle.cibleMaxS));
      // Un appui avant le depart n'a rien a mesurer : on n'arme pas.
      expect(materiel.desarmements, greaterThan(0));
      expect(materiel.leds.last, 0);
    });

    test('le départ allume TOUT et repart le chrono', () {
      moteur.demarrer();
      moteur.donnerLeDepart();
      expect(moteur.etape, EtapeChronoAveugle.course);
      // GO et non LED : allumage et chrono dans la meme instruction.
      expect(materiel.signaux.last, 0x0F);
      expect(materiel.dernierArmement, 0x0F);
      expect(materiel.dernierContinu, isTrue);
    });

    test('la LED de celui qui pèse s\'éteint, les autres restent', () {
      moteur.demarrer();
      moteur.donnerLeDepart();
      moteur.surBuzz(_bleu, 9000);
      // Le bleu s'est engage : sa lumiere s'eteint, ce qui sème le doute chez
      // les autres sans leur dire quand il croyait y etre.
      expect(materiel.leds.last, 0x0F & ~_bit(_bleu));
      expect(moteur.etape, EtapeChronoAveugle.course);
    });

    test('un joueur ne pèse qu\'une fois', () {
      moteur.demarrer();
      moteur.donnerLeDepart();
      moteur.surBuzz(_bleu, 9000);
      moteur.surBuzz(_bleu, 9500);
      expect(moteur.temps[_bleu], 9000);
    });

    test('quand tout le monde a pesé, la manche se tranche', () {
      moteur.demarrer();
      moteur.donnerLeDepart();
      for (final qui in [_rouge, _bleu, _jaune, _vert]) {
        moteur.surBuzz(qui, 9000);
      }
      expect(moteur.etape, EtapeChronoAveugle.resultat);
      expect(materiel.desarmements, greaterThan(1));
    });
  });

  group('Le plus proche gagne', () {
    setUp(() => moteur = creer());

    test('trop tôt ou trop tard, seul l\'écart compte', () {
      moteur.demarrer();
      final cible = moteur.cibleMs;
      moteur.donnerLeDepart();

      // Le rouge est 2 s TROP TARD, le bleu 1,5 s TROP TOT : c'est le bleu
      // qui gagne. Un ecart calcule dans le mauvais sens donnerait le rouge.
      moteur.surBuzz(_rouge, cible + 2000);
      moteur.surBuzz(_bleu, cible - 1500);
      moteur.surBuzz(_jaune, cible + 4000);
      moteur.surBuzz(_vert, cible - 6000);

      expect(moteur.gagnant, _bleu);
      expect(moteur.ecartGagnant, 1500);
      expect(moteur.scores[_bleu], 1);
      expect(materiel.leds.last, _bit(_bleu));
    });

    test('celui qui n\'a pas pesé ne gagne pas', () {
      moteur.demarrer();
      final cible = moteur.cibleMs;
      moteur.donnerLeDepart();
      moteur.surBuzz(_rouge, cible + 3000);
      moteur.tempsEcoule();

      expect(moteur.gagnant, _rouge);
      expect(moteur.temps[_bleu], isNull);
      expect(moteur.ecartDe(_bleu), isNull);
    });

    test('si personne ne pèse, la manche est nulle', () {
      moteur.demarrer();
      moteur.donnerLeDepart();
      moteur.tempsEcoule();

      expect(moteur.etape, EtapeChronoAveugle.resultat);
      expect(moteur.gagnant, isNull);
      expect(moteur.scores, [0, 0, 0, 0]);
      expect(materiel.leds.last, 0);
    });

    test('le meilleur écart de la partie se retient', () {
      moteur = creer(manches: 2);
      moteur.demarrer();
      var cible = moteur.cibleMs;
      moteur.donnerLeDepart();
      moteur.surBuzz(_bleu, cible + 800);
      moteur.tempsEcoule();
      expect(moteur.meilleurEcart, 800);

      moteur.continuer();
      cible = moteur.cibleMs;
      moteur.donnerLeDepart();
      moteur.surBuzz(_rouge, cible - 120);
      moteur.tempsEcoule();
      expect(moteur.meilleurEcart, 120);
    });
  });

  group('Le record du buzzer', () {
    test('un écart plus petit bat le record et le fait remonter', () {
      moteur = creer(manches: 1);
      int? remonte;
      moteur
        ..record = 500
        ..surNouveauRecord = (e) => remonte = e;

      moteur.demarrer();
      final cible = moteur.cibleMs;
      moteur.donnerLeDepart();
      moteur.surBuzz(_bleu, cible + 200);
      moteur.tempsEcoule();
      moteur.continuer();

      expect(moteur.recordBattu, isTrue);
      expect(moteur.record, 200);
      expect(remonte, 200);
    });

    test('un écart plus grand ne touche à rien', () {
      moteur = creer(manches: 1);
      int? remonte;
      moteur
        ..record = 100
        ..surNouveauRecord = (e) => remonte = e;

      moteur.demarrer();
      final cible = moteur.cibleMs;
      moteur.donnerLeDepart();
      moteur.surBuzz(_bleu, cible + 900);
      moteur.tempsEcoule();
      moteur.continuer();

      expect(moteur.recordBattu, isFalse);
      expect(moteur.record, 100);
      expect(remonte, isNull);
    });
  });

  group('La fin de partie', () {
    test('le mot de la fin vient des mêmes listes que les autres jeux', () {
      moteur = creer(manches: 1);
      moteur.demarrer();
      final cible = moteur.cibleMs;
      moteur.donnerLeDepart();
      moteur.surBuzz(_bleu, cible + 100);
      moteur.tempsEcoule();
      moteur.continuer();

      expect(moteur.etape, EtapeChronoAveugle.finie);
      expect(moteur.vainqueur, _bleu);
      expect(motsDeVictoire, contains(moteur.motFinal));
    });

    test('un bris ne se lance que sur une égalité, et une seule manche', () {
      moteur = creer(manches: 1);
      moteur.demarrer();
      moteur.donnerLeDepart();
      moteur.tempsEcoule();       // personne ne marque
      moteur.continuer();
      expect(moteur.egalite, isTrue);

      moteur.lancerBrisDegalite();
      expect(moteur.brisEgalite, isTrue);
      expect(moteur.etape, EtapeChronoAveugle.annonce);

      final cible = moteur.cibleMs;
      moteur.donnerLeDepart();
      moteur.surBuzz(_vert, cible + 300);
      moteur.tempsEcoule();
      moteur.continuer();
      // Un bris se joue en UNE manche.
      expect(moteur.etape, EtapeChronoAveugle.finie);
      expect(moteur.vainqueur, _vert);
    });
  });

  group("L'ecran public pendant la course", () {
    // La salle doit voir qui s'est deja engage, comme les LED le montrent.
    // Mais JAMAIS son temps : ce serait la reference de duree que tout le jeu
    // consiste a ne pas avoir.
    test('un temps a zero veut dire « pas encore pese »', () {
      moteur = creer();
      moteur.demarrer();
      moteur.donnerLeDepart();
      moteur.surBuzz(_bleu, 9000);

      final vu = PopoutSnapshot.duChronoAveugle(
        moteur,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
      );
      // Zero est la convention du firmware pour « n'a pas buzze ».
      expect(vu.blindTimes[_bleu], 9000);
      expect(vu.blindTimes[_rouge], 0);
      expect(vu.blindTimes[_jaune], 0);
      moteur.dispose();
    });

    test('la cible reste affichee, jamais le temps ecoule', () {
      moteur = creer();
      moteur.demarrer();
      final cible = moteur.cibleSecondes;
      moteur.donnerLeDepart();

      final vu = PopoutSnapshot.duChronoAveugle(
        moteur,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
      );
      expect(vu.blindTargetS, cible);
      // Rien qui s'ecoule ne voyage vers l'ecran public.
      expect(vu.chronoRestant, isNull);
      moteur.dispose();
    });
  });

  test("ARM part AVANT GO : sinon le chrono repartirait apres l'allumage", () {
    moteur = creer();
    moteur.demarrer();
    materiel.trace.clear();
    moteur.donnerLeDepart();

    // AppControl::arm remet armedAt a zero, tout comme go. C'est donc le
    // DERNIER des deux qui fixe l'origine du chrono, et il faut que ce soit
    // celui qui allume les lumieres.
    expect(materiel.trace, ['ARM', 'GO']);
    moteur.dispose();
  });
}
