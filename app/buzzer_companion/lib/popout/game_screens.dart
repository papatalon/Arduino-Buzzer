import 'package:flutter/material.dart';

import '../broadsheet/tokens.dart';
import '../protocol.dart';
import 'popout_snapshot.dart';

// Écrans publics propres à chaque jeu non-quiz. Un jeu, un écran : le
// Réflexe montre des millisecondes, le Chrono aveugle une cible et des
// écarts, le Duel deux joueurs face à face, Ne buzze pas la révélation du
// son qui vient de passer. Rien de tout ça ne rentre dans une mise en page
// commune sans mentir sur l'un des quatre.
//
// CONTRAINTE QUI GOUVERNE TOUT : l'écran public est vu par les joueurs. Il
// ne doit jamais divulguer ce que le jeu cache, ni servir de signal de
// départ concurrent. Chaque écran ci-dessous en tient compte, et les
// commentaires disent où.

// Repli commun aux quatre : une fois la partie terminée, tous annoncent la
// même chose (gagnant, égalité, ou personne).
class GameOverZone extends StatelessWidget {
  const GameOverZone({super.key, required this.snapshot, this.detail});

  final PopoutSnapshot snapshot;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final winner = snapshot.gameWinner;
    final gagne = winner != null && winner >= 0 && winner < kBuzzerColors.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (gagne)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${snapshot.teamName(winner).toUpperCase()} GAGNE',
              maxLines: 1,
              style: BSType.heroDigitPopout(size: 110, color: kBuzzerColors[winner].fill),
            ),
          )
        else
          Text(
            snapshot.gameTie ? 'ÉGALITÉ' : 'AUCUN VAINQUEUR',
            style: BSType.heroDigitPopout(size: 92, color: BSColors.text),
            textAlign: TextAlign.center,
          ),
        if (detail != null && detail!.isNotEmpty) ...[
          const SizedBox(height: BSSpace.s6),
          Text(detail!, style: BSType.body(size: 32, color: BSColors.neutral700)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- Réflexe

class ReflexZone extends StatelessWidget {
  const ReflexZone({super.key, required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (isPhase(snapshot.phaseAffichee, 'REFLEX_OVER')) {
      final record = snapshot.reflexRecordMs;
      final aRecord = record != null && record != 65535 && record != 0;
      return GameOverZone(
        snapshot: snapshot,
        detail: snapshot.reflexNewRecord
            ? 'Record battu : ${snapshot.reflexBestMs} ms'
            : (aRecord ? 'Record à battre : $record ms' : null),
      );
    }

    if (isPhase(snapshot.phaseAffichee, 'REFLEX_RESULT')) {
      final winner = snapshot.reflexWinner;
      if (winner == null || winner < 0) {
        return Text(
          snapshot.reflexFalseStarts.length >= snapshot.present.where((p) => p).length
              ? 'TOUS FAUX DÉPART'
              : "PERSONNE N'A BUZZÉ",
          style: BSType.heroDigitPopout(size: 92, color: BSColors.neutral700),
          textAlign: TextAlign.center,
        );
      }
      final couleur = kBuzzerColors[winner].fill;
      final ms = snapshot.reflexMs ?? 0;
      final meilleur = snapshot.reflexBestMs != null && snapshot.reflexBestMs == ms;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              snapshot.teamName(winner).toUpperCase(),
              maxLines: 1,
              style: BSType.buzzerNamePopout(color: couleur).copyWith(fontSize: 52),
            ),
          ),
          Text('$ms', style: BSType.heroDigitPopout(size: 200, color: couleur)),
          Text('MILLISECONDES', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
          if (meilleur) ...[
            const SizedBox(height: BSSpace.s6),
            Text(
              'MEILLEUR TEMPS DE LA PARTIE',
              style: BSType.popoutHeaderMeta(color: BSColors.accent2_700),
            ),
          ],
        ],
      );
    }

    // REFLEX_ARM et REFLEX_GO rendent EXACTEMENT la même chose, et c'est
    // délibéré : si l'écran changeait au signal, les joueurs le prendraient
    // comme départ à la place de la LED du buzzer. Or un aller-retour BLE
    // plus un rendu à l'écran, c'est des dizaines de millisecondes
    // irrégulières, sur un jeu qui se décide au centième. Le seul signal
    // légitime est la LED.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ATTENDEZ LE SIGNAL', style: BSType.heroDigitPopout(size: 84, color: BSColors.text)),
        if (snapshot.reflexFalseStarts.isNotEmpty) ...[
          const SizedBox(height: BSSpace.s8),
          // Un faux départ est déjà public : la LED s'éteint et le buzzer
          // l'annonce. Le répéter ici ne divulgue rien.
          Text(
            snapshot.reflexFalseStarts.map((i) => snapshot.teamName(i)).join(', ').toUpperCase(),
            style: BSType.buzzerNamePopout(color: BSColors.accent2_700).copyWith(fontSize: 40),
            textAlign: TextAlign.center,
          ),
          Text(
            snapshot.reflexFalseStarts.length > 1 ? 'FAUX DÉPARTS' : 'FAUX DÉPART',
            style: BSType.popoutHeaderMeta(color: BSColors.neutral600),
          ),
        ],
      ],
    );
  }
}

// --------------------------------------------------------- Chrono aveugle

String _secondes(int ms) {
  if (ms <= 0) return '';
  final s = ms / 1000;
  return '${s.toStringAsFixed(1).replaceAll('.', ',')} s';
}

class BlindZone extends StatelessWidget {
  const BlindZone({super.key, required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (isPhase(snapshot.phaseAffichee, 'BLIND_OVER')) {
      return GameOverZone(snapshot: snapshot);
    }

    final cible = snapshot.blindTargetS;

    if (isPhase(snapshot.phaseAffichee, 'BLIND_RESULT')) {
      final cibleMs = (cible ?? 0) * 1000;
      final enJeu = [
        for (var i = 0; i < 4; i++)
          if (i < snapshot.present.length && snapshot.present[i]) i,
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('CIBLE $cible SECONDES', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
          const SizedBox(height: BSSpace.s6),
          for (final i in enJeu)
            Padding(
              padding: const EdgeInsets.only(bottom: BSSpace.s3),
              child: _LigneTemps(
                snapshot: snapshot,
                index: i,
                ms: i < snapshot.blindTimes.length ? snapshot.blindTimes[i] : 0,
                cibleMs: cibleMs,
                gagnant: snapshot.blindWinner == i,
              ),
            ),
        ],
      );
    }

    // BLIND_ANNOUNCE et BLIND_RUN, encore une fois identiques et surtout
    // TOTALEMENT IMMOBILES. Tout le jeu consiste à estimer une durée sans
    // repère : la moindre chose qui bouge à l'écran (compteur, barre,
    // animation, même un point clignotant) donnerait cette référence et
    // viderait le jeu de son intérêt.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('CIBLE', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s2),
        Text('$cible', style: BSType.heroDigitPopout(size: 240, color: BSColors.accent)),
        Text('SECONDES', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s8),
        Text('Buzzez au bon moment.', style: BSType.body(size: 34, color: BSColors.neutral700)),
      ],
    );
  }
}

class _LigneTemps extends StatelessWidget {
  const _LigneTemps({
    required this.snapshot,
    required this.index,
    required this.ms,
    required this.cibleMs,
    required this.gagnant,
  });

  final PopoutSnapshot snapshot;
  final int index;
  final int ms;
  final int cibleMs;
  final bool gagnant;

  @override
  Widget build(BuildContext context) {
    final couleur = kBuzzerColors[index].fill;
    final ecart = ms > 0 ? (ms - cibleMs) : null;
    return SizedBox(
      width: 900,
      child: Row(
        children: [
          Container(width: 26, height: 26, color: couleur),
          const SizedBox(width: BSSpace.s4),
          SizedBox(
            width: 320,
            child: Text(
              snapshot.teamName(index).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BSType.buzzerNamePopout(color: gagnant ? couleur : BSColors.text)
                  .copyWith(fontSize: 44),
            ),
          ),
          SizedBox(
            width: 220,
            child: Text(
              ms > 0 ? _secondes(ms) : 'Pas buzzé',
              style: BSType.scorePopout(color: gagnant ? couleur : BSColors.text).copyWith(fontSize: 44),
            ),
          ),
          if (ecart != null)
            Text(
              '${ecart >= 0 ? '+' : '-'}${_secondes(ecart.abs())}',
              style: BSType.body(size: 34, color: BSColors.neutral600),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Duel

class DuelZone extends StatelessWidget {
  const DuelZone({super.key, required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (isPhase(snapshot.phaseAffichee, 'DUEL_OVER')) {
      return GameOverZone(snapshot: snapshot);
    }

    if (isPhase(snapshot.phaseAffichee, 'DUEL_RESULT')) {
      final fautif = snapshot.duelFalseStarter;
      final winner = snapshot.duelWinner;
      if (fautif != null && fautif >= 0 && fautif < 4) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'FAUX DÉPART',
              style: BSType.heroDigitPopout(size: 92, color: BSColors.accent2_700),
            ),
            const SizedBox(height: BSSpace.s4),
            Text(
              snapshot.teamName(fautif).toUpperCase(),
              style: BSType.buzzerNamePopout(color: kBuzzerColors[fautif].fill).copyWith(fontSize: 52),
            ),
          ],
        );
      }
      if (winner == null || winner < 0) {
        return Text(
          "PERSONNE N'A BUZZÉ",
          style: BSType.heroDigitPopout(size: 92, color: BSColors.neutral700),
          textAlign: TextAlign.center,
        );
      }
      final couleur = kBuzzerColors[winner].fill;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              snapshot.teamName(winner).toUpperCase(),
              maxLines: 1,
              style: BSType.buzzerNamePopout(color: couleur).copyWith(fontSize: 52),
            ),
          ),
          Text('${snapshot.duelMs ?? 0}', style: BSType.heroDigitPopout(size: 200, color: couleur)),
          Text('MILLISECONDES', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
        ],
      );
    }

    // DUEL_ARM et DUEL_GO, identiques. Le signal du Duel est SONORE, et
    // c'est ce qui le rend juste : les deux duellistes entendent le même
    // haut-parleur au même instant, parfois dos à dos, parfois les yeux
    // fermés. Un écran qui s'allumerait au « go » créerait un second signal,
    // plus lent, et avantagerait celui qui regarde plutôt que celui qui
    // écoute.
    final a = snapshot.duelPlayerA;
    final b = snapshot.duelPlayerB;
    if (a == null || b == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Duelliste(snapshot: snapshot, index: a),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text('vs', style: BSType.body(size: 56, color: BSColors.neutral500)),
            ),
            _Duelliste(snapshot: snapshot, index: b),
          ],
        ),
        const SizedBox(height: BSSpace.s8),
        Text('Écoutez le signal.', style: BSType.body(size: 34, color: BSColors.neutral700)),
      ],
    );
  }
}

class _Duelliste extends StatelessWidget {
  const _Duelliste({required this.snapshot, required this.index});
  final PopoutSnapshot snapshot;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Column(
        children: [
          Container(width: 120, height: 12, color: kBuzzerColors[index].fill),
          const SizedBox(height: BSSpace.s3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              snapshot.teamName(index).toUpperCase(),
              maxLines: 1,
              style: BSType.heroDigitPopout(size: 76, color: BSColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- Ne buzze pas

class SoundGameZone extends StatelessWidget {
  const SoundGameZone({super.key, required this.snapshot});
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (isPhase(snapshot.phaseAffichee, 'SOUND_OVER')) {
      return GameOverZone(snapshot: snapshot);
    }

    if (isPhase(snapshot.phaseAffichee, 'SOUND_LEARN')) {
      final qui = snapshot.soundLearning;
      if (qui == null || qui < 0) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('APPRENTISSAGE TERMINÉ', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
            const SizedBox(height: BSSpace.s4),
            Text('Prêts ?', style: BSType.heroDigitPopout(size: 120, color: BSColors.text)),
          ],
        );
      }
      final couleur = kBuzzerColors[qui].fill;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('RETENEZ CE SON', style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
          const SizedBox(height: BSSpace.s4),
          Container(width: 200, height: 16, color: couleur),
          const SizedBox(height: BSSpace.s4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              snapshot.teamName(qui).toUpperCase(),
              maxLines: 1,
              style: BSType.heroDigitPopout(size: 140, color: couleur),
            ),
          ),
        ],
      );
    }

    // SOUND_PLAY. Le propriétaire du son EN COURS n'arrive jamais jusqu'ici :
    // le Mega ne l'envoie qu'une fois la fenêtre pour buzzer refermée (voir
    // SoundGame::judgeCurrent). Ce qui s'affiche est donc toujours le son
    // PRÉCÉDENT, déjà joué et déjà jugé. C'est toute la question du jeu :
    // l'écran ne peut pas y répondre avant les joueurs.
    final owner = snapshot.soundLastOwner;
    if (owner == null || owner == -2) {
      return Text(
        'Ouvrez grand les oreilles.',
        style: BSType.body(size: 34, color: BSColors.neutral700),
        textAlign: TextAlign.center,
      );
    }
    if (owner < 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("C'ÉTAIT", style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
          const SizedBox(height: BSSpace.s2),
          Text('UN LEURRE', style: BSType.heroDigitPopout(size: 120, color: BSColors.accent2)),
        ],
      );
    }
    final couleur = kBuzzerColors[owner].fill;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("C'ÉTAIT LE SON DE", style: BSType.popoutHeaderMeta(color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            snapshot.teamName(owner).toUpperCase(),
            maxLines: 1,
            style: BSType.heroDigitPopout(size: 140, color: couleur),
          ),
        ),
        const SizedBox(height: BSSpace.s4),
        Text(
          snapshot.soundLastClaimed ? 'Reconnu !' : 'Laissé passer.',
          style: BSType.body(size: 34, color: BSColors.neutral700),
        ),
      ],
    );
  }
}
