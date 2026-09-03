import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_quiz.dart' show CommandesBuzzer;
import 'package:buzzer_companion/jeu/moteur_reflexe.dart';

// LES RÈGLES DU RÉFLEXE, et surtout les quatre façons de traiter un faux
// départ. Elles font des soirées différentes : se tromper de comportement se
// verrait au tableau des points, pas à l'écran.
//
// Le temps de réaction n'est jamais calculé ici : il arrive mesuré par le
// Mega, parce qu'un aller-retour Bluetooth fausserait tout. Les tests le
// fournissent donc directement, comme le matériel le ferait.

class _Materiel implements CommandesBuzzer {
  final List<int> armements = [];
  final List<int> signaux = [];
  final List<int> leds = [];
  int desarmements = 0;

  /// Vrai quand l'armement en cours accepte plusieurs appuis. Tous les jeux
  /// sauf le quiz en ont besoin.
  bool dernierContinu = false;

  int? get dernierArmement => armements.isEmpty ? null : armements.last;

  @override
  void armer(int masque, {bool continu = false}) {
    armements.add(masque);
    dernierContinu = continu;
  }

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
  late MoteurReflexe moteur;

  // Un hasard fixe : le délai avant le signal ne doit pas rendre un test
  // capricieux.
  MoteurReflexe creer({FauxDepart regle = FauxDepart.ecarte, int manches = 3}) {
    materiel = _Materiel();
    final m = MoteurReflexe(ble: materiel, hasard: Random(1))
      ..manchesPrevues = manches
      ..regleFauxDepart = regle;
    return m;
  }

  // Le signal ne tombe pas tout seul dans un test : on l'appelle. Ce que
  // vérifie la suite, ce sont les règles, pas la durée d'un minuteur.
  void donnerLeSignal(MoteurReflexe m) {
    expect(m.etape, EtapeReflexe.attente);
    m.donnerLeSignal();
  }

  group('Le déroulement', () {
    setUp(() => moteur = creer());

    test('les buzzers sont armés AVANT le signal, en mode continu', () {
      moteur.demarrer();
      expect(moteur.etape, EtapeReflexe.attente);
      // Sans ça, un appui prématuré ne parviendrait jamais à l'application et
      // il n'y aurait aucun faux départ à juger.
      expect(materiel.dernierArmement, 0x0F);
      expect(materiel.dernierContinu, isTrue);
      // Les LED sont éteintes : c'est leur allumage qui est le signal.
      expect(materiel.leds.last, 0);
    });

    test('le signal passe par GO, pas par un allumage ordinaire', () {
      moteur.demarrer();
      donnerLeSignal(moteur);
      // GO allume ET repart le chrono cote Mega, dans la meme instruction.
      expect(materiel.signaux.last, 0x0F);
    });

    test('le premier a peser remporte la manche et son temps', () {
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 240);

      expect(moteur.etape, EtapeReflexe.resultat);
      expect(moteur.gagnant, _bleu);
      expect(moteur.tempsGagnant, 240);
      expect(moteur.scores[_bleu], 1);
      expect(moteur.meilleurTemps, 240);
      // Sa LED reste seule allumee : la salle voit qui a gagne.
      expect(materiel.leds.last, _bit(_bleu));
    });

    test('les appuis suivants ne changent plus rien', () {
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 240);
      moteur.surBuzz(_rouge, 250);
      expect(moteur.gagnant, _bleu);
    });

    test('le meilleur temps retient le plus court de la partie', () {
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 240);
      moteur.continuer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_rouge, 310);
      expect(moteur.meilleurTemps, 240);

      moteur.continuer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_vert, 190);
      expect(moteur.meilleurTemps, 190);
    });

    test('un buzzer absent ne joue pas', () {
      moteur = creer();
      moteur.presents = [true, false, true, true];
      moteur.demarrer();
      expect(materiel.dernierArmement, 0x0F & ~_bit(_bleu));
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 200);
      expect(moteur.gagnant, isNull);
    });

    test('la limite de manches termine la partie', () {
      moteur = creer(manches: 2);
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 240);
      moteur.continuer();
      expect(moteur.manche, 2);

      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 240);
      moteur.continuer();
      expect(moteur.etape, EtapeReflexe.finie);
      expect(moteur.meneur, _bleu);
    });
  });

  group('Faux départ : écarté', () {
    setUp(() => moteur = creer(regle: FauxDepart.ecarte));

    test('le fautif ne joue plus la manche, les autres continuent', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 800);   // avant le signal

      expect(moteur.fautifs[_bleu], isTrue);
      expect(moteur.enLice[_bleu], isFalse);
      expect(moteur.scores[_bleu], 0);   // ecarte, mais pas puni au score
      // Rearme sans le fautif ; la manche n'est pas relancee.
      expect(materiel.dernierArmement, 0x0F & ~_bit(_bleu));
      expect(moteur.etape, EtapeReflexe.attente);
    });

    test('le fautif ne peut plus gagner, meme apres le signal', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 800);
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 200);
      expect(moteur.gagnant, isNull);

      moteur.surBuzz(_rouge, 260);
      expect(moteur.gagnant, _rouge);
    });

    test('si tout le monde se brûle, la manche est nulle', () {
      moteur.demarrer();
      for (final qui in [_rouge, _bleu, _jaune, _vert]) {
        moteur.surBuzz(qui, 500);
      }
      expect(moteur.etape, EtapeReflexe.resultat);
      expect(moteur.personne, isTrue);
      expect(moteur.gagnant, isNull);
      // Personne ne marque : une manche nulle ne recompense pas le dernier
      // a s'etre brule.
      expect(moteur.scores, [0, 0, 0, 0]);
    });

    test('la manche suivante remet tout le monde en lice', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 800);
      donnerLeSignal(moteur);
      moteur.surBuzz(_rouge, 260);
      moteur.continuer();

      expect(moteur.enLice.every((e) => e), isTrue);
      expect(moteur.fautifs.every((f) => !f), isTrue);
      expect(materiel.dernierArmement, 0x0F);
    });
  });

  group('Faux départ : pénalité', () {
    setUp(() => moteur = creer(regle: FauxDepart.penalite));

    test('un point en moins, mais il reste en lice', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 800);

      expect(moteur.scores[_bleu], -1);
      // Tout l'interet du mode : personne ne regarde les autres jouer.
      expect(moteur.enLice[_bleu], isTrue);
      expect(moteur.etape, EtapeReflexe.attente);
    });

    test('il peut encore gagner la manche', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 800);
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 210);
      expect(moteur.gagnant, _bleu);
      // Le point gagne annule la penalite, il revient a zero.
      expect(moteur.scores[_bleu], 0);
    });

    test('on ne se fait punir qu\'une fois par manche', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 700);
      moteur.surBuzz(_bleu, 900);
      expect(moteur.scores[_bleu], -1);
    });
  });

  group('Faux départ : manche relancée', () {
    setUp(() => moteur = creer(regle: FauxDepart.relance));

    test('personne n\'est puni et la manche repart', () {
      moteur.demarrer();
      final armementsAvant = materiel.armements.length;
      moteur.surBuzz(_bleu, 800);

      expect(moteur.scores, [0, 0, 0, 0]);
      expect(moteur.enLice.every((e) => e), isTrue);
      expect(moteur.etape, EtapeReflexe.attente);
      // Un nouvel armement complet : la manche a bien ete rouverte.
      expect(materiel.armements.length, greaterThan(armementsAvant));
      expect(materiel.dernierArmement, 0x0F);
    });

    test('le numero de manche ne change pas : on la rejoue', () {
      moteur.demarrer();
      expect(moteur.manche, 1);
      moteur.surBuzz(_bleu, 800);
      expect(moteur.manche, 1);
    });
  });

  group('Faux départ : toléré', () {
    setUp(() => moteur = creer(regle: FauxDepart.tolere));

    test('un appui avant le signal ne change rien du tout', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 800);

      expect(moteur.scores, [0, 0, 0, 0]);
      expect(moteur.fautifs.every((f) => !f), isTrue);
      expect(moteur.enLice.every((e) => e), isTrue);
      expect(moteur.etape, EtapeReflexe.attente);
    });

    test('et il peut gagner normalement ensuite', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 800);
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 230);
      expect(moteur.gagnant, _bleu);
      expect(moteur.scores[_bleu], 1);
    });
  });

  group('Personne ne pèse', () {
    test('la manche se termine sans gagnant', () {
      moteur = creer();
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.personneNaPese();

      expect(moteur.etape, EtapeReflexe.resultat);
      expect(moteur.personne, isTrue);
      expect(moteur.gagnant, isNull);
      expect(materiel.desarmements, greaterThan(0));
    });
  });
}
