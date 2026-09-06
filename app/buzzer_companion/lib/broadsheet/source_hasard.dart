import 'package:flutter/material.dart';

import '../questionnaires/active_questionnaire.dart';
import '../questionnaires/criteres_tirage.dart';
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
  // LES CRITÈRES NE VIVENT PLUS ICI. Ils vivaient dans cet état de widget, et
  // n'y survivaient donc ni à un aller-retour vers l'écran Questions, ni à la
  // fermeture de l'application : entre deux manches de la même soirée, il
  // fallait recocher les quatre mêmes cases devant la salle qui attend. Ils
  // appartiennent au tirage, qui les garde et les écrit sur le disque (voir
  // CriteresTirage).
  //
  // UNE SEULE LISTE DE FACETTES depuis que les onze catégories sont aussi des
  // thématiques : « Musique » et « Spécial Noël » se cochent dans la même
  // grille, ce que le tirage faisait déjà en les réunissant dans un seul OU.
  CriteresTirage get _criteresRetenus => widget.tirage.criteres;
  Set<String> get _themes => _criteresRetenus.themes;
  Set<Tranche> get _tranches => _criteresRetenus.tranches;
  Set<int> get _niveaux => _criteresRetenus.niveaux;
  int get _nombre => _criteresRetenus.nombre;

  bool _deplie = false;
  String? _erreur;

  // CE QUE LE DERNIER TIRAGE A DONNÉ, et l'heure qu'il était.
  //
  // Deux manches tirées sur les mêmes critères s'annoncent avec les mêmes
  // mots : « 20 questions tirées, niveau facile, moyen ». Cliquer « Tirer une
  // autre manche » ne changeait donc rien à l'écran, et on en concluait,
  // raisonnablement, que le tirage ne tirait plus rien — alors que les vingt
  // questions étaient neuves (deux manches de suite ne se recoupent jamais,
  // voir TirageQuestions._dejaPosees). L'heure, elle, change à chaque fois.
  DateTime? _tiree;

  // La remarque du tirage : manche tronquée, tranche laissée de côté. Elle
  // était calculée et jetée.
  String _note = '';

  bool get _choisi => widget.actif.tireAuHasard;

  @override
  void initState() {
    super.initState();
    widget.tirage.banque.addListener(_surBanque);
    // Les critères viennent du disque, donc plus tard que le premier build ;
    // et ils changent aussi sous nos pieds, depuis l'autre écran qui montre
    // cette même source.
    _criteresRetenus.addListener(_surCriteres);
    _elaguerLesThemes();
  }

  @override
  void dispose() {
    widget.tirage.banque.removeListener(_surBanque);
    _criteresRetenus.removeListener(_surCriteres);
    super.dispose();
  }

  // La banque arrive du disque puis du réseau : sans cette écoute, les
  // catégories n'apparaîtraient qu'au prochain passage sur l'écran.
  void _surBanque() {
    if (!mounted) return;
    _elaguerLesThemes();
    setState(() {});
  }

  void _surCriteres() {
    if (mounted) setState(() {});
  }

  // Une thématique retenue l'hiver dernier peut ne plus exister dans la
  // banque d'aujourd'hui. Cochée, elle ne laisserait passer aucune question
  // sans que sa case soit là pour se décocher.
  void _elaguerLesThemes() {
    final banque = widget.tirage.banque.banque;
    if (banque.isEmpty) return;
    _criteresRetenus.oublierThemesInconnus(banque.themes.map((f) => f.nom));
  }

  int get _disponibles => widget.tirage.compter(
        themes: _themes,
        niveaux: _niveaux,
        tranches: _tranches,
      );

  void _composer() {
    final compose = widget.tirage.composer(
      themes: _themes,
      niveaux: _niveaux,
      tranches: _tranches,
      nombre: _nombre,
    );
    if (compose == null) {
      setState(() {
        _erreur = widget.tirage.derniereErreur;
        _tiree = null;
        _note = '';
      });
      return;
    }
    widget.actif.use(compose, origine: 'Tirage au hasard');
    // Le périmètre du bris suit celui de la manche : départager une manche
    // d'histoire avec une question de cinéma serait injuste.
    widget.actif.perimetreDuBris = {..._themes};
    widget.actif.tireAuHasard = true;
    setState(() {
      _erreur = null;
      _tiree = DateTime.now();
      _note = compose.note;
      // Une manche vient d'être composée ici : les réglages restent ouverts,
      // même après une partie, qui remet la source à zéro (mancheJouee).
      _deplie = true;
    });
  }

  // « 20 h 41 », comme on écrit l'heure ici.
  static String _heure(DateTime t) =>
      '${t.hour} h ${t.minute.toString().padLeft(2, '0')}';

  // Ce que l'animateur a demandé, en une phrase. Les critères laissés vides
  // ne s'écrivent pas : « toutes catégories, pour tout le monde, tous
  // niveaux » serait du bruit sur le cas le plus courant.
  String get _criteres {
    final bouts = <String>[
      if (_themes.isNotEmpty) 'dans ${_themes.join(', ')}',
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
                  // LA GRILLE DE CASES À COCHER VIENT DE LA MAQUETTE
                  // (design_handoff_buzzer_console, écran 1g) : deux colonnes,
                  // carré de 17 px, compte à droite du nom.
                  //
                  // Elle avait été rendue en pastilles encadrées, dix-neuf
                  // d'affilée qui se repliaient sur six rangées au bord droit
                  // déchiqueté. Un bloc de boutons où rien ne distinguait
                  // « Musique » de « Sports d'hiver », et où le regard n'avait
                  // aucune colonne à suivre. La grille aligne les noms et
                  // aligne les comptes.
                  //
                  // UNE SEULE GRILLE, et non plus deux : les onze catégories
                  // sont devenues des thématiques, alors « Musique » et
                  // « Spécial Noël » se cochent au même endroit. Elles sont
                  // triées comme le générateur les donne, les onze anciennes
                  // catégories d'abord.
                  _GrilleFiltre(
                    titre: 'THÉMATIQUES',
                    indice: _themes.isEmpty ? 'aucune' : null,
                    colonnes: 2,
                    teinte: BSColors.accent2,
                    cases: [
                      for (final f in banque.banque.themes)
                        _Case(
                          label: f.nom,
                          emoji: f.emoji,
                          compte: f.questions,
                          coche: _themes.contains(f.nom),
                          onTap: () =>
                              _criteresRetenus.basculerTheme(f.nom),
                        ),
                    ],
                  ),
                  const SizedBox(height: BSSpace.s4),
                  // Quatre options et trois : une seule rangée chacune, et
                  // les deux côte à côte. Leur donner la grille à deux
                  // colonnes étirerait la page pour rien.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _GrilleFiltre(
                          titre: 'POUR QUI',
                          // Ne rien cocher ne veut pas dire « peu importe » :
                          // la manche réserve une place à chaque tranche, sans
                          // quoi elle reprenait les proportions de la banque,
                          // où les questions du monde des enfants sont rares.
                          indice: _tranches.isEmpty
                              ? 'tout le monde, chaque âge servi'
                              : null,
                          colonnes: 1,
                          enRangee: true,
                          cases: [
                            for (final t in Tranche.values)
                              _Case(
                                label: kNomsTranches[t]!,
                                coche: _tranches.contains(t),
                                onTap: () =>
                                    _criteresRetenus.basculerTranche(t),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: BSSpace.s6),
                      Expanded(
                        child: _GrilleFiltre(
                          titre: 'DIFFICULTÉ',
                          indice: _niveaux.isEmpty ? 'tous les niveaux' : null,
                          colonnes: 1,
                          enRangee: true,
                          cases: [
                            for (final n in kNomsNiveaux.keys)
                              _Case(
                                label: kNomsNiveaux[n]!,
                                coche: _niveaux.contains(n),
                                onTap: () =>
                                    _criteresRetenus.basculerNiveau(n),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: BSSpace.s4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text('Combien',
                            style: BSType.body(
                                size: 14, color: BSColors.neutral600)),
                      ),
                      PetitBouton(
                          '−',
                          _nombre > 1
                              ? () => _criteresRetenus.reglerNombre(_nombre - 1)
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
                              ? () => _criteresRetenus.reglerNombre(_nombre + 1)
                              : null),
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
                  ]
                  // L'ACCUSÉ DE RÉCEPTION DU TIRAGE. Sans lui, cliquer sur le
                  // bouton n'avait aucun effet visible : mêmes critères,
                  // même compte, mêmes mots. La remarque du tirage passe par
                  // ici aussi, quand il y en a une à faire.
                  else if (_choisi && _tiree != null) ...[
                    const SizedBox(height: BSSpace.s2),
                    SizedBox(
                      width: 560,
                      child: Text(
                        'Manche composée à ${_heure(_tiree!)} : '
                        '${widget.actif.total} questions neuves.'
                        '${_note.isEmpty ? '' : ' $_note'}',
                        style: BSType.body(
                            size: 14,
                            color: _note.isEmpty
                                ? BSColors.neutral600
                                : BSColors.accent2_800),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// UN CRITÈRE À COCHER : le nom, et combien la banque en porte.
//
// Le compte est ce qui manquait le plus. Sans lui, « Culture pop » et
// « Cinéma et télé » se ressemblent, alors que l'une en porte 428 et l'autre
// 271 : l'animateur qui coche une seule catégorie pour une manche de 25 n'a
// aucun moyen de savoir s'il vient de se peindre dans un coin.
class _Case {
  const _Case({
    required this.label,
    required this.coche,
    required this.onTap,
    this.emoji,
    this.compte,
  });
  final String label;
  final String? emoji;
  final int? compte;
  final bool coche;
  final VoidCallback onTap;
}

// LA GRILLE DE LA MAQUETTE : un intertitre, puis des cases en colonnes
// alignées. Carré de 17 px, aplat d'accent et crochet blanc une fois coché,
// filet neutral-500 sinon (design_handoff_buzzer_console/README.md, 1g).
//
// Ce que la grille apporte sur les pastilles qu'elle remplace : les noms
// commencent tous au même x, les comptes finissent tous au même x, et le bord
// droit est droit. Dix-neuf pastilles repliées ne donnaient aucune de ces
// trois choses, et le regard n'avait aucune colonne à suivre.
//
// RIEN DE COCHÉ VEUT DIRE « TOUT ». L'indice ne s'affiche que dans ce cas :
// dès qu'une case est cochée, la sélection se voit et l'indice n'a plus rien
// à dire.
class _GrilleFiltre extends StatelessWidget {
  const _GrilleFiltre({
    required this.titre,
    required this.cases,
    required this.colonnes,
    this.indice,
    this.teinte = BSColors.accent,
    this.enRangee = false,
  });

  final String titre;
  final List<_Case> cases;
  final int colonnes;
  final String? indice;
  final Color teinte;
  // Quatre tranches ou trois niveaux tiennent sur une ligne : leur donner des
  // colonnes étirerait la page pour rien.
  final bool enRangee;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(titre, style: BSType.sectionKicker()),
            if (indice != null) ...[
              const SizedBox(width: BSSpace.s2),
              Flexible(
                child: Text(
                  indice!,
                  overflow: TextOverflow.ellipsis,
                  style: BSType.body(size: 13, color: BSColors.neutral500)
                      .copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: BSSpace.s1),
        Container(height: 1, color: BSColors.divider),
        const SizedBox(height: BSSpace.s2),
        if (enRangee)
          Wrap(
            spacing: BSSpace.s4,
            runSpacing: BSSpace.s2,
            children: [for (final c in cases) _CaseACocher(c, teinte)],
          )
        else
          // Une colonne de Row plutôt qu'un GridView : la grille de Flutter
          // veut une hauteur bornée, et ce bloc vit dans une colonne qui se
          // déroule. Onze cases ne justifient pas non plus de construire à la
          // demande.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < cases.length; i += colonnes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    children: [
                      for (var j = 0; j < colonnes; j++)
                        Expanded(
                          child: i + j < cases.length
                              ? _CaseACocher(cases[i + j], teinte)
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _CaseACocher extends StatelessWidget {
  const _CaseACocher(this.c, this.teinte);

  final _Case c;
  final Color teinte;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: c.onTap,
        // Toute la ligne est cliquable, pas seulement le carré : viser
        // dix-sept pixels à la souris est une corvée quand le nom juste à
        // côté fait la même chose.
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 17,
              height: 17,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.coche ? teinte : Colors.transparent,
                  border: c.coche
                      ? null
                      : Border.all(color: BSColors.neutral500),
                ),
                child: c.coche
                    ? const Center(
                        child: Text('✓',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1)),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 11),
            if (c.emoji != null && c.emoji!.isNotEmpty) ...[
              Text(c.emoji!, style: BSType.body(size: 15)),
              const SizedBox(width: 6),
            ],
            Text(
              c.label,
              style: BSType.body(size: 16, color: BSColors.text).copyWith(
                fontWeight: c.coche ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (c.compte != null) ...[
              const SizedBox(width: 8),
              Text('${c.compte}',
                  style: BSType.body(size: 14, color: BSColors.neutral600)),
            ],
          ],
        ),
      ),
    );
  }
}
