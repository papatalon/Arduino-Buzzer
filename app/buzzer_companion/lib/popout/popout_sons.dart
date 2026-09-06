import 'package:flutter/material.dart';

import '../broadsheet/tokens.dart';
import '../protocol.dart';
import 'popout_snapshot.dart';

// LE CHOIX DES SONS, VU DE LA SALLE.
//
// Trois moments qui se passaient jusqu'ici entièrement sur la console : le
// rappel des sons, le mélange animé, et la grille ouverte pendant qu'une
// équipe choisit le sien. Les trois concernent d'abord les JOUEURS, et ils
// n'en voyaient rien : ils regardaient l'animateur cliquer, puis un son
// sortait. La roue qui ralentit ne vaut la peine d'être animée que si la
// salle la voit ralentir.
//
// Rien ici ne se commande : comme tout le reste du pop-out, c'est de
// l'état poussé par la console.
class ZoneDesSons extends StatelessWidget {
  const ZoneDesSons({super.key, required this.vue, required this.snapshot});

  final VueDesSons vue;
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    // Un seul des trois à la fois. L'ordre départage les cas limites : un
    // rappel lancé pendant qu'une grille traîne ouverte passe devant, parce
    // que c'est lui qui fait du bruit.
    if (vue.rappel != null) {
      return _Rappel(index: vue.rappel!, snapshot: snapshot);
    }
    if (vue.melange || vue.revelation) {
      return _Melange(vue: vue, snapshot: snapshot);
    }
    return _Grille(vue: vue, snapshot: snapshot);
  }
}

// Rappel des sons : le son d'une équipe joue, la salle voit de qui il s'agit.
class _Rappel extends StatelessWidget {
  const _Rappel({required this.index, required this.snapshot});

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

// LE MÉLANGE, EN DIRECT.
//
// Exactement ce que la console montre au même instant : la rangée que le
// chenillard éclaire ressort, les autres s'effacent, et les noms défilent au
// rythme de la roue. Les lumières de la table, l'écran de l'animateur et
// celui de la salle racontent ainsi la même chose à la seconde près.
class _Melange extends StatelessWidget {
  const _Melange({required this.vue, required this.snapshot});

  final VueDesSons vue;
  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final enJeu = [
      for (var i = 0; i < kBuzzerColors.length; i++)
        if (i < snapshot.present.length && snapshot.present[i]) i,
    ];
    // La roue s'est arrêtée : plus rien ne bouge, tout se lit d'un coup.
    final fige = vue.revelation;
    return Padding(
      padding: const EdgeInsets.fromLTRB(80, 40, 80, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fige ? 'VOICI VOS SONS' : 'MÉLANGE DES SONS',
            textAlign: TextAlign.center,
            style: BSType.popoutHeaderMeta(
              color: fige ? BSColors.accent2_700 : BSColors.neutral600,
            ),
          ),
          const SizedBox(height: BSSpace.s8),
          for (final i in enJeu)
            Expanded(
              child: _RangeeMelange(
                index: i,
                nom: i < vue.melangeNoms.length ? vue.melangeNoms[i] : '',
                equipe: snapshot.teamName(i),
                // Pendant que la roue tourne, seule la rangée allumée est
                // lisible : c'est le buzzer dont la LED est allumée sur la
                // table au même instant.
                allumee: fige || vue.melangeAllume == i,
                fige: fige,
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeeMelange extends StatelessWidget {
  const _RangeeMelange({
    required this.index,
    required this.nom,
    required this.equipe,
    required this.allumee,
    required this.fige,
  });

  final int index;
  final String nom;
  final String equipe;
  final bool allumee;
  final bool fige;

  @override
  Widget build(BuildContext context) {
    final couleur = kBuzzerColors[index];
    return Opacity(
      opacity: allumee ? 1 : 0.22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            color: allumee ? couleur.fill : BSColors.neutral300,
          ),
          const SizedBox(width: BSSpace.s4),
          SizedBox(
            width: 380,
            child: Text(
              equipe.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BSType.buzzerNamePopout(color: couleur.fill).copyWith(fontSize: 40),
            ),
          ),
          const SizedBox(width: BSSpace.s6),
          // Aligné à GAUCHE, tout de suite après le nom d'équipe : aligné à
          // droite, un nom court se retrouvait à mille pixels de l'équipe à
          // qui il appartient, et l'œil ne faisait plus la paire.
          Expanded(
            child: Text(
              nom.isEmpty ? '...' : nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BSType.heroDigitPopout(
                size: 52,
                color: fige ? BSColors.accent2_800 : BSColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// LA GRILLE, PENDANT QU'UNE ÉQUIPE CHOISIT.
//
// C'est la personne qui choisit qui a besoin de la voir, pas l'animateur :
// lui a déjà la sienne sous la souris. Le NUMÉRO passe donc devant le nom,
// parce que c'est ce qu'on se dit à voix haute d'un bout à l'autre de la
// salle (« fais-moi entendre le 14 »). Le nom complet du son retenu se lit
// en entier dans le bandeau du haut, où il a la place.
class _Grille extends StatelessWidget {
  const _Grille({required this.vue, required this.snapshot});

  final VueDesSons vue;
  final PopoutSnapshot snapshot;

  // Quatre colonnes tant que la bibliothèque tient dessus. Au-delà, on en
  // ajoute plutôt que d'allonger la grille vers le bas : la hauteur est ce
  // qui manque, et une tuile plus étroite reste lisible là où une grille
  // rétrécie ne l'est plus.
  static int _colonnes(int total) => total > 36 ? 5 : 4;

  @override
  Widget build(BuildContext context) {
    final pour = vue.grilleBuzzer;
    if (pour == null || pour < 0 || pour >= kBuzzerColors.length) {
      return const SizedBox.shrink();
    }
    final couleur = kBuzzerColors[pour];
    final sons = vue.grilleSons;
    final choisi = pour < vue.grilleAssignation.length ? vue.grilleAssignation[pour] : -1;

    final colonnes = _colonnes(sons.length);
    final rangees = (sons.length / colonnes).ceil();
    const largeurTuile = 336.0;
    const hauteurTuile = 58.0;
    const espace = 10.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 24, 52, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(width: 30, height: 30, color: couleur.fill),
              const SizedBox(width: BSSpace.s3),
              // Le nom d'équipe et la consigne restent deux morceaux : « Les
              // Bleuets choisit son son » se lit mal, et un nom d'équipe peut
              // être au pluriel comme au singulier. Séparés, la phrase tient
              // dans les deux cas.
              Text(
                snapshot.teamName(pour).toUpperCase(),
                style: BSType.popoutHeaderMeta(color: couleur.fill),
              ),
              const SizedBox(width: BSSpace.s3),
              Text(
                '·  CHOISIS TON SON',
                style: BSType.popoutHeaderMeta(color: BSColors.neutral600),
              ),
            ],
          ),
          const SizedBox(height: BSSpace.s2),
          // SUR SA PROPRE LIGNE, et non au bout de la précédente : les noms de
          // fichiers sont longs, et à droite d'une consigne il ne restait la
          // place que pour deux lettres. C'est pourtant la seule ligne de
          // l'écran où le son retenu se lit EN ENTIER, les tuiles n'ayant que
          // la largeur d'une colonne.
          Text(
            choisi >= 0 && choisi < sons.length
                ? 'PRÉSENTEMENT : ${choisi + 1} · ${sons[choisi]}'
                : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BSType.popoutHeaderMeta(color: BSColors.neutral700),
          ),
          const SizedBox(height: BSSpace.s3),
          Expanded(
            // La grille garde ses proportions et rapetisse en bloc si la
            // bibliothèque grossit un jour au-delà de ce que le châssis
            // peut montrer. Mieux vaut tout voir un peu plus petit que
            // devoir faire défiler une page projetée.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: colonnes * largeurTuile + (colonnes - 1) * espace,
                height: rangees * hauteurTuile + (rangees - 1) * espace,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: colonnes,
                    mainAxisExtent: hauteurTuile,
                    crossAxisSpacing: espace,
                    mainAxisSpacing: espace,
                  ),
                  itemCount: sons.length,
                  itemBuilder: (context, i) {
                    // Un son déjà porté par une autre équipe reste
                    // choisissable : on le signale, on ne le barre pas.
                    int? prisPar;
                    for (var b = 0; b < kBuzzerColors.length; b++) {
                      if (b != pour &&
                          b < vue.grilleAssignation.length &&
                          vue.grilleAssignation[b] == i) {
                        prisPar = b;
                      }
                    }
                    return _TuileSon(
                      numero: i + 1,
                      nom: sons[i],
                      couleur: couleur,
                      choisi: i == choisi,
                      prisPar: prisPar,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TuileSon extends StatelessWidget {
  const _TuileSon({
    required this.numero,
    required this.nom,
    required this.couleur,
    required this.choisi,
    required this.prisPar,
  });

  final int numero;
  final String nom;
  final BuzzerColor couleur;
  final bool choisi;
  final int? prisPar;

  @override
  Widget build(BuildContext context) {
    // Le son retenu est peint AUX COULEURS DU BUZZER, pas juste souligné :
    // de vingt pieds, un liseré ne se voit pas.
    final fond = choisi ? couleur.fill : null;
    final encre = choisi ? couleur.onFill : BSColors.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: BSSpace.s2, vertical: 4),
      decoration: BoxDecoration(
        color: fond,
        border: Border(
          top: BorderSide(color: choisi ? couleur.fill : BSColors.divider, width: 3),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              '$numero',
              textAlign: TextAlign.right,
              style: BSType.buzzerNamePopout(color: choisi ? encre : BSColors.neutral600),
            ),
          ),
          const SizedBox(width: BSSpace.s2),
          Expanded(
            child: Text(
              nom.isEmpty ? 'Son $numero' : nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BSType.body(size: 26, color: encre),
            ),
          ),
          if (prisPar != null) ...[
            const SizedBox(width: BSSpace.s1),
            Container(width: 14, height: 14, color: kBuzzerColors[prisPar!].fill),
          ],
        ],
      ),
    );
  }
}
