import 'package:flutter/material.dart';

import '../questionnaires/active_questionnaire.dart';
import '../questionnaires/catalogue.dart';
import '../questionnaires/questionnaire.dart';
import '../questionnaires/tirage_questions.dart';
import 'source_questions.dart';
import 'tokens.dart';

// TROISIÈME SOURCE : une manche composée sur place.
//
// L'animateur choisit un périmètre et un nombre, et le tirage assemble une
// manche qui n'existera qu'une fois. C'est la source la plus souple pour une
// soirée improvisée : personne n'a besoin d'avoir préparé quoi que ce soit,
// et deux soirées ne se ressemblent pas.
//
// TROIS CHOSES QUE CET ÉCRAN A DÛ APPRENDRE.
//
// Le bouton vient EN DERNIER, après les réglages qu'il consomme. Il était posé
// sur la ligne, donc au-dessus d'eux : on demandait d'agir avant d'avoir
// montré sur quoi.
//
// Les réglages restent PLIÉS tant que cette source n'est pas retenue. Les
// dix-neuf collections déployées écrasaient les deux autres sources, alors que
// c'est le choix le moins fréquent des trois.
//
// Le périmètre est un MENU, pas vingt pastilles. Choisir un élément parmi
// vingt est exactement ce à quoi sert un menu ; des pastilles se justifient
// quand les options sont peu nombreuses et qu'on veut les comparer d'un coup
// d'œil, ce qui n'est pas le cas ici.
//
// LE NIVEAU ET LA TRANCHE D'ÂGE, eux, SONT des pastilles : trois et quatre
// options, qu'on veut voir toutes en même temps parce qu'on en coche
// plusieurs. Rien de coché veut dire « sans filtre », pas « rien » : c'est
// l'état normal, et l'écran le dit plutôt que de laisser deviner.
//
// L'ORDRE DE LECTURE suit la phrase qu'on se dit : où piocher, pour qui,
// à quelle difficulté, combien. La tranche d'âge vient avant le niveau parce
// qu'elle est le choix qu'on fait en regardant la pièce, alors que le niveau
// se lit À L'INTÉRIEUR d'une tranche : « facile » ne veut pas dire la même
// chose pour un enfant et pour un aîné.
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

  String? _collection; // null = toutes les questions
  // Vides = sans filtre. Voir l'en-tête : c'est l'état normal, pas un oubli.
  final Set<Tranche> _tranches = {};
  final Set<int> _niveaux = {};
  int _nombre = _parDefaut;
  bool _enCours = false;
  bool _deplie = false;
  String? _erreur;

  bool get _choisi => widget.actif.tireAuHasard;

  @override
  void initState() {
    super.initState();
    widget.tirage.catalogue.addListener(_surCatalogue);
  }

  @override
  void dispose() {
    widget.tirage.catalogue.removeListener(_surCatalogue);
    super.dispose();
  }

  // Le catalogue arrive du disque puis du réseau : sans cette écoute, les
  // collections n'apparaîtraient qu'au prochain passage sur l'écran.
  void _surCatalogue() {
    if (mounted) setState(() {});
  }

  Future<void> _composer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final compose = await widget.tirage.composer(
      collection: _collection,
      niveaux: _niveaux,
      tranches: _tranches,
      nombre: _nombre,
    );
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _erreur = compose == null ? widget.tirage.derniereErreur : null;
    });
    if (compose != null) {
      widget.actif.use(compose, origine: 'Tirage au hasard');
      // Le périmètre du bris suit celui de la manche : départager une manche
      // d'histoire avec une question de cinéma serait injuste.
      widget.actif.collectionDuBris = _collection;
      widget.actif.tireAuHasard = true;
    }
  }

  String get _nomDuPerimetre => _collection ?? 'Toutes les questions';

  // Ce que l'animateur a demandé, en une phrase. Les critères laissés vides
  // ne s'écrivent pas : « pour tout le monde, tous niveaux » serait du bruit
  // sur le cas le plus courant.
  String get _criteres {
    final bouts = <String>[
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoixLigne(
          choisi: _choisi,
          titre: 'Questions au hasard',
          detail: _choisi
              ? '${widget.actif.total} questions tirées dans « $_nomDuPerimetre »$_criteres.'
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
                // Les deux réglages sur une même ligne : ils se lisent
                // ensemble, « vingt questions prises dans l'histoire ».
                Wrap(
                  spacing: BSSpace.s4,
                  runSpacing: BSSpace.s3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MenuPerimetre(
                      valeur: _collection,
                      collections: widget.tirage.collections,
                      onChange: (v) => setState(() => _collection = v),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PetitBouton(
                            '−',
                            _nombre > 1
                                ? () => setState(() => _nombre -= 1)
                                : null),
                        SizedBox(
                          width: 52,
                          child: Text(
                            '$_nombre',
                            textAlign: TextAlign.center,
                            style: BSType.body(size: 20, color: BSColors.text)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        PetitBouton(
                            '+',
                            _nombre < 99
                                ? () => setState(() => _nombre += 1)
                                : null),
                        const SizedBox(width: BSSpace.s2),
                        Text('questions',
                            style: BSType.body(
                                size: 15, color: BSColors.neutral600)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: BSSpace.s3),
                // POUR QUI, puis À QUELLE DIFFICULTÉ. La tranche d'abord :
                // c'est ce qu'on décide en regardant la pièce, et le niveau
                // se lit à l'intérieur d'elle.
                _LigneFiltre(
                  titre: 'Pour qui',
                  vide: _tranches.isEmpty,
                  quandVide: 'tout le monde',
                  options: [
                    for (final t in Tranche.values)
                      _Option(
                        label: kNomsTranches[t]!,
                        coche: _tranches.contains(t),
                        onTap: () => setState(() =>
                            _tranches.contains(t) ? _tranches.remove(t) : _tranches.add(t)),
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
                        onTap: () => setState(() =>
                            _niveaux.contains(n) ? _niveaux.remove(n) : _niveaux.add(n)),
                      ),
                  ],
                ),
                const SizedBox(height: BSSpace.s3),
                // EN DERNIER : le bouton vient après ce qu'il consomme.
                OutlinedButton(
                  onPressed: _enCours ? null : _composer,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BSColors.accent700,
                    side: const BorderSide(color: BSColors.accent300),
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: Text(_enCours
                      ? 'Tirage en cours...'
                      : _choisi
                          ? 'Tirer une autre manche'
                          : 'Composer la manche'),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: BSSpace.s2),
                  Text(_erreur!,
                      style: BSType.body(size: 14, color: BSColors.accent2_800)),
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
// l'animateur qui voit quatre cases vides croit devoir en cocher une, alors
// que ne rien cocher est l'état normal et le plus large.
class _Option {
  const _Option({required this.label, required this.coche, required this.onTap});
  final String label;
  final bool coche;
  final VoidCallback onTap;
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
    return Wrap(
      spacing: BSSpace.s2,
      runSpacing: BSSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 84,
          child: Text(titre,
              style: BSType.body(size: 14, color: BSColors.neutral600)),
        ),
        for (final o in options) _Pastille(o),
        if (vide)
          Padding(
            padding: const EdgeInsets.only(left: BSSpace.s2),
            child: Text(quandVide,
                style: BSType.body(size: 13, color: BSColors.neutral500)
                    .copyWith(fontStyle: FontStyle.italic)),
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
    return InkWell(
      onTap: o.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: o.coche ? BSColors.accent : Colors.transparent,
          border: Border.all(
            color: o.coche ? BSColors.accent : BSColors.divider,
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

// Le périmètre : un élément parmi vingt, donc un menu. Dessiné à la main
// plutôt qu'avec un DropdownButton de Material, dont les coins arrondis et
// l'ombre jureraient avec le reste.
class _MenuPerimetre extends StatelessWidget {
  const _MenuPerimetre({
    required this.valeur,
    required this.collections,
    required this.onChange,
  });

  final String? valeur;
  final List<CatalogueCollection> collections;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      tooltip: 'Choisir où piocher',
      position: PopupMenuPosition.under,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      color: BSColors.bg,
      onSelected: onChange,
      itemBuilder: (context) => [
        const PopupMenuItem<String?>(
          value: null,
          child: Text('Toutes les questions'),
        ),
        for (final c in collections)
          PopupMenuItem<String?>(
            value: c.name,
            child: Text('${c.emoji} ${c.name}'.trim()),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(border: Border.all(color: BSColors.divider)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              valeur ?? 'Toutes les questions',
              style: BSType.body(size: 15, color: BSColors.text)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: BSSpace.s2),
            const Icon(Icons.expand_more, size: 18, color: BSColors.neutral600),
          ],
        ),
      ),
    );
  }
}
