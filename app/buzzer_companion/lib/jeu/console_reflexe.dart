import 'package:flutter/material.dart';

import '../broadsheet/boutons.dart';
import '../broadsheet/tokens.dart';
import '../protocol.dart';
import '../team_names.dart';
import 'moteur_reflexe.dart';

// LA CONSOLE DE L'ANIMATEUR PENDANT UN RÉFLEXE.
//
// Elle a très peu à faire, et c'est voulu : une fois la manche lancée, tout se
// joue entre les boutons et les lumières. L'animateur regarde la salle, pas
// l'écran. Il n'y a donc rien à juger, seulement à enchaîner.

const _libellesFauxDepart = {
  FauxDepart.ecarte: (
    nom: 'Écarté de la manche',
    quoi: 'La règle du buzzer. Le fautif ne joue plus cette manche, les autres continuent.',
  ),
  FauxDepart.penalite: (
    nom: 'Pénalité',
    quoi: 'Un point en moins, mais il reste en lice. Personne ne regarde les autres jouer.',
  ),
  FauxDepart.relance: (
    nom: 'Manche relancée',
    quoi: 'Nouveau délai, personne n\'est puni. Convivial, mais ça peut traîner.',
  ),
  FauxDepart.tolere: (
    nom: 'Toléré',
    quoi: 'Les appuis avant le signal sont ignorés. Aucune faute n\'est comptée.',
  ),
};

class ConsoleReflexe extends StatelessWidget {
  const ConsoleReflexe({
    super.key,
    required this.moteur,
    required this.teams,
    required this.onChangerDeJeu,
  });

  final MoteurReflexe moteur;
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
            EtapeReflexe.repos =>
              _Lancement(moteur: moteur, onChangerDeJeu: onChangerDeJeu),
            EtapeReflexe.finie => _FinDePartie(moteur: moteur, teams: teams),
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
  final MoteurReflexe moteur;
  final VoidCallback onChangerDeJeu;

  @override
  State<_Lancement> createState() => _LancementState();
}

class _LancementState extends State<_Lancement> {
  late int _manches = widget.moteur.manchesPrevues;
  late FauxDepart _regle = widget.moteur.regleFauxDepart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Réflexe', style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        Text(
          'Les boutons s\'éteignent, un délai imprévisible passe, puis tout '
          's\'allume. Le premier à peser remporte la manche.',
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s3),
        BSGhostButton(label: 'Changer de jeu', onPressed: widget.onChangerDeJeu),
        const SizedBox(height: BSSpace.s4),
        Container(height: 2, color: BSColors.text),
        const SizedBox(height: BSSpace.s4),

        Text('COMBIEN DE MANCHES', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s3),
        _Compteur(
          valeur: _manches,
          onChange: (v) => setState(() => _manches = v),
        ),
        const SizedBox(height: BSSpace.s6),

        // LE FAUX DÉPART EST LE SEUL VRAI RÉGLAGE de ce jeu. Les quatre
        // conduites font des soirées différentes, et aucune n'est meilleure :
        // c'est la salle qui décide, pas le code.
        Text('UN APPUI AVANT LE SIGNAL', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        for (final entree in _libellesFauxDepart.entries) ...[
          _CarteRegle(
            nom: entree.value.nom,
            quoi: entree.value.quoi,
            choisi: _regle == entree.key,
            onTap: () => setState(() => _regle = entree.key),
          ),
          const SizedBox(height: BSSpace.s2),
        ],

        const SizedBox(height: BSSpace.s6),
        BSPrimaryButton(
          label: 'Lancer la partie',
          grand: true,
          onPressed: widget.moteur.aucunJoueur
              ? null
              : () => widget.moteur.demarrer(manches: _manches, regle: _regle),
        ),
        if (widget.moteur.aucunJoueur) ...[
          const SizedBox(height: BSSpace.s2),
          Text('Aucun buzzer en jeu.',
              style: BSType.body(size: 15, color: BSColors.neutral600)),
        ],
      ],
    );
  }
}

class _CarteRegle extends StatelessWidget {
  const _CarteRegle({
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
        padding: const EdgeInsets.symmetric(
            horizontal: BSSpace.s3, vertical: BSSpace.s3),
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

class _Compteur extends StatelessWidget {
  const _Compteur({required this.valeur, required this.onChange});
  final int valeur;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BSSecondaryButton(
          label: '-',
          onPressed: valeur <= 1 ? null : () => onChange(valeur - 1),
        ),
        SizedBox(
          width: 110,
          child: Center(
            child: Text('$valeur', style: BSType.buzzerNameConsole(size: 26)),
          ),
        ),
        BSSecondaryButton(
          label: '+',
          onPressed: valeur >= 20 ? null : () => onChange(valeur + 1),
        ),
      ],
    );
  }
}

// --- Pendant la partie ---------------------------------------------------

class _EnManche extends StatelessWidget {
  const _EnManche({required this.moteur, required this.teams});
  final MoteurReflexe moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('RÉFLEXE', style: BSType.sectionKicker()),
            const Spacer(),
            Text(
              moteur.manchesPrevues > 0
                  ? 'Manche ${moteur.manche} sur ${moteur.manchesPrevues}'
                  : 'Manche ${moteur.manche}',
              style: BSType.body(size: 13, color: BSColors.neutral600),
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s2),
        switch (moteur.etape) {
          EtapeReflexe.attente => _Attente(moteur: moteur, teams: teams),
          EtapeReflexe.signal => _Signal(moteur: moteur),
          _ => _Resultat(moteur: moteur, teams: teams),
        },
        const SizedBox(height: BSSpace.s6),
        Container(height: 1, color: BSColors.divider),
        const SizedBox(height: BSSpace.s3),
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            if (moteur.meilleurTemps != null)
              Text('Meilleur temps de la partie : ${moteur.meilleurTemps} ms',
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

class _Attente extends StatelessWidget {
  const _Attente({required this.moteur, required this.teams});
  final MoteurReflexe moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final fautifs = [
      for (var i = 0; i < 4; i++)
        if (moteur.fautifs[i]) i
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Le signal va tomber', style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        Text(
          'Ne dites rien : le délai est imprévisible, et l\'annoncer '
          'gâcherait la manche.',
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        if (fautifs.isNotEmpty) ...[
          const SizedBox(height: BSSpace.s4),
          Text('FAUX DÉPART', style: BSType.sectionKicker()),
          const SizedBox(height: BSSpace.s2),
          Wrap(
            spacing: BSSpace.s3,
            runSpacing: BSSpace.s2,
            children: [
              for (final i in fautifs)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 14, color: kBuzzerColors[i].fill),
                    const SizedBox(width: 6),
                    Text(
                      moteur.enLice[i]
                          ? '${teams.nameFor(i)} (pénalisé)'
                          : '${teams.nameFor(i)} (écarté)',
                      style: BSType.body(size: 15, color: BSColors.accent2_700),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Signal extends StatelessWidget {
  const _Signal({required this.moteur});
  final MoteurReflexe moteur;

  @override
  Widget build(BuildContext context) {
    return Text('Maintenant !',
        style: BSType.questionConsole().copyWith(color: BSColors.accent2));
  }
}

class _Resultat extends StatelessWidget {
  const _Resultat({required this.moteur, required this.teams});
  final MoteurReflexe moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final qui = moteur.gagnant;
    final derniere = moteur.manchesPrevues > 0 &&
        moteur.manche >= moteur.manchesPrevues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (qui != null) ...[
          Row(
            children: [
              Container(width: 52, height: 52, color: kBuzzerColors[qui].fill),
              const SizedBox(width: BSSpace.s3),
              Text(teams.nameFor(qui), style: BSType.buzzerNameConsole(size: 38)),
            ],
          ),
          const SizedBox(height: BSSpace.s2),
          Text('${moteur.tempsGagnant} ms',
              style: BSType.buzzerNameConsole(size: 30, color: BSColors.accent2_700)),
        ] else
          Text(
            moteur.fautifs.any((f) => f)
                ? 'Manche nulle : tout le monde s\'est brûlé'
                : 'Personne n\'a pesé',
            style: BSType.buzzerNameConsole(size: 28),
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
  final MoteurReflexe moteur;
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
  final MoteurReflexe moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final qui = moteur.meneur;
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
        if (moteur.meilleurTemps != null) ...[
          const SizedBox(height: BSSpace.s3),
          Text('Meilleur temps de la soirée : ${moteur.meilleurTemps} ms',
              style: BSType.body(size: 17, color: BSColors.neutral600)),
        ],
        const SizedBox(height: BSSpace.s6),
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s6),
        BSPrimaryButton(
            label: 'Nouvelle partie',
            grand: true,
            onPressed: moteur.retourAuMenu),
      ],
    );
  }
}
