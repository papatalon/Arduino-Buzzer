import 'package:flutter/material.dart';

import '../ble_link_service.dart';
import '../protocol.dart';
import '../team_names.dart';
import 'boutons.dart';
import 'phosphor_duotone.dart';
import 'pulse.dart';
import 'tokens.dart';

// Colonne centrale de la console pendant une question (design_handoff_
// buzzer_console/README.md, "Le flux d'une question (Chrono pénalité)").
// Les quatre états gérés avec la télémétrie actuelle : 3b (armée) → 1a
// (buzz) → 3d (point marqué) → 3c (révélation). La question ne bouge pas
// entre ces états — seul le bloc sous elle change de contenu — et la
// réponse reste visible en tout temps sur la console (contrat de
// confidentialité : seul le pop-out doit attendre une révélation).
//
// Les boutons envoient "KEY|<touche>" au firmware (BleLink::pollKey côté
// Mega) : chaque action rejoue exactement la touche physique correspondante
// dans la même machine à états, vérifiée dans Buzzer.cpp avant d'écrire ce
// fichier. La touche elle-même n'est plus affichée dans le libellé : l'app
// est maintenant le mode de contrôle principal, le raccourci clavier
// physique n'a plus d'intérêt pour l'opérateur (décision du client).
class QuestionFlowView extends StatelessWidget {
  const QuestionFlowView({super.key, required this.game, required this.ble, required this.teams});

  final GameState game;
  final BleLinkService ble;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final state = game.questionFlowState;
    final revealed = state == QuestionFlowState.revealed;

    final progress = questionProgressLabel(game.questionsAsked, game.qcountValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if ((game.questionCategory ?? '').isNotEmpty)
              Text(game.questionCategory!.toUpperCase(), style: BSType.sectionKicker()),
            if (progress.isNotEmpty) ...[
              const Spacer(),
              Text(progress, style: BSType.body(size: 13, color: BSColors.neutral600)),
            ],
          ],
        ),
        const SizedBox(height: BSSpace.s2),
        // Pas de question à afficher : questionnaire libre, où l'animateur
        // pose les siennes, ou application redémarrée en pleine partie. On le
        // dit plutôt que de laisser un blanc qui ressemble à une panne. La
        // conduite, elle, reste entière en dessous.
        if ((game.questionText ?? '').isEmpty) ...[
          Text(
            'Question posée à voix haute',
            style: BSType.questionConsole().copyWith(color: BSColors.neutral500),
          ),
          const SizedBox(height: BSSpace.s3),
        ] else ...[
          Text(
            game.questionText!,
            style: revealed
                ? BSType.body(size: 44, color: BSColors.neutral700)
                    .copyWith(fontWeight: FontWeight.w600, height: 1.1)
                : BSType.questionConsole(),
          ),
          const SizedBox(height: BSSpace.s3),
          _AnswerBlock(state: state, answer: game.answerText ?? ''),
        ],
        const SizedBox(height: BSSpace.s6),
        switch (state) {
          QuestionFlowState.arming => _ArmingBlock(game: game, ble: ble, teams: teams),
          QuestionFlowState.buzzed => _BuzzedBlock(game: game, ble: ble, teams: teams),
          QuestionFlowState.scored => _ScoredBlock(game: game, ble: ble, teams: teams),
          QuestionFlowState.revealed => _RevealedBlock(ble: ble),
          QuestionFlowState.none => const SizedBox.shrink(),
        },
      ],
    );
  }
}

// Confirmation avant de terminer une partie (phase END_CONFIRM) : le
// firmware attend '#' pour confirmer ou '*' pour reprendre. Sans cet
// ecran, cliquer "Terminer la partie" laissait l'operateur bloque.
class EndConfirmView extends StatelessWidget {
  const EndConfirmView({super.key, required this.ble});
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Terminer la partie ?', style: BSType.questionConsole()),
          const SizedBox(height: BSSpace.s2),
          Text(
            'Les scores seront affiches et la partie prendra fin.',
            style: BSType.body(size: 17, color: BSColors.neutral700),
          ),
          const SizedBox(height: BSSpace.s6),
          Row(
            children: [
              BSPrimaryButton(label: 'Oui, terminer', onPressed: () => ble.sendKey('#')),
              const SizedBox(width: BSSpace.s3),
              BSSecondaryButton(label: 'Reprendre la partie', onPressed: () => ble.sendKey('*')),
            ],
          ),
        ],
      ),
    );
  }
}

// Ecran final (phase END_GAME). En cas d'egalite le firmware propose un
// bris d'egalite sur '#', sinon '#' revient au menu : les libelles
// suivent donc l'etat reel (voir le message ENDGAME).
class EndGameView extends StatelessWidget {
  const EndGameView({super.key, required this.game, required this.ble, required this.teams});
  final GameState game;
  final BleLinkService ble;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final idx = game.endGameWinner;
    final winner = (idx != null && idx >= 0 && idx < kBuzzerColors.length) ? kBuzzerColors[idx] : null;
    final tie = game.endGameTie;

    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tie ? 'Égalité' : 'Fin de partie', style: BSType.questionConsole()),
          const SizedBox(height: BSSpace.s3),
          if (!tie && winner != null)
            Row(
              children: [
                Container(width: 52, height: 52, color: winner.fill),
                const SizedBox(width: BSSpace.s3),
                Text('${teams.nameFor(idx!)} gagne', style: BSType.buzzerNameConsole(size: 38)),
              ],
            ),
          if (tie)
            Text(
              'Plusieurs buzzers sont a egalite.',
              style: BSType.body(size: 17, color: BSColors.neutral700),
            ),
          const SizedBox(height: BSSpace.s6),
          Row(
            children: [
              if (tie) ...[
                BSPrimaryButton(label: "Lancer un bris d'égalité", onPressed: () => ble.sendKey('#')),
                const SizedBox(width: BSSpace.s3),
                BSSecondaryButton(label: "Accepter l'égalité", onPressed: () => ble.sendKey('*')),
              ] else
                BSPrimaryButton(label: 'Retour au menu', onPressed: () => ble.sendKey('#')),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.state, required this.answer});
  final QuestionFlowState state;
  final String answer;

  @override
  Widget build(BuildContext context) {
    if (state == QuestionFlowState.revealed) {
      return Container(
        padding: const EdgeInsets.all(BSSpace.s3),
        decoration: const BoxDecoration(
          color: BSColors.accent2_100,
          border: Border(left: BorderSide(color: BSColors.accent2, width: 5)),
        ),
        child: Text(answer, style: BSType.answerConsole(color: BSColors.accent2_800)),
      );
    }
    return Text(answer, style: BSType.answerConsole());
  }
}

// --- Blocs par état ------------------------------------------------------

class _ArmingBlock extends StatelessWidget {
  const _ArmingBlock({required this.game, required this.ble, required this.teams});
  final TeamNames teams;
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final chrono = usesChrono(game.gameMode);

    // Un lastBuzz encore renseigné en phase d'attente veut dire qu'une
    // réponse vient d'être refusée : le buzzer fautif est désactivé pour
    // cette question, mais les autres peuvent encore répondre (voir
    // Buzzer::badAnswer). Une nouvelle question remet lastBuzz à null,
    // donc pas de confusion possible avec un vrai début de question.
    final idx = game.lastBuzz;
    final rejected = (idx != null && idx >= 0 && idx < kBuzzerColors.length) ? kBuzzerColors[idx] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: BSSpace.s2),
              Pulse(
                duration: const Duration(seconds: 2),
                delay: Duration(milliseconds: i * 250),
                child: Container(width: 26, height: 52, color: BSColors.neutral300),
              ),
            ],
          ],
        ),
        const SizedBox(height: BSSpace.s3),
        Text(
          rejected != null ? '${teams.nameFor(idx!)} s\'est trompé' : "Personne n'a buzzé",
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s1),
        Text(
          rejected != null
              ? 'Les autres peuvent encore répondre.'
              : (chrono ? 'Lis la question à voix haute, puis lance le chrono.' : 'En attente d\'un buzz.'),
          style: BSType.body(size: 15, color: BSColors.neutral600),
        ),
        const SizedBox(height: BSSpace.s4),
        if (chrono) ...[
          Text('CHRONO NON LANCÉ', style: BSType.datelineRail(color: BSColors.neutral600)),
          const SizedBox(height: BSSpace.s4),
        ],
        Row(
          children: [
            if (chrono) ...[
              BSPrimaryButton(label: 'Lancer le chrono', onPressed: () => ble.sendKey('D')),
              const SizedBox(width: BSSpace.s3),
            ],
            BSSecondaryButton(label: 'Révéler la réponse', onPressed: () => ble.sendKey('0')),
          ],
        ),
        const SizedBox(height: BSSpace.s2),
        Row(
          children: [
            // Son d'ambiance pendant que la reponse se fait attendre
            // (touche # en WAITING_BUZZER, voir Buzzer.ino).
            BSGhostButton(label: "Son d'attente", onPressed: () => ble.sendKey('#')),
            const SizedBox(width: BSSpace.s3),
            BSGhostButton(label: 'Corriger', onPressed: () => ble.sendKey('B')),
            const SizedBox(width: BSSpace.s3),
            BSGhostButton(label: 'Terminer la partie', onPressed: () => ble.sendKey('C')),
          ],
        ),
      ],
    );
  }
}

class _BuzzedBlock extends StatelessWidget {
  const _BuzzedBlock({required this.game, required this.ble, required this.teams});
  final TeamNames teams;
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final idx = game.lastBuzz;
    if (idx == null || idx < 0 || idx >= kBuzzerColors.length) return const SizedBox.shrink();
    final color = kBuzzerColors[idx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Pulse(child: Container(width: 52, height: 52, color: color.fill)),
            const SizedBox(width: BSSpace.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${teams.nameFor(idx)} a buzzé', style: BSType.buzzerNameConsole(size: 38)),
                Text(
                  'Chrono arrêté · les autres buzzers sont neutralisés',
                  style: BSType.body(size: 15, color: BSColors.neutral600),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            BSPrimaryButton(label: 'Bonne réponse', onPressed: () => ble.sendKey('A')),
            const SizedBox(width: BSSpace.s3),
            BSSecondaryButton(label: 'Mauvaise réponse', onPressed: () => ble.sendKey('D')),
          ],
        ),
      ],
    );
  }
}

class _ScoredBlock extends StatelessWidget {
  const _ScoredBlock({required this.game, required this.ble, required this.teams});
  final TeamNames teams;
  final GameState game;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final idx = game.lastBuzz;
    if (idx == null || idx < 0 || idx >= kBuzzerColors.length) return const SizedBox.shrink();
    final color = kBuzzerColors[idx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 80, height: 80, color: color.fill),
            const SizedBox(width: BSSpace.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${teams.nameFor(idx)} marque', style: BSType.buzzerNameConsole(size: 56)),
                Text('${game.scores[idx]}', style: BSType.scoreConsole(color: BSColors.accent700)),
              ],
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            BSPrimaryButton(label: 'Continuer maintenant', onPressed: () => ble.sendKey('#')),
            const SizedBox(width: BSSpace.s3),
            BSGhostButton(label: 'Corriger', onPressed: () => ble.sendKey('B')),
          ],
        ),
      ],
    );
  }
}

class _RevealedBlock extends StatelessWidget {
  const _RevealedBlock({required this.ble});
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const PhosphorDuotone(PhosphorGlyphs.xCircle, size: 20, color: BSColors.neutral600),
            const SizedBox(width: BSSpace.s2),
            Text("Personne n'a trouvé", style: BSType.body(size: 17, color: BSColors.neutral700)),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        BSPrimaryButton(label: 'Continuer', onPressed: () => ble.sendKey('#')),
      ],
    );
  }
}
