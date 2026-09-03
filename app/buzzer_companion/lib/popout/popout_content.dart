import 'dart:io';

import 'package:flutter/material.dart';

import '../broadsheet/pulse.dart';
import '../broadsheet/tokens.dart';
import '../protocol.dart';
import 'game_screens.dart';
import 'popout_idle.dart';
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
    // Toute la mise en page dépend du jeu : un Simon n'a pas de points à
    // montrer, un Réflexe a les siens (pas ceux du quiz), et un jeu de quiz
    // garde l'écran d'origine. Voir GameLayout dans protocol.dart.
    //
    // La STRUCTURE se décide sur [gameMode], le jeu réellement chargé dans le
    // buzzer, et non sur [displayGameMode] : ce dernier reste vide tant que
    // l'opérateur n'a pas choisi lui-même (pour ne pas annoncer un jeu qu'il
    // n'a pas voulu), ce qui est la bonne règle pour un TITRE mais pas pour
    // une mise en page — une app relancée en pleine partie de Simon serait
    // sinon remise en écran de quiz, tableau des scores compris.
    final layout = layoutFor(snapshot.gameMode);
    // Aux menus et pendant la configuration, rien ne se joue : la salle ne
    // doit voir ni bandeau ni compteur, seulement le logo.
    // Quand l'application mene, la phase du buzzer ne dit plus rien : il
    // reste en APP_CONTROL du debut a la fin. C'est le moteur qui sait si une
    // partie tourne, et l'instantane le rapporte.
    final running = snapshot.appMene
        ? snapshot.flowState != QuestionFlowState.none ||
            snapshot.gameFinished ||
            snapshot.phaseJeu != null
        : isGameRunning(snapshot.phase);
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
                  // Pas de case tiretée quand aucun logo n'est choisi :
                  // l'emplacement disparaît au lieu de laisser un trou.
                  if (snapshot.logoPath != null) _EventLogoImage(path: snapshot.logoPath!),
                  const Spacer(),
                  if (running && _progressLabel(layout).isNotEmpty) ...[
                    _HeaderMeta(label: 'PROGRESSION', value: _progressLabel(layout)),
                    const SizedBox(width: 40),
                  ],
                  // Masqué tant qu'aucun jeu n'est choisi : un intitulé
                  // « JEU ACTIF » suivi du vide, devant la salle, fait
                  // penser à un écran cassé. Masqué aussi pendant l'attente,
                  // où l'écran annonce déjà le jeu à venir en grand, au
                  // centre : le répéter en petit dans le coin ferait doublon.
                  if (running && gameModeName(snapshot.displayGameMode).isNotEmpty)
                    _HeaderMeta(label: 'JEU ACTIF', value: gameModeName(snapshot.displayGameMode)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(52, 18, 52, 0),
              child: SizedBox(height: 4, child: ColoredBox(color: BSColors.text)),
            ),
            // Le rappel des sons passe avant tout le reste, partie en cours
            // ou non : pendant ces quelques secondes, la salle n'a qu'une
            // chose à faire, associer un son à une équipe.
            if (snapshot.recallIndex != null)
              Expanded(child: _SoundRecallZone(index: snapshot.recallIndex!, snapshot: snapshot))
            // Hors partie, l'écran d'attente prend tout le bas du châssis :
            // il porte son propre pied de page (les équipes du soir) à la
            // place du tableau des scores, qui n'aurait que des zéros à
            // montrer.
            else if (!running)
              Expanded(child: PopoutIdle(snapshot: snapshot))
            else
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 80),
                    // Dispatch par JEU et non par famille : chacun des
                    // quatre jeux à manches a désormais son propre écran,
                    // parce qu'ils n'ont pas la même chose à raconter (des
                    // millisecondes, une cible, un face à face, un son à
                    // révéler). Le repli _MancheZone ne sert plus qu'à un
                    // jeu qu'on ajouterait sans lui écrire son écran.
                    child: switch (snapshot.gameMode) {
                      7 => ReflexZone(snapshot: snapshot),
                      8 => BlindZone(snapshot: snapshot),
                      9 => SoundGameZone(snapshot: snapshot),
                      10 => DuelZone(snapshot: snapshot),
                      _ => switch (layout) {
                          GameLayout.quiz => _CenterZone(snapshot: snapshot),
                          GameLayout.manches => _MancheZone(snapshot: snapshot),
                          GameLayout.simon => _SimonZone(snapshot: snapshot),
                        },
                    },
                  ),
                ),
              ),
            // Deux raisons de n'avoir aucun bandeau : le jeu en cours ne
            // marque pas de points (Simon), ou aucune partie ne tourne. Dans
            // les deux cas un tableau de zéros devant la salle serait faux.
            if (running && gameHasScores(snapshot.gameMode)) ...[
              const SizedBox(height: 4, child: ColoredBox(color: BSColors.text)),
              _Scoreboard(
                snapshot: snapshot,
                scores: layout == GameLayout.manches ? snapshot.gameScores : snapshot.scores,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _progressLabel(GameLayout layout) {
    // Un bris se joue EN PLUS : « manche 3 sur 2 » n'a aucun sens, et le nom
    // de ce qui se joue vaut mieux qu'un compte faux.
    if (snapshot.brisEgalite) return "BRIS D'ÉGALITÉ";
    return switch (layout) {
        GameLayout.quiz => questionProgressLabel(snapshot.questionsAsked, snapshot.qcountValue),
        GameLayout.manches => roundProgressLabel(
            snapshot.gameRound,
            snapshot.gameTotalRounds,
            gameMode: snapshot.gameMode,
          ),
        // Le niveau de Simon est le sujet de l'écran, pas une métadonnée de
        // coin : il est affiché en grand au centre.
        GameLayout.simon => '',
    };
  }
}

// Image choisie par l'opérateur (voir EventLogo). Un fichier disparu depuis
// le choix ne doit pas casser l'écran public en pleine soirée : on n'affiche
// simplement rien.
class _EventLogoImage extends StatelessWidget {
  const _EventLogoImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 64, maxWidth: 320),
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
    // Fin de partie menée par l'application : le buzzer n'a pas d'écran de
    // fin à montrer, c'est le moteur qui désigne le gagnant.
    if (snapshot.appMene && snapshot.gameFinished) {
      // Le MEME ecran de fin que les autres jeux : une soiree se termine de la
      // meme facon, quel que soit ce a quoi on vient de jouer.
      return GameOverZone(snapshot: snapshot);
    }
    return switch (snapshot.flowState) {
      QuestionFlowState.arming => _ArmingZone(snapshot: snapshot),
      QuestionFlowState.buzzed => _BuzzedZone(snapshot: snapshot),
      QuestionFlowState.scored => _ScoredZone(snapshot: snapshot),
      QuestionFlowState.revealed => _RevealedZone(snapshot: snapshot),
      // Aucun jeu choisi : rien n'est en attente, donc on n'annonce rien.
      // L'écran garde son logo et son tableau des scores, ce qui est un
      // état d'accueil convenable devant la salle.
      QuestionFlowState.none => gameModeName(snapshot.displayGameMode).isEmpty
          ? const SizedBox.shrink()
          : Text(
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
    // Pour les jeux avec chrono, la question n'arrive dans l'instantané
    // qu'une fois le chrono lancé (voir PopoutSnapshot.fromGameState) : tant
    // que ce n'est pas le cas, rien à afficher ici sauf l'attente elle-même
    // — le public ne doit pas la voir pendant que l'animateur la lit encore
    // à voix haute. Les jeux sans chrono (Classique, Pénalité...) n'ont pas
    // cette attente : la question arrive tout de suite, pas de barre.
    final chrono = usesChrono(snapshot.gameMode);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (snapshot.questionText != null) ...[
          Text(snapshot.questionText!, style: BSType.questionPopout(), textAlign: TextAlign.center),
          const SizedBox(height: BSSpace.s6),
        ] else if (snapshot.motAttention.isNotEmpty) ...[
          // Manche libre : la question se pose a voix haute. Sans ca, l'ecran
          // reste vide au moment precis ou la salle devrait ecouter, ce qui
          // ressemble a une panne. Plus discret qu'une vraie question : ce
          // n'en est pas une, et l'animateur parle par-dessus.
          SizedBox(
            width: 1100,
            child: Text(
              snapshot.motAttention,
              textAlign: TextAlign.center,
              style: BSType.body(size: 46, color: BSColors.neutral600),
            ),
          ),
          const SizedBox(height: BSSpace.s6),
        ],
        // LE DÉCOMPTE, aussi gros pour la salle que pour l'animateur : c'est
        // lui qui pousse les joueurs à se décider. Tant qu'il n'est pas lancé,
        // la barre pleine annonce ce qui s'en vient.
        if (snapshot.chronoRestant != null) ...[
          Text('${snapshot.chronoRestant} s',
              style: BSType.heroDigitPopout(size: 96, color: BSColors.accent2)),
          const SizedBox(height: BSSpace.s2),
          _BarreChrono(
            restant: snapshot.chronoRestant!,
            total: snapshot.chronoTotal,
          ),
        ] else if (chrono) ...[
          Text('CHRONO NON LANCÉ', style: BSType.popoutHeaderMeta(color: BSColors.neutral500)),
          const SizedBox(height: BSSpace.s2),
          Container(width: 400, height: 20, color: BSColors.neutral300),
        ],
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
        // Rétrécit si le nom d'équipe est long : à 64 px, quelques mots de
        // plus suffisent à déborder les 1440 px de l'écran.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${snapshot.teamName(idx).toUpperCase()} A BUZZÉ',
            maxLines: 1,
            style: BSType.heroDigitPopout(size: 64, color: color.fill),
          ),
        ),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${snapshot.teamName(idx!).toUpperCase()} MARQUE',
              maxLines: 1,
              style: BSType.heroDigitPopout(size: 96, color: color.fill),
            ),
          ),
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

// Jeux à manches (Réflexe, Chrono aveugle, Ne buzze pas, Duel) : pas de
// question à afficher, donc le centre porte la manche en cours, puis le
// résultat une fois la partie terminée.
class _MancheZone extends StatelessWidget {
  const _MancheZone({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.gameFinished) {
      final winner = snapshot.gameWinner;
      if (winner != null && winner >= 0 && winner < kBuzzerColors.length) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${snapshot.teamName(winner).toUpperCase()} GAGNE',
            maxLines: 1,
            style: BSType.heroDigitPopout(size: 110, color: kBuzzerColors[winner].fill),
          ),
        );
      }
      return Text(
        snapshot.gameTie ? 'ÉGALITÉ' : 'AUCUN VAINQUEUR',
        style: BSType.heroDigitPopout(size: 92, color: BSColors.text),
        textAlign: TextAlign.center,
      );
    }

    final label = roundProgressLabel(
      snapshot.gameRound,
      snapshot.gameTotalRounds,
      gameMode: snapshot.gameMode,
    );
    if (label.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        style: BSType.heroDigitPopout(size: 92, color: BSColors.text),
      ),
    );
  }
}

// Simon : le cas qui a motivé toute cette passe. Jeu collaboratif, aucun
// point n'est marqué, donc rien à mettre dans un tableau des scores (il est
// masqué en amont) — ce qui compte est le niveau, seul, en grand.
class _SimonZone extends StatelessWidget {
  const _SimonZone({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final done = snapshot.simonLevel;
    if (done == null) return const SizedBox.shrink();
    // LA FIN DE PARTIE PASSE PAR L'ÉCRAN COMMUN, comme tous les autres jeux.
    // Sans lui, la salle voyait le même « NIVEAU ATTEINT » qu'en pleine
    // partie : rien ne disait que c'était fini, et le mot de la fin ne
    // sortait jamais.
    if (snapshot.gameFinished) {
      // LA SEQUENCE FAIT GROSSIR CET ECRAN, et une longue partie en met
      // trente-deux couleurs. Plutot que de choisir des tailles qui tiennent
      // dans le pire cas et qui seraient minuscules dans le cas ordinaire, on
      // laisse l'ensemble se reduire quand il deborde : devant une salle,
      // rien ne doit jamais etre coupe.
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: GameOverZone(
          snapshot: snapshot,
          resultat: '$done',
          detail: done > 1 ? 'niveaux réussis' : 'niveau réussi',
          complement: snapshot.simonSequence.isEmpty
              ? null
              : _SimonFin(snapshot: snapshot),
        ),
      );
    }
    // [simonLevel] compte les niveaux RÉUSSIS : celui qui se joue est donc
    // le suivant, comme sur l'écran du buzzer ("SIMON - Niveau N").
    final shown = done + 1;
    final length = snapshot.simonLength ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('NIVEAU', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s2),
        Text('$shown', style: BSType.heroDigitPopout(size: 220, color: BSColors.accent)),
        if (length > 0) ...[
          const SizedBox(height: BSSpace.s4),
          Text(
            '${snapshot.simonEntered ?? 0} / $length',
            style: BSType.body(size: 40, color: BSColors.neutral700),
          ),
        ],
      ],
    );
  }
}

// CE QU'ÉTAIT LA SÉQUENCE, et où la chaîne a lâché.
//
// Une fois la partie finie, c'est ce que toute la salle veut voir : elle vient
// de la subir sans jamais l'avoir en entier sous les yeux.
//
// NOMMER LE FAUTIF SANS L'ACCABLER. Il est de toute façon désigné, sa LED est
// restée allumée sur son buzzer. Le taire serait donc juste gênant. Mais
// « Bleu s'est trompé » ne fait que pointer quelqu'un devant tout le monde,
// alors que « Bleu a pesé, c'était à Rouge » raconte la séquence : la même
// information, sans le procès. Le détail des couleurs se lit tout seul
// juste au-dessus, et le mot de la fin qui suit parle de l'équipe entière.
class _SimonFin extends StatelessWidget {
  const _SimonFin({required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final sequence = snapshot.simonSequence;
    // Une séquence longue doit tenir devant une salle sans devenir un mur de
    // confettis : les carrés rapetissent plutôt que de partir sur six rangées.
    final taille = sequence.length <= 12
        ? 68.0
        : sequence.length <= 20
            ? 52.0
            : 38.0;
    final fautif = snapshot.simonFautif;
    final attendu = snapshot.simonAttendu;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('LA SÉQUENCE',
            style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var k = 0; k < sequence.length; k++)
                Container(
                  width: taille,
                  height: taille,
                  decoration: BoxDecoration(
                    color: kBuzzerColors[sequence[k]].fill,
                    // La case où ça s'est arrêté, encadrée : c'est le
                    // renseignement, le reste n'est que le décompte.
                    border: k == _positionAtteinte(sequence.length)
                        ? Border.all(color: BSColors.text, width: 5)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (fautif != null && attendu != null) ...[
          const SizedBox(height: BSSpace.s4),
          Text(
            '${snapshot.teamName(fautif)} a pesé, '
            "c'était à ${snapshot.teamName(attendu)}.",
            textAlign: TextAlign.center,
            style: BSType.body(size: 34, color: BSColors.text),
          ),
        ],
      ],
    );
  }

  /// Où l'équipe s'est rendue, dans le sens où la séquence est MONTRÉE. En
  /// mode inverse elle part de la fin : compter depuis le début encadrerait
  /// la mauvaise couleur.
  int _positionAtteinte(int longueur) {
    final saisis = snapshot.simonEntered ?? 0;
    return snapshot.gameMode == 6 ? longueur - 1 - saisis : saisis;
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.snapshot, required this.scores});
  final PopoutSnapshot snapshot;
  // Ceux du quiz ou ceux du jeu en cours, selon la mise en page : sans ça,
  // un Réflexe affichait les points du quiz précédent.
  final List<int> scores;

  @override
  Widget build(BuildContext context) {
    // Seuls les buzzers en jeu. Un buzzer absent n'a pas de score à montrer,
    // et l'estomper laissait une colonne grise devant la salle qui ne fait
    // que soulever une question. Les équipes restantes se partagent toute la
    // largeur : à deux, chacune a la moitié de l'écran.
    final enJeu = [
      for (var i = 0; i < 4; i++)
        if (i < snapshot.present.length && snapshot.present[i]) i,
    ];
    if (enJeu.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 140,
      child: Row(
        // Expanded doit rester un enfant DIRECT du Row : l'envelopper dans
        // quoi que ce soit ferait planter la mise en page à l'exécution.
        children: [
          for (var rang = 0; rang < enJeu.length; rang++)
            Expanded(child: _buildColonne(enJeu[rang], rang == 0)),
        ],
      ),
    );
  }

  Widget _buildColonne(int i, bool premiere) {
    // Ecarte pour CETTE question : une mauvaise reponse met son auteur hors
    // jeu jusqu'a la suivante. Montre seulement tant que la question est
    // ouverte : une fois tranchee, tout le monde revient, et garder la
    // mention serait faux.
    final ecarte = snapshot.mancheOuverte &&
        i < snapshot.enLice.length &&
        !snapshot.enLice[i];
    final teinte = ecarte ? BSColors.neutral500 : null;
    return Container(
      color: snapshot.lastBuzz == i ? BSColors.accent100 : null,
      padding: EdgeInsets.only(left: premiere ? 52 : 28, top: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 6),
            // La pastille perd sa couleur : c'est ce qui se voit du fond de la
            // salle, bien avant le mot.
            color: ecarte ? BSColors.neutral300 : kBuzzerColors[i].fill,
          ),
          const SizedBox(width: 14),
          // Expanded borne la colonne à sa part de l'écran, sinon un nom
          // long déborde sur le buzzer voisin. Le nom rétrécit pour tenir
          // plutôt que d'être tronqué : sur un écran vu par la salle, un nom
          // d'équipe coupé au milieu ferait négligé.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      snapshot.teamName(i).toUpperCase(),
                      maxLines: 1,
                      style: BSType.buzzerNamePopout(color: teinte),
                    ),
                  ),
                  // Le score et la mention sur la MEME ligne : ajouter une
                  // troisieme ligne ferait grandir la colonne et le bandeau
                  // sauterait a chaque mauvaise reponse, devant la salle.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        i < scores.length ? '${scores[i]}' : '',
                        style: BSType.scorePopout(color: teinte),
                      ),
                      if (ecarte) ...[
                        const SizedBox(width: 14),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Text('ÉCARTÉ',
                              style: BSType.popoutHeaderMeta(
                                  color: BSColors.neutral500)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Plein écran pendant le rappel des sons : une couleur, un nom, rien
// d'autre. Le son joue en même temps, et c'est l'association des deux qui
// compte. Un bandeau de scores ou un compteur en même temps ne ferait que
// disperser l'attention au moment où elle doit être entière.
class _SoundRecallZone extends StatelessWidget {
  const _SoundRecallZone({required this.index, required this.snapshot});

  final int index;
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final couleur = kBuzzerColors[index].fill;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('VOICI VOTRE SON', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
            const SizedBox(height: BSSpace.s6),
            Container(width: 320, height: 24, color: couleur),
            const SizedBox(height: BSSpace.s6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                snapshot.teamName(index).toUpperCase(),
                maxLines: 1,
                style: BSType.heroDigitPopout(size: 170, color: couleur),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// La barre qui se vide avec le décompte. Même largeur que la barre grise du
// chrono non lancé, pour que le passage de l'une à l'autre ne fasse pas
// sauter la mise en page.
class _BarreChrono extends StatelessWidget {
  const _BarreChrono({required this.restant, required this.total});

  final int restant;
  final int total;

  @override
  Widget build(BuildContext context) {
    final part = total > 0 ? (restant / total).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: 400,
      height: 20,
      child: Row(
        children: [
          Expanded(
            flex: (part * 1000).round(),
            child: const ColoredBox(color: BSColors.accent2),
          ),
          Expanded(
            flex: 1000 - (part * 1000).round(),
            child: const ColoredBox(color: BSColors.neutral300),
          ),
        ],
      ),
    );
  }
}
