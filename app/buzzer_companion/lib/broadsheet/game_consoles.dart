import 'package:flutter/material.dart';

import '../ble_link_service.dart';
import '../protocol.dart';
import '../team_names.dart';
import 'tokens.dart';

// Consoles de conduite des jeux non-quiz, une par jeu.
//
// POURQUOI UNE PAR JEU. L'écran public a déjà un écran dédié par jeu, parce
// qu'ils n'ont pas la même chose à raconter. La console, elle, les traitait
// tous pareil : le nom du jeu, le libellé brut de la phase, un tableau de
// scores. L'animateur voyait « REFLEX_ARM » et devait deviner ce qu'on
// attendait de lui.
//
// CE QUE LA CONSOLE DIT ET QUE L'ÉCRAN PUBLIC NE DIT PAS. C'est la seule
// raison d'être de ces vues : si elles répètent l'écran public, elles ne
// servent à rien. Chacune montre donc ce que la salle ne doit pas voir, ou
// ce dont seul l'animateur a besoin pour parler.

// --- Blocs partagés -------------------------------------------------------

// La consigne du moment, en français, à la place du nom de phase du
// firmware. C'est la première chose que l'animateur cherche.
class ConsigneBlock extends StatelessWidget {
  const ConsigneBlock({super.key, required this.titre, this.detail, this.alerte = false});

  final String titre;
  final String? detail;
  // Passe le bloc en magenta : quelque chose demande une décision ou une
  // annonce, plutôt que de simplement se dérouler.
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final couleur = alerte ? BSColors.accent2_800 : BSColors.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titre,
          style: BSType.body(size: 24, color: couleur).copyWith(fontWeight: FontWeight.w600),
        ),
        if (detail != null) ...[
          const SizedBox(height: BSSpace.s1),
          SizedBox(
            width: 560,
            child: Text(detail!, style: BSType.body(size: 17, color: BSColors.neutral700)),
          ),
        ],
      ],
    );
  }
}

// Tableau des points du jeu en cours. Le meneur est marqué, parce que
// l'animateur commente le classement à voix haute et ne devrait pas avoir à
// comparer des chiffres en lisant.
class GameScoreTable extends StatelessWidget {
  const GameScoreTable({
    super.key,
    required this.game,
    required this.teams,
    this.titre = 'POINTS DE CE JEU',
    this.surligne,
  });

  final GameState game;
  final TeamNames teams;
  final String titre;
  // Buzzer à mettre en avant, en plus du meneur : le gagnant de la manche
  // qui vient de se jouer, par exemple.
  final int? surligne;

  @override
  Widget build(BuildContext context) {
    final scores = game.gameScores;
    final presents = [for (var i = 0; i < 4; i++) if (game.present[i]) i];
    final meilleur = presents.isEmpty
        ? 0
        : presents.map((i) => i < scores.length ? scores[i] : 0).reduce((a, b) => a > b ? a : b);
    // Personne n'est « en tête » quand tout le monde est à zéro.
    final leaders = meilleur == 0
        ? <int>{}
        : {for (final i in presents) if ((i < scores.length ? scores[i] : 0) == meilleur) i};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titre, style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        for (final i in presents)
          Padding(
            padding: const EdgeInsets.only(bottom: BSSpace.s1),
            child: Row(
              children: [
                Container(width: 14, height: 14, color: kBuzzerColors[i].fill),
                const SizedBox(width: BSSpace.s2),
                SizedBox(
                  width: 200,
                  child: Text(
                    teams.nameFor(i),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BSType.body(
                      size: 18,
                      color: i == surligne ? BSColors.accent700 : BSColors.text,
                    ).copyWith(fontWeight: i == surligne ? FontWeight.w600 : FontWeight.normal),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${i < scores.length ? scores[i] : 0}',
                    style: BSType.body(size: 18, color: BSColors.text)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (leaders.contains(i))
                  Text('en tête', style: BSType.body(size: 14, color: BSColors.accent700)),
              ],
            ),
          ),
      ],
    );
  }
}

// --- Réflexe --------------------------------------------------------------

// Le premier à buzzer après un signal donné à un moment imprévisible.
//
// CE QUE SEULE LA CONSOLE SAIT. Sur l'écran public, « armé » et « signal
// donné » sont dessinés EXACTEMENT pareil, et c'est délibéré : si l'écran
// changeait au signal, les joueurs le prendraient comme départ à la place de
// la LED du buzzer, et un aller-retour Bluetooth fausserait les temps.
// L'animateur est donc le seul à savoir où en est la manche, et sa console
// doit le dire sans ambiguïté.
//
// Les FAUX DÉPARTS aussi n'existent que sur la console pendant la manche.
// La salle ne les apprend qu'au résultat ; l'animateur, lui, doit savoir
// tout de suite qui s'est éliminé pour pouvoir le raconter.
class ReflexConsole extends StatelessWidget {
  const ReflexConsole({
    super.key,
    required this.game,
    required this.teams,
    required this.ble,
  });

  final GameState game;
  final TeamNames teams;
  final BleLinkService ble;

  @override
  Widget build(BuildContext context) {
    final p = game.phase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _consigne(p),
        const SizedBox(height: BSSpace.s4),
        if (!isPhase(p, 'REFLEX_OVER')) ...[
          _fauxDeparts(),
          GameScoreTable(game: game, teams: teams, surligne: _gagnantManche()),
        ] else
          GameScoreTable(game: game, teams: teams, titre: 'POINTS FINAUX'),
      ],
    );
  }

  int? _gagnantManche() {
    final w = game.reflexWinner;
    return (isPhase(game.phase, 'REFLEX_RESULT') && w != null && w >= 0) ? w : null;
  }

  Widget _consigne(int? p) {
    final manche = roundProgressLabel(game.gameRound, game.gameTotalRounds, gameMode: game.gameMode);

    if (isPhase(p, 'REFLEX_ARM')) {
      return ConsigneBlock(
        titre: manche.isEmpty ? 'Buzzers armés' : '$manche · Buzzers armés',
        detail: "Le signal partira tout seul, après un délai imprévisible. Ne "
            "l'annoncez pas. L'écran public montre la même chose maintenant et "
            "au signal, pour que la salle ne s'en serve pas comme départ.",
      );
    }

    if (isPhase(p, 'REFLEX_GO')) {
      return ConsigneBlock(
        titre: manche.isEmpty ? 'Signal donné' : '$manche · Signal donné',
        detail: 'Les LED sont allumées. Le premier à buzzer remporte la manche. '
            "Vous êtes seul à voir que le signal est parti.",
        alerte: true,
      );
    }

    if (isPhase(p, 'REFLEX_RESULT')) return _resultat(manche);

    if (isPhase(p, 'REFLEX_OVER')) {
      final record = game.reflexRecordMs;
      final vraiRecord = record != null && record != 0 && record != 65535;
      return ConsigneBlock(
        titre: _finDePartie(),
        detail: game.reflexNewRecord
            ? 'Record battu : ${game.reflexBestMs} ms. À annoncer.'
            : (vraiRecord ? 'Record de la maison, toujours debout : $record ms.' : null),
        alerte: game.reflexNewRecord,
      );
    }

    return ConsigneBlock(titre: phaseLabel(p));
  }

  Widget _resultat(String manche) {
    final gagnant = game.reflexWinner;
    final presents = game.present.where((p) => p).length;

    if (gagnant == null || gagnant < 0) {
      final tous = game.reflexFalseStarts.length >= presents && presents > 0;
      return ConsigneBlock(
        titre: tous ? 'Tout le monde est parti trop tôt' : "Personne n'a buzzé",
        detail: 'Manche nulle, aucun point. Enchaînez sur la suivante.',
        alerte: true,
      );
    }

    final ms = game.reflexMs ?? 0;
    final meilleur = game.reflexBestMs != null && game.reflexBestMs == ms;
    return ConsigneBlock(
      titre: '${teams.nameFor(gagnant)} remporte la manche, $ms ms',
      detail: meilleur
          ? 'Meilleur temps de la partie jusqu\'ici.'
          : (game.reflexBestMs != null
              ? 'Meilleur temps de la partie : ${game.reflexBestMs} ms.'
              : null),
    );
  }

  String _finDePartie() {
    final w = game.gameWinner;
    if (w != null && w >= 0 && w < 4) return '${teams.nameFor(w)} gagne le Réflexe';
    return game.gameTie ? 'Égalité' : 'Partie terminée';
  }

  // Console seulement, et seulement s'il y en a. Une section « Faux départs »
  // vide à chaque manche apprendrait à l'animateur à ne plus la regarder,
  // et il la manquerait le jour où elle se remplit.
  Widget _fauxDeparts() {
    final fautifs = game.reflexFalseStarts.where((i) => i >= 0 && i < 4).toList()..sort();
    if (fautifs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: BSSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PARTIS TROP TÔT, CETTE MANCHE', style: BSType.sectionKicker()),
          const SizedBox(height: BSSpace.s2),
          Wrap(
            spacing: BSSpace.s3,
            runSpacing: BSSpace.s1,
            children: [
              for (final i in fautifs)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 14, color: kBuzzerColors[i].fill),
                    const SizedBox(width: BSSpace.s1),
                    Text(
                      teams.nameFor(i),
                      style: BSType.body(size: 17, color: BSColors.accent2_800),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
