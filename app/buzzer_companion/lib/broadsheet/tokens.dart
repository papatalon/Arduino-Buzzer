import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// Tokens du design system Broadsheet, recopiés depuis
// design_handoff_buzzer_console/_ds/broadsheet-.../styles.css (source de
// vérité). Ne pas inventer de valeurs ici : si un token manque, retourner
// lire styles.css plutôt que d'approximer.
class BSColors {
  BSColors._();

  static const bg = Color(0xFFF3F2F2);
  static const surface = Color(0xFFEAE9E9);
  static const text = Color(0xFF201E1D);
  static const accent = Color(0xFF0088B0);
  static const accent2 = Color(0xFFD6006C);

  // color-mix(in srgb, #201e1d 16%, transparent)
  static const divider = Color.fromRGBO(0x20, 0x1E, 0x1D, 0.16);

  static const neutral100 = Color(0xFFF8F4F4);
  static const neutral200 = Color(0xFFEAE7E7);
  static const neutral300 = Color(0xFFD7D3D3);
  static const neutral400 = Color(0xFFBAB6B6);
  static const neutral500 = Color(0xFF9B9797);
  static const neutral600 = Color(0xFF7D7979);
  static const neutral700 = Color(0xFF605D5D);
  static const neutral800 = Color(0xFF444141);
  static const neutral900 = Color(0xFF2D2B2B);

  static const accent100 = Color(0xFFE9F8FF);
  static const accent200 = Color(0xFFCBEEFF);
  static const accent300 = Color(0xFF99E0FF);
  static const accent400 = Color(0xFF62C5EE);
  static const accent500 = Color(0xFF38A6CF);
  static const accent600 = Color(0xFF1186AC);
  static const accent700 = Color(0xFF006786);
  static const accent800 = Color(0xFF004961);
  static const accent900 = Color(0xFF0A303E);

  static const accent2_100 = Color(0xFFFFF1F4);
  static const accent2_200 = Color(0xFFFFDEE6);
  static const accent2_300 = Color(0xFFFFC0D0);
  static const accent2_400 = Color(0xFFFF90B1);
  static const accent2_500 = Color(0xFFFF458E);
  static const accent2_600 = Color(0xFFD82071);
  static const accent2_700 = Color(0xFFAA0B56);
  static const accent2_800 = Color(0xFF790E3D);
  static const accent2_900 = Color(0xFF4B1528);
}

class BSSpace {
  BSSpace._();
  static const s1 = 5.0;
  static const s2 = 10.0;
  static const s3 = 15.0;
  static const s4 = 20.0;
  static const s6 = 30.0;
  static const s8 = 40.0;
}

const _serifFamily = 'Source Serif 4';

// Source Serif 4 est une police variable avec un axe optique (opsz, 8-144) :
// dans un navigateur, `font-optical-sizing: auto` (comportement par défaut
// du CSS) l'ajuste en continu selon la taille du texte — gros titres plus
// contrastés, petit texte plus robuste. Flutter n'a pas d'équivalent
// automatique : sans le fixer nous-mêmes via FontVariation, tout le texte
// utilise la même instance par défaut et perd ce contraste attendu par la
// maquette (visible surtout sur les gros chiffres/titres).
TextStyle _serif({
  required double size,
  required FontWeight weight,
  double? height,
  double? letterSpacing,
  Color? color,
  FontStyle style = FontStyle.normal,
}) =>
    TextStyle(
      fontFamily: _serifFamily,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color ?? BSColors.text,
      fontStyle: style,
      fontVariations: [ui.FontVariation('opsz', size.clamp(8.0, 144.0))],
    );

// Échelle typographique du README (design_handoff_buzzer_console/README.md,
// section "Typographie"). Un seul nom par rôle utilisé dans la maquette.
class BSType {
  BSType._();

  static TextStyle sectionKicker({Color color = BSColors.neutral600}) => _serif(
        size: 12,
        weight: FontWeight.w600,
        height: 1,
        letterSpacing: 0.16 * 12,
        color: color,
      );

  static TextStyle datelineRail({Color? color}) => _serif(
        size: 12,
        weight: FontWeight.w600,
        height: 1,
        letterSpacing: 0.15 * 12,
        color: color ?? BSColors.neutral700,
      );

  static TextStyle body({double size = 15, Color? color}) => _serif(
        size: size,
        weight: FontWeight.w400,
        height: 1.4,
        color: color,
      );

  static TextStyle buzzerNameConsole({double size = 21, Color? color}) => _serif(
        size: size,
        weight: FontWeight.w600,
        height: size >= 26 ? 1.0 : 1.1,
        color: color,
      );

  static TextStyle scoreConsole({Color? color}) => _serif(
        size: 40,
        weight: FontWeight.w600,
        height: 1,
        color: color,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle questionConsole({Color? color}) => _serif(
        size: 54,
        weight: FontWeight.w600,
        height: 1.08,
        letterSpacing: -0.02 * 54,
        color: color,
      );

  static TextStyle answerConsole({Color color = BSColors.accent2_700}) => _serif(
        size: 34,
        weight: FontWeight.w400,
        height: 1.2,
        style: FontStyle.italic,
        color: color,
      );

  static TextStyle questionPopout({Color color = Colors.white}) => _serif(
        size: 96,
        weight: FontWeight.w600,
        height: 1.06,
        letterSpacing: -0.025 * 96,
        color: color,
      );

  static TextStyle scorePopout({Color? color}) => _serif(
        size: 74,
        weight: FontWeight.w600,
        height: 0.9,
        color: color,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle buzzerNamePopout({Color? color}) => _serif(
        size: 26,
        weight: FontWeight.w600,
        height: 1,
        letterSpacing: 0.04 * 26,
        color: color,
      );

  // Métadonnées du bandeau de tête du pop-out (jeu actif / progression).
  // Pas de taille donnée explicitement par le README pour ce champ précis,
  // mais la règle du plancher de lisibilité (26px, aucune exception pour du
  // contenu réel) s'applique : on reste nettement au-dessus.
  static TextStyle popoutHeaderMeta({Color? color}) => _serif(
        size: 28,
        weight: FontWeight.w600,
        height: 1,
        letterSpacing: 0.1 * 28,
        color: color ?? BSColors.neutral700,
      );

  static TextStyle heroDigitPopout({double size = 140, Color? color}) => _serif(
        size: size,
        weight: FontWeight.w600,
        height: 1,
        letterSpacing: -0.035 * size,
        color: color,
      );
}
