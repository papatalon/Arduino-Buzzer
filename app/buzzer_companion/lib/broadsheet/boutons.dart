import 'package:flutter/material.dart';

import 'tokens.dart';

// Les trois boutons du design system (btn-primary / btn-secondary / ghost,
// design_handoff_buzzer_console/README.md). Ils vivaient en privé dans
// question_flow.dart ; la console du moteur de jeu en a besoin des mêmes, et
// une deuxième copie aurait divergé au premier ajustement de style.
//
// Aucun coin arrondi, aucune ombre : c'est la règle du Broadsheet.

class BSPrimaryButton extends StatelessWidget {
  const BSPrimaryButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: BSColors.accent,
        foregroundColor: BSColors.bg,
        disabledBackgroundColor: BSColors.neutral300,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: Text(label,
          style: BSType.body(size: 15, color: BSColors.bg).copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class BSSecondaryButton extends StatelessWidget {
  const BSSecondaryButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: BSColors.text,
        side: const BorderSide(color: BSColors.divider),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: Text(label,
          style: BSType.body(size: 15, color: BSColors.text).copyWith(fontWeight: FontWeight.w600)),
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
