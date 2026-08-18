import 'package:flutter/material.dart';

import '../popout/popout_launcher.dart';
import '../popout/popout_snapshot.dart';
import '../protocol.dart';
import 'phosphor_duotone.dart';
import 'tokens.dart';

// Rail droit (340px) de la console : tableau des buzzers, vignette de
// l'écran public, actions de partie. Voir design_handoff_buzzer_console
// /README.md, section "Rail droit (340 px)".
class RightRail extends StatelessWidget {
  const RightRail({super.key, required this.game, required this.popout});

  final GameState game;
  final PopoutLauncher popout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BuzzerTable(game: game),
          const SizedBox(height: BSSpace.s6),
          _PublicScreenPreview(game: game, popout: popout),
        ],
      ),
    );
  }
}

class _BuzzerTable extends StatelessWidget {
  const _BuzzerTable({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: BSSpace.s3),
          _BuzzerRow(
            color: kBuzzerColors[i],
            present: game.present[i],
            score: game.scores[i],
            soundIndex: game.buzzerSound[i],
          ),
        ],
      ],
    );
  }
}

class _BuzzerRow extends StatelessWidget {
  const _BuzzerRow({
    required this.color,
    required this.present,
    required this.score,
    required this.soundIndex,
  });

  final BuzzerColor color;
  final bool present;
  final int score;
  final int? soundIndex;

  @override
  Widget build(BuildContext context) {
    final status = !present ? 'absent' : (soundIndex != null ? 'son $soundIndex · présent' : 'présent');
    return Opacity(
      opacity: present ? 1 : 0.45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 20, height: 20, color: color.fill),
          const SizedBox(width: BSSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(color.name, style: BSType.buzzerNameConsole(size: 21)),
                Text(status, style: BSType.body(size: 14, color: BSColors.neutral700)),
              ],
            ),
          ),
          Text(present ? '$score' : '—', style: BSType.scoreConsole()),
        ],
      ),
    );
  }
}

class _PublicScreenPreview extends StatelessWidget {
  const _PublicScreenPreview({required this.game, required this.popout});
  final GameState game;
  final PopoutLauncher popout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ÉCRAN PUBLIC', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        ListenableBuilder(
          listenable: popout,
          builder: (context, _) {
            final active = popout.isOpen;
            return SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: active ? popout.close : () => popout.open(PopoutSnapshot.fromGameState(game)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: active ? BSColors.accent700 : BSColors.text,
                  backgroundColor: active ? BSColors.accent100 : null,
                  side: BorderSide(color: active ? BSColors.accent : BSColors.divider, width: active ? 1.5 : 1),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                icon: PhosphorDuotone(
                  active ? PhosphorGlyphs.checkCircle : PhosphorGlyphs.arrowSquareOut,
                  size: 16,
                  color: active ? BSColors.accent700 : BSColors.text,
                ),
                label: Text(
                  active ? 'Écran public actif · réattacher' : 'Détacher · écran 2',
                  style: BSType.body(size: 14, color: active ? BSColors.accent700 : BSColors.text)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
