import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/popout/popout_content.dart';
import 'package:buzzer_companion/popout/popout_snapshot.dart';
import 'package:buzzer_companion/protocol.dart';

// LE CHOIX DES SONS SE PASSE DEVANT LA SALLE, PAS DERRIERE.
//
// Le melange animé et la grille de selection vivaient entierement sur la
// console : les joueurs regardaient l'animateur cliquer, puis un son sortait.
// Ces tests rendent l'ecran public pour de vrai, parce qu'une zone qui ne
// s'affiche pas ne se voit d'aucune autre facon qu'a l'usage, devant tout le
// monde.

PopoutSnapshot _auRepos({required VueDesSons vue}) => PopoutSnapshot(
      scores: const [0, 0, 0, 0],
      present: const [true, true, true, true],
      flowState: QuestionFlowState.none,
      teamNames: const ['Les Bleuets', 'Bleu', 'Jaune', 'Vert'],
      vueSons: vue,
    );

void main() {
  Future<void> rendre(WidgetTester tester, PopoutSnapshot snap) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: FittedBox(child: PopoutContent(snapshot: snap))),
      ),
    ));
  }

  group('Le melange', () {
    testWidgets('la salle voit la roue tourner, pas le plan d\'attente',
        (tester) async {
      await rendre(
        tester,
        _auRepos(
          vue: const VueDesSons(
            melange: true,
            melangeAllume: 2,
            melangeNoms: ['air-horn', 'burp', 'tada', 'r2d2'],
          ),
        ),
      );
      expect(find.text('MÉLANGE DES SONS'), findsOneWidget);
      expect(find.text("LE JEU S'EN VIENT"), findsNothing);
      // Les quatre noms qui defilent, y compris ceux des rangees estompees :
      // c'est le defilement simultane qui donne l'effet machine a sous.
      expect(find.text('tada'), findsOneWidget);
      expect(find.text('air-horn'), findsOneWidget);
    });

    testWidgets('un buzzer absent ne prend pas de place dans la roue',
        (tester) async {
      await rendre(
        tester,
        PopoutSnapshot(
          scores: const [0, 0, 0, 0],
          present: const [true, false, true, false],
          flowState: QuestionFlowState.none,
          vueSons: const VueDesSons(
            melange: true,
            melangeAllume: 0,
            melangeNoms: ['air-horn', 'burp', 'tada', 'r2d2'],
          ),
        ),
      );
      expect(find.text('air-horn'), findsOneWidget);
      expect(find.text('burp'), findsNothing);
    });

    // La roue s'arrete, les sons sont retires, et il faut quelques secondes
    // pour lire le resultat. Sans cette pause, l'ecran repasserait a
    // l'attente au moment precis ou il y a enfin quelque chose a lire.
    testWidgets('la revelation nomme les sons tires', (tester) async {
      await rendre(
        tester,
        _auRepos(
          vue: const VueDesSons(
            revelation: true,
            melangeNoms: ['air-horn', 'burp', 'tada', 'r2d2'],
          ),
        ),
      );
      expect(find.text('VOICI VOS SONS'), findsOneWidget);
      expect(find.text('MÉLANGE DES SONS'), findsNothing);
      expect(find.text('r2d2'), findsOneWidget);
    });
  });

  group('La grille', () {
    const sons = ['air-horn', 'burp', 'tada', 'r2d2', 'goat'];

    testWidgets('elle dit pour QUI on choisit, et ce qui est retenu',
        (tester) async {
      await rendre(
        tester,
        _auRepos(
          vue: const VueDesSons(
            grilleBuzzer: 0,
            grilleSons: sons,
            grilleAssignation: [2, 1, 3, 0],
          ),
        ),
      );
      // Le nom d'equipe, pas la couleur, quand l'animateur en a saisi un.
      expect(find.text('LES BLEUETS'), findsOneWidget);
      expect(find.text('·  CHOISIS TON SON'), findsOneWidget);
      // Numerotation 1-based, la meme que sur la console : c'est le numero
      // qu'on se dit a voix haute d'un bout a l'autre de la salle.
      expect(find.text('PRÉSENTEMENT : 3 · tada'), findsOneWidget);
      expect(find.text('goat'), findsOneWidget);
    });

    testWidgets('fermee, elle rend l\'ecran a son plan d\'attente',
        (tester) async {
      await rendre(tester, _auRepos(vue: VueDesSons.aucune));
      expect(find.text("LE JEU S'EN VIENT"), findsOneWidget);
      expect(find.textContaining('CHOISIS TON SON'), findsNothing);
    });
  });

  group('Le transport jusqu\'a la fenetre', () {
    test('tout ce qui se voit survit a l\'aller-retour', () {
      const vue = VueDesSons(
        melange: true,
        melangeAllume: 1,
        melangeNoms: ['a', 'b', 'c', 'd'],
        grilleBuzzer: 3,
        grilleSons: ['un', 'deux'],
        grilleAssignation: [1, 0, 1, 0],
      );
      final refait = PopoutSnapshot.decode(
        _auRepos(vue: vue).encode(),
      ).vueSons;
      expect(refait.melange, isTrue);
      expect(refait.melangeAllume, 1);
      expect(refait.melangeNoms, ['a', 'b', 'c', 'd']);
      expect(refait.grilleBuzzer, 3);
      expect(refait.grilleSons, ['un', 'deux']);
      expect(refait.grilleAssignation, [1, 0, 1, 0]);
    });

    // Une trentaine de noms a chaque instantane, y compris pendant une
    // partie ou personne ne regarde la grille, ne servirait qu'a grossir un
    // message qui passe par un canal BLE-adjacent a chaque pas de la roue.
    test('la liste des sons ne part pas quand la grille est fermee', () {
      const vue = VueDesSons(grilleSons: ['un', 'deux', 'trois']);
      final refait = PopoutSnapshot.decode(_auRepos(vue: vue).encode()).vueSons;
      expect(refait.grilleSons, isEmpty);
    });

    test('un instantane d\'avant la fonction se decode sans rien montrer', () {
      // Le champ absent (aucune cle « vueSons ») ne doit pas faire lever :
      // les deux fenetres sont relancees separement pendant une soiree.
      final refait = VueDesSons.decode(null);
      expect(refait.quelqueChose, isFalse);
    });
  });
}
