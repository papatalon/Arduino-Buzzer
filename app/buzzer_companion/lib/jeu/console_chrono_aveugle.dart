import 'package:flutter/material.dart';

import '../broadsheet/boutons.dart';
import '../broadsheet/tokens.dart';
import '../protocol.dart';
import '../team_names.dart';
import 'moteur_chrono_aveugle.dart';

// LA CONSOLE PENDANT UN CHRONO AVEUGLE.
//
// Deux gestes seulement : annoncer la durée à voix haute, puis donner le top.
// Ensuite l'animateur n'a plus rien à faire qu'à regarder la salle se
// tortiller, ce qui est tout l'intérêt du jeu.
//
// LA DURÉE CIBLE NE VA PAS SUR L'ÉCRAN PUBLIC pendant la course. Elle y est
// annoncée avant le départ, puis l'écran se fige : afficher un compte à
// rebours viderait le jeu de sa substance.
class ConsoleChronoAveugle extends StatelessWidget {
  const ConsoleChronoAveugle({
    super.key,
    required this.moteur,
    required this.teams,
    required this.onChangerDeJeu,
  });

  final MoteurChronoAveugle moteur;
  final TeamNames teams;
  final VoidCallback onChangerDeJeu;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: moteur,
      builder: (context, _) => SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: switch (moteur.etape) {
            EtapeChronoAveugle.repos =>
              _Lancement(moteur: moteur, onChangerDeJeu: onChangerDeJeu),
            EtapeChronoAveugle.finie =>
              _FinDePartie(moteur: moteur, teams: teams),
            _ => _EnManche(moteur: moteur, teams: teams),
          },
        ),
      ),
    );
  }
}

// --- Avant la partie -----------------------------------------------------

class _Lancement extends StatefulWidget {
  const _Lancement({required this.moteur, required this.onChangerDeJeu});
  final MoteurChronoAveugle moteur;
  final VoidCallback onChangerDeJeu;

  @override
  State<_Lancement> createState() => _LancementState();
}

class _LancementState extends State<_Lancement> {
  late int _manches = widget.moteur.manchesPrevues;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Chrono aveugle', style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        SizedBox(
          width: 620,
          child: Text(
            "Une durée est tirée au sort et annoncée. Vous donnez le top, puis "
            "plus rien ne bouge : chacun pèse quand il croit y être, et le plus "
            "proche remporte la manche.",
            style: BSType.body(size: 17, color: BSColors.neutral700),
          ),
        ),
        const SizedBox(height: BSSpace.s2),
        Text(
          "Aucune connaissance demandée : petits et grands sont à égalité.",
          style: BSType.body(size: 15, color: BSColors.neutral600),
        ),
        const SizedBox(height: BSSpace.s3),
        BSGhostButton(label: 'Changer de jeu', onPressed: widget.onChangerDeJeu),
        const SizedBox(height: BSSpace.s4),
        Container(height: 2, color: BSColors.text),
        const SizedBox(height: BSSpace.s4),

        Text('COMBIEN DE MANCHES', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s3),
        Row(
          children: [
            BSSecondaryButton(
              label: '-',
              onPressed: _manches <= 1 ? null : () => setState(() => _manches--),
            ),
            SizedBox(
              width: 110,
              child: Center(
                child:
                    Text('$_manches', style: BSType.buzzerNameConsole(size: 26)),
              ),
            ),
            BSSecondaryButton(
              label: '+',
              onPressed:
                  _manches >= 20 ? null : () => setState(() => _manches++),
            ),
          ],
        ),
        if (widget.moteur.aUnRecord) ...[
          const SizedBox(height: BSSpace.s4),
          Text('Record du buzzer : ${widget.moteur.record} ms d\'écart',
              style: BSType.body(size: 15, color: BSColors.neutral600)),
        ],
        const SizedBox(height: BSSpace.s6),
        BSPrimaryButton(
          label: 'Lancer la partie',
          grand: true,
          onPressed: widget.moteur.compteDeJoueursValide
              ? () => widget.moteur.demarrer(manches: _manches)
              : null,
        ),
        if (!widget.moteur.compteDeJoueursValide) ...[
          const SizedBox(height: BSSpace.s2),
          Text('Aucun buzzer branché.',
              style: BSType.body(size: 15, color: BSColors.neutral600)),
        ],
      ],
    );
  }
}

// --- Pendant la partie ---------------------------------------------------

class _EnManche extends StatelessWidget {
  const _EnManche({required this.moteur, required this.teams});
  final MoteurChronoAveugle moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('CHRONO AVEUGLE', style: BSType.sectionKicker()),
            const Spacer(),
            Text(
              moteur.brisEgalite
                  ? "Bris d'égalité"
                  : moteur.manchesPrevues > 0
                      ? 'Manche ${moteur.manche} sur ${moteur.manchesPrevues}'
                      : 'Manche ${moteur.manche}',
              style: BSType.body(
                  size: 13,
                  color: moteur.brisEgalite
                      ? BSColors.accent2_700
                      : BSColors.neutral600),
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s2),
        switch (moteur.etape) {
          EtapeChronoAveugle.annonce => _Annonce(moteur: moteur),
          EtapeChronoAveugle.course => _Course(moteur: moteur, teams: teams),
          _ => _Resultat(moteur: moteur, teams: teams),
        },
        const SizedBox(height: BSSpace.s6),
        Container(height: 1, color: BSColors.divider),
        const SizedBox(height: BSSpace.s3),
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            if (moteur.meilleurEcart != null)
              Text('Meilleur écart de la partie : ${moteur.meilleurEcart} ms',
                  style: BSType.body(size: 15, color: BSColors.neutral600)),
            const Spacer(),
            BSGhostButton(
                label: 'Terminer la partie', onPressed: moteur.terminer),
          ],
        ),
      ],
    );
  }
}

class _Annonce extends StatelessWidget {
  const _Annonce({required this.moteur});
  final MoteurChronoAveugle moteur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('La cible', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        Text('${moteur.cibleSecondes} secondes',
            style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s3),
        Text(
          'Annoncez-la à voix haute, puis donnez le top.',
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s4),
        BSPrimaryButton(
          label: 'Top, ça part',
          grand: true,
          onPressed: moteur.donnerLeDepart,
        ),
      ],
    );
  }
}

class _Course extends StatelessWidget {
  const _Course({required this.moteur, required this.teams});
  final MoteurChronoAveugle moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final enAttente = [
      for (var i = 0; i < 4; i++)
        if (moteur.presents[i] && moteur.temps[i] == null) i
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${moteur.cibleSecondes} secondes',
            style: BSType.questionConsole().copyWith(color: BSColors.accent2)),
        const SizedBox(height: BSSpace.s3),
        // LE TEMPS ÉCOULÉ N'EST PAS AFFICHÉ, même ici : un animateur qui le
        // lit finit par le laisser paraître sur son visage, et la salle
        // regarde son visage.
        Text(
          enAttente.isEmpty
              ? 'Tout le monde a pesé.'
              : "Personne ne voit le temps passer, vous non plus.",
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s4),
        Text('ENCORE EN LICE', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        Wrap(
          spacing: BSSpace.s3,
          runSpacing: BSSpace.s2,
          children: [
            for (var i = 0; i < 4; i++)
              if (moteur.presents[i])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      color: moteur.temps[i] == null
                          ? kBuzzerColors[i].fill
                          : BSColors.neutral300,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      moteur.temps[i] == null
                          ? teams.nameFor(i)
                          : '${teams.nameFor(i)} a pesé',
                      style: BSType.body(
                        size: 15,
                        color: moteur.temps[i] == null
                            ? BSColors.text
                            : BSColors.neutral500,
                      ),
                    ),
                    const SizedBox(width: BSSpace.s3),
                  ],
                ),
          ],
        ),
      ],
    );
  }
}

class _Resultat extends StatelessWidget {
  const _Resultat({required this.moteur, required this.teams});
  final MoteurChronoAveugle moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final qui = moteur.gagnant;
    final derniere =
        moteur.manchesPrevues > 0 && moteur.manche >= moteur.manchesPrevues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cible : ${moteur.cibleSecondes} secondes',
            style: BSType.body(size: 15, color: BSColors.neutral600)),
        const SizedBox(height: BSSpace.s2),
        if (qui != null) ...[
          Row(
            children: [
              Container(width: 52, height: 52, color: kBuzzerColors[qui].fill),
              const SizedBox(width: BSSpace.s3),
              Text(teams.nameFor(qui),
                  style: BSType.buzzerNameConsole(size: 38)),
            ],
          ),
          const SizedBox(height: BSSpace.s2),
          Text('${moteur.ecartGagnant} ms d\'écart',
              style: BSType.buzzerNameConsole(
                  size: 26, color: BSColors.accent2_700)),
        ] else
          Text("Personne n'a pesé", style: BSType.buzzerNameConsole(size: 28)),
        const SizedBox(height: BSSpace.s4),
        // Le détail de chacun : c'est ce qui fait rire, et c'est ce que
        // l'animateur lit à voix haute.
        for (var i = 0; i < 4; i++)
          if (moteur.presents[i])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(width: 12, height: 12, color: kBuzzerColors[i].fill),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: Text(teams.nameFor(i),
                        style:
                            BSType.body(size: 15, color: BSColors.neutral700)),
                  ),
                  Text(
                    moteur.temps[i] == null
                        ? "n'a pas pesé"
                        : '${(moteur.temps[i]! / 1000).toStringAsFixed(2)} s '
                            '(${moteur.ecartDe(i)} ms)',
                    style: BSType.body(size: 15, color: BSColors.text),
                  ),
                ],
              ),
            ),
        const SizedBox(height: BSSpace.s4),
        BSPrimaryButton(
          label: derniere ? 'Voir le résultat' : 'Manche suivante',
          grand: true,
          onPressed: moteur.continuer,
        ),
      ],
    );
  }
}

class _TableauScores extends StatelessWidget {
  const _TableauScores({required this.moteur, required this.teams});
  final MoteurChronoAveugle moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          if (moteur.presents[i])
            Padding(
              padding: const EdgeInsets.only(right: BSSpace.s6),
              child: Row(
                children: [
                  Container(width: 14, height: 14, color: kBuzzerColors[i].fill),
                  const SizedBox(width: 6),
                  Text(teams.nameFor(i),
                      style: BSType.body(size: 15, color: BSColors.neutral700)),
                  const SizedBox(width: 8),
                  Text('${moteur.scores[i]}',
                      style: BSType.buzzerNameConsole(size: 22)),
                ],
              ),
            ),
      ],
    );
  }
}

// --- Après la partie -----------------------------------------------------

class _FinDePartie extends StatelessWidget {
  const _FinDePartie({required this.moteur, required this.teams});
  final MoteurChronoAveugle moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final qui = moteur.vainqueur;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(moteur.egalite ? 'Égalité' : 'Fin de partie',
            style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s4),
        if (qui != null)
          Row(
            children: [
              Container(width: 52, height: 52, color: kBuzzerColors[qui].fill),
              const SizedBox(width: BSSpace.s3),
              Text('${teams.nameFor(qui)} gagne',
                  style: BSType.buzzerNameConsole(size: 38)),
            ],
          )
        else
          Text('Plusieurs buzzers sont à égalité.',
              style: BSType.body(size: 17, color: BSColors.neutral700)),
        if (moteur.meilleurEcart != null) ...[
          const SizedBox(height: BSSpace.s3),
          Text(
            moteur.recordBattu
                ? "Record battu : ${moteur.meilleurEcart} ms d'écart"
                : "Meilleur écart de la partie : ${moteur.meilleurEcart} ms",
            style: BSType.body(
                size: 17,
                color: moteur.recordBattu
                    ? BSColors.accent2_700
                    : BSColors.neutral600),
          ),
          if (!moteur.recordBattu && moteur.aUnRecord) ...[
            const SizedBox(height: 2),
            Text("Record du buzzer : ${moteur.record} ms",
                style: BSType.body(size: 15, color: BSColors.neutral600)),
          ],
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
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s6),
        Wrap(
          spacing: BSSpace.s4,
          runSpacing: BSSpace.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (moteur.egalite)
              BSPrimaryButton(
                label: 'Départager',
                onPressed: moteur.lancerBrisDegalite,
                grand: true,
              ),
            BSSecondaryButton(
              label: moteur.egalite ? "Accepter l'égalité" : 'Nouvelle partie',
              onPressed: moteur.retourAuMenu,
              grand: true,
            ),
          ],
        ),
      ],
    );
  }
}
