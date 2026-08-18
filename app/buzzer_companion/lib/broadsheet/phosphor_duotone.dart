import 'package:flutter/material.dart';

// Rendu manuel des icônes Phosphor duotone : le package `phosphor_flutter`
// (2.1.0, dernière version publiée le 2026-08-17) ne compile plus sous
// Flutter 3.47 / Dart 3.13 — `IconData` y est devenu une `final class`, et
// son wrapper `PhosphorIconData extends IconData` casse la build Windows
// ("can't be extended outside of its library"). Faute de correctif publié,
// on vendore juste la police duotone du projet officiel
// (github.com/phosphor-icons/flutter, lib/fonts/Phosphor-Duotone.ttf) et on
// reproduit ici la même logique de rendu que leur widget `PhosphorIcon`
// (voir lib/src/phosphor_icon.dart upstream) : un empilement d'un glyphe
// secondaire à 20% d'opacité sous le glyphe primaire plein.
//
// Les codes restent des littéraux `IconData(0x..., fontFamily: ...)`
// (comme dans le fichier généré par le package d'origine) plutôt que des
// int recalculés à l'exécution : le tree-shaking d'icônes de Flutter
// n'analyse que des invocations littérales et fait échouer le build sinon
// ("Avoid non-constant invocations of IconData").
const _f = 'PhosphorDuotone';

class PhosphorGlyph {
  const PhosphorGlyph(this.primary, this.secondary);
  final IconData primary;
  final IconData secondary;
}

class PhosphorGlyphs {
  PhosphorGlyphs._();

  static const bluetooth = PhosphorGlyph(
    IconData(0xe0db, fontFamily: _f),
    IconData(0xe0da, fontFamily: _f),
  );
  static const bluetoothConnected = PhosphorGlyph(
    IconData(0xe0dd, fontFamily: _f),
    IconData(0xe0dc, fontFamily: _f),
  );
  static const arrowSquareOut = PhosphorGlyph(
    IconData(0xe5df, fontFamily: _f),
    IconData(0xe5de, fontFamily: _f),
  );
  static const checkCircle = PhosphorGlyph(
    IconData(0xe185, fontFamily: _f),
    IconData(0xe184, fontFamily: _f),
  );
  static const xCircle = PhosphorGlyph(
    IconData(0xe4f9, fontFamily: _f),
    IconData(0xe4f8, fontFamily: _f),
  );
  static const check = PhosphorGlyph(
    IconData(0xe183, fontFamily: _f),
    IconData(0xe182, fontFamily: _f),
  );
  static const clock = PhosphorGlyph(
    IconData(0xe19b, fontFamily: _f),
    IconData(0xe19a, fontFamily: _f),
  );
  static const timer = PhosphorGlyph(
    IconData(0xe493, fontFamily: _f),
    IconData(0xe492, fontFamily: _f),
  );
  static const musicNotes = PhosphorGlyph(
    IconData(0xe341, fontFamily: _f),
    IconData(0xe340, fontFamily: _f),
  );
  static const play = PhosphorGlyph(
    IconData(0xe3d1, fontFamily: _f),
    IconData(0xe3d0, fontFamily: _f),
  );
  static const skipForward = PhosphorGlyph(
    IconData(0xe5a7, fontFamily: _f),
    IconData(0xe5a6, fontFamily: _f),
  );
  static const shuffle = PhosphorGlyph(
    IconData(0xe423, fontFamily: _f),
    IconData(0xe422, fontFamily: _f),
  );
  static const lightbulb = PhosphorGlyph(
    IconData(0xe2dd, fontFamily: _f),
    IconData(0xe2dc, fontFamily: _f),
  );
  static const speakerHigh = PhosphorGlyph(
    IconData(0xe44b, fontFamily: _f),
    IconData(0xe44a, fontFamily: _f),
  );
  static const magnifyingGlass = PhosphorGlyph(
    IconData(0xe30d, fontFamily: _f),
    IconData(0xe30c, fontFamily: _f),
  );
  static const plus = PhosphorGlyph(
    IconData(0xe3d5, fontFamily: _f),
    IconData(0xe3d4, fontFamily: _f),
  );
  static const arrowCounterClockwise = PhosphorGlyph(
    IconData(0xe039, fontFamily: _f),
    IconData(0xe038, fontFamily: _f),
  );
  static const arrowRight = PhosphorGlyph(
    IconData(0xe06d, fontFamily: _f),
    IconData(0xe06c, fontFamily: _f),
  );
}

class PhosphorDuotone extends StatelessWidget {
  const PhosphorDuotone(this.glyph, {super.key, this.size = 20, this.color});

  final PhosphorGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? IconTheme.of(context).color;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.20,
          child: Icon(glyph.secondary, size: size, color: resolvedColor),
        ),
        Icon(glyph.primary, size: size, color: resolvedColor),
      ],
    );
  }
}
