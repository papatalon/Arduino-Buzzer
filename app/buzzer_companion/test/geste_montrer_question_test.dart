import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/jeu/geste_montrer_question.dart';

// Espace montre la question, puis plus rien. Le risque est qu'elle serve
// aussi à presser le bouton qui a le focus : « Personne ne trouve » dans
// la foulée, devant la salle.
void main() {
  KeyEvent bas(LogicalKeyboardKey touche) => KeyDownEvent(
        physicalKey: touche == LogicalKeyboardKey.space
            ? PhysicalKeyboardKey.space
            : PhysicalKeyboardKey.arrowRight,
        logicalKey: touche,
        timeStamp: Duration.zero,
      );

  KeyEvent repete(LogicalKeyboardKey touche) => KeyRepeatEvent(
        physicalKey: touche == LogicalKeyboardKey.space
            ? PhysicalKeyboardKey.space
            : PhysicalKeyboardKey.arrowRight,
        logicalKey: touche,
        timeStamp: Duration.zero,
      );

  KeyEvent haut(LogicalKeyboardKey touche) => KeyUpEvent(
        physicalKey: touche == LogicalKeyboardKey.space
            ? PhysicalKeyboardKey.space
            : PhysicalKeyboardKey.arrowRight,
        logicalKey: touche,
        timeStamp: Duration.zero,
      );

  test('espace montre la question une fois, et la suite est avalée', () {
    final geste = GesteMontrerQuestion();
    var fois = 0;

    expect(
      geste.traiter(bas(LogicalKeyboardKey.space),
          questionRetenue: true, dansUnChamp: false, montrer: () => fois++),
      KeyEventResult.handled,
    );
    expect(fois, 1);

    // La question est montrée : le bouton a disparu, mais la touche est
    // encore enfoncée. Elle ne doit plus rien déclencher.
    expect(
      geste.traiter(repete(LogicalKeyboardKey.space),
          questionRetenue: false, dansUnChamp: false, montrer: () => fois++),
      KeyEventResult.handled,
    );
    expect(
      geste.traiter(haut(LogicalKeyboardKey.space),
          questionRetenue: false, dansUnChamp: false, montrer: () => fois++),
      KeyEventResult.handled,
    );
    expect(fois, 1);
  });

  test('les deux chemins du clavier ne montrent la question qu\'une fois', () {
    // HardwareKeyboard puis le focus reçoivent le même appui.
    final geste = GesteMontrerQuestion();
    final appui = bas(LogicalKeyboardKey.space);
    var fois = 0;
    geste.traiter(appui,
        questionRetenue: true, dansUnChamp: false, montrer: () => fois++);
    geste.traiter(appui,
        questionRetenue: false, dansUnChamp: false, montrer: () => fois++);
    expect(fois, 1);
  });

  test('hors lecture, espace reste au bouton qui a le focus', () {
    final geste = GesteMontrerQuestion();
    var fois = 0;
    expect(
      geste.traiter(bas(LogicalKeyboardKey.space),
          questionRetenue: false, dansUnChamp: false, montrer: () => fois++),
      KeyEventResult.ignored,
    );
    expect(fois, 0);
  });

  test('dans un champ de texte, espace s\'écrit', () {
    final geste = GesteMontrerQuestion();
    var fois = 0;
    expect(
      geste.traiter(bas(LogicalKeyboardKey.space),
          questionRetenue: true, dansUnChamp: true, montrer: () => fois++),
      KeyEventResult.ignored,
    );
    expect(fois, 0);
  });

  test('la flèche droite montre aussi, une entrée ne fait rien', () {
    final geste = GesteMontrerQuestion();
    var fois = 0;
    expect(
      geste.traiter(bas(LogicalKeyboardKey.arrowRight),
          questionRetenue: true, dansUnChamp: false, montrer: () => fois++),
      KeyEventResult.handled,
    );
    expect(
      geste.traiter(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
            timeStamp: Duration.zero,
          ),
          questionRetenue: true,
          dansUnChamp: false,
          montrer: () => fois++),
      KeyEventResult.ignored,
    );
    expect(fois, 1);
  });
}
