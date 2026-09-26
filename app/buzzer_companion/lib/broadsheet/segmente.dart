import 'package:flutter/material.dart';

import 'tokens.dart';

// Le contrôle segmenté du design system (`.seg` de styles.css) : un cadre,
// des options séparées par un filet, celle qui est retenue en aplat d'accent.
// Sans coins arrondis, comme tout le reste de la console.
//
// Deux onglets ne méritent pas un TabBar : celui de Material apporte un
// indicateur animé, un défilement et un thème à mater, pour un choix entre
// deux mots.
//
// Partagé depuis qu'un deuxième écran en a eu besoin : deux copies d'un même
// contrôle divergent au premier ajustement de style.
class BSSegmente extends StatelessWidget {
  const BSSegmente({
    super.key,
    required this.options,
    required this.choisi,
    required this.onChoisir,
  });

  final List<String> options;
  final int choisi;
  final ValueChanged<int> onChoisir;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: BSColors.divider)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                color: i == choisi ? BSColors.accent : Colors.transparent,
                border: i == 0
                    ? null
                    : const Border(
                        left: BorderSide(color: BSColors.divider),
                      ),
              ),
              child: InkWell(
                onTap: () => onChoisir(i),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Text(
                    options[i],
                    style: BSType.body(
                      size: 15,
                      color: i == choisi ? BSColors.bg : BSColors.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
