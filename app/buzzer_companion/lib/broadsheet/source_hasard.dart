import 'package:flutter/material.dart';

import '../questionnaires/active_questionnaire.dart';
import '../questionnaires/questionnaire.dart';
import '../questionnaires/tirage_questions.dart';
import 'source_questions.dart';
import 'tokens.dart';

// LA MANCHE COMPOSÉE SUR PLACE, devenue la façon normale de jouer.
//
// L'animateur dit ce qu'il a devant lui — des enfants, un mélange, des
// connaisseurs — et la manche se compose. Elle n'existera qu'une fois, et
// deux soirées ne se ressemblent pas.
//
// L'ORDRE DE LECTURE suit la phrase qu'on se dit : dans quoi on pioche, pour
// qui, à quelle difficulté, combien. La tranche d'âge vient avant le niveau
// parce qu'elle est le choix qu'on fait en regardant la pièce, alors que le
// niveau se lit À L'INTÉRIEUR d'elle : « facile » ne veut pas dire la même
// chose pour un enfant et pour un aîné.
//
// RIEN DE COCHÉ VEUT DIRE « TOUT », pas « rien ». C'est l'état normal et le
// plus large, et chaque ligne le dit plutôt que de laisser deviner : devant
// quatre cases vides, on croit devoir en choisir une.
//
// LE COMPTE S'AFFICHE AVANT DE COMPOSER. Un filtre qui ne laisse que huit
// questions doit se voir pendant qu'on coche, pas après avoir cliqué : sinon
// l'animateur découvre sa manche tronquée une fois la partie lancée.
//
// LES RÉGLAGES RESTENT PLIÉS tant que cette source n'est pas retenue. Déployés,
// ils écrasent les deux autres sources.
class SourceAuHasard extends StatefulWidget {
  const SourceAuHasard({
    super.key,
    required this.actif,
    required this.tirage,
  });

  final ActiveQuestionnaire actif;
  final TirageQuestions tirage;

  @override
  State<SourceAuHasard> createState() => _SourceAuHasardState();
}

class _SourceAuHasardState extends State<SourceAuHasard> {
  static const _parDefaut = 20;

  // Vides = sans filtre. Voir l'en-tête : c'est l'état normal, pas un oubli.
  final Set<String> _categories = {};
  final Set<String> _themes = {};
  final Set<Tranche> _tranches = {};
  final Set<int> _niveaux = {};
  int _nombre = _parDefaut;
  bool _deplie = false;
  String? _erreur;

  bool get _choisi => widget.actif.tireAuHasard;

  @override
  void initState() {
    super.initState();
    widget.tirage.banque.addListener(_surBanque);
  }

  @override
  void dispose() {
    widget.tirage.banque.removeListener(_surBanque);
    super.dispose();
  }

  // La banque arrive du disque puis du réseau : sans cette écoute, les
  // catégories n'apparaîtraient qu'au prochain passage sur l'écran.
  void _surBanque() {
    if (mounted) setState(() {});
  }

  int get _disponibles => widget.tirage.compter(
        categories: _categories,
        themes: _themes,
        niveaux: _niveaux,
        tranches: _tranches,
      );

  void _composer() {
    final compose = widget.tirage.composer(
      categories: _categories,
      themes: _themes,
      niveaux: _niveaux,
      tranches: _tranches,
      nombre: _nombre,
    );
    setState(() => _erreur = compose == null ? widget.tirage.derniereErreur : null);
    if (compose != null) {
      widget.actif.use(compose, origine: 'Tirage au hasard');
      // Le périmètre du bris suit celui de la manche : départager une manche
      // d'histoire avec une question de cinéma serait injuste.
      widget.actif.perimetreDuBris = {..._categories, ..._themes};
      widget.actif.tireAuHasard = true;
    }
  }

  // Ce que l'animateur a demandé, en une phrase. Les critères laissés vides
  // ne s'écrivent pas : « toutes catégories, pour tout le monde, tous
  // niveaux » serait du bruit sur le cas le plus courant.
  String get _criteres {
    final bouts = <String>[
      if (_categories.isNotEmpty || _themes.isNotEmpty)
        'dans ${[..._categories, ..._themes].join(', ')}',
      if (_tranches.isNotEmpty)
        'pour ${[for (final t in Tranche.values) if (_tranches.contains(t)) kNomsTranches[t]!].join(', ')}',
      if (_niveaux.isNotEmpty)
        'niveau ${[for (final n in kNomsNiveaux.keys) if (_niveaux.contains(n)) kNomsNiveaux[n]!].join(', ')}',
    ];
    return bouts.isEmpty ? '' : ', ${bouts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final ouvert = _deplie || _choisi;
    final banque = widget.tirage.banque;
    final dispo = _disponibles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoixLigne(
          choisi: _choisi,
          titre: 'Questions au hasard',
          detail: _choisi
              ? '${widget.actif.total} questions tirées$_criteres.'
              : "Une manche composée sur place, qui n'existera qu'une fois.",
          onTap: () => setState(() => _deplie = !ouvert),
        ),
        if (ouvert)
          Padding(
            padding: const EdgeInsets.only(left: BSSpace.s6, top: BSSpace.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (banque.banque.isEmpty)
                  Text(
                    banque.loading
                        ? 'Lecture de la banque...'
                        : banque.lastError ?? 'Aucune question disponible.',
                    style: BSType.body(size: 15, color: BSColors.neutral600),
                  )
                else ...[
                  _LigneFiltre(
                    titre: 'Dans quoi',
                    vide: _categories.isEmpty && _themes.isEmpty,
                    quandVide: 'toute la banque',
                    options: [
                      for (final f in banque.banque.categories)
                        _Option(
                          label: '${f.emoji} ${f.nom}'.trim(),
                          coche: _categories.contains(f.nom),
                          onTap: () => setState(() => _categories.contains(f.nom)
                              ? _categories.remove(f.nom)
                              : _categories.add(f.nom)),
                        ),
                      // Les thématiques après les catégories, et distinguées :
                      // elles TRAVERSENT les catégories, cocher « Spécial
                      // Noël » n'est pas du même ordre que cocher « Musique ».
                      for (final f in banque.banque.themes)
                        _Option(
                          label: '${f.emoji} ${f.nom}'.trim(),
                          coche: _themes.contains(f.nom),
                          traversant: true,
                          onTap: () => setState(() => _themes.contains(f.nom)
                              ? _themes.remove(f.nom)
                              : _themes.add(f.nom)),
                        ),
                    ],
                  ),
                  const SizedBox(height: BSSpace.s2),
                  _LigneFiltre(
                    titre: 'Pour qui',
                    vide: _tranches.isEmpty,
                    quandVide: 'tout le monde',
                    options: [
                      for (final t in Tranche.values)
                        _Option(
                          label: kNomsTranches[t]!,
                          coche: _tranches.contains(t),
                          onTap: () => setState(() => _tranches.contains(t)
                              ? _tranches.remove(t)
                              : _tranches.add(t)),
                        ),
                    ],
                  ),
                  const SizedBox(height: BSSpace.s2),
                  _LigneFiltre(
                    titre: 'Difficulté',
                    vide: _niveaux.isEmpty,
                    quandVide: 'tous les niveaux',
                    options: [
                      for (final n in kNomsNiveaux.keys)
                        _Option(
                          label: kNomsNiveaux[n]!,
                          coche: _niveaux.contains(n),
                          onTap: () => setState(() => _niveaux.contains(n)
                              ? _niveaux.remove(n)
                              : _niveaux.add(n)),
                        ),
                    ],
                  ),
                  const SizedBox(height: BSSpace.s3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text('Combien',
                            style: BSType.body(
                                size: 14, color: BSColors.neutral600)),
                      ),
                      PetitBouton('−',
                          _nombre > 1 ? () => setState(() => _nombre -= 1) : null),
                      SizedBox(
                        width: 52,
                        child: Text(
                          '$_nombre',
                          textAlign: TextAlign.center,
                          style: BSType.body(size: 20, color: BSColors.text)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      PetitBouton('+',
                          _nombre < 99 ? () => setState(() => _nombre += 1) : null),
                      const SizedBox(width: BSSpace.s3),
                      // LE COMPTE, à côté du nombre demandé : c'est là qu'on
                      // voit qu'on en demande vingt pour huit disponibles.
                      Text(
                        dispo >= _nombre
                            ? '$dispo questions répondent aux critères'
                            : 'Seulement $dispo question${dispo > 1 ? 's' : ''} '
                                'répond${dispo > 1 ? 'ent' : ''} aux critères',
                        style: BSType.body(
                            size: 14,
                            color: dispo >= _nombre
                                ? BSColors.neutral600
                                : BSColors.accent2_800),
                      ),
                    ],
                  ),
                  const SizedBox(height: BSSpace.s3),
                  // EN DERNIER : le bouton vient après ce qu'il consomme.
                  OutlinedButton(
                    onPressed: dispo == 0 ? null : _composer,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BSColors.accent700,
                      side: const BorderSide(color: BSColors.accent300),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
                    child: Text(_choisi
                        ? 'Tirer une autre manche'
                        : 'Composer la manche'),
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: BSSpace.s2),
                    Text(_erreur!,
                        style:
                            BSType.body(size: 14, color: BSColors.accent2_800)),
                  ],
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// UNE LIGNE DE FILTRE : un titre, des pastilles, et ce que veut dire « rien
// de coché ». Cette dernière mention est le cœur du contrôle : sans elle,
// l'animateur qui voit des cases vides croit devoir en cocher une, alors que
// ne rien cocher est l'état normal et le plus large.
class _Option {
  const _Option({
    required this.label,
    required this.coche,
    required this.onTap,
    this.traversant = false,
  });
  final String label;
  final bool coche;
  final VoidCallback onTap;
  // Une thématique, qui traverse les catégories. Dessinée autrement pour
  // qu'on ne la prenne pas pour une douzième catégorie.
  final bool traversant;
}

class _LigneFiltre extends StatelessWidget {
  const _LigneFiltre({
    required this.titre,
    required this.options,
    required this.vide,
    required this.quandVide,
  });

  final String titre;
  final List<_Option> options;
  final bool vide;
  final String quandVide;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: SizedBox(
            width: 84,
            child: Text(titre,
                style: BSType.body(size: 14, color: BSColors.neutral600)),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: BSSpace.s2,
            runSpacing: BSSpace.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final o in options) _Pastille(o),
              if (vide)
                Padding(
                  padding: const EdgeInsets.only(left: BSSpace.s2, top: 7),
                  child: Text(quandVide,
                      style: BSType.body(size: 13, color: BSColors.neutral500)
                          .copyWith(fontStyle: FontStyle.italic)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// Cochée, la pastille se remplit : la couleur seule ne suffirait pas à qui
// distingue mal le bleu, alors le contour s'épaissit aussi.
class _Pastille extends StatelessWidget {
  const _Pastille(this.o);
  final _Option o;

  @override
  Widget build(BuildContext context) {
    final teinte = o.traversant ? BSColors.accent2 : BSColors.accent;
    return InkWell(
      onTap: o.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: o.coche ? teinte : Colors.transparent,
          border: Border.all(
            color: o.coche ? teinte : BSColors.divider,
            width: o.coche ? 2 : 1,
          ),
        ),
        child: Text(
          o.label,
          style: BSType.body(
                  size: 14, color: o.coche ? BSColors.bg : BSColors.text)
              .copyWith(fontWeight: o.coche ? FontWeight.w600 : FontWeight.w400),
        ),
      ),
    );
  }
}
