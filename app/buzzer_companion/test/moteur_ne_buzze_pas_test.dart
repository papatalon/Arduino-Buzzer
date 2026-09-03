import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_ne_buzze_pas.dart';
import 'package:buzzer_companion/jeu/moteur_quiz.dart' show CommandesBuzzer, ModeArmement;
import 'package:buzzer_companion/audio/sonorisation.dart';
import 'package:buzzer_companion/jeu/mots_de_la_fin.dart';
import 'package:buzzer_companion/popout/popout_snapshot.dart';

// LES RÈGLES DE « NE BUZZE PAS », qui sont les plus faciles à casser en
// silence de tous les jeux : quatre façons de gagner ou perdre un point, dont
// une qui se déclenche par ce que le joueur N'A PAS fait.
//
// Le barème est celui du buzzer, reprises telles quelles parce qu'elles ont
// été jouées pendant des soirées.

class _Materiel implements CommandesBuzzer {
  final List<int> armements = [];
  final List<int> leds = [];
  int desarmements = 0;
  bool dernierContinu = false;

  int? get dernierArmement => armements.isEmpty ? null : armements.last;

  @override
  void armer(int masque, {ModeArmement mode = ModeArmement.premier}) {
    armements.add(masque);
    dernierContinu = (mode == ModeArmement.continu);
  }

  @override
  void desarmer() => desarmements++;

  @override
  void allumerLeds(int masque) => leds.add(masque);

  @override
  void allumerSignal(int masque, {bool avecSonDuel = false}) {}
}


/// Espionne CE QUI SORT DES HAUT-PARLEURS, sans monter de moteur audio.
class _Sonorisation implements Sonorisation {
  final List<String> joues = [];

  /// On pilote la fin des sons a la main : sans ca le test dependrait
  /// d'une vraie horloge et d'un vrai moteur audio.
  bool joue = false;

  @override
  bool get sonEnCours => joue;

  @override
  bool get finDesSonsConnue => true;

  @override
  dynamic noSuchMethod(Invocation i) {
    final nom = i.memberName.toString();
    joues.add(nom.substring(nom.indexOf('"') + 1, nom.lastIndexOf('"')));
    return null;
  }
}

const _rouge = 0, _bleu = 1, _jaune = 2, _vert = 3;
int _bit(int i) => 1 << i;

void main() {
  late _Materiel materiel;
  late MoteurNeBuzzePas moteur;

  MoteurNeBuzzePas creer({int chances = 4, bool leurres = false}) {
    materiel = _Materiel();
    return MoteurNeBuzzePas(ble: materiel, hasard: Random(1))
      ..chancesParBuzzer = chances
      ..avecLeurres = leurres;
  }

  // L'écoute guidée, buzzer par buzzer : chacun pèse pour entendre le sien.
  void faireLEcoute(MoteurNeBuzzePas m) {
    // L'ecoute attend maintenant la fin de chaque son : on la pousse a la
    // main plutot que de dependre d'une vraie horloge.
    m.delaiAvantDeSonderMs = 0;
    var garde = 0;
    while (m.aQuiLeTour != null && garde++ < 20) {
      m.surBuzz(m.aQuiLeTour!, 0);
      if (m.sonEnEcoute) m.verifierLaFinDuSon();
    }
  }

  group("L'assignation", () {
    test('les sons sont tirés au sort, pas ceux qui sont configurés', () {
      moteur = creer();
      moteur.demarrer(nombreDeSonsDisponibles: 12);

      // Quatre sons attribues, tous DIFFERENTS : sans ca, deux joueurs
      // auraient le meme et la partie serait injouable.
      final attribues = [
        for (var i = 0; i < 4; i++) moteur.assignation[i]
      ].whereType<int>().toList();
      expect(attribues.length, 4);
      expect(attribues.toSet().length, 4);
      for (final s in attribues) {
        expect(s, inInclusiveRange(0, 11));
      }
    });

    test('deux parties de suite ne donnent pas la même assignation', () {
      // C'est tout l'interet du twist : les habitues ne peuvent pas
      // apprendre leur son par coeur d'une soiree a l'autre.
      final a = MoteurNeBuzzePas(ble: _Materiel(), hasard: Random(1))
        ..demarrer(nombreDeSonsDisponibles: 30);
      final b = MoteurNeBuzzePas(ble: _Materiel(), hasard: Random(2))
        ..demarrer(nombreDeSonsDisponibles: 30);
      expect(a.assignation, isNot(b.assignation));
    });

    test('un buzzer absent ne reçoit pas de son', () {
      moteur = creer();
      moteur.presentsMateriel = [true, false, true, true];
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      expect(moteur.assignation[_bleu], isNull);
    });
  });

  group("L'écoute guidée", () {
    setUp(() => moteur = creer());

    test('un seul buzzer à la fois est armé', () {
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      expect(moteur.etape, EtapeNeBuzzePas.ecoute);
      expect(moteur.aQuiLeTour, _rouge);
      // Seul celui dont c'est le tour : un voisin impatient ne peut pas
      // declencher le son de quelqu'un d'autre ni bruler son tour.
      expect(materiel.dernierArmement, _bit(_rouge));
      expect(materiel.leds.last, _bit(_rouge));
      expect(materiel.dernierContinu, isFalse);
    });

    test('un appui fait entendre son son et passe au suivant', () {
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      moteur.surBuzz(_rouge, 0);
      expect(moteur.aEcoute[_rouge], isTrue);
      expect(moteur.aQuiLeTour, _bleu);
      expect(materiel.dernierArmement, _bit(_bleu));
    });

    test("l'appui de quelqu'un d'autre ne fait rien", () {
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      moteur.surBuzz(_vert, 0);
      expect(moteur.aEcoute[_vert], isFalse);
      expect(moteur.aQuiLeTour, _rouge);
    });

    test("l'écoute se termine quand chacun a entendu le sien", () {
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      expect(moteur.ecouteTerminee, isTrue);
      expect(moteur.aQuiLeTour, isNull);
    });

    test('le flux ne part pas avant la fin de l\'écoute', () {
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      moteur.lancerLeFlux();
      expect(moteur.etape, EtapeNeBuzzePas.ecoute);

      faireLEcoute(moteur);
      moteur.lancerLeFlux();
      expect(moteur.etape, EtapeNeBuzzePas.flux);
      moteur.dispose();
    });
  });

  group('Le barème', () {
    setUp(() {
      moteur = creer();
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();
    });

    tearDown(() => moteur.dispose());

    test('reconnaître son son vaut un point', () {
      final qui = moteur.proprietaireDuSon!;
      // Deuxieme moitie de l'ecart : juste, mais pas rapide.
      moteur.surBuzz(qui, moteur.ecartCourantMs - 10);
      expect(moteur.scores[qui], 1);
    });

    test('deux points dans la première moitié de l\'écart', () {
      final qui = moteur.proprietaireDuSon!;
      moteur.surBuzz(qui, 100);
      // Sans ca, ecouter le son en entier avant de peser serait sans risque.
      expect(moteur.scores[qui], 2);
    });

    test("peser sur le son d'un autre coûte un point", () {
      final proprio = moteur.proprietaireDuSon!;
      final autre = [_rouge, _bleu, _jaune, _vert].firstWhere((i) => i != proprio);
      moteur.surBuzz(autre, 200);
      expect(moteur.scores[autre], -1);
    });

    test("mais le propriétaire peut encore réclamer son son", () {
      final proprio = moteur.proprietaireDuSon!;
      final autre = [_rouge, _bleu, _jaune, _vert].firstWhere((i) => i != proprio);
      moteur.surBuzz(autre, 200);
      moteur.surBuzz(proprio, 300);
      expect(moteur.scores[proprio], greaterThan(0));
    });

    test('on ne réagit qu\'une fois par son', () {
      final proprio = moteur.proprietaireDuSon!;
      moteur.surBuzz(proprio, 100);
      moteur.surBuzz(proprio, 200);
      expect(moteur.scores[proprio], 2);
    });

    test('LAISSER PASSER SON PROPRE SON COÛTE UN POINT', () {
      final qui = moteur.proprietaireDuSon!;
      // Personne ne pese, on passe au son suivant : sans cette penalite, ne
      // jamais peser serait une strategie sans risque.
      moteur.sonSuivant();
      expect(moteur.scores[qui], -1);
    });

    test('celui qui a réclamé son son n\'est pas puni ensuite', () {
      final qui = moteur.proprietaireDuSon!;
      moteur.surBuzz(qui, 100);
      moteur.sonSuivant();
      expect(moteur.scores[qui], 2);
    });
  });

  group("L'écart se resserre", () {
    test('de l\'écart de départ vers le plus serré, puis plancher', () {
      moteur = creer(chances: 12);      // sans limite, pour derouler
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();
      expect(moteur.ecartCourantMs,
          MoteurNeBuzzePas.ecartDepartMs - MoteurNeBuzzePas.ecartPasMs);

      for (var i = 0; i < 40; i++) {
        moteur.sonSuivant();
      }
      // Le plancher tient : l'ecart ne devient jamais negatif.
      expect(moteur.ecartCourantMs, MoteurNeBuzzePas.ecartMinMs);
      moteur.dispose();
    });
  });

  group('Les leurres', () {
    test('un leurre n\'appartient à personne et coûte un point', () {
      moteur = creer(chances: 6, leurres: true);
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();

      // On deroule jusqu'a tomber sur un leurre.
      var essais = 0;
      while (moteur.proprietaireDuSon != null && essais < 100) {
        moteur.sonSuivant();
        essais++;
      }
      expect(moteur.proprietaireDuSon, isNull, reason: 'aucun leurre tire');
      // Le son joue n'est celui de personne.
      expect(moteur.assignation.contains(moteur.sonCourant), isFalse);

      final avant = moteur.scores[_rouge];
      moteur.surBuzz(_rouge, 200);
      expect(moteur.scores[_rouge], avant - 1);
      moteur.dispose();
    });

    test('sans leurres, tout son joué appartient à quelqu\'un', () {
      moteur = creer(chances: 12, leurres: false);
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();
      for (var i = 0; i < 20; i++) {
        expect(moteur.proprietaireDuSon, isNotNull);
        moteur.sonSuivant();
      }
      moteur.dispose();
    });
  });

  group('La fin de partie', () {
    test('le nombre de sons prévu termine la partie', () {
      moteur = creer(chances: 1);
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();
      // Un tour par buzzer present, donc quatre.
      expect(moteur.sonsPrevus, 4);
      for (var i = 0; i < 4; i++) {
        moteur.sonSuivant();
      }

      expect(moteur.etape, EtapeNeBuzzePas.finie);
      expect(materiel.leds.last, 0);
      expect(motsDeVictoire.contains(moteur.motFinal) ||
          motsDEgalite.contains(moteur.motFinal), isTrue);
    });
  });

  group("L'ecran public", () {
    // L'INVARIANT DU JEU : l'ecran ne montre QUE le son precedent, deja joue
    // et deja juge. Reveler a qui appartient le son EN COURS repondrait a la
    // seule question que le jeu pose, et rien dans l'affichage ne le dirait.
    PopoutSnapshot vu(MoteurNeBuzzePas m) => PopoutSnapshot.duNeBuzzePas(
          m,
          teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
          logoPath: null,
        );

    test("le proprietaire du son EN COURS ne voyage jamais vers l'ecran", () {
      moteur = creer();
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();

      // Premier son : rien n'est encore passe, donc il n'y a rien a montrer.
      expect(vu(moteur).soundLastOwner, -2);

      final premier = moteur.proprietaireDuSon;
      moteur.sonSuivant();
      // Le premier son est maintenant le precedent : il peut se montrer.
      expect(vu(moteur).soundLastOwner, premier);
      // Et il n'est PAS celui qui joue.
      expect(vu(moteur).soundLastOwner, isNot(moteur.proprietaireDuSon));
      moteur.dispose();
    });

    test('reconnu ou laisse passer suit le son precedent, pas le courant', () {
      moteur = creer();
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();

      moteur.surBuzz(moteur.proprietaireDuSon!, 100);
      moteur.sonSuivant();
      expect(vu(moteur).soundLastClaimed, isTrue);

      // Celui-la, personne ne le reclame.
      moteur.sonSuivant();
      expect(vu(moteur).soundLastClaimed, isFalse);
      moteur.dispose();
    });

    test("pendant l'ecoute, l'ecran nomme celui dont c'est le tour", () {
      moteur = creer();
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      expect(vu(moteur).soundLearning, moteur.aQuiLeTour);

      faireLEcoute(moteur);
      // -1 est la convention du firmware pour « ecoute terminee ».
      expect(vu(moteur).soundLearning, -1);
    });

    test('les scores affiches sont ceux du jeu, pas ceux du questionnaire', () {
      moteur = creer();
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();
      moteur.surBuzz(moteur.proprietaireDuSon!, 100);

      expect(vu(moteur).gameScores, moteur.scores);
      expect(vu(moteur).scores, [0, 0, 0, 0]);
      moteur.dispose();
    });
  });


  group("L'apercu de duree", () {
    // L'ecart se resserre, donc la duree N'EST PAS proportionnelle : une
    // multiplication simple donnerait une estimation de plus en plus fausse a
    // mesure que la partie s'allonge, et c'est justement sur les longues
    // parties que l'animateur a besoin de savoir si ca rentre.
    test('doubler les sons ne double pas la duree', () {
      final court = MoteurNeBuzzePas.dureeEstimee(20).inMilliseconds;
      final long = MoteurNeBuzzePas.dureeEstimee(40).inMilliseconds;
      expect(long, lessThan(court * 2));
    });

    test('la duree suit les vrais ecarts, plancher compris', () {
      // Les cinq premiers : 2400 + 2300 + 2200 + 2100 + 2000.
      expect(MoteurNeBuzzePas.dureeEstimee(5).inMilliseconds, 11000);  // 2400+2300+2200+2100+2000
      // Passe le plancher, chaque son ajoute exactement l'ecart minimal.
      final a = MoteurNeBuzzePas.dureeEstimee(50).inMilliseconds;
      final b = MoteurNeBuzzePas.dureeEstimee(51).inMilliseconds;
      expect(b - a, MoteurNeBuzzePas.ecartMinMs);
    });

    test('aucun son, aucune duree', () {
      expect(MoteurNeBuzzePas.dureeEstimee(0), Duration.zero);
    });
  });


  group('Les sons de la partie, et rien d\'autre', () {
    // LE SON EST LA QUESTION dans ce jeu, pas la decoration. Un « bonne
    // reponse » par-dessus couvrirait le son suivant, qui part une seconde et
    // demie plus tard, et dirait a toute la salle si celui qui vient de peser
    // avait raison : exactement ce qu'elle doit deviner.
    late _Sonorisation entendus;

    MoteurNeBuzzePas avecSon() {
      materiel = _Materiel();
      entendus = _Sonorisation();
      return MoteurNeBuzzePas(ble: materiel, sons: entendus, hasard: Random(1))
        ..chancesParBuzzer = 4
        ..avecLeurres = false;
    }

    test('un bon clic ne declenche aucun son de reaction', () {
      moteur = avecSon();
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();
      entendus.joues.clear();

      moteur.surBuzz(moteur.proprietaireDuSon!, 100);
      expect(entendus.joues, isEmpty);
      moteur.dispose();
    });

    test('un mauvais clic non plus', () {
      moteur = avecSon();
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();
      final proprio = moteur.proprietaireDuSon!;
      entendus.joues.clear();

      moteur.surBuzz(
          [_rouge, _bleu, _jaune, _vert].firstWhere((i) => i != proprio), 200);
      expect(entendus.joues, isEmpty);
      moteur.dispose();
    });

    test('le flux ne joue que ses propres sons', () {
      moteur = avecSon();
      moteur.demarrer(nombreDeSonsDisponibles: 12);
      faireLEcoute(moteur);
      moteur.lancerLeFlux();
      entendus.joues.clear();

      moteur.surBuzz(moteur.proprietaireDuSon!, 100);
      moteur.sonSuivant();
      moteur.sonSuivant();
      // Deux sons de flux, rien de plus : pas de bonneReponse empilee.
      expect(entendus.joues, ['sonNumero', 'sonNumero']);
      moteur.dispose();
    });
  });


  group("L'écoute attend la fin du son", () {
    // LE PIEGE : si le suivant est arme pendant que le son precedent joue, il
    // pese par-dessus et memorise un melange des deux. C'est exactement
    // l'association sur laquelle toute la partie repose, et rien ne le
    // signalerait avant que quelqu'un se trompe dans le flux.
    late _Sonorisation audio;

    MoteurNeBuzzePas avecAudio() {
      materiel = _Materiel();
      audio = _Sonorisation();
      // On pilote la fin des sons a la main, sans dependre d'une horloge.
      return MoteurNeBuzzePas(ble: materiel, sons: audio, hasard: Random(1))
        ..delaiAvantDeSonderMs = 0;
    }

    test('personne n\'est armé pendant que le son joue', () {
      moteur = avecAudio()..demarrer(nombreDeSonsDisponibles: 12);
      audio.joue = true;
      moteur.surBuzz(_rouge, 0);

      expect(moteur.sonEnEcoute, isTrue);
      expect(materiel.desarmements, greaterThan(0));
      expect(materiel.leds.last, 0);
      moteur.dispose();
    });

    test("l'écran reste sur le buzzer courant, pas sur le suivant", () {
      moteur = avecAudio()..demarrer(nombreDeSonsDisponibles: 12);
      audio.joue = true;
      moteur.surBuzz(_rouge, 0);

      // Nommer deja le bleu lui dirait de peser, et il peserait par-dessus.
      expect(moteur.aQuiLeTour, _rouge);
      moteur.dispose();
    });

    test('le suivant est armé quand le silence revient', () {
      moteur = avecAudio()..demarrer(nombreDeSonsDisponibles: 12);
      audio.joue = true;
      moteur.surBuzz(_rouge, 0);

      audio.joue = false;
      moteur.verifierLaFinDuSon();

      expect(moteur.sonEnEcoute, isFalse);
      expect(moteur.aQuiLeTour, _bleu);
      expect(materiel.dernierArmement, _bit(_bleu));
      moteur.dispose();
    });

    test('un son qui joue encore ne libère pas le tour', () {
      moteur = avecAudio()..demarrer(nombreDeSonsDisponibles: 12);
      audio.joue = true;
      moteur.surBuzz(_rouge, 0);
      moteur.verifierLaFinDuSon();

      expect(moteur.aQuiLeTour, _rouge);
      expect(moteur.sonEnEcoute, isTrue);
      moteur.dispose();
    });

    test('une réécoute attend aussi, elle couvrirait le tour suivant', () {
      moteur = avecAudio()..demarrer(nombreDeSonsDisponibles: 12);
      audio.joue = true;
      moteur.surBuzz(_rouge, 0);
      audio.joue = false;
      moteur.verifierLaFinDuSon();

      audio.joue = true;
      moteur.reecouter(_rouge);
      expect(moteur.sonEnEcoute, isTrue);
      expect(materiel.leds.last, 0);
      moteur.dispose();
    });
  });


  group("L'équité du parcours", () {
    // LE BUG QUI A MOTIVE CE PARCOURS : les tours etaient tires au hasard un
    // par un, alors sur seize tours il arrivait couramment qu'un buzzer ne
    // sorte JAMAIS. Ce joueur ne pouvait pas marquer un seul point, et rien
    // nulle part ne l'expliquait. Un test qui compte les tours est le seul
    // moyen de voir ca : a l'oeil, une partie injuste ressemble a une partie
    // ou quelqu'un joue mal.
    List<int?> parcoursDe(MoteurNeBuzzePas m) => m.parcours;

    test('chaque buzzer présent a exactement le même nombre de tours', () {
      for (var graine = 0; graine < 30; graine++) {
        final m = MoteurNeBuzzePas(ble: _Materiel(), hasard: Random(graine))
          ..chancesParBuzzer = 4
          ..avecLeurres = true;
        m.demarrer(nombreDeSonsDisponibles: 20);

        for (var i = 0; i < 4; i++) {
          expect(parcoursDe(m).where((p) => p == i).length, 4,
              reason: 'graine $graine, buzzer $i');
        }
      }
    });

    test('un buzzer absent n\'a aucun tour, les autres gardent les leurs', () {
      moteur = creer(chances: 3);
      moteur.presentsMateriel = [true, false, true, true];
      moteur.demarrer(nombreDeSonsDisponibles: 20);

      expect(parcoursDe(moteur).where((p) => p == _bleu), isEmpty);
      for (final i in [_rouge, _jaune, _vert]) {
        expect(parcoursDe(moteur).where((p) => p == i).length, 3);
      }
    });

    test('le total découle des chances et du nombre de buzzers', () {
      moteur = creer(chances: 4);
      moteur.demarrer(nombreDeSonsDisponibles: 20);
      expect(moteur.sonsPrevus, 16);

      moteur = creer(chances: 5);
      moteur.presentsMateriel = [true, true, false, false];
      moteur.demarrer(nombreDeSonsDisponibles: 20);
      expect(moteur.sonsPrevus, 10);
    });

    test('le même buzzer ne joue jamais deux tours de suite', () {
      // Sinon la personne pese, son son revient une seconde et demie plus
      // tard, et elle croit avoir mal entendu.
      for (var graine = 0; graine < 30; graine++) {
        final m = MoteurNeBuzzePas(ble: _Materiel(), hasard: Random(graine))
          ..chancesParBuzzer = 4
          ..avecLeurres = true;
        m.demarrer(nombreDeSonsDisponibles: 20);

        final p = parcoursDe(m);
        for (var i = 1; i < p.length; i++) {
          if (p[i] == null) continue;
          expect(p[i], isNot(p[i - 1]), reason: 'graine $graine, tour $i');
        }
      }
    });
  });

  group('Les leurres restent proportionnés', () {
    // « Si 16 tours, on ne veut pas 100 leurres » : le nombre est tire au sort
    // pour que deux parties ne se ressemblent pas, mais borne par les tours
    // des joueurs.
    test('leur nombre suit la longueur de la partie', () {
      for (var graine = 0; graine < 30; graine++) {
        final m = MoteurNeBuzzePas(ble: _Materiel(), hasard: Random(graine))
          ..chancesParBuzzer = 4
          ..avecLeurres = true;
        m.demarrer(nombreDeSonsDisponibles: 20);

        final leurres = m.parcours.where((p) => p == null).length;
        final tours = m.parcours.length - leurres;
        expect(leurres,
            inInclusiveRange(
                (tours * MoteurNeBuzzePas.leurresMinPourCent / 100).floor(),
                (tours * MoteurNeBuzzePas.leurresMaxPourCent / 100).ceil()),
            reason: 'graine $graine');
      }
    });

    test('deux parties ne tirent pas le même nombre de leurres', () {
      final compte = <int>{};
      for (var graine = 0; graine < 20; graine++) {
        final m = MoteurNeBuzzePas(ble: _Materiel(), hasard: Random(graine))
          ..chancesParBuzzer = 4
          ..avecLeurres = true;
        m.demarrer(nombreDeSonsDisponibles: 20);
        compte.add(m.parcours.where((p) => p == null).length);
      }
      expect(compte.length, greaterThan(1));
    });

    test('sans leurres, aucun tour n\'est vide', () {
      moteur = creer(chances: 4);
      moteur.demarrer(nombreDeSonsDisponibles: 20);
      expect(moteur.parcours.contains(null), isFalse);
    });
  });

}
