import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/moteur_quiz.dart'
    show CommandesBuzzer, ModeArmement;
import 'package:buzzer_companion/jeu/moteur_simon.dart';
import 'package:buzzer_companion/popout/popout_content.dart';
import 'package:buzzer_companion/popout/popout_snapshot.dart';
import 'package:buzzer_companion/protocol.dart';

// LES RÈGLES DE SIMON, désormais tenues par l'application.
//
// Elles sont reprises du firmware à l'identique, parce qu'elles ont été jouées
// et ajustées pendant des soirées. Ce qui se vérifie ici, ce sont les endroits
// où le portage pouvait silencieusement les trahir : le mode d'armement, la
// séquence tirée hors des couleurs en jeu, le sens de la répétition inverse,
// et ce que la salle voit.

class _Materiel implements CommandesBuzzer {
  final List<int> armements = [];
  final List<ModeArmement> modes = [];
  final List<int> leds = [];
  int desarmements = 0;

  int? get dernierArmement => armements.isEmpty ? null : armements.last;
  ModeArmement? get dernierMode => modes.isEmpty ? null : modes.last;

  @override
  void armer(int masque, {ModeArmement mode = ModeArmement.premier}) {
    armements.add(masque);
    modes.add(mode);
  }

  @override
  void desarmer() => desarmements++;

  @override
  void allumerLeds(int masque) => leds.add(masque);

  @override
  void allumerSignal(int masque, {bool avecSonDuel = false}) =>
      leds.add(masque);
}

const _rouge = 0, _bleu = 1, _jaune = 2, _vert = 3;
int _bit(int i) => 1 << i;

/// Avance jusqu'au moment où l'équipe a la main, et PAS PLUS LOIN : le délai
/// de dix secondes sans appui part dès que la démonstration rend la main, donc
/// avancer généreusement terminerait la partie au lieu de la commencer.
void _passerLaDemo(FakeAsync horloge, MoteurSimon m) {
  final duree = MoteurSimon.avantLaDemoMs +
      m.sequence.length * (MoteurSimon.allumeMs + MoteurSimon.silenceMs);
  horloge.elapse(Duration(milliseconds: duree + 10));
  expect(m.etape, EtapeSimon.repetition,
      reason: 'la démonstration devrait avoir rendu la main');
}

/// Rejoue la séquence sans se tromper, dans le sens attendu.
void _rejouerJuste(MoteurSimon m) {
  final attendu = m.alEnvers ? m.sequence.reversed.toList() : m.sequence;
  for (final c in List<int>.of(attendu)) {
    m.surBuzz(c, 0);
  }
}

void main() {
  late _Materiel materiel;

  MoteurSimon creer({List<bool>? presents, bool envers = false, int graine = 1}) {
    materiel = _Materiel();
    final m = MoteurSimon(ble: materiel, hasard: Random(graine))
      ..alEnvers = envers;
    if (presents != null) m.presentsMateriel = List<bool>.of(presents);
    return m;
  }

  group('Le lancement', () {
    test('la partie commence par une seule couleur', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        expect(m.etape, EtapeSimon.demonstration);
        expect(m.sequence.length, 1);
        expect(m.niveau, 0);
        m.dispose();
      });
    });

    test('à un seul joueur, on ne lance pas', () {
      // La séquence serait la même couleur répétée : il n'y aurait rien à
      // mémoriser, et le buzzer refuse déjà de lancer en dessous de deux.
      final m = creer(presents: [true, false, false, false])..demarrer();
      expect(m.compteDeJoueursValide, isFalse);
      expect(m.etape, EtapeSimon.repos);
      m.dispose();
    });

    test('la séquence ne sort JAMAIS des couleurs en jeu', () {
      fakeAsync((horloge) {
        // À deux joueurs, tirer parmi les quatre demanderait des couleurs que
        // personne ne tient : la partie serait perdue d'avance sans que rien
        // ne l'explique.
        final m = creer(presents: [true, false, false, true]);
        m.demarrer();
        for (var niveau = 0; niveau < 8; niveau++) {
          _passerLaDemo(horloge, m);
          _rejouerJuste(m);
          horloge.elapse(const Duration(seconds: 3)); // la pause « bravo »
        }
        expect(m.sequence, everyElement(anyOf(_rouge, _vert)));
        m.dispose();
      });
    });

    test('tout le monde pèse à peu près autant', () {
      // Le tirage indépendant du firmware laissait couramment un joueur avec
      // un seul appui sur dix pendant qu'un autre en avait cinq. Sans score
      // pour consoler qui que ce soit, celui-là a juste regardé les autres.
      for (var graine = 0; graine < 40; graine++) {
        fakeAsync((horloge) {
          final m = creer(graine: graine);
          m.demarrer();
          for (var niveau = 0; niveau < 12; niveau++) {
            _passerLaDemo(horloge, m);
            _rejouerJuste(m);
            horloge.elapse(const Duration(seconds: 3));
          }
          final compte = [0, 0, 0, 0];
          for (final c in m.sequence) {
            compte[c]++;
          }
          // Douze couleurs pour quatre joueurs : trois chacun, à une près
          // quand le compte ne tombe pas rond.
          expect(compte.reduce((a, b) => a > b ? a : b) -
              compte.reduce((a, b) => a < b ? a : b),
              lessThanOrEqualTo(1),
              reason: 'graine $graine : $compte');
          m.dispose();
        });
      }
    });

    test('la séquence reste imprévisible', () {
      // L'équité ne doit pas devenir un tour de rôle : « rouge, bleu, jaune,
      // vert, rouge... » se retiendrait sans mémoire.
      final vues = <String>{};
      for (var graine = 0; graine < 20; graine++) {
        fakeAsync((horloge) {
          final m = creer(graine: graine);
          m.demarrer();
          for (var niveau = 0; niveau < 4; niveau++) {
            _passerLaDemo(horloge, m);
            _rejouerJuste(m);
            horloge.elapse(const Duration(seconds: 3));
          }
          vues.add(m.sequence.join(','));
          m.dispose();
        });
      }
      expect(vues.length, greaterThan(10));
    });

    test('un buzzer débranché en cours de partie ne change pas la séquence',
        () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        // Les couleurs de la partie sont figées au lancement.
        m.presentsMateriel = [true, true, false, false];
        _rejouerJuste(m);
        horloge.elapse(const Duration(seconds: 3));
        _passerLaDemo(horloge, m);
        expect(m.sequence.length, 2);
        m.dispose();
      });
    });
  });

  group("L'armement", () {
    test('la répétition arme en mode RÉPÉTÉ, pas continu', () {
      fakeAsync((horloge) {
        // En continu, le buzzer qui pèse sort du masque : l'application
        // devrait réarmer entre deux appuis de la même couleur, et
        // l'aller-retour Bluetooth avalerait le second.
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        expect(materiel.dernierMode, ModeArmement.repete);
        expect(materiel.dernierArmement, 0x0F);
        m.dispose();
      });
    });

    test('la même couleur peut être pesée deux fois de suite', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false])..demarrer();
        // On force une séquence « rouge, rouge », le cas qui a motivé le mode
        // répété : il sort une fois sur quatre à quatre joueurs.
        _passerLaDemo(horloge, m);
        m.sequence
          ..clear()
          ..addAll([_rouge, _rouge]);

        m.surBuzz(_rouge, 0);
        expect(m.saisis, 1);
        m.surBuzz(_rouge, 0);
        // Aucun réarmement n'a été nécessaire entre les deux.
        expect(m.niveau, 1);
        expect(materiel.armements.length, 1);
        m.dispose();
      });
    });

    test('rien n\'est armé pendant la démonstration', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        // Un appui pendant la séquence ferait rater le niveau à quelqu'un qui
        // s'est juste accoudé sur son bouton.
        expect(materiel.armements, isEmpty);
        expect(materiel.desarmements, greaterThan(0));
        horloge.elapse(const Duration(milliseconds: 1600));
        m.surBuzz(_rouge, 0);
        expect(m.saisis, 0);
        m.dispose();
      });
    });
  });

  group('Le rythme de la démonstration', () {
    test('la première couleur attend, les suivantes s\'enchaînent', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false])..demarrer();
        m.sequence
          ..clear()
          ..addAll([_rouge, _bleu]);

        // Pause de lecture avant la première couleur.
        horloge.elapse(const Duration(milliseconds: 1499));
        expect(m.couleurAllumee, isNull);
        horloge.elapse(const Duration(milliseconds: 2));
        expect(m.couleurAllumee, _rouge);

        // Allumage, puis silence, puis la suivante.
        horloge.elapse(const Duration(milliseconds: 600));
        expect(m.couleurAllumee, isNull);
        horloge.elapse(const Duration(milliseconds: 250));
        expect(m.couleurAllumee, _bleu);
        m.dispose();
      });
    });

    test('la séquence s\'allonge d\'une couleur par niveau réussi', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        for (var attendu = 1; attendu <= 4; attendu++) {
          _passerLaDemo(horloge, m);
          expect(m.sequence.length, attendu);
          _rejouerJuste(m);
          horloge.elapse(const Duration(seconds: 3));
        }
        expect(m.niveau, 4);
        m.dispose();
      });
    });

    test('la pause « bravo » laisse le temps de se réjouir', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        _rejouerJuste(m);
        expect(m.etape, EtapeSimon.bravo);
        horloge.elapse(const Duration(milliseconds: 1900));
        expect(m.etape, EtapeSimon.bravo);
        horloge.elapse(const Duration(milliseconds: 200));
        expect(m.etape, EtapeSimon.demonstration);
        m.dispose();
      });
    });
  });

  group('La répétition', () {
    test('une couleur fausse termine la partie et nomme le fautif', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false])..demarrer();
        _passerLaDemo(horloge, m);
        m.sequence
          ..clear()
          ..addAll([_rouge]);

        m.surBuzz(_bleu, 0);
        expect(m.etape, EtapeSimon.finie);
        expect(m.raisonDeLaFin, FinDeSimon.rate);
        expect(m.fautif, _bleu);
        // Sa LED reste allumée : la salle voit qui a rompu la chaîne.
        expect(materiel.leds.last, _bit(_bleu));
        m.dispose();
      });
    });

    test('dix secondes sans appui arrêtent la partie sans accuser personne',
        () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        horloge.elapse(const Duration(seconds: 11));
        expect(m.etape, EtapeSimon.finie);
        expect(m.raisonDeLaFin, FinDeSimon.tropLent);
        expect(m.fautif, isNull);
        m.dispose();
      });
    });

    test('chaque appui juste relance le délai', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        m.sequence
          ..clear()
          ..addAll([_rouge, _bleu, _jaune]);

        horloge.elapse(const Duration(seconds: 8));
        m.surBuzz(_rouge, 0);
        horloge.elapse(const Duration(seconds: 8));
        m.surBuzz(_bleu, 0);
        horloge.elapse(const Duration(seconds: 8));
        // Sans la relance, la partie serait morte depuis longtemps.
        expect(m.etape, EtapeSimon.repetition);
        expect(m.saisis, 2);
        m.dispose();
      });
    });

    test('un buzzer absent ne peut pas faire échouer la partie', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false])..demarrer();
        _passerLaDemo(horloge, m);
        // Un buzzer déclaré absent reste branché. Le Mega ne l'arme pas, mais
        // le moteur ne doit pas non plus le juger s'il arrivait quand même.
        m.surBuzz(_vert, 0);
        expect(m.etape, EtapeSimon.repetition);
        expect(m.raisonDeLaFin, isNull);
        m.dispose();
      });
    });

    test('l\'écho lumineux s\'éteint tout seul', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false])..demarrer();
        _passerLaDemo(horloge, m);
        m.sequence
          ..clear()
          ..addAll([_rouge, _bleu]);

        m.surBuzz(_rouge, 0);
        expect(m.couleurAllumee, _rouge);
        horloge.elapse(const Duration(milliseconds: 401));
        expect(m.couleurAllumee, isNull);
        expect(materiel.leds.last, 0);
        m.dispose();
      });
    });
  });

  group('Simon inverse', () {
    test('la séquence se rejoue de la fin vers le début', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false], envers: true)
          ..demarrer();
        _passerLaDemo(horloge, m);
        m.sequence
          ..clear()
          ..addAll([_rouge, _bleu]);

        // Dans l'ordre normal ce serait juste : ici c'est l'erreur.
        m.surBuzz(_rouge, 0);
        expect(m.raisonDeLaFin, FinDeSimon.rate);
        m.dispose();
      });
    });

    test('rejouée à l\'envers, elle passe', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false], envers: true)
          ..demarrer();
        _passerLaDemo(horloge, m);
        m.sequence
          ..clear()
          ..addAll([_rouge, _bleu]);

        m.surBuzz(_bleu, 0);
        m.surBuzz(_rouge, 0);
        expect(m.niveau, 1);
        expect(m.etape, EtapeSimon.bravo);
        m.dispose();
      });
    });

    test('la démonstration reste dans le sens normal', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false], envers: true)
          ..demarrer();
        m.sequence
          ..clear()
          ..addAll([_rouge, _bleu]);

        horloge.elapse(const Duration(milliseconds: 1501));
        // C'est bien la PREMIÈRE couleur qui est montrée en premier ; seule la
        // répétition s'inverse.
        expect(m.couleurAllumee, _rouge);
        m.dispose();
      });
    });
  });

  group('La fin de partie', () {
    test('l\'abandon garde le niveau atteint', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        _rejouerJuste(m);
        horloge.elapse(const Duration(seconds: 3));
        _passerLaDemo(horloge, m);

        m.abandonner();
        expect(m.etape, EtapeSimon.finie);
        expect(m.raisonDeLaFin, FinDeSimon.abandon);
        expect(m.niveau, 1);
        expect(m.fautif, isNull);
        m.dispose();
      });
    });

    test('la fin désarme et ne laisse aucun minuteur derrière', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        final avant = materiel.desarmements;
        m.abandonner();
        expect(materiel.desarmements, greaterThan(avant));

        // Si le délai de dix secondes tournait encore, il retrancherait la
        // partie une deuxième fois.
        horloge.elapse(const Duration(seconds: 30));
        expect(m.raisonDeLaFin, FinDeSimon.abandon);
        m.dispose();
      });
    });

    test('le mot de la fin commente le niveau, pas une victoire', () {
      // Simon est collaboratif : personne ne gagne, donc les mots de victoire
      // et d'égalité sonneraient faux.
      expect(motDuNiveau(0), contains('Même pas un niveau'));
      expect(motDuNiveau(1), isNot(motDuNiveau(0)));
      expect(motDuNiveau(4), isNot(motDuNiveau(1)));
      expect(motDuNiveau(8), isNot(motDuNiveau(4)));
      expect(motDuNiveau(12), isNot(motDuNiveau(8)));
      expect(motDuNiveau(MoteurSimon.longueurMax), contains('éléphant'));
    });

    test('quitter range tout', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        m.quitter();
        expect(m.etape, EtapeSimon.repos);
        expect(materiel.leds.last, 0);
        horloge.elapse(const Duration(seconds: 30));
        expect(m.etape, EtapeSimon.repos);
        m.dispose();
      });
    });
  });

  group("L'écran public", () {
    test('le niveau montré est celui qui SE JOUE, pas celui qui est réussi',
        () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        _rejouerJuste(m);
        horloge.elapse(const Duration(seconds: 3));
        _passerLaDemo(horloge, m);

        final vu = PopoutSnapshot.duSimon(
          m,
          teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
          logoPath: null,
        );
        // L'écran ajoute 1 tant que la partie tourne (voir _SimonZone) : le
        // moteur doit donc envoyer les niveaux RÉUSSIS, pas le niveau affiché.
        expect(vu.simonLevel, 1);
        expect(vu.simonLength, 2);
        expect(vu.gameFinished, isFalse);
        m.dispose();
      });
    });

    test('la mise en page masque le tableau des scores', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        final vu = PopoutSnapshot.duSimon(
          m,
          teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
          logoPath: null,
        );
        // Aucun point n'est marque : un tableau de zeros devant la salle ne
        // souleverait qu'une question. C'est GameLayout qui le masque.
        expect(layoutFor(vu.gameMode), GameLayout.simon);
        // Jeu collaboratif : jamais de gagnant individuel.
        expect(vu.gameWinner, isNull);
        m.dispose();
      });
    });

    test('la progression avance à chaque bonne couleur', () {
      fakeAsync((horloge) {
        final m = creer(presents: [true, true, false, false])..demarrer();
        _passerLaDemo(horloge, m);
        m.sequence
          ..clear()
          ..addAll([_rouge, _bleu, _rouge]);

        m.surBuzz(_rouge, 0);
        final vu = PopoutSnapshot.duSimon(
          m,
          teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
          logoPath: null,
        );
        expect(vu.simonEntered, 1);
        expect(vu.simonLength, 3);
        m.dispose();
      });
    });

    test('la partie finie montre le niveau atteint', () {
      fakeAsync((horloge) {
        final m = creer()..demarrer();
        _passerLaDemo(horloge, m);
        m.abandonner();
        final vu = PopoutSnapshot.duSimon(
          m,
          teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
          logoPath: null,
        );
        expect(vu.gameFinished, isTrue);
        expect(vu.simonLevel, 0);
        expect(vu.motFinal, isNotEmpty);
        m.dispose();
      });
    });

    testWidgets('la salle voit que la partie est finie, pas juste un niveau',
        (tester) async {
      // L'écran montrait le même « NIVEAU ATTEINT » qu'en pleine partie :
      // rien ne disait que c'était fini, et le mot de la fin ne sortait
      // jamais. Une partie arrêtée par l'animateur se voyait donc comme une
      // partie en cours.
      final materiel2 = _Materiel();
      final m = MoteurSimon(ble: materiel2, hasard: Random(1));
      m.demarrer();
      m.abandonner();

      final vu = PopoutSnapshot.duSimon(
        m,
        teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
        logoPath: null,
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: PopoutContent(snapshot: vu))));

      expect(find.text('FIN DE PARTIE'), findsOneWidget);
      expect(find.text(m.motFinal), findsOneWidget);
      // Jeu collaboratif : « AUCUN VAINQUEUR » serait faux, personne n'en
      // cherchait un.
      expect(find.text('AUCUN VAINQUEUR'), findsNothing);
      m.dispose();
    });

    test('le mode inverse se distingue du mode normal à l\'écran', () {
      fakeAsync((horloge) {
        final normal = creer()..demarrer();
        final envers = creer(envers: true)..demarrer();
        expect(
          PopoutSnapshot.duSimon(normal,
                  teamNames: const ['R', 'B', 'J', 'V'], logoPath: null)
              .gameMode,
          5,
        );
        expect(
          PopoutSnapshot.duSimon(envers,
                  teamNames: const ['R', 'B', 'J', 'V'], logoPath: null)
              .gameMode,
          6,
        );
        normal.dispose();
        envers.dispose();
      });
    });
  });
}
