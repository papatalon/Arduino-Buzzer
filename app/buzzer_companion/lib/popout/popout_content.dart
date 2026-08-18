import 'package:flutter/material.dart';

import '../broadsheet/dashed_box.dart';
import '../broadsheet/tokens.dart';
import '../protocol.dart';
import 'popout_snapshot.dart';

// Contenu visuel du châssis pop-out (design_handoff_buzzer_console/README.md,
// "Le châssis du pop-out (invariant)") : 1440×810, fond clair (jamais sombre
// — le design system n'a aucune surface foncée). Widget partagé entre deux
// usages : plein format dans la vraie deuxième fenêtre, et réduit (FittedBox)
// dans la vignette de contrôle du rail droit — pour que cette vignette
// montre vraiment ce que le public voit, pas un placeholder séparé.
class PopoutContent extends StatelessWidget {
  const PopoutContent({super.key, required this.snapshot});

  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1440,
      height: 810,
      child: ColoredBox(
        color: BSColors.bg,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 30, 52, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const DashedBox(
                    width: 118,
                    height: 44,
                    child: Text('logo soirée', style: TextStyle(fontSize: 13, color: BSColors.neutral600)),
                  ),
                  const Spacer(),
                  _HeaderMeta(label: 'JEU ACTIF', value: gameModeName(snapshot.gameMode)),
                  const SizedBox(width: 52),
                  const _HeaderMeta(label: 'PROGRESSION', value: '—'),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(52, 18, 52, 0),
              child: SizedBox(height: 4, child: ColoredBox(color: BSColors.text)),
            ),
            Expanded(
              child: Center(
                child: Text(
                  "Le contenu (question, chrono, buzz) arrive à l'étape 4.",
                  style: BSType.body(size: 20, color: BSColors.neutral600),
                ),
              ),
            ),
            const SizedBox(height: 4, child: ColoredBox(color: BSColors.text)),
            _Scoreboard(snapshot: snapshot),
          ],
        ),
      ),
    );
  }
}

class _HeaderMeta extends StatelessWidget {
  const _HeaderMeta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
        Text(value.toUpperCase(), style: BSType.popoutHeaderMeta(color: BSColors.text)),
      ],
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Row(
        children: List.generate(4, (i) {
          final color = kBuzzerColors[i];
          final present = i < snapshot.present.length && snapshot.present[i];
          final flashed = snapshot.lastBuzz == i;
          return Expanded(
            child: Container(
              color: flashed ? BSColors.accent100 : null,
              padding: EdgeInsets.only(
                left: i == 0 ? 52 : 28,
                top: 18,
              ),
              child: Opacity(
                opacity: present ? 1 : 0.4,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 22, height: 22, margin: const EdgeInsets.only(top: 6), color: color.fill),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(color.name.toUpperCase(), style: BSType.buzzerNamePopout()),
                        Text(
                          present && i < snapshot.scores.length ? '${snapshot.scores[i]}' : '—',
                          style: BSType.scorePopout(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
