import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/sound_engine.dart';
import '../ble_link_service.dart';
import '../event_logo.dart';
import '../popout/popout_launcher.dart';
import '../questionnaires/questionnaire_store.dart';
import '../team_names.dart';
import '../protocol.dart';
import 'game_rules_panel.dart';
import 'game_setup_view.dart';
import 'phosphor_duotone.dart';
import 'question_flow.dart';
import 'right_rail.dart';
import 'screens/buzzers_screen.dart';
import 'screens/device_screen.dart';
import 'screens/game_choice_screen.dart';
import 'screens/questions_screen.dart';
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
    required this.sound,
    required this.teams,
    required this.logo,
    required this.questionnaires,
  });

  final BleLinkService ble;
  final GameState game;
  final PopoutLauncher popout;
  final SoundEngine sound;
  final TeamNames teams;
  final EventLogo logo;
  final QuestionnaireStore questionnaires;

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
        // Sans ce ListenableBuilder, le rail de dateline, la colonne centrale
        // et le tableau des scores ne se reconstruisent jamais tout seuls
        // quand `game`/`ble` changent (seuls les deux ListenableBuilder
        // ponctuels — statut BLE de la barre latérale, bouton de l'écran
        // public — écoutaient quoi que ce soit) : ils ne rafraîchissaient
        // qu'au hasard d'un rebuild déclenché ailleurs (le tic d'horloge
        // toutes les 30s, un clic de nav), ce qui ressemblait à des lenteurs
        // BLE alors que la donnée était déjà arrivée depuis longtemps.
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.ble, widget.game]),
          builder: (context, _) {
            return Row(
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
                              Expanded(
                                child: _CenterColumn(
                                  section: _section,
                                  game: widget.game,
                                  ble: widget.ble,
                                  sound: widget.sound,
                                  teams: widget.teams,
                                  logo: widget.logo,
                                  questionnaires: widget.questionnaires,
                                  onNavigate: (s) => setState(() => _section = s),
                                ),
                              ),
                              // Le rail droit fait partie du châssis pendant
                              // qu'on anime : il surveille les buzzers et
                              // l'écran public. Écrire un questionnaire est
                              // un tout autre travail, qui se fait souvent
                              // buzzer débranché et longtemps avant la
                              // soirée : la table des buzzers n'y sert à
                              // rien et vole 380 px à la saisie.
                              if (_section != ConsoleSection.questions) ...[
                                const SizedBox(width: 44),
                                DecoratedBox(
                                  decoration: const BoxDecoration(
                                    border: Border(left: BorderSide(color: BSColors.divider)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 32),
                                    child: RightRail(
                                      game: widget.game,
                                      popout: widget.popout,
                                      teams: widget.teams,
                                      logo: widget.logo,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
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
          Text(gameModeName(game.displayGameMode).toUpperCase(), style: BSType.datelineRail()),
          const SizedBox(width: 26),
          Text(clock, style: BSType.datelineRail(color: BSColors.text)),
        ],
      ),
    );
  }
}

class _CenterColumn extends StatelessWidget {
  const _CenterColumn({
    required this.section,
    required this.game,
    required this.ble,
    required this.sound,
    required this.teams,
    required this.logo,
    required this.questionnaires,
    required this.onNavigate,
  });

  final SoundEngine sound;
  final TeamNames teams;
  final EventLogo logo;
  final QuestionnaireStore questionnaires;

  final ConsoleSection section;
  final GameState game;
  final BleLinkService ble;
  final ValueChanged<ConsoleSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case ConsoleSection.buzzers:
        return BuzzersScreen(game: game, sound: sound, ble: ble, teams: teams);
      case ConsoleSection.jeuActif:
        return GameChoiceScreen(
          game: game,
          ble: ble,
          // Une fois le jeu choisi, il n'y a plus rien à faire sur cet écran
          // - retour direct sur "Partie" pour enchaîner sur la partie.
          onGameSelected: () => onNavigate(ConsoleSection.partie),
        );
      case ConsoleSection.questions:
        return QuestionsScreen(store: questionnaires);
      case ConsoleSection.appareil:
        return DeviceScreen(ble: ble, game: game, logo: logo);
      case ConsoleSection.partie:
        break;
    }
    // Le buzzer n'a pas encore dit où il atterrit : on ne devine pas. Une
    // ligne calme le temps de l'aller-retour vaut mieux qu'un écran de
    // lancement complet qui disparaît aussitôt.
    if (game.awaitingSelection) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Envoi au buzzer...',
          style: BSType.body(size: 20, color: BSColors.neutral600),
        ),
      );
    }
    if (isGameSetupPhase(game.phase)) {
      return GameSetupView(game: game, ble: ble);
    }
    if (isEndConfirmPhase(game.phase)) {
      return EndConfirmView(ble: ble);
    }
    if (isEndGamePhase(game.phase)) {
      return EndGameView(game: game, ble: ble, teams: teams);
    }
    if (game.questionFlowState != QuestionFlowState.none) {
      return Align(
        alignment: Alignment.topLeft,
        child: QuestionFlowView(game: game, ble: ble, teams: teams),
      );
    }
    // Les jeux non-quiz n'ont pas de question : sans cette branche, la
    // console tombait sur le repli générique et n'annonçait qu'un nom de
    // phase brut pendant toute une partie de Réflexe ou de Simon.
    final layout = layoutFor(game.gameMode);
    if (layout != GameLayout.quiz && isGameRunning(game.phase)) {
      // Défilable : progression, scores et boutons de conduite ne tiennent
      // pas toujours dans la hauteur d'une fenêtre réduite.
      return SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: _GameProgressView(game: game, teams: teams, layout: layout, ble: ble),
        ),
      );
    }
    final label = phaseLabel(game.phase);
    final mode = gameModeName(game.displayGameMode);
    return SingleChildScrollView(
      child: Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.isNotEmpty ? label : 'En attente de données du buzzer',
            style: BSType.questionConsole(),
          ),
          const SizedBox(height: BSSpace.s2),
          Text(
            mode.isNotEmpty ? mode : 'Aucun jeu choisi',
            style: BSType.body(size: 17, color: BSColors.neutral700),
          ),
          // Proposer « Lancer la partie » sans jeu choisi serait trompeur :
          // le Mega démarrerait celui qu'il garde en mémoire, pas celui que
          // l'opérateur croit lancer. On l'oriente d'abord vers le choix.
          if (isAtConfigurationMenu(game.phase)) ...[
            const SizedBox(height: BSSpace.s4),
            if (mode.isEmpty)
              OutlinedButton(
                onPressed: () => onNavigate(ConsoleSection.jeuActif),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BSColors.text,
                  side: const BorderSide(color: BSColors.divider),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text('Choisir un jeu'),
              )
            else
              _LaunchButton(game: game, ble: ble, onNavigate: onNavigate),
          ],
          // Le moment où l'animateur explique le jeu à la salle et refait
          // entendre les sons est le même : juste avant de lancer. Les deux
          // vivent donc ici, entre le choix du jeu et le départ.
          if (isAtConfigurationMenu(game.phase) && mode.isNotEmpty) ...[
            const SizedBox(height: BSSpace.s6),
            Container(height: 1, color: BSColors.divider),
            const SizedBox(height: BSSpace.s4),
            _SoundRecallButton(game: game, sound: sound, teams: teams),
            const SizedBox(height: BSSpace.s6),
            GameRulesPanel(gameMode: game.displayGameMode),
          ],
        ],
      ),
      ),
    );
  }
}

// Suivi d'un jeu non-quiz dans la console. Même règle que l'écran public :
// les points montrés sont ceux du jeu en cours, et Simon n'en a aucun.
class _GameProgressView extends StatelessWidget {
  const _GameProgressView({
    required this.game,
    required this.teams,
    required this.layout,
    required this.ble,
  });

  final GameState game;
  final TeamNames teams;
  final GameLayout layout;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(gameModeName(game.displayGameMode), style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        Text(phaseLabel(game.phase), style: BSType.body(size: 15, color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s6),
        if (layout == GameLayout.simon) ..._simon() else ..._manches(),
        const SizedBox(height: BSSpace.s6),
        _GameControls(game: game, ble: ble),
      ],
    );
  }

  List<Widget> _simon() {
    final done = game.simonLevel;
    if (done == null) {
      return [Text("En attente du buzzer", style: BSType.body(size: 17, color: BSColors.neutral700))];
    }
    // [simonLevel] compte les niveaux réussis : celui qui se joue est le
    // suivant, comme sur l'écran du buzzer.
    final shown = game.gameFinished ? done : done + 1;
    final length = game.simonLength ?? 0;
    return [
      Text(game.gameFinished ? 'NIVEAU ATTEINT' : 'NIVEAU', style: BSType.sectionKicker()),
      Text('$shown', style: BSType.scoreConsole(color: BSColors.accent).copyWith(fontSize: 64)),
      if (!game.gameFinished && length > 0)
        Text('${game.simonEntered ?? 0} / $length', style: BSType.body(size: 17, color: BSColors.neutral700)),
    ];
  }

  List<Widget> _manches() {
    final progress = roundProgressLabel(game.gameRound, game.gameTotalRounds, gameMode: game.gameMode);
    return [
      if (progress.isNotEmpty) ...[
        Text(progress, style: BSType.body(size: 22, color: BSColors.text).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: BSSpace.s4),
      ],
      if (game.gameFinished) ...[
        Text(_resultLabel(), style: BSType.body(size: 22, color: BSColors.accent2_800).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: BSSpace.s4),
      ],
      Text('POINTS DE CE JEU', style: BSType.sectionKicker()),
      const SizedBox(height: BSSpace.s2),
      for (var i = 0; i < 4; i++)
        if (game.present[i])
          Padding(
            padding: const EdgeInsets.only(bottom: BSSpace.s1),
            child: Row(
              children: [
                Container(width: 14, height: 14, color: kBuzzerColors[i].fill),
                const SizedBox(width: BSSpace.s2),
                SizedBox(width: 200, child: Text(teams.nameFor(i), style: BSType.body(size: 18, color: BSColors.text))),
                Text(
                  '${i < game.gameScores.length ? game.gameScores[i] : 0}',
                  style: BSType.body(size: 18, color: BSColors.text).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
    ];
  }

  String _resultLabel() {
    final winner = game.gameWinner;
    if (winner != null && winner >= 0 && winner < 4) return '${teams.nameFor(winner)} gagne la partie';
    return game.gameTie ? 'Égalité' : 'Aucun vainqueur';
  }
}

// « Lancer la partie », avec le contrôle du nombre de joueurs fait ICI plutôt
// que d'attendre le refus du buzzer. Simon exige quatre buzzers et le Duel
// exactement deux ; le firmware refuse bien le lancement dans le cas
// contraire, mais son avertissement s'affiche sur le LCD, que l'app fige
// quand elle a le contrôle. Sans ce garde-fou, le clic ne faisait
// visiblement rien. Le message du Mega (WARN|PLAYERS) reste relayé en
// dessous, comme filet.
class _LaunchButton extends StatelessWidget {
  const _LaunchButton({required this.game, required this.ble, required this.onNavigate});

  final GameState game;
  final BleLinkService ble;
  final ValueChanged<ConsoleSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final requis = playerRange(game.displayGameMode);
    final presents = game.present.where((p) => p).length;
    final compte = requis == null || (presents >= requis.min && presents <= requis.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: compte ? () => ble.sendKey('#') : null,
          style: FilledButton.styleFrom(
            backgroundColor: BSColors.accent,
            foregroundColor: BSColors.bg,
            disabledBackgroundColor: BSColors.neutral300,
            disabledForegroundColor: BSColors.neutral600,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          child: const Text('Lancer la partie'),
        ),
        if (!compte || game.playersWarning != null) ...[
          const SizedBox(height: BSSpace.s2),
          Row(
            children: [
              Text(
                _explication(requis ?? game.playersWarning, presents),
                style: BSType.body(size: 15, color: BSColors.accent2_800),
              ),
              const SizedBox(width: BSSpace.s2),
              TextButton(
                onPressed: () => onNavigate(ConsoleSection.buzzers),
                style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
                child: const Text('Régler la présence'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _explication(({int min, int max})? requis, int presents) {
    final buzzers = presents <= 1 ? '$presents buzzer' : '$presents buzzers';
    if (requis == null) return 'Le nombre de buzzers ne convient pas à ce jeu. $buzzers en jeu.';
    if (requis.min == requis.max) {
      return 'Ce jeu se joue à ${requis.min}, ni plus ni moins. $buzzers en jeu.';
    }
    return 'Ce jeu se joue de ${requis.min} à ${requis.max} buzzers. $buzzers en jeu.';
  }
}

// Une action que l'animateur peut déclencher dans la phase courante, et la
// touche du clavier physique qu'elle rejoue.
class _GameAction {
  const _GameAction(this.label, this.key, {this.primary = false});
  final String label;
  final String key;
  final bool primary;
}

// Boutons de conduite des jeux non-quiz. Sans eux, ces jeux étaient
// INJOUABLES depuis l'app : le Chrono aveugle attend « # » pour donner le
// départ, « Ne buzze pas » attend « # » après l'apprentissage, le Réflexe et
// le Duel attendent « # » pour enchaîner les manches. Le clavier physique
// étant verrouillé pendant que l'app a le contrôle, plus personne ne pouvait
// donner ces ordres, et l'écran ne proposait rien à cliquer.
class _GameControls extends StatelessWidget {
  const _GameControls({required this.game, required this.ble});

  final GameState game;
  final BleLinkService ble;

  // Les touches viennent directement des switch de chaque jeu côté firmware
  // (Reflex::arm/result/gameOver, BlindTimer::announce/run/result, etc.) :
  // toute divergence ici se verrait comme un bouton sans effet.
  List<_GameAction> _actions() {
    final p = game.phase;

    if (isPhase(p, 'SIMON_SHOW') || isPhase(p, 'SIMON_PLAY')) {
      return const [_GameAction('Abandonner', 'C')];
    }
    if (isPhase(p, 'BLIND_ANNOUNCE')) {
      return const [
        _GameAction('Donner le départ', '#', primary: true),
        _GameAction('Terminer la partie', 'C'),
      ];
    }
    if (isPhase(p, 'SOUND_LEARN')) {
      return const [
        _GameAction("C'est parti", '#', primary: true),
        _GameAction('Retour au menu', 'C'),
      ];
    }
    if (isPhase(p, 'REFLEX_RESULT') || isPhase(p, 'BLIND_RESULT') || isPhase(p, 'DUEL_RESULT')) {
      final derniere = game.gameRound != null &&
          game.gameTotalRounds != null &&
          game.gameRound! >= game.gameTotalRounds!;
      return [
        _GameAction(derniere ? 'Voir les résultats' : 'Manche suivante', '#', primary: true),
        const _GameAction('Terminer la partie', 'C'),
      ];
    }
    if (isPhase(p, 'REFLEX_ARM') ||
        isPhase(p, 'REFLEX_GO') ||
        isPhase(p, 'BLIND_RUN') ||
        isPhase(p, 'DUEL_ARM') ||
        isPhase(p, 'DUEL_GO') ||
        isPhase(p, 'SOUND_PLAY')) {
      return const [_GameAction('Terminer la partie', 'C')];
    }
    if (isPhase(p, 'SIMON_OVER') ||
        isPhase(p, 'REFLEX_OVER') ||
        isPhase(p, 'BLIND_OVER') ||
        isPhase(p, 'DUEL_OVER') ||
        isPhase(p, 'SOUND_OVER')) {
      return const [
        _GameAction('Rejouer', '#', primary: true),
        _GameAction('Retour au menu', '*'),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: BSSpace.s2,
      runSpacing: BSSpace.s2,
      children: [
        for (final a in actions)
          if (a.primary)
            FilledButton(
              onPressed: () => ble.sendKey(a.key),
              style: FilledButton.styleFrom(
                backgroundColor: BSColors.accent,
                foregroundColor: BSColors.bg,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: Text(a.label),
            )
          else
            OutlinedButton(
              onPressed: () => ble.sendKey(a.key),
              style: OutlinedButton.styleFrom(
                foregroundColor: BSColors.text,
                side: const BorderSide(color: BSColors.divider),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: Text(a.label),
            ),
      ],
    );
  }
}

// Refait entendre à la salle le son de chaque équipe, un par un, pendant que
// l'écran public montre de qui il s'agit. « Ne buzze pas » a toujours eu
// cette étape ; elle est utile à tous les jeux, parce que personne ne
// reconnaît son buzz s'il ne l'a pas entendu depuis le début de la soirée.
//
// Déclenché par l'animateur plutôt qu'automatiquement au départ : la partie
// s'ouvre sur une musique d'intro, et y superposer quatre sons de buzz les
// rendrait justement méconnaissables. Ici, il le lance pendant qu'il
// explique le jeu, et peut le rejouer si la salle a mal entendu.
class _SoundRecallButton extends StatelessWidget {
  const _SoundRecallButton({required this.game, required this.sound, required this.teams});

  final GameState game;
  final SoundEngine sound;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sound,
      builder: (context, _) {
        final enCours = sound.recalling;
        final qui = sound.recallIndex;
        return Row(
          children: [
            OutlinedButton(
              onPressed: enCours ? sound.stopRecall : () => sound.startRecall(game.present),
              style: OutlinedButton.styleFrom(
                foregroundColor: BSColors.text,
                side: const BorderSide(color: BSColors.divider),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: Text(enCours ? 'Arrêter le rappel' : 'Rappeler les sons'),
            ),
            const SizedBox(width: BSSpace.s3),
            if (qui != null) ...[
              Container(width: 16, height: 16, color: kBuzzerColors[qui].fill),
              const SizedBox(width: BSSpace.s2),
              Text(teams.nameFor(qui), style: BSType.body(size: 17, color: BSColors.text)),
            ] else
              Expanded(
                child: Text(
                  'Fait entendre le son de chaque équipe, avec sa couleur sur '
                  "l'écran public.",
                  style: BSType.body(size: 15, color: BSColors.neutral600),
                ),
              ),
          ],
        );
      },
    );
  }
}
