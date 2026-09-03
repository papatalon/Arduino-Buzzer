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
    quoi: "Les appuis avant le signal sont ignorés. Aucune faute n'est comptée.",
  ),
  FauxDepart.offreLaManche: (
    nom: "La manche va à l'adversaire",
    quoi: "La règle du Duel. Celui qui anticipe offre la manche à l'autre, "
        "qui n'a rien besoin de faire.",
  ),
  FauxDepart.elimine: (
    nom: 'Éliminé de la partie',
    quoi: "Le plus dur : une seule anticipation et la soirée est finie. S'il ne "
        "reste qu'un joueur, il gagne sur-le-champ.",
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
            EtapeReflexe.repos => _Lancement(
                moteur: moteur,
                teams: teams,
                onChangerDeJeu: onChangerDeJeu),
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
  const _Lancement({
    required this.moteur,
    required this.teams,
    required this.onChangerDeJeu,
  });
  final MoteurReflexe moteur;
  final TeamNames teams;
  final VoidCallback onChangerDeJeu;

  @override
  State<_Lancement> createState() => _LancementState();
}

class _LancementState extends State<_Lancement> {
  late int _manches = widget.moteur.manchesPrevues;
  late FauxDepart _regle = widget.moteur.regleFauxDepart;

  /// LES DUELLISTES SE DESIGNENT, ils ne se retirent pas.
  ///
  /// La liste part VIDE : « Qui se bat ? » pose un choix positif, et
  /// commencer avec tout le monde coche transformait la reponse en
  /// elimination. Un troisieme clic remplace le plus ancien plutot que
  /// d'etre refuse : refuser oblige a decocher d'abord, pour rien.
  ///
  /// Rien n'est applique au moteur avant « Lancer la partie » : cet ecran
  /// est un formulaire, pas une telecommande.
  final List<int> _duellistes = [];

  @override
  void initState() {
    super.initState();
    // Le Duel n'a qu'une regle de faux depart : la reprendre du moteur
    // laisserait une regle de Reflexe selectionnee et invisible.
    if (widget.moteur.jeu == JeuDeVitesse.duel) {
      _regle = FauxDepart.offreLaManche;
    } else if (_regle == FauxDepart.offreLaManche) {
      _regle = FauxDepart.ecarte;
    }
  }

  bool get _estDuel => widget.moteur.jeu == JeuDeVitesse.duel;

  // Au Duel, il en faut exactement deux ; au Reflexe, au moins un buzzer
  // branche suffit.
  bool get _pret => _estDuel
      ? _duellistes.length == 2
      : widget.moteur.presentsMateriel.any((p) => p);

  void _basculerDuelliste(int i) {
    setState(() {
      if (_duellistes.remove(i)) return;
      // Le troisieme chasse le plus ancien : on comprend tout de suite qu'on
      // vient de changer d'avis, sans avoir a decocher.
      if (_duellistes.length >= 2) _duellistes.removeAt(0);
      _duellistes.add(i);
    });
  }

  void _lancer() {
    if (_estDuel) {
      widget.moteur.retenirSelection([
        for (var i = 0; i < 4; i++) _duellistes.contains(i),
      ]);
    }
    widget.moteur.demarrer(manches: _manches, regle: _regle);
  }

  @override
  Widget build(BuildContext context) {
    final duel = _estDuel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(duel ? 'Duel' : 'Réflexe', style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        Text(
          duel
              ? "Un son part au hasard. Le premier des deux duellistes a peser "
                  "remporte la manche. Ils peuvent jouer dos à dos, les yeux "
                  "fermés."
              : "Les boutons s'éteignent, un délai imprévisible passe, puis "
                  "tout s'allume. Le premier à peser remporte la manche.",
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s3),
        BSGhostButton(label: 'Changer de jeu', onPressed: widget.onChangerDeJeu),
        const SizedBox(height: BSSpace.s4),
        Container(height: 2, color: BSColors.text),
        const SizedBox(height: BSSpace.s4),

        // LES DUELLISTES SE CHOISISSENT ICI, et pour cette partie seulement.
        // L'ecran Buzzers dit qui est BRANCHE ; ici on dit qui joue. Passer
        // par la-bas pour retirer deux buzzers, puis les remettre apres, serait
        // un detour absurde pour une manche.
        if (duel) ...[
          Text('QUI SE BAT', style: BSType.sectionKicker()),
          const SizedBox(height: BSSpace.s2),
          _ChoixDuellistes(
            moteur: widget.moteur,
            teams: widget.teams,
            retenus: _duellistes,
            onBascule: _basculerDuelliste,
          ),
          const SizedBox(height: BSSpace.s6),
        ],

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
        // « Offre la manche » ne se propose QU'AU DUEL : a trois ou quatre,
        // offrir la manche « a l'adversaire » ne veut rien dire. Et le Duel ne
        // propose que celle-la : c'est sa regle sur le buzzer.
        for (final entree in _libellesFauxDepart.entries.where((e) =>
            duel
                ? e.key == FauxDepart.offreLaManche
                : e.key != FauxDepart.offreLaManche)) ...[
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
          onPressed: _pret ? _lancer : null,
        ),
        if (!_pret) ...[
          const SizedBox(height: BSSpace.s2),
          Text(
            duel
                ? 'Désignez les deux duellistes.'
                : 'Aucun buzzer branché.',
            style: BSType.body(size: 15, color: BSColors.neutral600),
          ),
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
            Text(moteur.jeu == JeuDeVitesse.duel ? 'DUEL' : 'RÉFLEXE',
                style: BSType.sectionKicker()),
            const Spacer(),
            Text(
              // Un bris se joue en plus des manches prevues : le compter
              // donnerait « manche 3 sur 2 ».
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
        if (moteur.gagnantParElimination != null) ...[
          const SizedBox(height: BSSpace.s2),
          Text(
            "Il reste seul en lice : les autres se sont éliminés sur un faux "
            "départ.",
            style: BSType.body(size: 17, color: BSColors.accent2_700),
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
        if (moteur.meilleurTemps != null) ...[
          const SizedBox(height: BSSpace.s3),
          Text(
            moteur.recordBattu
                ? 'Record battu : ${moteur.meilleurTemps} ms'
                : 'Meilleur temps de la partie : ${moteur.meilleurTemps} ms',
            style: BSType.body(
                size: 17,
                color: moteur.recordBattu
                    ? BSColors.accent2_700
                    : BSColors.neutral600),
          ),
          // Le record du buzzer, pas celui de cette soiree : il vit en EEPROM
          // et vaut aussi pour les parties jouees au clavier.
          if (!moteur.recordBattu && moteur.aUnRecord) ...[
            const SizedBox(height: 2),
            Text('Record du buzzer : ${moteur.record} ms',
                style: BSType.body(size: 15, color: BSColors.neutral600)),
          ],
        ],
        const SizedBox(height: BSSpace.s6),
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s6),
        // SUR UNE EGALITE, C'EST L'ANIMATEUR QUI DECIDE. Une soiree peut tres
        // bien se terminer a egalite ; forcer une manche de plus a des gens
        // qui rangent deja leurs manteaux serait penible.
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

// Les deux duellistes, choisis pour la partie en cours.
//
// Un buzzer débranché ne s'affiche pas : on ne peut pas faire jouer ce qui
// n'est pas là, et l'estomper poserait une question à laquelle l'écran ne
// répond pas. Pour le rebrancher, c'est l'écran Buzzers.
class _ChoixDuellistes extends StatelessWidget {
  const _ChoixDuellistes({
    required this.moteur,
    required this.teams,
    required this.retenus,
    required this.onBascule,
  });

  final MoteurReflexe moteur;
  final TeamNames teams;
  final List<int> retenus;
  final ValueChanged<int> onBascule;

  @override
  Widget build(BuildContext context) {
    final branches = [
      for (var i = 0; i < 4; i++)
        if (moteur.presentsMateriel[i]) i
    ];
    if (branches.isEmpty) {
      return Text('Aucun buzzer branché.',
          style: BSType.body(size: 15, color: BSColors.neutral600));
    }
    return Wrap(
      spacing: BSSpace.s2,
      runSpacing: BSSpace.s2,
      children: [
        for (final i in branches)
          InkWell(
            onTap: () => onBascule(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: retenus.contains(i)
                    ? BSColors.accent100
                    : Colors.transparent,
                border: Border.all(
                  color:
                      retenus.contains(i) ? BSColors.accent : BSColors.divider,
                  width: retenus.contains(i) ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    color: retenus.contains(i)
                        ? kBuzzerColors[i].fill
                        : BSColors.neutral300,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    teams.nameFor(i),
                    style: BSType.body(
                      size: 15,
                      color: retenus.contains(i)
                          ? BSColors.text
                          : BSColors.neutral600,
                    ).copyWith(
                        fontWeight: retenus.contains(i)
                            ? FontWeight.w600
                            : FontWeight.normal),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
