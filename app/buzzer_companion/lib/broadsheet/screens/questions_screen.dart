import 'package:flutter/material.dart';

import '../../protocol.dart';
import '../../questionnaires/questionnaire.dart';
import '../../questionnaires/questionnaire_store.dart';
import '../tokens.dart';

// Écran "Questions" : atelier de questionnaires thématiques. On en écrit un,
// on l'enregistre en JSON dans le dossier de son choix, et on le recharge le
// soir venu (spécial Noël, party de bureau, anniversaire).
//
// C'est la banque de l'app, distincte de celle du firmware : les 10
// catégories compilées dans Questions.cpp restent le fonds de commerce des
// soirées ordinaires, ces fichiers-ci servent aux soirées à thème. Les deux
// ne se mélangent pas.
//
// Deux moments successifs, pas deux volets : la bibliothèque prend tout
// l'écran pour choisir, l'éditeur prend tout l'écran pour écrire. Garder la
// liste visible pendant la saisie volait sa largeur à la seule chose qu'on
// fait à ce moment-là.
class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen({super.key, required this.store});

  final QuestionnaireStore store;

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  Questionnaire? _open;
  String? _openPath;
  bool _dirty = false;
  // Gardée ici, et non dans la bibliothèque : refermer l'éditeur doit
  // ramener dans la collection d'où on venait, pas à la case départ.
  _Selection _selection = const _Selection.grille();

  @override
  void initState() {
    super.initState();
    widget.store.loadPreferences();
  }

  void _touch() => setState(() => _dirty = true);

  void _newQuestionnaire() {
    setState(() {
      _open = Questionnaire(questions: [QuizQuestion()]);
      _openPath = null;
      _dirty = false;
    });
  }

  Future<void> _openFile(QuestionnaireFile file) async {
    if (!await _confirmDiscard()) return;
    final loaded = await widget.store.load(file.path);
    if (loaded == null || !mounted) return;
    setState(() {
      _open = loaded;
      _openPath = file.path;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final open = _open;
    if (open == null) return;
    // Un questionnaire sans titre finirait en « Questionnaire.json », puis
    // « Questionnaire.json » écrasé au suivant. On exige le titre.
    if (open.title.trim().isEmpty) {
      _tell('Donnez un titre au questionnaire avant de l\'enregistrer.');
      return;
    }
    final path = await widget.store.save(open, existingPath: _openPath);
    if (!mounted) return;
    if (path == null) {
      _tell(widget.store.lastError ?? 'Enregistrement impossible.');
      return;
    }
    setState(() {
      _openPath = path;
      _dirty = false;
    });
  }

  // Renommer revient à écrire un nouveau fichier : l'ancien resterait à côté
  // sous son ancien nom. On l'efface après coup, jamais avant, pour ne pas
  // perdre le questionnaire si l'écriture échoue.
  Future<void> _saveAsNewName() async {
    final open = _open;
    if (open == null || open.title.trim().isEmpty) return;
    final ancien = _openPath;
    final path = await widget.store.save(open);
    if (!mounted || path == null) return;
    if (ancien != null && ancien != path) {
      await widget.store.delete(ancien);
    }
    if (!mounted) return;
    setState(() {
      _openPath = path;
      _dirty = false;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BSColors.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Abandonner les modifications ?', style: BSType.buzzerNameConsole(size: 22)),
        content: Text(
          'Le questionnaire ouvert a été modifié et son enregistrement est en attente.',
          style: BSType.body(size: 16, color: BSColors.neutral700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: BSColors.neutral700),
            child: const Text('Revenir'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: BSColors.accent2,
              foregroundColor: BSColors.bg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BSColors.text,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        content: Text(message, style: BSType.body(size: 15, color: BSColors.bg)),
      ),
    );
  }

  // Fermer l'éditeur et revenir à la bibliothèque.
  Future<void> _close() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() {
      _open = null;
      _openPath = null;
      _dirty = false;
    });
  }

  // Deux moments, pas deux volets. On choisit un questionnaire, PUIS on
  // l'écrit : garder la bibliothèque à l'écran pendant la saisie coûtait
  // 300 px à la seule chose qu'on est en train de faire, et mettait un
  // bouton « Nouveau » à portée de clic d'un travail non enregistré.
  // Chacun des deux moments prend donc tout l'écran.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        if (_open == null) {
          return _Library(
            store: widget.store,
            selection: _selection,
            onSelect: (s) => setState(() => _selection = s),
            onNew: _newQuestionnaire,
            onOpen: _openFile,
            onImport: () async {
              final path = await widget.store.import();
              if (!mounted) return;
              if (path == null && widget.store.lastError != null) {
                _tell(widget.store.lastError!);
              }
            },
          );
        }
        return _Editor(
          questionnaire: _open!,
          dirty: _dirty,
          saved: _openPath != null,
          onBack: _close,
          onChanged: _touch,
          onSave: _save,
          onRename: _saveAsNewName,
          onExport: () => widget.store.export(_open!),
          onDelete: _openPath == null ? null : _deleteOpen,
        );
      },
    );
  }

  Future<void> _deleteOpen() async {
    final path = _openPath;
    if (path == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BSColors.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Supprimer ce questionnaire ?', style: BSType.buzzerNameConsole(size: 22)),
        content: Text(
          'Le fichier sera effacé du dossier. Cette action ne se défait pas.',
          style: BSType.body(size: 16, color: BSColors.neutral700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: BSColors.neutral700),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: BSColors.accent2,
              foregroundColor: BSColors.bg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.delete(path);
    if (!mounted) return;
    setState(() {
      _open = null;
      _openPath = null;
      _dirty = false;
    });
  }
}

// --------------------------------------------------------------- Bibliothèque

// Où en est la bibliothèque : la grille des collections, une collection
// précise, ou tout le dossier d'un coup.
//
// Un seul objet plutôt que deux champs (« quelle collection » et « est-ce
// qu'on montre tout »), qui pourraient se contredire.
class _Selection {
  const _Selection.grille()
      : collection = null,
        toutes = false;
  const _Selection.tout()
      : collection = null,
        toutes = true;
  const _Selection.de(String this.collection) : toutes = false;

  final String? collection;
  final bool toutes;

  bool get estGrille => collection == null && !toutes;
}

class _Library extends StatelessWidget {
  const _Library({
    required this.store,
    required this.selection,
    required this.onSelect,
    required this.onNew,
    required this.onOpen,
    required this.onImport,
  });

  final QuestionnaireStore store;
  final _Selection selection;
  final ValueChanged<_Selection> onSelect;
  final VoidCallback onNew;
  final ValueChanged<QuestionnaireFile> onOpen;
  final VoidCallback onImport;

  // Deux niveaux : on choisit une collection, PUIS un questionnaire. Cent
  // trente et une cartes d'un seul tenant, c'est un mur où plus rien ne se
  // trouve ; une vingtaine de tuiles, ça se lit d'un coup d'œil.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: selection.estGrille ? _grille() : _liste(),
        ),
      ),
    );
  }

  // --- Premier niveau : les collections

  List<Widget> _grille() {
    return [
      Row(
        children: [
          Text('Questionnaires', style: BSType.buzzerNameConsole(size: 26)),
          const SizedBox(width: BSSpace.s4),
          _boutonPlein('Nouveau', onNew),
          const SizedBox(width: BSSpace.s2),
          _boutonContour('Importer', onImport),
        ],
      ),
      const SizedBox(height: BSSpace.s2),
      SizedBox(
        width: 760,
        child: Text(
          'Préparez un questionnaire à thème, chargez-le le soir venu. Les '
          'fichiers sont du JSON en clair : vous pouvez les retoucher dans un '
          "éditeur de texte, les copier sur une clé, ou les envoyer à quelqu'un "
          "pour qu'il écrive les questions.",
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
      ),
      const SizedBox(height: BSSpace.s6),
      if (store.files.isEmpty)
        Text(
          'Aucun questionnaire pour le moment.',
          style: BSType.body(size: 17, color: BSColors.neutral600),
        )
      else ...[
        Text('COLLECTIONS', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        Wrap(
          spacing: BSSpace.s4,
          runSpacing: BSSpace.s4,
          children: [
            // La tuile qui ne filtre rien, en tête : c'est le repli quand on
            // ne sait pas dans quelle collection chercher.
            _CollectionCard(
              titre: 'Tous les questionnaires',
              fichiers: store.files.length,
              questions: store.questionCount,
              vedette: true,
              onTap: () => onSelect(const _Selection.tout()),
            ),
            for (final collection in store.collections)
              _CollectionCard(
                titre: collection.name,
                fichiers: collection.files.length,
                questions: collection.questionCount,
                vedette: false,
                onTap: () => onSelect(_Selection.de(collection.name)),
              ),
          ],
        ),
      ],
      const SizedBox(height: BSSpace.s8),
      ..._dossier(),
    ];
  }

  // --- Second niveau : les questionnaires d'une collection

  List<Widget> _liste() {
    final titre = selection.toutes ? 'Tous les questionnaires' : selection.collection!;
    final fichiers = selection.toutes
        ? store.files
        : store.files.where((f) => f.displayCollection == titre).toList();

    return [
      Row(
        children: [
          TextButton(
            onPressed: () => onSelect(const _Selection.grille()),
            style: TextButton.styleFrom(
              foregroundColor: BSColors.neutral700,
              padding: const EdgeInsets.only(right: BSSpace.s2),
            ),
            child: const Text('‹ Collections'),
          ),
          const SizedBox(width: BSSpace.s2),
          // Flexible : une collection nommée par l'opérateur peut être
          // longue, et le titre ne doit pas pousser les boutons hors écran.
          Flexible(
            child: Text(
              titre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BSType.buzzerNameConsole(size: 26),
            ),
          ),
          const SizedBox(width: BSSpace.s4),
          _boutonPlein('Nouveau', onNew),
          const SizedBox(width: BSSpace.s2),
          _boutonContour('Importer', onImport),
        ],
      ),
      const SizedBox(height: BSSpace.s1),
      Text(
        '${fichiers.length} questionnaire${fichiers.length > 1 ? 's' : ''}',
        style: BSType.body(size: 15, color: BSColors.accent700),
      ),
      const SizedBox(height: BSSpace.s6),
      if (fichiers.isEmpty)
        Text(
          'Cette collection est vide.',
          style: BSType.body(size: 17, color: BSColors.neutral600),
        )
      else
        Wrap(
          spacing: BSSpace.s4,
          runSpacing: BSSpace.s4,
          children: [
            for (final file in fichiers)
              _QuestionnaireCard(file: file, onTap: () => onOpen(file)),
          ],
        ),
    ];
  }

  // --- Le dossier, montré au premier niveau seulement : au second, on est
  // venu chercher un questionnaire, pas régler un chemin.

  List<Widget> _dossier() {
    return [
      Container(height: 1, color: BSColors.divider),
      const SizedBox(height: BSSpace.s4),
      Text('DOSSIER', style: BSType.sectionKicker()),
      const SizedBox(height: BSSpace.s1),
      SizedBox(
        width: 900,
        child: Row(
          children: [
            // Sélectionnable : c'est le chemin qu'on copie pour aller y
            // déposer un fichier reçu par courriel.
            Expanded(
              child: SelectableText(
                store.folderPath.isEmpty ? '...' : store.folderPath,
                style: BSType.body(size: 15, color: BSColors.neutral700),
              ),
            ),
            const SizedBox(width: BSSpace.s3),
            TextButton(
              onPressed: store.chooseFolder,
              style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
              child: const Text('Changer de dossier'),
            ),
            // Proposé seulement s'il y a quelque chose à défaire : sans
            // dossier choisi, « Par défaut » ne ferait rien.
            if (store.usesCustomFolder)
              TextButton(
                onPressed: store.useDefaultFolder,
                style: TextButton.styleFrom(foregroundColor: BSColors.neutral600),
                child: const Text('Par défaut'),
              ),
          ],
        ),
      ),
      if (store.lastError != null) ...[
        const SizedBox(height: BSSpace.s2),
        SizedBox(
          width: 900,
          child: Text(
            store.lastError!,
            style: BSType.body(size: 15, color: BSColors.accent2_800),
          ),
        ),
      ],
    ];
  }

  static Widget _boutonPlein(String texte, VoidCallback onTap) => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: BSColors.accent,
          foregroundColor: BSColors.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        child: Text(texte),
      );

  static Widget _boutonContour(String texte, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: BSColors.text,
          side: const BorderSide(color: BSColors.divider),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        child: Text(texte),
      );
}

// Une tuile de collection. Même grammaire que les cartes de questionnaire, en
// filet plus épais : c'est le niveau au-dessus.
class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.titre,
    required this.fichiers,
    required this.questions,
    required this.vedette,
    required this.onTap,
  });

  final String titre;
  final int fichiers;
  final int questions;
  // La tuile « Tous les questionnaires » : même forme, couleur d'accent, pour
  // qu'elle se distingue des collections sans être un autre objet.
  final bool vedette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final couleur = vedette ? BSColors.accent : BSColors.text;
    final card = Container(
      width: 260,
      padding: const EdgeInsets.only(top: BSSpace.s2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: couleur, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BSType.buzzerNameConsole(size: 22, color: couleur),
          ),
          const SizedBox(height: BSSpace.s1),
          Text(
            '$fichiers questionnaire${fichiers > 1 ? 's' : ''}',
            style: BSType.body(size: 15, color: BSColors.accent700),
          ),
          Text(
            '$questions question${questions > 1 ? 's' : ''}',
            style: BSType.body(size: 13, color: BSColors.neutral600),
          ),
        ],
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

// Même grammaire que les cartes de « Jeu actif » : un filet épais en tête,
// pas d'encadré ni d'ombre.
class _QuestionnaireCard extends StatelessWidget {
  const _QuestionnaireCard({required this.file, required this.onTap});

  final QuestionnaireFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 320,
      padding: const EdgeInsets.only(top: BSSpace.s2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: file.valid ? BSColors.text : BSColors.neutral400, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            file.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BSType.buzzerNameConsole(
              size: 23,
              color: file.valid ? BSColors.text : BSColors.neutral500,
            ),
          ),
          const SizedBox(height: BSSpace.s1),
          Text(
            file.valid
                ? '${file.questionCount} question${file.questionCount > 1 ? 's' : ''}'
                : 'Fichier illisible',
            style: BSType.body(
              size: 15,
              color: file.valid ? BSColors.accent700 : BSColors.accent2_800,
            ),
          ),
          Text(_dateLabel(file.modified), style: BSType.body(size: 13, color: BSColors.neutral600)),
        ],
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }

  static String _dateLabel(DateTime d) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return 'Modifié le ${deux(d.day)}/${deux(d.month)}/${d.year} à ${deux(d.hour)}:${deux(d.minute)}';
  }
}

// -------------------------------------------------------------------- Éditeur

class _Editor extends StatelessWidget {
  const _Editor({
    required this.questionnaire,
    required this.dirty,
    required this.onBack,
    required this.saved,
    required this.onChanged,
    required this.onSave,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  final Questionnaire questionnaire;
  final bool dirty;
  final VoidCallback onBack;
  final bool saved;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final total = questionnaire.questions.length;
    final utiles = questionnaire.usableCount;
    // Liste PARESSEUSE, et pas une colonne : la banque complète du buzzer
    // fait 2000 questions, soit 4000 champs de saisie. Tout construire d'un
    // coup rendait le fichier impossible à ouvrir. Ici, seules les lignes
    // visibles existent.
    //
    // Conséquence assumée : une ligne sortie de l'écran est détruite, avec
    // son champ. Le texte survit (il est déjà écrit dans le questionnaire, à
    // chaque frappe), mais pas le curseur : revenir sur une question après
    // avoir beaucoup défilé demande de recliquer dedans.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            children: [
              // Retour à la bibliothèque : seule sortie de l'éditeur, donc
              // toujours au même endroit, en tête de page.
              TextButton(
                onPressed: onBack,
                style: TextButton.styleFrom(
                  foregroundColor: BSColors.neutral700,
                  padding: const EdgeInsets.only(right: BSSpace.s2),
                ),
                child: const Text('‹ Questionnaires'),
              ),
              const SizedBox(width: BSSpace.s2),
              Expanded(
                child: _Field(
                  // Clé sur l'identité du questionnaire : sans elle, ouvrir
                  // un autre fichier réutiliserait le champ existant et
                  // garderait l'ancien texte à l'écran.
                  key: ValueKey(questionnaire),
                  value: questionnaire.title,
                  hint: 'Titre du questionnaire',
                  style: BSType.buzzerNameConsole(size: 26),
                  onChanged: (v) {
                    questionnaire.title = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: BSSpace.s3),
              if (dirty)
                Padding(
                  padding: const EdgeInsets.only(right: BSSpace.s2),
                  child: Text('Non enregistré', style: BSType.body(size: 14, color: BSColors.accent2_800)),
                ),
              FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: BSColors.accent,
                  foregroundColor: BSColors.bg,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                child: const Text('Enregistrer'),
              ),
              if (saved) ...[
                const SizedBox(width: BSSpace.s2),
                TextButton(
                  onPressed: onRename,
                  style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
                  child: const Text('Renommer le fichier'),
                ),
              ],
              const SizedBox(width: BSSpace.s2),
              TextButton(
                onPressed: onExport,
                style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
                child: const Text('Exporter'),
              ),
              if (onDelete != null)
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(foregroundColor: BSColors.neutral600),
                  child: const Text('Supprimer'),
                ),
            ],
          ),
          const SizedBox(height: BSSpace.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sans ce champ, tout ce qu'on écrit soi-même s'entasse à
              // jamais dans « Mes questionnaires » : le classement ne
              // servirait qu'aux fichiers générés.
              SizedBox(
                width: 280,
                child: _Field(
                  key: ValueKey('collection-${identityHashCode(questionnaire)}'),
                  value: questionnaire.collection,
                  hint: 'Collection (facultative)',
                  style: BSType.body(size: 16, color: BSColors.neutral700),
                  onChanged: (v) {
                    questionnaire.collection = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: BSSpace.s4),
              Expanded(
                child: _Field(
                  key: ValueKey('note-${identityHashCode(questionnaire)}'),
                  value: questionnaire.note,
                  hint: "Note pour l'animateur (facultative)",
                  style: BSType.body(size: 16, color: BSColors.neutral700),
                  onChanged: (v) {
                    questionnaire.note = v;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: BSSpace.s4),
          // En-têtes de colonnes : inutiles avec une question, précieux avec
          // trente, quand la catégorie n'est plus qu'une colonne de texte
          // gris parmi d'autres.
          Row(
            children: [
              Expanded(
                child: Text(
                  utiles == total
                      ? '$total question${total > 1 ? 's' : ''}'
                      : '$utiles question${utiles > 1 ? 's' : ''} sur $total (les autres sont vides)',
                  style: BSType.sectionKicker(),
                ),
              ),
              SizedBox(width: 240, child: Text('CATÉGORIE', style: BSType.sectionKicker())),
              const SizedBox(width: 44),
            ],
          ),
              const SizedBox(height: BSSpace.s2),
              Container(height: 1, color: BSColors.text),
            ],
          ),
        ),
        SliverList.builder(
          itemCount: questionnaire.questions.length,
          itemBuilder: (context, i) => _QuestionRow(
            key: ValueKey('${identityHashCode(questionnaire)}-${identityHashCode(questionnaire.questions[i])}'),
            index: i,
            question: questionnaire.questions[i],
            onChanged: onChanged,
            // Jamais moins d'une ligne : un questionnaire sans aucune
            // ligne n'offrirait plus rien où écrire.
            onDelete: questionnaire.questions.length <= 1
                ? null
                : () {
                    questionnaire.questions.removeAt(i);
                    onChanged();
                  },
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: BSSpace.s4),
              OutlinedButton(
                onPressed: () {
                  questionnaire.questions.add(QuizQuestion());
                  onChanged();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: BSColors.text,
                  side: const BorderSide(color: BSColors.divider),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                child: const Text('Ajouter une question'),
              ),
              const SizedBox(height: BSSpace.s8),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    super.key,
    required this.index,
    required this.question,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final QuizQuestion question;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BSColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BSSpace.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${index + 1}',
                  style: BSType.body(size: 17, color: BSColors.neutral500),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(
                    value: question.question,
                    hint: 'Question',
                    style: BSType.body(size: 19, color: BSColors.text),
                    onChanged: (v) {
                      question.question = v;
                      onChanged();
                    },
                  ),
                  const SizedBox(height: BSSpace.s1),
                  _Field(
                    value: question.answer,
                    hint: 'Réponse',
                    style: BSType.answerConsole().copyWith(fontSize: 17),
                    onChanged: (v) {
                      question.answer = v;
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: BSSpace.s3),
            // Catégorie libre, avec les dix du firmware en suggestion : un
            // questionnaire à thème invente ses propres catégories
            // (« Films de Noël »), mais autant ne pas retaper « Histoire ».
            SizedBox(
              width: 240,
              child: _CategoryField(
                value: question.category,
                onChanged: (v) {
                  question.category = v;
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 44,
              child: IconButton(
                tooltip: onDelete == null ? null : 'Retirer cette question',
                onPressed: onDelete,
                color: BSColors.neutral500,
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Field(
            value: value,
            hint: 'Catégorie',
            style: BSType.body(size: 15, color: BSColors.neutral700),
            onChanged: onChanged,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Catégories courantes',
          color: BSColors.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          onSelected: onChanged,
          itemBuilder: (context) => [
            for (final name in kCategoryNames)
              PopupMenuItem(
                value: name,
                child: Text(name, style: BSType.body(size: 15, color: BSColors.text)),
              ),
          ],
          icon: const Icon(Icons.arrow_drop_down, size: 20, color: BSColors.neutral500),
        ),
      ],
    );
  }
}

// Champ de saisie sans décor : le design system n'a ni encadré ni ombre, et
// un formulaire de vingt questions couvert de boîtes serait illisible. Un
// simple filet sous le texte suffit à dire qu'on peut écrire là.
class _Field extends StatefulWidget {
  const _Field({
    super.key,
    required this.value,
    required this.hint,
    required this.style,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final TextStyle style;
  final ValueChanged<String> onChanged;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: widget.style,
      minLines: 1,
      maxLines: 4,
      cursorColor: BSColors.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: widget.style.copyWith(color: BSColors.neutral400),
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: BSColors.divider),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: BSColors.accent, width: 2),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
