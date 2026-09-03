import 'package:flutter/material.dart';

import '../broadsheet/boutons.dart';
import '../broadsheet/tokens.dart';
import '../protocol.dart';
import '../team_names.dart';
import 'moteur_simon.dart';

// LA CONSOLE PENDANT UN SIMON.
//
// Deux gestes en tout : lancer, et arrêter si ça traîne. Le reste du temps
// l'animateur regarde la salle, pas son écran, donc rien ici ne demande d'être
// lu de près.
//
// LA COULEUR ATTENDUE N'EST JAMAIS AFFICHÉE pendant la répétition. C'est la
// même règle que la cible du Chrono aveugle : un animateur qui la lit finit
// par la laisser paraître, et la salle regarde son visage. Il voit déjà les
// LED s'allumer pendant la démonstration, comme tout le monde ; ce qu'il ne
// doit pas avoir, c'est une longueur d'avance sur les joueurs.
//
// LA SÉQUENCE COMPLÈTE, elle, s'affiche à la fin. À ce moment-là il n'y a plus
// rien à protéger, et c'est ce que l'animateur raconte à voix haute : où
// exactement la chaîne a cassé.
class ConsoleSimon extends StatelessWidget {
  const ConsoleSimon({
    super.key,
    required this.moteur,
    required this.teams,
    required this.onChangerDeJeu,
    required this.onChoisirLeSens,
  });

  final MoteurSimon moteur;
  final TeamNames teams;
  final VoidCallback onChangerDeJeu;

  /// LE SENS EST UN RÉGLAGE, PAS UN JEU. « Simon inverse » n'a donc pas sa
  /// carte dans la grille : mêmes règles, même matériel, même déroulement.
  /// Le rappel remonte quand même jusqu'au jeu retenu (5 ou 6), parce que
  /// c'est lui qui nomme le jeu partout ailleurs, l'écran public compris.
  final ValueChanged<bool> onChoisirLeSens;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: moteur,
      builder: (context, _) => SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: switch (moteur.etape) {
            EtapeSimon.repos => _Lancement(
                moteur: moteur,
                teams: teams,
                onChangerDeJeu: onChangerDeJeu,
                onChoisirLeSens: onChoisirLeSens),
            EtapeSimon.finie => _FinDePartie(moteur: moteur, teams: teams),
            _ => _EnPartie(moteur: moteur),
          },
        ),
      ),
    );
  }
}

// --- Avant la partie -----------------------------------------------------

class _Lancement extends StatelessWidget {
  const _Lancement({
    required this.moteur,
    required this.teams,
    required this.onChangerDeJeu,
    required this.onChoisirLeSens,
  });

  final MoteurSimon moteur;
  final TeamNames teams;
  final VoidCallback onChangerDeJeu;
  final ValueChanged<bool> onChoisirLeSens;

  @override
  Widget build(BuildContext context) {
    final envers = moteur.alEnvers;
    final joueurs = [
      for (var i = 0; i < 4; i++) if (moteur.presentsMateriel[i]) i
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(envers ? 'Simon inverse' : 'Simon',
            style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        SizedBox(
          width: 620,
          child: Text(
            "La machine joue une séquence de couleurs, l'équipe la rejoue. "
                "Elle s'allonge d'une couleur par niveau et ne s'arrête qu'à la "
                "première erreur : il n'y a donc pas de longueur à régler.",
            style: BSType.body(size: 17, color: BSColors.neutral700),
          ),
        ),
        const SizedBox(height: BSSpace.s2),
        SizedBox(
          width: 620,
          child: Text(
            "Personne ne marque de point : tout le monde joue ensemble contre "
                "la machine.",
            style: BSType.body(size: 15, color: BSColors.neutral600),
          ),
        ),
        const SizedBox(height: BSSpace.s3),
        BSGhostButton(label: 'Changer de jeu', onPressed: onChangerDeJeu),
        const SizedBox(height: BSSpace.s4),
        Container(height: 2, color: BSColors.text),
        const SizedBox(height: BSSpace.s4),

        // LE SEUL RÉGLAGE, et il se décide juste avant de lancer : c'est en
        // regardant la salle qu'on sait si elle est d'attaque pour l'envers.
        Text('LE SENS', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s3),
        _CarteSens(
          nom: 'Dans le même ordre',
          quoi: "La séquence se rejoue du début à la fin, comme elle a été "
              "montrée.",
          choisi: !envers,
          onTap: () => onChoisirLeSens(false),
        ),
        const SizedBox(height: BSSpace.s2),
        _CarteSens(
          nom: "À l'envers",
          quoi: "La dernière couleur montrée est la première à peser. "
              "Beaucoup plus dur qu'il en a l'air.",
          choisi: envers,
          onTap: () => onChoisirLeSens(true),
        ),
        const SizedBox(height: BSSpace.s6),

        // QUI TIENT QUELLE COULEUR : le seul vrai préalable du jeu, et le
        // moment de le dire à voix haute. Une équipe qui se trompe de couleur
        // fait rater la partie sans jamais comprendre pourquoi.
        Text('CHACUN SA COULEUR', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s3),
        Wrap(
          spacing: BSSpace.s4,
          runSpacing: BSSpace.s3,
          children: [
            for (final i in joueurs)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 28, height: 28, color: kBuzzerColors[i].fill),
                  const SizedBox(width: BSSpace.s2),
                  Text(teams.nameFor(i),
                      style: BSType.buzzerNameConsole(size: 22)),
                ],
              ),
          ],
        ),
        const SizedBox(height: BSSpace.s3),
        Text(
          'La séquence n\'utilise que ces couleurs.',
          style: BSType.body(size: 15, color: BSColors.neutral600),
        ),
        const SizedBox(height: BSSpace.s6),
        BSPrimaryButton(
          label: 'Lancer la partie',
          grand: true,
          onPressed:
              moteur.compteDeJoueursValide ? () => moteur.demarrer() : null,
        ),
        if (!moteur.compteDeJoueursValide) ...[
          const SizedBox(height: BSSpace.s2),
          Text(
            joueurs.isEmpty
                ? 'Aucun buzzer branché.'
                : 'Il faut au moins deux buzzers : à un seul, la séquence '
                    'serait la même couleur répétée.',
            style: BSType.body(size: 15, color: BSColors.neutral600),
          ),
        ],
      ],
    );
  }
}

// Deux options seulement, et l'une des deux change la règle du jeu : elles
// s'affichent toutes les deux, expliquées, plutôt que de se cacher derrière
// une bascule dont l'état ne dirait pas ce qu'il fait. Même carte que le choix
// de la règle des faux départs, au Réflexe.
class _CarteSens extends StatelessWidget {
  const _CarteSens({
    required this.nom,
    required this.quoi,
    required this.choisi,
    required this.onTap,
  });

  final String nom;
  final String quoi;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(BSSpace.s3),
        decoration: BoxDecoration(
          color: choisi ? BSColors.accent100 : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: choisi ? BSColors.accent : BSColors.divider,
              width: choisi ? 5 : 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nom, style: BSType.buzzerNameConsole(size: 20)),
            const SizedBox(height: 2),
            Text(quoi, style: BSType.body(size: 15, color: BSColors.neutral700)),
          ],
        ),
      ),
    );
  }
}

// --- Pendant la partie ---------------------------------------------------

class _EnPartie extends StatelessWidget {
  const _EnPartie({required this.moteur});
  final MoteurSimon moteur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(moteur.alEnvers ? 'SIMON INVERSE' : 'SIMON',
                style: BSType.sectionKicker()),
            const Spacer(),
            Text('${moteur.sequence.length} couleurs',
                style: BSType.body(size: 13, color: BSColors.neutral600)),
          ],
        ),
        const SizedBox(height: BSSpace.s2),

        // LE NIVEAU EST LE SUJET, comme sur l'écran public. [niveau] compte
        // les niveaux réussis : celui qui se joue est le suivant.
        Text('Niveau ${moteur.niveau + 1}', style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s3),

        switch (moteur.etape) {
          EtapeSimon.demonstration => _Demonstration(moteur: moteur),
          EtapeSimon.bravo => _Bravo(moteur: moteur),
          _ => _Repetition(moteur: moteur),
        },

        const SizedBox(height: BSSpace.s6),
        Container(height: 1, color: BSColors.divider),
        const SizedBox(height: BSSpace.s3),
        Row(
          children: [
            Text(
              moteur.niveau == 0
                  ? 'Aucun niveau réussi pour l\'instant'
                  : '${moteur.niveau} ${moteur.niveau > 1 ? "niveaux réussis" : "niveau réussi"}',
              style: BSType.body(size: 15, color: BSColors.neutral600),
            ),
            const Spacer(),
            BSGhostButton(
                label: 'Arrêter la partie', onPressed: moteur.abandonner),
          ],
        ),
      ],
    );
  }
}

class _Demonstration extends StatelessWidget {
  const _Demonstration({required this.moteur});
  final MoteurSimon moteur;

  @override
  Widget build(BuildContext context) {
    final allumee = moteur.couleurAllumee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('La machine joue la séquence.',
            style: BSType.body(size: 17, color: BSColors.neutral700)),
        const SizedBox(height: BSSpace.s2),
        Text('Silence complet : ça se joue à l\'oreille autant qu\'à l\'œil.',
            style: BSType.body(size: 15, color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s4),
        // La couleur en cours, et rien de plus : la suite se dévoile au rythme
        // du jeu, comme la salle la découvre.
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              color: allumee == null
                  ? BSColors.neutral200
                  : kBuzzerColors[allumee].fill,
            ),
            const SizedBox(width: BSSpace.s3),
            Text(
              allumee == null
                  ? '...'
                  : kBuzzerColors[allumee].name.toUpperCase(),
              style: BSType.buzzerNameConsole(size: 28),
            ),
          ],
        ),
      ],
    );
  }
}

class _Repetition extends StatelessWidget {
  const _Repetition({required this.moteur});
  final MoteurSimon moteur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          moteur.alEnvers
              ? 'À eux de la rejouer, à l\'envers.'
              : 'À eux de la rejouer.',
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s4),
        Text('OÙ ILS EN SONT', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        Text('${moteur.saisis} / ${moteur.sequence.length}',
            style: BSType.buzzerNameConsole(size: 44)),
        const SizedBox(height: BSSpace.s2),
        // Ce qu'on NE montre pas ici est délibéré : la couleur attendue reste
        // hors de l'écran. Voir l'en-tête du fichier.
        Text(
          'Dix secondes sans le moindre appui et la partie s\'arrête.',
          style: BSType.body(size: 15, color: BSColors.neutral600),
        ),
      ],
    );
  }
}

class _Bravo extends StatelessWidget {
  const _Bravo({required this.moteur});
  final MoteurSimon moteur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Niveau ${moteur.niveau} réussi',
            style: BSType.buzzerNameConsole(size: 34, color: BSColors.accent)),
        const SizedBox(height: BSSpace.s2),
        Text('La séquence s\'allonge d\'une couleur.',
            style: BSType.body(size: 17, color: BSColors.neutral700)),
      ],
    );
  }
}

// --- Après la partie -----------------------------------------------------

class _FinDePartie extends StatelessWidget {
  const _FinDePartie({required this.moteur, required this.teams});
  final MoteurSimon moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final fautif = moteur.fautif;
    final titre = switch (moteur.raisonDeLaFin) {
      FinDeSimon.rate => 'La chaîne a cassé',
      FinDeSimon.tropLent => 'Plus personne ne jouait',
      FinDeSimon.abandon => 'Partie arrêtée',
      FinDeSimon.parfait => 'Séquence maximale',
      null => 'Fin de partie',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titre, style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s4),
        Text('NIVEAU ATTEINT', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        Text('${moteur.niveau}', style: BSType.buzzerNameConsole(size: 56)),
        if (fautif != null) ...[
          const SizedBox(height: BSSpace.s4),
          Row(
            children: [
              Container(
                  width: 40, height: 40, color: kBuzzerColors[fautif].fill),
              const SizedBox(width: BSSpace.s3),
              Text('${teams.nameFor(fautif)} a pesé hors tour',
                  style: BSType.buzzerNameConsole(size: 24)),
            ],
          ),
        ],
        if (moteur.motFinal.isNotEmpty) ...[
          const SizedBox(height: BSSpace.s3),
          SizedBox(
            width: 620,
            child: Text(moteur.motFinal,
                style: BSType.body(size: 17, color: BSColors.neutral600)),
          ),
        ],
        const SizedBox(height: BSSpace.s6),
        Container(height: 1, color: BSColors.divider),
        const SizedBox(height: BSSpace.s3),

        // LA SÉQUENCE, enfin visible. Il n'y a plus rien à protéger, et c'est
        // ce que l'animateur raconte : jusqu'où ça tenait, et où ça a lâché.
        Text('LA SÉQUENCE', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        _Sequence(moteur: moteur),
        const SizedBox(height: BSSpace.s2),
        Text(
          moteur.alEnvers
              ? 'Montrée dans cet ordre, à rejouer de la droite vers la gauche. '
                  'La position atteinte est encadrée.'
              : 'La position atteinte est encadrée.',
          style: BSType.body(size: 15, color: BSColors.neutral600),
        ),
        const SizedBox(height: BSSpace.s6),
        Wrap(
          spacing: BSSpace.s4,
          runSpacing: BSSpace.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BSPrimaryButton(
              label: 'Rejouer',
              onPressed: moteur.rejouer,
              grand: true,
            ),
            BSSecondaryButton(
              label: 'Nouvelle partie',
              onPressed: moteur.quitter,
              grand: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _Sequence extends StatelessWidget {
  const _Sequence({required this.moteur});
  final MoteurSimon moteur;

  @override
  Widget build(BuildContext context) {
    // La position atteinte, dans le sens où la séquence est MONTRÉE. En mode
    // inverse, l'équipe part de la fin : encadrer la case comptée depuis le
    // début désignerait la mauvaise couleur.
    final atteinte = moteur.alEnvers
        ? moteur.sequence.length - 1 - moteur.saisis
        : moteur.saisis;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var k = 0; k < moteur.sequence.length; k++)
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: kBuzzerColors[moteur.sequence[k]].fill,
              border: k == atteinte
                  ? Border.all(color: BSColors.text, width: 3)
                  : null,
            ),
          ),
      ],
    );
  }
}
