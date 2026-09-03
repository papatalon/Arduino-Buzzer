import 'package:flutter/material.dart';

import '../broadsheet/boutons.dart';
import '../broadsheet/tokens.dart';
import '../protocol.dart';
import '../team_names.dart';
import 'moteur_ne_buzze_pas.dart';

// LA CONSOLE PENDANT « NE BUZZE PAS ».
//
// L'animateur a trois choses à faire : lancer, guider l'écoute, donner le
// départ du flux. Ensuite il n'a plus qu'à regarder — et à lire les points, qui
// bougent dans les deux sens à chaque son.
class ConsoleNeBuzzePas extends StatelessWidget {
  const ConsoleNeBuzzePas({
    super.key,
    required this.moteur,
    required this.teams,
    required this.nombreDeSons,
    required this.onChangerDeJeu,
  });

  final MoteurNeBuzzePas moteur;
  final TeamNames teams;

  /// Combien de sons la sortie choisie propose : la bibliothèque de
  /// l'application, ou la carte SD du buzzer.
  final int nombreDeSons;

  final VoidCallback onChangerDeJeu;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: moteur,
      builder: (context, _) => SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: switch (moteur.etape) {
            EtapeNeBuzzePas.repos => _Lancement(
                moteur: moteur,
                nombreDeSons: nombreDeSons,
                onChangerDeJeu: onChangerDeJeu),
            EtapeNeBuzzePas.ecoute => _Ecoute(moteur: moteur, teams: teams),
            EtapeNeBuzzePas.flux => _Flux(moteur: moteur, teams: teams),
            EtapeNeBuzzePas.finie =>
              _FinDePartie(moteur: moteur, teams: teams),
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
    required this.nombreDeSons,
    required this.onChangerDeJeu,
  });

  final MoteurNeBuzzePas moteur;
  final int nombreDeSons;
  final VoidCallback onChangerDeJeu;

  @override
  State<_Lancement> createState() => _LancementState();
}

class _LancementState extends State<_Lancement> {
  late int _chances = widget.moteur.chancesParBuzzer;
  late bool _leurres = widget.moteur.avecLeurres;

  int get _joueurs => widget.moteur.presents.where((p) => p).length;
  int get _joueursTours => _chances * _joueurs;

  /// Les leurres sont tires au sort au lancement ; pour l'apercu on prend le
  /// milieu de la fourchette, sinon la duree annoncee sauterait a chaque clic.
  int get _totalEstime =>
      _joueursTours +
      (_leurres
          ? (_joueursTours *
                  (MoteurNeBuzzePas.leurresMinPourCent +
                      MoteurNeBuzzePas.leurresMaxPourCent) /
                  200)
              .round()
          : 0);

  @override
  Widget build(BuildContext context) {
    // Quatre sons différents au minimum, sinon deux joueurs auraient le même
    // et la partie serait injouable.
    final assezDeSons = widget.nombreDeSons >= 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Ne buzze pas', style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        SizedBox(
          width: 620,
          child: Text(
            "Des sons s'enchaînent, de plus en plus serrés. Il faut peser "
            "quand c'est le sien, et surtout pas quand c'est celui d'un autre.",
            style: BSType.body(size: 17, color: BSColors.neutral700),
          ),
        ),
        const SizedBox(height: BSSpace.s2),
        SizedBox(
          width: 620,
          child: Text(
            "Les sons sont tirés au sort pour chaque partie : personne ne peut "
            "arriver en connaissant le sien.",
            style: BSType.body(size: 15, color: BSColors.accent700),
          ),
        ),
        const SizedBox(height: BSSpace.s3),
        BSGhostButton(label: 'Changer de jeu', onPressed: widget.onChangerDeJeu),
        const SizedBox(height: BSSpace.s4),
        Container(height: 2, color: BSColors.text),
        const SizedBox(height: BSSpace.s4),

        // LES CHANCES PAR BUZZER, pas le nombre de tours.
        //
        // C'est le reglage qui garantit l'equite : chaque buzzer present
        // obtient exactement ce nombre de tours. Le total en decoule et
        // s'affiche a cote, parce que c'est lui qui dit combien de temps ca
        // dure, et il change quand quelqu'un se retire.
        Text('CHANCES PAR BUZZER', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s3),
        Row(
          children: [
            BSSecondaryButton(
              label: '-1',
              onPressed:
                  _chances <= 2 ? null : () => setState(() => _chances -= 1),
            ),
            SizedBox(
              width: 140,
              child: Center(
                child: Text(
                  '$_chances',
                  style: BSType.buzzerNameConsole(size: 26),
                ),
              ),
            ),
            BSSecondaryButton(
              label: '+1',
              onPressed:
                  _chances >= 12 ? null : () => setState(() => _chances += 1),
            ),
            const SizedBox(width: BSSpace.s4),
            Text(
              _joueurs == 0
                  ? 'aucun buzzer présent'
                  : '$_joueursTours tours pour ${_joueurs == 1 ? "1 buzzer" : "$_joueurs buzzers"}'
                      '${_leurres ? ", plus les leurres" : ""}'
                      ', ${_apercuDeLaDuree(_totalEstime)}',
              style: BSType.body(size: 15, color: BSColors.neutral600),
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s2),
        Text(
          'Chaque tour est une manche, et tout le monde en a autant.',
          style: BSType.body(size: 14, color: BSColors.neutral600),
        ),
        const SizedBox(height: BSSpace.s6),

        Text('LES LEURRES', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        _LigneLeurres(
          actifs: _leurres,
          onChange: (v) => setState(() => _leurres = v),
        ),
        const SizedBox(height: BSSpace.s6),
        BSPrimaryButton(
          label: "Lancer l'écoute",
          grand: true,
          onPressed: (assezDeSons && widget.moteur.compteDeJoueursValide)
              ? () => widget.moteur.demarrer(
                    nombreDeSonsDisponibles: widget.nombreDeSons,
                    chances: _chances,
                    leurres: _leurres,
                  )
              : null,
        ),
        if (!widget.moteur.compteDeJoueursValide) ...[
          const SizedBox(height: BSSpace.s2),
          Text('Aucun buzzer branché.',
              style: BSType.body(size: 15, color: BSColors.neutral600)),
        ] else if (!assezDeSons) ...[
          const SizedBox(height: BSSpace.s2),
          Text(
            "Il faut au moins quatre sons de buzzer disponibles ; il y en a "
            "${widget.nombreDeSons}.",
            style: BSType.body(size: 15, color: BSColors.accent2_800),
          ),
        ],
      ],
    );
  }
}

class _LigneLeurres extends StatelessWidget {
  const _LigneLeurres({required this.actifs, required this.onChange});

  final bool actifs;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChange(!actifs),
      child: Container(
        width: 620,
        padding: const EdgeInsets.symmetric(
            horizontal: BSSpace.s3, vertical: BSSpace.s3),
        decoration: BoxDecoration(
          color: actifs ? BSColors.accent100 : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: actifs ? BSColors.accent : BSColors.divider,
              width: actifs ? 5 : 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(actifs ? 'Avec leurres' : 'Sans leurres',
                style: BSType.buzzerNameConsole(size: 20)),
            const SizedBox(height: 2),
            Text(
              actifs
                  ? "Des sons qui n'appartiennent à personne se glissent dans "
                      "le flux. Les pièges les plus efficaces."
                  : "Tout son joué appartient à quelqu'un.",
              style: BSType.body(size: 15, color: BSColors.neutral700),
            ),
          ],
        ),
      ),
    );
  }
}

// --- L'écoute ------------------------------------------------------------

class _Ecoute extends StatelessWidget {
  const _Ecoute({required this.moteur, required this.teams});
  final MoteurNeBuzzePas moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final qui = moteur.aQuiLeTour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('NE BUZZE PAS', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        if (qui != null) ...[
          Text('Écoute des sons', style: BSType.questionConsole()),
          const SizedBox(height: BSSpace.s4),
          // La consigne à dire à voix haute, mot pour mot : l'animateur n'a
          // pas à l'inventer à chaque tour.
          Row(
            children: [
              Container(width: 52, height: 52, color: kBuzzerColors[qui].fill),
              const SizedBox(width: BSSpace.s3),
              Text(
                moteur.sonEnEcoute
                    ? '${teams.nameFor(qui)} écoute son son'
                    : '${teams.nameFor(qui)}, appuie sur ton bouton',
                style: BSType.buzzerNameConsole(size: 30),
              ),
            ],
          ),
          const SizedBox(height: BSSpace.s3),
          Text(
            moteur.sonEnEcoute
                // On reste sur le même buzzer tant que ça joue : appeler le
                // suivant maintenant le ferait peser par-dessus, et il
                // retiendrait un mélange des deux sons.
                ? 'Laissez le son finir avant de passer au suivant.'
                : 'Un seul appui. Le son qui joue est le sien pour cette partie.',
            style: BSType.body(size: 17, color: BSColors.neutral700),
          ),
        ] else ...[
          Text('Tout le monde a entendu son son',
              style: BSType.questionConsole()),
          const SizedBox(height: BSSpace.s3),
          Text(
            "Vous pouvez refaire entendre un son avant de lancer, si quelqu'un "
            "hésite.",
            style: BSType.body(size: 17, color: BSColors.neutral700),
          ),
        ],
        const SizedBox(height: BSSpace.s6),
        Text('QUI A ENTENDU LE SIEN', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        Wrap(
          spacing: BSSpace.s3,
          runSpacing: BSSpace.s2,
          children: [
            for (var i = 0; i < 4; i++)
              if (moteur.presents[i])
                _LigneEcoute(
                  index: i,
                  nom: teams.nameFor(i),
                  faite: moteur.aEcoute[i],
                  // Le réécouter n'est offert qu'à celui qui a déjà entendu :
                  // avant, ce serait lui souffler son son hors de son tour.
                  // Et jamais pendant qu'un son joue : deux sons empilés ne
                  // s'apprennent ni l'un ni l'autre.
                  onReecouter: (moteur.aEcoute[i] && !moteur.sonEnEcoute)
                      ? () => moteur.reecouter(i)
                      : null,
                ),
          ],
        ),
        const SizedBox(height: BSSpace.s6),
        BSPrimaryButton(
          label: 'Lancer le flux',
          grand: true,
          onPressed: moteur.ecouteTerminee ? moteur.lancerLeFlux : null,
        ),
        if (!moteur.ecouteTerminee) ...[
          const SizedBox(height: BSSpace.s2),
          Text('Chacun doit avoir entendu le sien.',
              style: BSType.body(size: 15, color: BSColors.neutral600)),
        ],
      ],
    );
  }
}

class _LigneEcoute extends StatelessWidget {
  const _LigneEcoute({
    required this.index,
    required this.nom,
    required this.faite,
    required this.onReecouter,
  });

  final int index;
  final String nom;
  final bool faite;
  final VoidCallback? onReecouter;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          color: faite ? kBuzzerColors[index].fill : BSColors.neutral300,
        ),
        const SizedBox(width: 6),
        Text(nom,
            style: BSType.body(
                size: 15,
                color: faite ? BSColors.text : BSColors.neutral600)),
        if (onReecouter != null)
          BSGhostButton(label: 'Réécouter', onPressed: onReecouter),
        const SizedBox(width: BSSpace.s2),
      ],
    );
  }
}

// --- Le flux -------------------------------------------------------------

class _Flux extends StatelessWidget {
  const _Flux({required this.moteur, required this.teams});
  final MoteurNeBuzzePas moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('NE BUZZE PAS', style: BSType.sectionKicker()),
            const Spacer(),
            Text(
              moteur.sonsPrevus > 0
                  ? 'Son ${moteur.sonsJoues} sur ${moteur.sonsPrevus}'
                  : 'Son ${moteur.sonsJoues}',
              style: BSType.body(size: 13, color: BSColors.neutral600),
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s2),
        Text('Ça joue', style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        // À QUI EST LE SON N'EST PAS AFFICHÉ. L'animateur regarde la salle,
        // et son visage la renseignerait. Les points, eux, disent tout ce
        // qu'il y a à savoir une fois le son passé.
        Text(
          "Écart de ${moteur.ecartCourantMs} ms entre deux sons, et il se "
          "resserre.",
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s6),
        Container(height: 1, color: BSColors.divider),
        const SizedBox(height: BSSpace.s3),
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            const Spacer(),
            BSGhostButton(
                label: 'Terminer la partie', onPressed: moteur.terminer),
          ],
        ),
      ],
    );
  }
}

class _TableauScores extends StatelessWidget {
  const _TableauScores({required this.moteur, required this.teams});
  final MoteurNeBuzzePas moteur;
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
  final MoteurNeBuzzePas moteur;
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
        BSPrimaryButton(
          label: 'Nouvelle partie',
          grand: true,
          onPressed: moteur.retourAuMenu,
        ),
      ],
    );
  }
}

/// « environ 20 secondes » plutot que « 19 500 ms » : l'animateur decide
/// avec ca, il ne chronometre pas. Arrondi a la dizaine de secondes en bas
/// d'une minute, puis a la minute, parce qu'une precision plus fine serait
/// fausse de toute facon (les buzz coupent les ecarts).
String _apercuDeLaDuree(int sons) {
  final s = MoteurNeBuzzePas.dureeEstimee(sons).inSeconds;
  if (s < 60) return 'environ ${(s / 10).round() * 10} secondes';
  final min = (s / 60).round();
  return 'environ $min ${min > 1 ? "minutes" : "minute"}';
}
