import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// LA TOUCHE QUI MONTRE LA QUESTION, et rien d'autre.
//
// Espace est le geste naturel. Flèche droite et Page suivante restent, ce
// sont celles d'une télécommande. Les trois font la même chose, et seulement
// pendant que le bouton « Montrer la question » est à l'écran.
//
// Espace est avalée jusqu'au relâchement. Flutter s'en sert aussi pour
// presser le bouton qui a le focus : sans ça, tenir la touche montrerait la
// question puis enchaînerait sur « Personne ne trouve ».
class GesteMontrerQuestion {
  bool _espaceTenue = false;

  KeyEventResult traiter(
    KeyEvent evenement, {
    required bool questionRetenue,
    required bool dansUnChamp,
    required void Function() montrer,
  }) {
    final touche = evenement.logicalKey;
    final espace = touche == LogicalKeyboardKey.space;
    final presentation = touche == LogicalKeyboardKey.arrowRight ||
        touche == LogicalKeyboardKey.pageDown;

    if (evenement is KeyUpEvent) {
      if (!espace) return KeyEventResult.ignored;
      final tenait = _espaceTenue;
      _espaceTenue = false;
      return tenait ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (evenement is! KeyDownEvent && evenement is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (dansUnChamp) return KeyEventResult.ignored;

    // La répétition de l'espace qui vient de montrer la question.
    if (espace && _espaceTenue) return KeyEventResult.handled;

    if (!questionRetenue || evenement is KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!espace && !presentation) return KeyEventResult.ignored;

    montrer();
    if (espace) _espaceTenue = true;
    return KeyEventResult.handled;
  }
}
