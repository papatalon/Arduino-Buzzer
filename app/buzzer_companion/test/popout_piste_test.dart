import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/popout/popout_content.dart';
import 'package:buzzer_companion/popout/popout_snapshot.dart';
import 'package:buzzer_companion/protocol.dart';

// LA MUSIQUE NE DOIT PAS MANGER L'ÉCRAN D'ATTENTE.
//
// Les phrases qui tournent sont ce qui fait sourire la salle entre deux
// parties ; le bandeau de la piste vient en plus, jamais à la place. Et il
// disparaît dès que la musique s'arrête, sinon l'écran annoncerait une
// chanson qui ne joue plus, ce qui arrive exactement au départ d'une partie.

PopoutSnapshot _attente({required PisteEnCours piste}) => PopoutSnapshot(
      scores: const [0, 0, 0, 0],
      present: const [true, true, true, true],
      flowState: QuestionFlowState.none,
      teamNames: const ['Rouge', 'Bleu', 'Jaune', 'Vert'],
      pisteEnCours: piste,
    );

const _piste = PisteEnCours(
  titre: 'Dégénérations',
  artiste: 'Mes Aïeux',
  enLecture: true,
);

Future<void> _rendre(WidgetTester tester, PopoutSnapshot snap) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: FittedBox(child: PopoutContent(snapshot: snap))),
      ),
    ));

void main() {
  testWidgets('la piste s\'affiche sans chasser les phrases d\'attente',
      (tester) async {
    await _rendre(tester, _attente(piste: _piste));

    expect(find.text('EN LECTURE SUR SPOTIFY'), findsOneWidget);
    expect(find.text('Dégénérations'), findsOneWidget);
    expect(find.text('Mes Aïeux'), findsOneWidget);
    // Le chapeau et le pied de page de l'écran d'attente sont toujours là :
    // c'est la preuve que le bandeau s'est ajouté au lieu de remplacer.
    expect(find.text("LE JEU S'EN VIENT"), findsOneWidget);
    expect(find.text('PRÊT'), findsNWidgets(4));
  });

  testWidgets('en pause, le bandeau disparaît', (tester) async {
    await _rendre(
        tester, _attente(piste: _piste.copierAvec(enLecture: false)));

    expect(find.text('EN LECTURE SUR SPOTIFY'), findsNothing);
    expect(find.text('Dégénérations'), findsNothing);
    expect(find.text("LE JEU S'EN VIENT"), findsOneWidget);
  });

  testWidgets('sans musique du tout, rien ne change à l\'écran',
      (tester) async {
    await _rendre(tester, _attente(piste: PisteEnCours.aucune));
    expect(find.text('EN LECTURE SUR SPOTIFY'), findsNothing);
    expect(find.text("LE JEU S'EN VIENT"), findsOneWidget);
  });

  test('la piste survit à l\'aller-retour vers la fenêtre publique', () {
    // La fenêtre du pop-out ne partage pas la mémoire : tout passe par du
    // JSON. Un champ oublié à l'encodage ne se voit qu'ici.
    final retour = PopoutSnapshot.decode(
        _attente(piste: const PisteEnCours(
          titre: 'Un titre',
          artiste: 'Quelqu\'un',
          pochette: r'C:\pochettes\abc.jpg',
          enLecture: true,
        )).encode()).pisteEnCours;

    expect(retour.titre, 'Un titre');
    expect(retour.artiste, "Quelqu'un");
    expect(retour.pochette, r'C:\pochettes\abc.jpg');
    expect(retour.enLecture, isTrue);
  });

  test('un instantané d\'avant la fonction se décode sans rien montrer', () {
    // Le cas d'une console et d'un pop-out qui ne sont pas de la même
    // version : la clé manque, et ça ne doit pas casser l'écran public.
    final refait = PisteEnCours.decode(null);
    expect(refait.quelqueChose, isFalse);
    expect(refait.titre, isEmpty);
  });

  test('un titre sans lecture ne montre rien', () {
    const arretee = PisteEnCours(titre: 'Un titre', enLecture: false);
    expect(arretee.quelqueChose, isFalse);
  });
}
