import 'package:flutter/material.dart';

import 'tokens.dart';

// Les trois boutons du design system (btn-primary / btn-secondary / ghost,
// design_handoff_buzzer_console/README.md). Ils vivaient en privé dans
// question_flow.dart ; la console du moteur de jeu en a besoin des mêmes, et
// une deuxième copie aurait divergé au premier ajustement de style.
//
// Aucun coin arrondi, aucune ombre : c'est la règle du Broadsheet.

// [grand] : les boutons de CONDUITE de partie. L'animateur est debout, il
// anime une salle et jette un oeil a l'ecran entre deux phrases. Des boutons
// de la taille d'un formulaire l'obligent a viser, et se tromper entre
// « bonne » et « mauvaise reponse » se paie devant tout le monde.
//
// Volontairement reserve aux gestes frequents du jeu. Terminer la partie ou
// corriger restent petits et a l'ecart : rares, et l'un des deux se regrette.
class BSPrimaryButton extends StatelessWidget {
  const BSPrimaryButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.grand = false});
  final String label;
  final VoidCallback? onPressed;
  final bool grand;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: BSColors.accent,
        foregroundColor: BSColors.bg,
        disabledBackgroundColor: BSColors.neutral300,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: EdgeInsets.symmetric(
            horizontal: grand ? 40 : 20, vertical: grand ? 26 : 14),
      ),
      child: Text(label,
          style: BSType.body(size: grand ? 21 : 15, color: BSColors.bg)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class BSSecondaryButton extends StatelessWidget {
  const BSSecondaryButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.grand = false,
      this.teinte});
  final String label;
  final VoidCallback? onPressed;
  final bool grand;
  /// Couleur du texte et du filet. Sert a rendre « mauvaise reponse »
  /// impossible a confondre avec « bonne reponse » : la difference se voit
  /// a la couleur, pas seulement au mot.
  final Color? teinte;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: teinte ?? BSColors.text,
        side: BorderSide(
            color: teinte ?? BSColors.divider, width: grand ? 2 : 1),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: EdgeInsets.symmetric(
            horizontal: grand ? 40 : 20, vertical: grand ? 26 : 14),
      ),
      child: Text(label,
          style: BSType.body(size: grand ? 21 : 15, color: teinte ?? BSColors.text)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class BSGhostButton extends StatelessWidget {
  const BSGhostButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
      child: Text(label,
          style: BSType.body(size: 15, color: BSColors.accent700)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }
}
