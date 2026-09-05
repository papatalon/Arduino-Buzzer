import 'package:flutter/material.dart';

import '../questionnaires/active_questionnaire.dart';
import 'tokens.dart';

// D'OU VIENNENT LES QUESTIONS D'UNE PARTIE.
//
// Trois sources, et le choix se pose de la meme facon partout : dans l'ecran
// de lancement du moteur de jeu quand l'application mene, et dans le repli
// « Partie » quand c'est le buzzer qui mene.
//
//   Un questionnaire PERSONNALISE : celui que l'operateur a ecrit lui-meme.
//   C'est la seule chose qu'on choisit encore fichier par fichier.
//
//   Un TIRAGE : une manche composee sur place dans la banque, selon un
//   perimetre, une tranche d'age et un niveau. Voir source_hasard.dart.
//
//   Un questionnaire LIBRE : l'animateur pose ses propres questions, a voix
//   haute, et l'application ne fait que tenir les points. C'est le mode
//   d'origine du buzzer, celui d'avant l'application.
//
// LE CATALOGUE N'EST PLUS UN MENU. Ses 283 questionnaires prefaits existaient
// pour etre choisis un par un ; le tirage fait mieux, en composant une manche
// selon la piece qu'on a devant soi. Ils restent la banque dans laquelle le
// tirage pioche, et se consultent depuis l'ecran Questions, mais on ne les
// met plus en jeu tels quels : choisir « Histoire 07 sur 11 » ne veut rien
// dire pour personne.
//
// Choisir « libre » N'OUBLIE PAS le questionnaire deja choisi : on peut
// glisser une manche improvisee entre deux manches d'un questionnaire sans
// avoir a le rechoisir apres.
//
// Ces widgets vivaient en prive dans console_shell.dart. L'ecran de lancement
// du moteur en avait besoin, et j'ai commence par en ecrire une version
// appauvrie a cote, qui a fait perdre la manche libre. C'est exactement la
// duplication qui avait deja vide l'ecran public le meme jour.

// Valeur proposee quand on passe a « un nombre fixe ». Vingt questions font
// une manche d'une trentaine de minutes, ce qui correspond au plafond des
// questionnaires generes.
const kNombreLibreParDefaut = 20;

// n'est pas un Radio de Material : le design system n'a ni ses couleurs ni
// son animation, et un cercle dessiné suffit.
class ChoixLigne extends StatelessWidget {
  const ChoixLigne({
    super.key,
    required this.choisi,
    required this.titre,
    required this.detail,
    required this.onTap,
    this.action,
  });

  final bool choisi;
  final String titre;
  final String detail;
  // Null quand la ligne n'a rien a cocher : le curseur reste normal et le
  // clic ne fait rien, plutot que de declencher une action inattendue.
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 620,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: choisi ? BSColors.accent : BSColors.neutral400,
                      width: 2,
                    ),
                  ),
                  child: choisi
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: BSColors.accent,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: BSSpace.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: BSType.body(
                        size: 18,
                        color: choisi ? BSColors.text : BSColors.neutral700,
                      ).copyWith(fontWeight: choisi ? FontWeight.w600 : FontWeight.normal),
                    ),
                    Text(detail, style: BSType.body(size: 14, color: BSColors.neutral600)),
                  ],
                ),
              ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }
}

class SourceQuestionnaire extends StatelessWidget {
  const SourceQuestionnaire(
      {super.key, required this.actif, required this.onChoisir});

  final ActiveQuestionnaire actif;
  final VoidCallback onChoisir;

  @override
  Widget build(BuildContext context) {
    final aUnQuestionnaire = actif.active;
    return ChoixLigne(
      choisi: !actif.libre && aUnQuestionnaire,
      titre: aUnQuestionnaire
          ? '« ${actif.title} », ${actif.total} questions'
          : 'Un questionnaire que vous avez écrit',
      detail: aUnQuestionnaire
          ? actif.origine
          : 'Ceux de votre dossier « Personnalisé ». Pour une manche prise '
              'dans la banque, utilisez le tirage ci-dessous.',
      // Sans questionnaire choisi, cliquer la LIGNE ne fait rien : elle
      // n'aurait rien à cocher. Elle menait à la bibliothèque, et changer
      // d'écran quand on croit cocher une option est déroutant. Seul le
      // bouton « Choisir », à droite, navigue.
      onTap: aUnQuestionnaire ? actif.reprendreQuestionnaire : null,
      action: TextButton(
        onPressed: onChoisir,
        style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
        child: Text(aUnQuestionnaire ? 'Changer' : 'Choisir'),
      ),
    );
  }
}

class SourceLibre extends StatelessWidget {
  const SourceLibre({super.key, required this.actif});

  final ActiveQuestionnaire actif;

  @override
  Widget build(BuildContext context) {
    return ChoixLigne(
      choisi: actif.libre,
      titre: 'Questionnaire libre',
      detail: "Vous posez vos questions, l'application tient les points.",
      onTap: () => actif.utiliserLibre(nombre: actif.nombreLibre),
    );
  }
}

// Combien de questions pour une manche libre. Sans questionnaire, personne ne
// connaît la longueur : soit l'animateur l'annonce d'avance et la partie
// s'arrête toute seule, soit il garde la main.
class NombreLibre extends StatelessWidget {
  const NombreLibre(
      {super.key, required this.actif, required this.parDefaut});

  final ActiveQuestionnaire actif;
  final int parDefaut;

  @override
  Widget build(BuildContext context) {
    final fixe = actif.nombreLibre != null;
    final n = actif.nombreLibre ?? parDefaut;

    return Padding(
      padding: const EdgeInsets.only(left: BSSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('COMBIEN DE QUESTIONS ?', style: BSType.sectionKicker()),
          const SizedBox(height: BSSpace.s2),
          ChoixLigne(
            choisi: fixe,
            titre: 'Un nombre fixe',
            detail: "La partie se termine d'elle-même après la dernière.",
            onTap: () => actif.reglerNombreLibre(n),
            action: fixe
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PetitBouton('−', n > 1 ? () => actif.reglerNombreLibre(n - 1) : null),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '$n',
                          textAlign: TextAlign.center,
                          style: BSType.body(size: 20, color: BSColors.text)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      // Le firmware plafonne a 99 (QCOUNT_MAX) : au-dela, il
                      // ramenerait silencieusement a « ouvert ».
                      PetitBouton('+', n < 99 ? () => actif.reglerNombreLibre(n + 1) : null),
                    ],
                  )
                : null,
          ),
          const SizedBox(height: BSSpace.s2),
          ChoixLigne(
            choisi: !fixe,
            titre: 'Sans limite',
            detail: 'Vous terminez la partie quand vous voulez.',
            onTap: () => actif.reglerNombreLibre(null),
          ),
        ],
      ),
    );
  }
}

class PetitBouton extends StatelessWidget {
  const PetitBouton(this.label, this.onTap, {super.key});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: BSColors.text,
        side: const BorderSide(color: BSColors.divider),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: BSType.body(size: 18)),
    );
  }
}

