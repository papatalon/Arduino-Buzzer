import 'dart:async';

import 'package:flutter/material.dart';

import '../ble_link_service.dart';
import '../popout/popout_launcher.dart';
import '../protocol.dart';
import 'phosphor_duotone.dart';
import 'question_flow.dart';
import 'right_rail.dart';
import 'tokens.dart';

enum ConsoleSection { partie, jeuActif, buzzers, questions, appareil }

const _sectionLabels = {
  ConsoleSection.partie: 'Partie',
  ConsoleSection.jeuActif: 'Jeu actif',
  ConsoleSection.buzzers: 'Buzzers',
  ConsoleSection.questions: 'Questions',
  ConsoleSection.appareil: 'Appareil',
};

// Châssis invariant de la console (design_handoff_buzzer_console/README.md,
// "Le châssis de la console (invariant)") : barre latérale, rail de
// dateline, colonne centrale, rail droit. Ce châssis ne bouge jamais d'un
// état à l'autre — seule la colonne centrale change de contenu selon la
// section active et, plus tard, la phase du jeu.
class ConsoleShell extends StatefulWidget {
  const ConsoleShell({
    super.key,
    required this.ble,
    required this.game,
    required this.popout,
  });

  final BleLinkService ble;
  final GameState game;
  final PopoutLauncher popout;

  @override
  State<ConsoleShell> createState() => _ConsoleShellState();
}

class _ConsoleShellState extends State<ConsoleShell> {
  ConsoleSection _section = ConsoleSection.partie;
  late String _clock;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clock = _formatClock(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _clock = _formatClock(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _formatClock(DateTime now) =>
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BSColors.bg,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              ble: widget.ble,
              selected: _section,
              onSelect: (s) => setState(() => _section = s),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(34, 26, 34, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(height: 5, color: BSColors.text),
                    _DatelineRail(game: widget.game, clock: _clock),
                    Container(height: 1, color: BSColors.text),
                    const SizedBox(height: 30),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _CenterColumn(section: _section, game: widget.game)),
                          const SizedBox(width: 44),
                          DecoratedBox(
                            decoration: const BoxDecoration(
                              border: Border(left: BorderSide(color: BSColors.divider)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: RightRail(game: widget.game, popout: widget.popout),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.ble, required this.selected, required this.onSelect});

  final BleLinkService ble;
  final ConsoleSection selected;
  final ValueChanged<ConsoleSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 196,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 26, 0, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(fontFamily: 'Source Serif 4', fontWeight: FontWeight.w600, fontSize: 22, height: 1),
                children: [
                  const TextSpan(text: 'Buzzer', style: TextStyle(color: BSColors.text)),
                  const TextSpan(text: '.', style: TextStyle(color: BSColors.accent2)),
                ],
              ),
            ),
            const SizedBox(height: BSSpace.s6),
            Text('ÉCRANS', style: BSType.sectionKicker()),
            const SizedBox(height: BSSpace.s2),
            for (final section in ConsoleSection.values)
              _NavEntry(
                label: _sectionLabels[section]!,
                active: section == selected,
                onTap: () => onSelect(section),
              ),
            const Spacer(),
            ListenableBuilder(
              listenable: ble,
              builder: (context, _) {
                final connected = ble.connectedDeviceId != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PhosphorDuotone(
                          connected ? PhosphorGlyphs.bluetoothConnected : PhosphorGlyphs.bluetooth,
                          size: 16,
                          color: connected ? BSColors.accent700 : BSColors.neutral500,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            connected ? (ble.connectedDeviceName ?? ble.connectedDeviceId!) : 'Non connecté',
                            style: BSType.body(size: 14, color: BSColors.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(ble.status, style: BSType.body(size: 14, color: BSColors.neutral600)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavEntry extends StatelessWidget {
  const _NavEntry({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            if (active)
              Container(width: 4, height: 18, color: BSColors.accent)
            else
              const SizedBox(width: 0),
            SizedBox(width: active ? 9 : 13),
            Text(
              label,
              style: BSType.body(
                size: 18,
                color: active ? BSColors.text : BSColors.neutral700,
              ).copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatelineRail extends StatelessWidget {
  const _DatelineRail({required this.game, required this.clock});

  final GameState game;
  final String clock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text("CONSOLE DE L'ANIMATEUR", style: BSType.datelineRail()),
          const Spacer(),
          Text(gameModeName(game.gameMode).toUpperCase(), style: BSType.datelineRail()),
          const SizedBox(width: 26),
          Text(clock, style: BSType.datelineRail(color: BSColors.text)),
        ],
      ),
    );
  }
}

class _CenterColumn extends StatelessWidget {
  const _CenterColumn({required this.section, required this.game});

  final ConsoleSection section;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    if (section != ConsoleSection.partie) {
      return Center(
        child: Text(
          '${_sectionLabels[section]} — à construire (étape 5)',
          style: BSType.body(size: 16, color: BSColors.neutral600),
        ),
      );
    }
    if (game.questionFlowState != QuestionFlowState.none) {
      return Align(
        alignment: Alignment.topLeft,
        child: QuestionFlowView(game: game),
      );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(phaseLabel(game.phase), style: BSType.questionConsole()),
          const SizedBox(height: BSSpace.s2),
          Text(gameModeName(game.gameMode), style: BSType.body(size: 17, color: BSColors.neutral700)),
          const SizedBox(height: BSSpace.s6),
          Text(
            "En attente d'une question — les écrans de jeu spécifiques "
            "(Simon, Vol, Duel...) arrivent en étape suivante.",
            style: BSType.body(size: 15, color: BSColors.neutral600),
          ),
        ],
      ),
    );
  }
}
