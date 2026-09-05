import 'package:flutter/material.dart';

import '../../protocol.dart';
import '../../questionnaires/active_questionnaire.dart';
import '../../questionnaires/catalogue.dart';
import '../../questionnaires/questionnaire.dart';
import '../../questionnaires/questionnaire_store.dart';
import '../tokens.dart';

// Écran "Questions" : la bibliothèque de questionnaires, et l'atelier pour
// en écrire.
//
// DEUX PROVENANCES, et c'est ce qui structure tout l'écran.
//
// Le CATALOGUE est publié en ligne (buzzer.sd6tools.net) et se consulte en
// entier sans rien avoir téléchargé. Il est en lecture seule : personne ne
// modifie sur son poste un fichier que tout le monde reçoit. Le nuage de
// chaque carte garde une copie locale, ou la retire.
//
// « Personnalisé » est le dossier de l'opérateur, sur son disque, modifiable
// et jamais publié. C'est le seul endroit où il peut perdre du travail.
//
// Le classement se fait donc par provenance et non par métadonnée : un
// questionnaire personnel n'a pas de collection à lui, l'éditeur n'en demande
// plus.
//
// Deux moments successifs, pas deux volets : la bibliothèque prend tout
// l'écran pour choisir, l'éditeur prend tout l'écran pour écrire. Garder la
// liste visible pendant la saisie volait sa largeur à la seule chose qu'on
// fait à ce moment-là.
class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen(
      {super.key,
      required this.store,
      required this.catalogue,
      required this.actif,
      required this.pourLaPartie,
      required this.onRetourPartie});

  final QuestionnaireStore store;
  final CatalogueStore catalogue;
  final ActiveQuestionnaire actif;
  // Vrai quand on est arrive ici DEPUIS le lancement d'une partie. L'ecran
  // dit alors pourquoi, et comment revenir.
  final bool pourLaPartie;
  // Ramene a l'ecran Partie. Appele des qu'un questionnaire est mis en jeu :
  // choisir un questionnaire EST une etape du lancement, pas une visite a la
  // bibliotheque, et laisser l'operateur retrouver son chemin tout seul
  // apres coup etait un oubli.
  final VoidCallback onRetourPartie;

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  Questionnaire? _open;
  String? _openPath;
  // Renseigné quand ce qui est ouvert vient du catalogue : l'éditeur passe
  // alors en consultation, et « Dupliquer » remplace « Enregistrer ».
  CatalogueEntry? _openEntry;
  bool _dirty = false;
  // Gardée ici, et non dans la bibliothèque : refermer l'éditeur doit
  // ramener dans la collection d'où on venait, pas à la case départ.
  // Arrivé depuis le lancement d'une partie, on ouvre DIRECTEMENT sur
  // « Personnalisé » : c'est la seule provenance qu'on met encore en jeu
  // fichier par fichier. Le catalogue se pioche par le tirage, pas en
  // choisissant « Histoire 07 sur 11 » dans une grille de vingt tuiles.
  late _Selection _selection = widget.pourLaPartie
      ? const _Selection.de(kPersonnalise)
      : const _Selection.grille();

  @override
  void initState() {
    super.initState();
    widget.store.loadPreferences();
    widget.catalogue.init();
  }

  void _touch() => setState(() => _dirty = true);

  void _newQuestionnaire() {
    setState(() {
      _open = Questionnaire(questions: [QuizQuestion()]);
      _openPath = null;
      _openEntry = null;
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
      _openEntry = null;
      _dirty = false;
    });
  }

  Future<void> _openCatalogueEntry(CatalogueEntry entry) async {
    if (!await _confirmDiscard()) return;
    final loaded = await widget.catalogue.load(entry);
    if (!mounted) return;
    if (loaded == null) {
      _tell(widget.catalogue.lastError ??
          "« ${entry.title} » n'a pas pu être lu.");
      return;
    }
    setState(() {
      _open = loaded;
      _openPath = null;
      _openEntry = entry;
      _dirty = false;
    });
  }

  // Repart d'un questionnaire du catalogue pour en faire un à soi. Sans ça,
  // adapter une manche existante obligerait à la retaper.
  Future<void> _duplicateOpen() async {
    final open = _open;
    if (open == null) return;
    final path = await widget.store.duplicate(open);
    if (!mounted) return;
    if (path == null) {
      _tell(widget.store.lastError ?? 'Duplication impossible.');
      return;
    }
    final copie = await widget.store.load(path);
    if (!mounted || copie == null) return;
    setState(() {
      _open = copie;
      _openPath = path;
      _openEntry = null;
      _dirty = false;
      _selection = const _Selection.de(kPersonnalise);
    });
    _tell('Copie créée dans $kPersonnalise. Elle est modifiable.');
  }

  // Met le questionnaire ouvert en jeu. À partir de là, c'est l'application
  // qui fournit les questions et le buzzer ne s'occupe que des boutons.
  void _useForGame() {
    final open = _open;
    if (open == null) return;
    if (open.questions.where((q) => q.isUsable).isEmpty) {
      _tell("Ce questionnaire n'a aucune question à poser.");
      return;
    }
    final entry = _openEntry;
    widget.actif.use(
      open.copy(),
      origine: entry == null
          ? kPersonnalise
          : entry.collection.isEmpty
              ? 'Catalogue'
              : 'Catalogue · ${entry.collection}',
    );
    // Une copie, pas l'objet ouvert : sinon continuer à écrire dans
    // l'éditeur modifierait la partie en cours sous les pieds de l'animateur.
    //
    // Et on ramène à Partie plutôt que d'y envoyer par un message. Choisir un
    // questionnaire EST une étape du lancement : laisser l'opérateur retrouver
    // son chemin après coup était un oubli, et il n'avait aucun moyen évident
    // de revenir s'il s'était trompé de source.
    _tell('« ${open.title} » est en jeu.');
    widget.onRetourPartie();
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
      _openEntry = null;
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
      // Les deux sources sont écoutées ensemble : un nuage cliqué change le
      // catalogue, un enregistrement change le dossier, et la bibliothèque
      // doit se redessiner dans les deux cas.
      listenable: Listenable.merge([widget.store, widget.catalogue]),
      builder: (context, _) {
        if (_open == null) {
          return _Library(
            store: widget.store,
            pourLaPartie: widget.pourLaPartie,
            onRetourPartie: widget.onRetourPartie,
            catalogue: widget.catalogue,
            selection: _selection,
            onSelect: (s) => setState(() => _selection = s),
            onNew: _newQuestionnaire,
            onOpen: _openFile,
            onOpenEntry: _openCatalogueEntry,

            onImport: () async {
              final path = await widget.store.import();
              if (!mounted) return;
              if (path == null && widget.store.lastError != null) {
                _tell(widget.store.lastError!);
              }
            },
          );
        }
        final entry = _openEntry;
        return _Editor(
          questionnaire: _open!,
          dirty: _dirty,
          saved: _openPath != null,
          // Lecture seule : ce qui vient du catalogue appartient à tout le
          // monde, le modifier sur un poste n'aurait aucun sens.
          readOnly: entry != null,
          origine: entry?.collection,
          pourLaPartie: widget.pourLaPartie,
          onBack: _close,
          onChanged: _touch,
          onSave: _save,
          onRename: _saveAsNewName,
          onDuplicate: _duplicateOpen,
          onUseForGame: _useForGame,
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
      _openEntry = null;
      _dirty = false;
    });
  }
}

// --------------------------------------------------------------- Bibliothèque

// Où en est la bibliothèque : la grille des collections, une collection
// précise, ou tout d'un coup.
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
  bool get estPersonnalise => collection == kPersonnalise;
}

// L'heure seule quand c'est aujourd'hui, la date en plus sinon : une copie
// hors ligne peut remonter à des semaines, et « lue à 10:39 » laisserait
// croire à ce matin.
String _quand(DateTime? moment) {
  if (moment == null) return 'à une date inconnue';
  String deux(int n) => n.toString().padLeft(2, '0');
  final heure = 'à ${deux(moment.hour)}:${deux(moment.minute)}';
  final maintenant = DateTime.now();
  final memeJour = moment.year == maintenant.year &&
      moment.month == maintenant.month &&
      moment.day == maintenant.day;
  return memeJour ? heure : 'le ${deux(moment.day)}/${deux(moment.month)} $heure';
}

class _Library extends StatelessWidget {
  const _Library({
    required this.store,
    required this.pourLaPartie,
    required this.onRetourPartie,
    required this.catalogue,
    required this.selection,
    required this.onSelect,
    required this.onNew,
    required this.onOpen,
    required this.onOpenEntry,
    required this.onImport,
  });

  final QuestionnaireStore store;
  final bool pourLaPartie;
  final VoidCallback onRetourPartie;
  final CatalogueStore catalogue;
  final _Selection selection;
  final ValueChanged<_Selection> onSelect;
  final VoidCallback onNew;
  final ValueChanged<QuestionnaireFile> onOpen;
  final ValueChanged<CatalogueEntry> onOpenEntry;
  final VoidCallback onImport;

  // Deux niveaux : on choisit une collection, PUIS un questionnaire. Cent
  // vingt-cinq cartes d'un seul tenant, c'est un mur où plus rien ne se
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

  // Bandeau montré quand on est arrivé ici depuis le lancement d'une partie.
  // Il répond aux deux questions qu'on se pose alors : pourquoi suis-je ici,
  // et comment j'en sors si je me suis trompé. La barre latérale suffisait
  // techniquement, mais on ne la regarde pas quand on est concentré sur une
  // tâche.
  List<Widget> _bandeauPartie() {
    if (!pourLaPartie) return const [];
    return [
      Container(
        margin: const EdgeInsets.only(bottom: BSSpace.s4),
        padding: const EdgeInsets.fromLTRB(BSSpace.s3, BSSpace.s2, BSSpace.s2, BSSpace.s2),
        decoration: const BoxDecoration(
          color: BSColors.accent100,
          border: Border(top: BorderSide(color: BSColors.accent, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Choisissez un de vos questionnaires, puis « Utiliser pour la '
                'partie ». Pour une manche tirée dans la banque, revenez à '
                'Partie et utilisez « Questions au hasard ».',
                style: BSType.body(size: 16, color: BSColors.accent900),
              ),
            ),
            const SizedBox(width: BSSpace.s3),
            TextButton(
              onPressed: onRetourPartie,
              style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
              child: const Text('‹ Retour à Partie'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _grille() {
    final entrees = catalogue.catalogue.entries;
    final questionsCatalogue =
        entrees.fold<int>(0, (somme, e) => somme + e.questionCount);

    return [
      ..._bandeauPartie(),
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
        width: 820,
        child: Text(
          'Le catalogue est la banque dans laquelle « Questions au hasard » '
          'pioche pendant une partie. Il se consulte en entier sans rien avoir '
          'téléchargé, et le nuage de chaque questionnaire le garde sur ce '
          'poste pour jouer sans réseau. Ce que vous écrivez vous-même vit '
          'dans « $kPersonnalise », ne part jamais en ligne, et reste le seul '
          'questionnaire qu\'on met en jeu tel quel.',
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
      ),
      const SizedBox(height: BSSpace.s6),
      Row(
        children: [
          Text('COLLECTIONS', style: BSType.sectionKicker()),
          const SizedBox(width: BSSpace.s3),
          // D'où vient cette liste, dit en clair. « Rien ne signale un
          // problème » est une preuve trop faible : sans cette ligne, la
          // seule façon de savoir que le catalogue vient du réseau était de
          // remarquer l'ABSENCE d'un avertissement.
          if (catalogue.loading)
            Text('Lecture du catalogue...',
                style: BSType.body(size: 14, color: BSColors.neutral600))
          // Trois provenances, pas deux. La copie livrée avec l'application a
          // l'âge de l'installation, ce qui n'est pas la même chose qu'un
          // cache vieux de trois jours : dire « hors ligne » pour les deux
          // laisserait croire qu'un rafraîchissement récent a eu lieu.
          else if (catalogue.depuisLeBuild)
            Text(
              'Hors ligne. Questions livrées avec l\'application, '
              'à rafraîchir dès que le réseau revient',
              style: BSType.body(size: 14, color: BSColors.accent2_800),
            )
          else if (catalogue.horsLigne)
            Text(
              'Hors ligne. Copie du poste, lue ${_quand(catalogue.lastFetch)}',
              style: BSType.body(size: 14, color: BSColors.accent2_800),
            )
          else if (entrees.isNotEmpty)
            Text(
              'Lu en ligne ${_quand(catalogue.lastFetch)} · '
              '${entrees.length} questionnaires, ${catalogue.localCount} sur ce poste',
              style: BSType.body(size: 14, color: BSColors.accent700),
            ),
          const SizedBox(width: BSSpace.s2),
          TextButton(
            onPressed: catalogue.loading ? null : catalogue.refresh,
            style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
            child: const Text('Rafraîchir'),
          ),
        ],
      ),
      const SizedBox(height: BSSpace.s2),
      Wrap(
        spacing: BSSpace.s4,
        runSpacing: BSSpace.s4,
        children: [
          // La tuile qui ne filtre rien, en tête : c'est le repli quand on ne
          // sait pas dans quelle collection chercher.
          _CollectionCard(
            titre: 'Tous les questionnaires',
            emoji: '📚',
            fichiers: entrees.length + store.files.length,
            questions: questionsCatalogue + store.questionCount,
            vedette: true,
            onTap: () => onSelect(const _Selection.tout()),
          ),
          // Ce que l'opérateur a écrit passe avant le catalogue : c'est le
          // seul endroit où il peut perdre quelque chose.
          _CollectionCard(
            titre: kPersonnalise,
            emoji: kEmojiPersonnalise,
            fichiers: store.files.length,
            questions: store.questionCount,
            vedette: false,
            onTap: () => onSelect(const _Selection.de(kPersonnalise)),
          ),
          for (final collection in catalogue.catalogue.collections)
            _CollectionCard(
              titre: collection.name,
              emoji: collection.emoji,
              fichiers: collection.fileCount,
              questions: collection.questionCount,
              vedette: false,
              nuage: _NuageCollection(catalogue: catalogue, collection: collection),
              onTap: () => onSelect(_Selection.de(collection.name)),
            ),
        ],
      ),
      if (catalogue.catalogue.isEmpty && !catalogue.loading) ...[
        const SizedBox(height: BSSpace.s4),
        SizedBox(
          width: 820,
          child: Text(
            catalogue.lastError ??
                "Aucun catalogue pour le moment. Vérifiez l'adresse ci-dessous.",
            style: BSType.body(size: 15, color: BSColors.accent2_800),
          ),
        ),
      ],
      const SizedBox(height: BSSpace.s8),
      ..._reglages(),
    ];
  }

  // --- Second niveau : les questionnaires

  List<Widget> _liste() {
    final titre = selection.toutes ? 'Tous les questionnaires' : selection.collection!;

    // Les deux provenances ne donnent pas la même carte : l'une se modifie et
    // s'efface, l'autre se télécharge et se consulte.
    final perso = (selection.toutes || selection.estPersonnalise) ? store.files : const [];
    final entrees = selection.estPersonnalise
        ? const <CatalogueEntry>[]
        : selection.toutes
            ? catalogue.catalogue.entries
            : catalogue.entriesOf(titre);
    final total = perso.length + entrees.length;

    return [
      ..._bandeauPartie(),
      Row(
        children: [
          // Pas de retour aux collections quand on choisit pour une partie :
          // la grille mène au catalogue, qui n'est plus une source de jeu.
          // Le bandeau au-dessus offre déjà la seule sortie qui a du sens.
          if (!pourLaPartie) ...[
            TextButton(
              onPressed: () => onSelect(const _Selection.grille()),
              style: TextButton.styleFrom(
                foregroundColor: BSColors.neutral700,
                padding: const EdgeInsets.only(right: BSSpace.s2),
              ),
              child: const Text('‹ Collections'),
            ),
            const SizedBox(width: BSSpace.s2),
          ],
          // Flexible : une collection peut avoir un nom long, et le titre ne
          // doit pas pousser les boutons hors écran.
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
      Row(
        children: [
          Text(
            '$total questionnaire${total > 1 ? 's' : ''}',
            style: BSType.body(size: 15, color: BSColors.accent700),
          ),
          if (entrees.isNotEmpty) ...[
            const SizedBox(width: BSSpace.s3),
            Text(
              '${entrees.where((e) => catalogue.estLocal(e.id)).length} sur ce poste',
              style: BSType.body(size: 15, color: BSColors.neutral600),
            ),
          ],
        ],
      ),
      const SizedBox(height: BSSpace.s6),
      if (total == 0)
        Text(
          selection.estPersonnalise
              ? "Aucun questionnaire à vous pour le moment. « Nouveau » en crée un, "
                  "et un questionnaire du catalogue peut être dupliqué ici."
              : 'Cette collection est vide.',
          style: BSType.body(size: 17, color: BSColors.neutral600),
        )
      else
        Wrap(
          spacing: BSSpace.s4,
          runSpacing: BSSpace.s4,
          children: [
            for (final file in perso)
              _QuestionnaireCard(file: file, onTap: () => onOpen(file)),
            for (final entry in entrees)
              _CatalogueCard(
                entry: entry,
                catalogue: catalogue,
                onTap: () => onOpenEntry(entry),
              ),
          ],
        ),
      if (catalogue.lastError != null) ...[
        const SizedBox(height: BSSpace.s4),
        SizedBox(
          width: 900,
          child: Text(catalogue.lastError!,
              style: BSType.body(size: 15, color: BSColors.accent2_800)),
        ),
      ],
    ];
  }

  // --- Les réglages, montrés au premier niveau seulement : au second, on est
  // venu chercher un questionnaire, pas régler un chemin.

  List<Widget> _reglages() {
    return [
      // Pas de bloc « catalogue en ligne » : son adresse est interne, il n'y
      // a rien à régler. Quand quelque chose échoue, le message d'erreur la
      // nomme, et c'est le seul moment où elle compte.
      Container(height: 1, color: BSColors.divider),
      const SizedBox(height: BSSpace.s4),
      Text('MES QUESTIONNAIRES', style: BSType.sectionKicker()),
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
    required this.emoji,
    required this.fichiers,
    required this.questions,
    required this.vedette,
    required this.onTap,
    this.nuage,
  });

  final String titre;
  final String emoji;
  final int fichiers;
  final int questions;
  // La tuile « Tous les questionnaires » : même forme, couleur d'accent, pour
  // qu'elle se distingue des collections sans être un autre objet.
  final bool vedette;
  // Absent pour « Tous » et « Personnalisé », qui ne se synchronisent pas.
  final Widget? nuage;
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
          // Sur sa propre ligne, pas devant le titre : les noms de collection
          // vont sur deux lignes, et un emoji collé au début du texte pousse
          // le retour à la ligne à un endroit différent pour chaque tuile.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26, height: 1.2)),
              const Spacer(),
              ?nuage,
            ],
          ),
          const SizedBox(height: BSSpace.s1),
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

// Une carte de questionnaire du catalogue. Le titre ouvre en consultation, le
// nuage rapatrie ou retire. Deux zones cliquables distinctes sur la même
// carte, donc le nuage arrête la propagation du geste.
class _CatalogueCard extends StatelessWidget {
  const _CatalogueCard({
    required this.entry,
    required this.catalogue,
    required this.onTap,
  });

  final CatalogueEntry entry;
  final CatalogueStore catalogue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final local = catalogue.estLocal(entry.id);
    final perime = catalogue.estPerime(entry);

    final card = Container(
      width: 320,
      padding: const EdgeInsets.only(top: BSSpace.s2),
      decoration: BoxDecoration(
        border: Border(
          // Filet plein quand le questionnaire est là, en pointillé de gris
          // quand il n'est qu'annoncé : l'état se voit sans lire le nuage.
          top: BorderSide(color: local ? BSColors.text : BSColors.neutral400, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BSType.buzzerNameConsole(
                    size: 23,
                    color: local ? BSColors.text : BSColors.neutral600,
                  ),
                ),
              ),
              const SizedBox(width: BSSpace.s2),
              _NuageQuestionnaire(catalogue: catalogue, entry: entry),
            ],
          ),
          const SizedBox(height: BSSpace.s1),
          Text(
            _compteEtNiveau(entry.questionCount, entry.etiquetteNiveau),
            style: BSType.body(
              size: 15,
              color: local ? BSColors.accent700 : BSColors.neutral600,
            ),
          ),
          Text(
            perime
                ? 'Une version plus récente est en ligne'
                : local
                    ? 'Sur ce poste, en lecture seule'
                    : 'En ligne, en lecture seule',
            style: BSType.body(
              size: 13,
              color: perime ? BSColors.accent2_800 : BSColors.neutral600,
            ),
          ),
        ],
      ),
    );

    // Tout le catalogue se lit, rapatrié ou non : le nuage commande la copie
    // hors ligne, pas le droit de lire. Une carte non locale se télécharge le
    // temps de l'ouvrir et ne laisse rien derrière elle.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

// Le nuage d'un questionnaire : un interrupteur. Un clic rapatrie, un clic
// retire. Quatre états, parce que « en cours » et « périmé » ne peuvent pas
// se confondre avec les deux autres sans mentir.
class _NuageQuestionnaire extends StatelessWidget {
  const _NuageQuestionnaire({required this.catalogue, required this.entry});

  final CatalogueStore catalogue;
  final CatalogueEntry entry;

  @override
  Widget build(BuildContext context) {
    // Même fileur pour le rapatriement et pour une lecture en ligne : dans
    // les deux cas quelque chose est en train d'arriver du réseau pour ce
    // questionnaire, et c'est ce que l'opérateur a besoin de savoir.
    if (catalogue.estEnCours(entry.id) || catalogue.estEnOuverture(entry.id)) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: BSColors.accent),
      );
    }

    final local = catalogue.estLocal(entry.id);
    final perime = catalogue.estPerime(entry);

    final IconData icone;
    final Color couleur;
    final String infobulle;
    if (perime) {
      icone = Icons.cloud_sync;
      couleur = BSColors.accent2;
      infobulle = 'Mettre à jour depuis le catalogue';
    } else if (local) {
      icone = Icons.cloud_done;
      couleur = BSColors.accent;
      infobulle = 'Sur ce poste. Cliquez pour retirer la copie locale.';
    } else {
      icone = Icons.cloud_outlined;
      couleur = BSColors.neutral500;
      infobulle = 'En ligne seulement. Cliquez pour garder sur ce poste.';
    }

    return Tooltip(
      message: infobulle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Sans ce garde, le clic sur le nuage ouvrirait aussi le
          // questionnaire, la carte entière étant cliquable.
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              local && !perime ? catalogue.unsync(entry) : catalogue.sync(entry),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Icon(icone, size: 22, color: couleur),
          ),
        ),
      ),
    );
  }
}

// Le nuage d'une collection. Trois états : rien, une partie, tout. La
// fraction est écrite en clair quand c'est partiel, parce qu'aucune nuance
// d'icône ne dit « trois manches sur huit » aussi bien qu'un chiffre.
class _NuageCollection extends StatelessWidget {
  const _NuageCollection({required this.catalogue, required this.collection});

  final CatalogueStore catalogue;
  final CatalogueCollection collection;

  @override
  Widget build(BuildContext context) {
    final entrees = catalogue.entriesOf(collection.name);
    final locales = entrees.where((e) => catalogue.estLocal(e.id)).length;
    final etat = catalogue.stateOf(collection.name);
    final occupe = entrees.any((e) => catalogue.estEnCours(e.id));

    if (occupe) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: BSColors.accent),
      );
    }

    final complet = etat == SyncState.complet;
    final IconData icone;
    final Color couleur;
    final String infobulle;
    switch (etat) {
      case SyncState.complet:
        icone = Icons.cloud_done;
        couleur = BSColors.accent;
        infobulle = 'Toute la collection est sur ce poste. '
            'Cliquez pour retirer les copies locales.';
      case SyncState.partiel:
        icone = Icons.cloud_download;
        couleur = BSColors.accent600;
        infobulle = '$locales sur ${entrees.length} sur ce poste. '
            'Cliquez pour rapatrier le reste.';
      case SyncState.absent:
        icone = Icons.cloud_outlined;
        couleur = BSColors.neutral500;
        infobulle = 'Cliquez pour rapatrier les ${entrees.length} questionnaires.';
    }

    return Tooltip(
      message: infobulle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => complet
              ? catalogue.unsyncCollection(collection.name)
              : catalogue.syncCollection(collection.name),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              children: [
                if (etat == SyncState.partiel)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('$locales/${entrees.length}',
                        style: BSType.body(size: 13, color: BSColors.accent700)),
                  ),
                Icon(icone, size: 22, color: couleur),
              ],
            ),
          ),
        ),
      ),
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
                ? _compteEtNiveau(file.questionCount, file.etiquetteNiveau)
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

// « 25 questions · facile ». Le niveau suit le compte sur la même ligne : c'est
// la deuxième chose qu'on veut savoir d'un questionnaire avant de l'ouvrir,
// et une ligne de plus par carte alourdirait toute la grille.
String _compteEtNiveau(int compte, String? niveau) {
  final base = '$compte question${compte > 1 ? 's' : ''}';
  return niveau == null ? base : '$base · $niveau';
}

// L'en-tête de l'éditeur détaille ce que la carte résume : « 25 questions ·
// 12 faciles, 10 moyennes, 3 difficiles ». Les questions vides restent
// signalées comme avant, et les niveaux ne s'affichent que s'il y en a.
String _resumeQuestions(int total, int utiles, Map<int, int> niveaux) {
  final compte = utiles == total
      ? '$total question${total > 1 ? 's' : ''}'
      : '$utiles question${utiles > 1 ? 's' : ''} sur $total (les autres sont vides)';
  if (niveaux.isEmpty) return compte;
  const pluriels = {1: 'faciles', 2: 'moyennes', 3: 'difficiles'};
  final parts = [
    for (final n in [1, 2, 3])
      if ((niveaux[n] ?? 0) > 0) '${niveaux[n]} ${pluriels[n]}',
  ];
  return '$compte · ${parts.join(', ')}';
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
    required this.onDuplicate,
    required this.onUseForGame,
    required this.onExport,
    required this.onDelete,
    required this.readOnly,
    required this.origine,
    required this.pourLaPartie,
  });

  final Questionnaire questionnaire;
  final bool dirty;
  final VoidCallback onBack;
  final bool saved;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onUseForGame;
  final VoidCallback onExport;
  final VoidCallback? onDelete;
  // Arrive depuis le lancement d'une partie : on ne vient chercher qu'une
  // chose, le questionnaire a jouer. Tout ce qui touche a la GESTION des
  // fichiers (dupliquer, exporter, supprimer) est du bruit a ce moment-la,
  // et « Utiliser pour la partie » devient l'action principale.
  final bool pourLaPartie;
  // Consultation : le questionnaire vient du catalogue. Les champs sont figés
  // et il n'y a ni Enregistrer, ni Renommer, ni Supprimer.
  final bool readOnly;
  // La collection d'origine, montrée en consultation pour qu'on sache d'où
  // sort ce qu'on lit.
  final String? origine;

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
                  readOnly: readOnly,
                  style: BSType.buzzerNameConsole(size: 26),
                  onChanged: (v) {
                    questionnaire.title = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: BSSpace.s3),
              // ARRIVE DEPUIS LE LANCEMENT D'UNE PARTIE : une seule action.
              //
              // L'animateur est venu chercher un questionnaire, pas gerer ses
              // fichiers. Dupliquer, exporter et supprimer n'ont rien a faire
              // la, et « Utiliser pour la partie » prend l'habit du bouton
              // principal parce que c'est la seule chose a faire ici.
              if (pourLaPartie)
                FilledButton(
                  onPressed: onUseForGame,
                  style: FilledButton.styleFrom(
                    backgroundColor: BSColors.accent,
                    foregroundColor: BSColors.bg,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: const Text('Utiliser pour la partie'),
                )
              else ...[
              if (readOnly) ...[
                Padding(
                  padding: const EdgeInsets.only(right: BSSpace.s2),
                  child: Text(
                    origine == null ? 'Catalogue' : 'Catalogue · $origine',
                    style: BSType.body(size: 14, color: BSColors.neutral600),
                  ),
                ),
                FilledButton(
                  onPressed: onDuplicate,
                  style: FilledButton.styleFrom(
                    backgroundColor: BSColors.accent,
                    foregroundColor: BSColors.bg,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: const Text('Dupliquer dans Personnalisé'),
                ),
              ] else ...[
                if (dirty)
                  Padding(
                    padding: const EdgeInsets.only(right: BSSpace.s2),
                    child: Text('Non enregistré',
                        style: BSType.body(size: 14, color: BSColors.accent2_800)),
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
              ],
              const SizedBox(width: BSSpace.s2),
              // Disponible dans les deux modes : un questionnaire du
              // catalogue se joue tel quel, il n'y a aucune raison
              // d'obliger à le dupliquer d'abord.
              OutlinedButton(
                onPressed: onUseForGame,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BSColors.text,
                  side: const BorderSide(color: BSColors.divider),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                child: const Text('Utiliser pour la partie'),
              ),
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
            ],
          ),
          const SizedBox(height: BSSpace.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Plus de champ Collection ni Emoji : la bibliothèque range
              // par provenance, et tout ce qui vient de ce dossier va sous
              // « Personnalisé ». Deux champs qui ne changent plus rien.
              Expanded(
                child: _Field(
                  key: ValueKey('note-${identityHashCode(questionnaire)}'),
                  value: questionnaire.note,
                  hint: "Note pour l'animateur (facultative)",
                  readOnly: readOnly,
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
                  _resumeQuestions(total, utiles, questionnaire.niveaux),
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
            readOnly: readOnly,
            onChanged: onChanged,
            // Jamais moins d'une ligne : un questionnaire sans aucune
            // ligne n'offrirait plus rien où écrire.
            onDelete: readOnly || questionnaire.questions.length <= 1
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
              if (!readOnly)
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
    required this.readOnly,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final QuizQuestion question;
  final bool readOnly;
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
                    readOnly: readOnly,
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
                    readOnly: readOnly,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CategoryField(
                    value: question.category,
                    readOnly: readOnly,
                    onChanged: (v) {
                      question.category = v;
                      onChanged();
                    },
                  ),
                  _NiveauField(
                    value: question.niveau,
                    readOnly: readOnly,
                    onChanged: (v) {
                      question.niveau = v;
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
            // La largeur reste réservée même en consultation : les lignes
            // gardent l'alignement de l'en-tête de colonnes. Mais la croix
            // disparaît au lieu d'être grisée, sinon la colonne se remplit
            // de boutons morts.
            SizedBox(
              width: 44,
              child: readOnly
                  ? null
                  : IconButton(
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

// Le niveau d'une question, sous sa catégorie. En consultation, un mot, ou
// rien si personne ne l'a coté. En édition, les trois mots côte à côte, celui
// qui est retenu souligné, et un second clic le retire : trois options ne
// méritent ni menu ni boîte.
class _NiveauField extends StatelessWidget {
  const _NiveauField(
      {required this.value, required this.readOnly, required this.onChanged});

  final int? value;
  final bool readOnly;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (readOnly) {
      final nom = kNomsNiveaux[value];
      if (nom == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: BSSpace.s1),
        child: Text(nom, style: BSType.body(size: 13, color: BSColors.neutral600)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: BSSpace.s1),
      child: Row(
        children: [
          for (final entry in kNomsNiveaux.entries) ...[
            InkWell(
              onTap: () => onChanged(value == entry.key ? null : entry.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  entry.value,
                  style: BSType.body(
                    size: 13,
                    color: value == entry.key ? BSColors.text : BSColors.neutral500,
                  ).copyWith(
                    decoration: value == entry.key ? TextDecoration.underline : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: BSSpace.s3),
          ],
        ],
      ),
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField(
      {required this.value, required this.readOnly, required this.onChanged});

  final String value;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Field(
            value: value,
            hint: 'Catégorie',
            readOnly: readOnly,
            style: BSType.body(size: 15, color: BSColors.neutral700),
            onChanged: onChanged,
          ),
        ),
        // Pas de menu en consultation : il n'y a rien à choisir, et une
        // flèche de menu suffit à faire croire le contraire.
        if (!readOnly)
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
    this.readOnly = false,
  });

  final String value;
  final String hint;
  final TextStyle style;
  final ValueChanged<String> onChanged;
  // En consultation, le champ garde exactement les mêmes mesures mais perd
  // son filet, son curseur et le droit d'écrire. Un TextField figé plutôt
  // qu'un Text : les lignes gardent leur hauteur au pixel près, et le texte
  // reste sélectionnable, donc copiable.
  final bool readOnly;

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
    final sansFilet = widget.readOnly;
    return TextField(
      controller: _controller,
      style: widget.style,
      minLines: 1,
      maxLines: 4,
      readOnly: widget.readOnly,
      showCursor: !widget.readOnly,
      cursorColor: BSColors.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.readOnly ? null : widget.hint,
        hintStyle: widget.style.copyWith(color: BSColors.neutral400),
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        enabledBorder: sansFilet
            ? InputBorder.none
            : const UnderlineInputBorder(
                borderSide: BorderSide(color: BSColors.divider),
              ),
        focusedBorder: sansFilet
            ? InputBorder.none
            : const UnderlineInputBorder(
                borderSide: BorderSide(color: BSColors.accent, width: 2),
              ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
