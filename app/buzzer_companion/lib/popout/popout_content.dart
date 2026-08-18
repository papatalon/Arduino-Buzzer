import 'package:flutter/material.dart';

import '../broadsheet/dashed_box.dart';
import '../broadsheet/pulse.dart';
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
                  // Pas de "PROGRESSION" (question X/Y) : aucune télémétrie
                  // réelle pour ça pour l'instant (voir QuestionsScreen).
                  _HeaderMeta(label: 'JEU ACTIF', value: gameModeName(snapshot.gameMode)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(52, 18, 52, 0),
              child: SizedBox(height: 4, child: ColoredBox(color: BSColors.text)),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 80),
                  child: _CenterZone(snapshot: snapshot),
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

// Bloc central pendant une question (design_handoff_buzzer_console/README.md,
// "Le flux d'une question (Chrono pénalité)") — miroir public du contenu
// console (QuestionFlowView), en respectant la confidentialité : la
// réponse n'arrive dans [snapshot] que si elle a déjà été révélée (voir
// PopoutSnapshot.fromGameState), donc rien à filtrer ici.
class _CenterZone extends StatelessWidget {
  const _CenterZone({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return switch (snapshot.flowState) {
      QuestionFlowState.arming => _ArmingZone(snapshot: snapshot),
      QuestionFlowState.buzzed => _BuzzedZone(snapshot: snapshot),
      QuestionFlowState.scored => _ScoredZone(snapshot: snapshot),
      QuestionFlowState.revealed => _RevealedZone(snapshot: snapshot),
      QuestionFlowState.none => Text(
          "En attente d'une question.",
          style: BSType.body(size: 20, color: BSColors.neutral600),
          textAlign: TextAlign.center,
        ),
    };
  }
}

class _ArmingZone extends StatelessWidget {
  const _ArmingZone({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    // La question n'arrive dans l'instantané qu'une fois le chrono lancé
    // (voir PopoutSnapshot.fromGameState) : tant que ce n'est pas le cas,
    // rien à afficher ici sauf l'attente elle-même — le public ne doit pas
    // la voir pendant que l'animateur la lit encore à voix haute.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (snapshot.questionText != null) ...[
          Text(snapshot.questionText!, style: BSType.questionPopout(), textAlign: TextAlign.center),
          const SizedBox(height: BSSpace.s6),
        ],
        Text('CHRONO NON LANCÉ', style: BSType.popoutHeaderMeta(color: BSColors.neutral500)),
        const SizedBox(height: BSSpace.s2),
        Container(width: 400, height: 20, color: BSColors.neutral300),
      ],
    );
  }
}

class _BuzzedZone extends StatelessWidget {
  const _BuzzedZone({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final idx = snapshot.lastBuzz;
    if (idx == null || idx < 0 || idx >= kBuzzerColors.length) return const SizedBox.shrink();
    final color = kBuzzerColors[idx];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pulse(child: Container(width: 88, height: 88, color: color.fill)),
        const SizedBox(height: BSSpace.s4),
        Text('${color.name.toUpperCase()} A BUZZÉ', style: BSType.heroDigitPopout(size: 64, color: color.fill)),
      ],
    );
  }
}

class _ScoredZone extends StatelessWidget {
  const _ScoredZone({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final idx = snapshot.lastBuzz;
    final color = (idx != null && idx >= 0 && idx < kBuzzerColors.length) ? kBuzzerColors[idx] : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color != null)
          Text('${color.name.toUpperCase()} MARQUE', style: BSType.heroDigitPopout(size: 96, color: color.fill)),
        const SizedBox(height: BSSpace.s4),
        if (snapshot.answerText != null)
          Text(snapshot.answerText!, style: BSType.answerPopout(size: 40), textAlign: TextAlign.center),
      ],
    );
  }
}

class _RevealedZone extends StatelessWidget {
  const _RevealedZone({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          snapshot.questionText ?? '',
          style: BSType.body(size: 40, color: BSColors.neutral700).copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: BSSpace.s4),
        Text('LA RÉPONSE ÉTAIT', style: BSType.popoutHeaderMeta(color: BSColors.accent2_700)),
        const SizedBox(height: BSSpace.s2),
        if (snapshot.answerText != null)
          Text(snapshot.answerText!, style: BSType.answerPopout(size: 140), textAlign: TextAlign.center),
        const SizedBox(height: BSSpace.s4),
        Text(
          "PERSONNE N'A TROUVÉ",
          style: BSType.body(size: 32, color: BSColors.neutral700).copyWith(fontWeight: FontWeight.w600),
        ),
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
                          present && i < snapshot.scores.length ? '${snapshot.scores[i]}' : '',
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
