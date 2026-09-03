import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_quiz.dart' show CommandesBuzzer;
import 'package:buzzer_companion/audio/sonorisation.dart';
import 'package:buzzer_companion/audio/sound_engine.dart';
import 'package:buzzer_companion/audio/sound_library.dart';
import 'package:buzzer_companion/ble_link_service.dart';
import 'package:buzzer_companion/jeu/moteur_reflexe.dart';
import 'package:buzzer_companion/jeu/mots_de_la_fin.dart';

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

  /// Vrai quand le dernier signal demandait au Mega de jouer le son lui-meme.
  bool dernierGoAvecSon = false;
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
  void allumerSignal(int masque, {bool avecSonDuel = false}) {
    signaux.add(masque);
    dernierGoAvecSon = avecSonDuel;
  }
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
      moteur.presentsMateriel = [true, false, true, true];
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

  group('Faux départ : éliminé de la partie', () {
    setUp(() => moteur = creer(regle: FauxDepart.elimine, manches: 5));

    test('le fautif ne revient pas a la manche suivante', () {
      moteur.demarrer();
      moteur.surBuzz(_bleu, 800);
      expect(moteur.dansLaPartie[_bleu], isFalse);

      donnerLeSignal(moteur);
      moteur.surBuzz(_rouge, 260);
      moteur.continuer();

      // Ecarte remettait tout le monde en lice ; eliminer, non.
      expect(moteur.enLice[_bleu], isFalse);
      expect(materiel.dernierArmement, 0x0F & ~_bit(_bleu));
    });

    test('le dernier survivant gagne sur-le-champ', () {
      moteur.demarrer();
      moteur.surBuzz(_rouge, 700);
      moteur.surBuzz(_jaune, 750);
      expect(moteur.etape, EtapeReflexe.attente);

      moteur.surBuzz(_vert, 800);
      // Il ne reste que le bleu : inutile de lui faire jouer les manches
      // restantes contre personne.
      expect(moteur.etape, EtapeReflexe.finie);
      expect(moteur.vainqueur, _bleu);
      expect(moteur.egalite, isFalse);
      // Il l'emporte MEME SANS POINT : les autres ne sont plus la.
      expect(moteur.scores[_bleu], 0);
    });

    test('sa LED reste allumee : la salle voit qui reste', () {
      moteur.demarrer();
      for (final qui in [_rouge, _jaune, _vert]) {
        moteur.surBuzz(qui, 700);
      }
      expect(materiel.leds.last, _bit(_bleu));
    });

    test('le mot de la fin est tire, comme au quiz', () {
      moteur.demarrer();
      for (final qui in [_rouge, _jaune, _vert]) {
        moteur.surBuzz(qui, 700);
      }
      expect(moteur.motFinal, isNotEmpty);
    });
  });

  group('La fin de partie', () {
    test('une victoire aux points tire dans la liste des victoires', () {
      moteur = creer(manches: 1);
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 240);
      moteur.continuer();

      expect(moteur.etape, EtapeReflexe.finie);
      expect(moteur.vainqueur, _bleu);
      expect(motsDeVictoire, contains(moteur.motFinal));
    });

    test('une egalite tire dans la liste des egalites', () {
      moteur = creer(manches: 1);
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.personneNaPese();     // personne ne marque
      moteur.continuer();

      expect(moteur.etape, EtapeReflexe.finie);
      expect(moteur.egalite, isTrue);
      expect(motsDEgalite, contains(moteur.motFinal));
    });
  });

  group("Le bris d'égalité", () {
    test('seuls les ex aequo jouent la manche de depart', () {
      moteur = creer(manches: 1);
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.personneNaPese();      // tout le monde a zero
      moteur.continuer();
      expect(moteur.egalite, isTrue);

      moteur.lancerBrisDegalite();
      expect(moteur.brisEgalite, isTrue);
      expect(moteur.etape, EtapeReflexe.attente);
      // Personne n'a marque : les quatre sont ex aequo.
      expect(materiel.dernierArmement, 0x0F);
      moteur.dispose();
    });

    test('celui qui remporte la manche gagne la partie', () {
      moteur = creer(manches: 1);
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.personneNaPese();
      moteur.continuer();
      moteur.lancerBrisDegalite();

      donnerLeSignal(moteur);
      moteur.surBuzz(_vert, 210);
      moteur.continuer();
      // Un bris se joue en UNE manche : on ne relance pas.
      expect(moteur.etape, EtapeReflexe.finie);
      expect(moteur.vainqueur, _vert);
      expect(moteur.egalite, isFalse);
      moteur.dispose();
    });

    test('rien ne se lance quand il y a deja un gagnant', () {
      moteur = creer(manches: 1);
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_bleu, 240);
      moteur.continuer();
      moteur.lancerBrisDegalite();
      expect(moteur.brisEgalite, isFalse);
    });
  });

  group('Le Duel', () {
    // Duel : meme moteur, trois differences. Deux joueurs, signal SONORE, et
    // un faux depart qui offre la manche a l'adversaire.
    MoteurReflexe creerDuel() {
      materiel = _Materiel();
      return MoteurReflexe(ble: materiel, hasard: Random(1))
        ..presentsMateriel = [true, false, false, true]   // rouge contre vert
        ..manchesPrevues = 3
        ..jeu = JeuDeVitesse.duel
        ..regleFauxDepart = FauxDepart.offreLaManche;
    }

    test("le signal n'allume RIEN : il s'entend", () {
      moteur = creerDuel();
      moteur.demarrer();
      donnerLeSignal(moteur);
      // Le chrono repart quand meme (GO), mais sans lumiere : les duellistes
      // jouent dos a dos, les yeux fermes.
      expect(materiel.signaux.last, 0);
    });

    test('le Reflexe, lui, allume bien ses buzzers', () {
      moteur = creer();
      moteur.demarrer();
      donnerLeSignal(moteur);
      expect(materiel.signaux.last, 0x0F);
    });

    test("un faux depart offre la manche a l'adversaire", () {
      moteur = creerDuel();
      moteur.demarrer();
      moteur.surBuzz(_rouge, 700);   // avant le signal

      // L'adversaire gagne sans avoir a appuyer : le faire courir seul
      // contre personne n'aurait aucun sens.
      expect(moteur.etape, EtapeReflexe.resultat);
      expect(moteur.gagnant, _vert);
      expect(moteur.scores[_vert], 1);
      expect(moteur.scores[_rouge], 0);
      expect(materiel.leds.last, _bit(_vert));
    });

    test('sinon, le premier a peser gagne comme au Reflexe', () {
      moteur = creerDuel();
      moteur.demarrer();
      donnerLeSignal(moteur);
      moteur.surBuzz(_vert, 230);
      expect(moteur.gagnant, _vert);
      expect(moteur.tempsGagnant, 230);
    });

    test('le Duel exige exactement deux duellistes', () {
      moteur = creerDuel();
      expect(moteur.compteDeJoueursValide, isTrue);

      moteur.presentsMateriel = [true, true, false, true];
      expect(moteur.compteDeJoueursValide, isFalse);

      moteur.presentsMateriel = [true, false, false, false];
      expect(moteur.compteDeJoueursValide, isFalse);
    });

    test('le Reflexe se contente de ce qu\'il y a', () {
      moteur = creer();
      moteur.presentsMateriel = [true, false, false, false];
      expect(moteur.compteDeJoueursValide, isTrue);
    });
  });

  group('Duel : qui joue le son de depart', () {
    // CE CHOIX DECIDE DE LA PRECISION. Si le son sort du buzzer, le Mega doit
    // le jouer LUI-MEME dans la commande de depart : lecture et chrono
    // deviennent consecutifs. Le faire partir de l'application ajouterait la
    // latence Bluetooth entre les deux, inconnue et de plusieurs dizaines de
    // ms sur une reaction qui en fait deux cents.
    Sonorisation creerSortie({required bool versApp}) {
      final ble = BleLinkService()..appHandlesSound = versApp;
      return Sonorisation(
        locale: SoundEngine(library: SoundLibrary(), onBusyChanged: (_) {}),
        ble: ble,
      );
    }

    test('son sur le buzzer : le Mega le joue dans la commande de depart', () {
      materiel = _Materiel();
      final m = MoteurReflexe(
        ble: materiel,
        sons: creerSortie(versApp: false),
        hasard: Random(1),
      )
        ..presentsMateriel = [true, false, false, true]
        ..jeu = JeuDeVitesse.duel;
      m.demarrer();
      m.donnerLeSignal();

      expect(materiel.dernierGoAvecSon, isTrue);
      m.dispose();
    });

    test("son sur le PC : l'application le joue, le Mega ne fait que le chrono",
        () {
      materiel = _Materiel();
      final m = MoteurReflexe(
        ble: materiel,
        sons: creerSortie(versApp: true),
        hasard: Random(1),
      )
        ..presentsMateriel = [true, false, false, true]
        ..jeu = JeuDeVitesse.duel;
      m.demarrer();
      m.donnerLeSignal();

      expect(materiel.dernierGoAvecSon, isFalse);
      m.dispose();
    });

    test('au Reflexe, jamais de son dans le signal', () {
      materiel = _Materiel();
      final m = MoteurReflexe(
        ble: materiel,
        sons: creerSortie(versApp: false),
        hasard: Random(1),
      );
      m.demarrer();
      m.donnerLeSignal();

      expect(materiel.dernierGoAvecSon, isFalse);
      // Et ses buzzers s'allument, eux.
      expect(materiel.signaux.last, 0x0F);
      m.dispose();
    });
  });
}
