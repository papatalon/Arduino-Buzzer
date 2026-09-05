import 'package:flutter/material.dart';

import '../../protocol.dart';
import '../../questionnaires/active_questionnaire.dart';
import '../../questionnaires/banque.dart';
import '../../questionnaires/questionnaire.dart';
import '../../questionnaires/questionnaire_store.dart';
import '../tokens.dart';

// Écran "Questions" : la bibliothèque de questionnaires, et l'atelier pour
// en écrire.
//
// UN SEUL TYPE DE FICHIER, depuis qu'il n'y a plus de questionnaires
// prédécoupés. Les 283 fichiers publiés en ligne ont laissé la place à une
// banque unique dans laquelle l'écran Partie compose une manche au moment de
// jouer, selon la catégorie, la tranche d'âge et le niveau demandés. Un
// fichier figé ne servait plus qu'à répéter, en moins souple, un tirage qui
// sait déjà le faire.
//
// Restent donc les questionnaires que l'opérateur écrit lui-même : sur son
// disque, modifiables, jamais publiés, et le seul endroit où il peut perdre
// du travail. La banque, elle, se lit ici mais ne se joue pas : le fureteur
// est en lecture seule et n'a aucun bouton pour mettre une liste en jeu.
//
// Deux moments successifs, pas deux volets : la bibliothèque prend tout
// l'écran pour choisir, l'éditeur prend tout l'écran pour écrire. Garder la
// liste visible pendant la saisie volait sa largeur à la seule chose qu'on
// fait à ce moment-là.
class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen({
    super.key,
    required this.store,
    required this.banque,
    required this.actif,
    required this.pourLaPartie,
    required this.onRetourPartie,
  });

  final QuestionnaireStore store;
  final BanqueStore banque;
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
  bool _dirty = false;
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

  // Met le questionnaire ouvert en jeu. À partir de là, c'est l'application
  // qui fournit les questions et le buzzer ne s'occupe que des boutons.
  void _useForGame() {
    final open = _open;
    if (open == null) return;
    if (open.questions.where((q) => q.isUsable).isEmpty) {
      _tell("Ce questionnaire n'a aucune question à poser.");
      return;
    }
    widget.actif.use(open.copy(), origine: kPersonnalise);
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
        title: Text(
          'Abandonner les modifications ?',
          style: BSType.buzzerNameConsole(size: 22),
        ),
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
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
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
        content: Text(
          message,
          style: BSType.body(size: 15, color: BSColors.bg),
        ),
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
      // Les deux sources sont écoutées ensemble : la banque arrive du réseau,
      // un enregistrement change le dossier, et l'écran doit se redessiner
      // dans les deux cas.
      listenable: Listenable.merge([widget.store, widget.banque]),
      builder: (context, _) {
        if (_open == null) {
          return _Library(
            store: widget.store,
            banque: widget.banque,
            pourLaPartie: widget.pourLaPartie,
            onRetourPartie: widget.onRetourPartie,
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
          pourLaPartie: widget.pourLaPartie,
          onBack: _close,
          onChanged: _touch,
          onSave: _save,
          onRename: _saveAsNewName,
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
        title: Text(
          'Supprimer ce questionnaire ?',
          style: BSType.buzzerNameConsole(size: 22),
        ),
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
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
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

// L'écran a maintenant DEUX PARTIES, et non plus deux provenances de
// questionnaires.
//
// « Personnalisé » est le dossier de l'opérateur : ses questionnaires à lui,
// modifiables, jamais publiés, et les seuls qu'on mette en jeu tels quels.
// C'est aussi le seul endroit où il peut perdre du travail, donc il passe en
// premier.
//
// LA BANQUE se consulte, ne se joue pas fichier par fichier. Elle a remplacé
// les 283 questionnaires prédécoupés : on compose sa manche au moment de
// jouer, dans l'écran Partie. Ce qu'on vient chercher ici, c'est vérifier une
// question, voir ce qu'une catégorie contient avant une soirée, ou juste
// lire. Le fureteur est donc en lecture seule et n'a aucun bouton « jouer » :
// il n'aurait aucun sens de mettre en jeu une liste filtrée depuis une
// bibliothèque alors que le tirage fait exactement cela, en mieux.
class _Library extends StatelessWidget {
  const _Library({
    required this.store,
    required this.banque,
    required this.pourLaPartie,
    required this.onRetourPartie,
    required this.onNew,
    required this.onOpen,
    required this.onImport,
  });

  final QuestionnaireStore store;
  final BanqueStore banque;
  final bool pourLaPartie;
  final VoidCallback onRetourPartie;
  final VoidCallback onNew;
  final ValueChanged<QuestionnaireFile> onOpen;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._bandeauPartie(),
            Row(
              children: [
                Text('Questions', style: BSType.buzzerNameConsole(size: 26)),
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
                'Ce que vous écrivez vous-même vit dans « $kPersonnalise », ne '
                'part jamais en ligne, et se met en jeu tel quel. La banque, '
                'elle, se consulte ici et se joue depuis l\'écran Partie : '
                '« Questions au hasard » y compose une manche selon la '
                'catégorie, la tranche d\'âge et le niveau que vous choisissez.',
                style: BSType.body(size: 17, color: BSColors.neutral700),
              ),
            ),
            const SizedBox(height: BSSpace.s6),
            ..._mesQuestionnaires(),
            // Le fureteur ne s'affiche pas quand on vient chercher un
            // questionnaire pour une partie : on est là pour choisir un
            // fichier, pas pour lire la banque.
            if (!pourLaPartie) ...[
              const SizedBox(height: BSSpace.s8),
              _FureteurBanque(banque: banque),
            ],
            const SizedBox(height: BSSpace.s8),
            ..._reglages(),
          ],
        ),
      ),
    );
  }

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
        padding: const EdgeInsets.fromLTRB(
          BSSpace.s3,
          BSSpace.s2,
          BSSpace.s2,
          BSSpace.s2,
        ),
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

  List<Widget> _mesQuestionnaires() {
    final fichiers = store.files;
    return [
      Row(
        children: [
          Text(kPersonnalise.toUpperCase(), style: BSType.sectionKicker()),
          const SizedBox(width: BSSpace.s3),
          Text(
            fichiers.isEmpty
                ? 'aucun pour le moment'
                : '${fichiers.length} questionnaire${fichiers.length > 1 ? 's' : ''}',
            style: BSType.body(size: 14, color: BSColors.neutral600),
          ),
        ],
      ),
      const SizedBox(height: BSSpace.s3),
      if (fichiers.isEmpty)
        SizedBox(
          width: 820,
          child: Text(
            'Rien ici encore. « Nouveau » ouvre un questionnaire vide, '
            '« Importer » reprend un fichier reçu de quelqu\'un d\'autre.',
            style: BSType.body(size: 16, color: BSColors.neutral600),
          ),
        )
      else
        Wrap(
          spacing: BSSpace.s6,
          runSpacing: BSSpace.s6,
          children: [
            for (final f in fichiers)
              _QuestionnaireCard(file: f, onTap: () => onOpen(f)),
          ],
        ),
    ];
  }

  List<Widget> _reglages() {
    return [
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
                style: TextButton.styleFrom(
                  foregroundColor: BSColors.neutral600,
                ),
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

  static Widget _boutonContour(String texte, VoidCallback onTap) =>
      OutlinedButton(
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

// ---------------------------------------------------------- Fureteur de banque

// LIRE LA BANQUE, sans la jouer.
//
// Trois usages, et un seul écran suffit pour les trois : vérifier une
// question dont on doute, voir ce qu'une catégorie contient avant une soirée,
// et compter ce qu'un filtre laisse. Les mêmes critères que le tirage, dans
// le même ordre, pour que ce qu'on lit ici corresponde à ce qu'on jouera.
//
// LES RÉPONSES SONT VISIBLES. C'est une bibliothèque, pas une partie : les
// cacher obligerait à cliquer 3684 fois pour vérifier une seule chose.
//
// LA LISTE EST PLAFONNÉE. Afficher 3684 lignes d'un coup fige la fenêtre
// plusieurs secondes pour un résultat que personne ne lit jusqu'au bout ; le
// compte total reste annoncé, et affiner le filtre est de toute façon le
// geste utile.
class _FureteurBanque extends StatefulWidget {
  const _FureteurBanque({required this.banque});

  final BanqueStore banque;

  @override
  State<_FureteurBanque> createState() => _FureteurBanqueState();
}

class _FureteurBanqueState extends State<_FureteurBanque> {
  static const _plafond = 60;

  final Set<String> _categories = {};
  final Set<String> _themes = {};
  final Set<Tranche> _tranches = {};
  final Set<int> _niveaux = {};
  String _recherche = '';

  // Sans accents et sans casse : on tape « quebec » et on trouve « Québec ».
  static String _plat(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c');

  bool _retenue(QuizQuestion q) {
    if (_categories.isNotEmpty || _themes.isNotEmpty) {
      final parCategorie = _categories.contains(q.category);
      final parTheme = q.themes.any(_themes.contains);
      if (!parCategorie && !parTheme) return false;
    }
    if (_niveaux.isNotEmpty &&
        q.niveau != null &&
        !_niveaux.contains(q.niveau)) {
      return false;
    }
    if (_tranches.isNotEmpty &&
        q.ages.isNotEmpty &&
        q.ages.intersection(_tranches).isEmpty) {
      return false;
    }
    if (_recherche.isNotEmpty) {
      final texte = _plat('${q.question} ${q.answer}');
      if (!texte.contains(_plat(_recherche))) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.banque;
    final trouvees = b.banque.questions.where(_retenue).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('LA BANQUE', style: BSType.sectionKicker()),
            const SizedBox(width: BSSpace.s3),
            // D'où vient cette liste, dit en clair. « Rien ne signale un
            // problème » est une preuve trop faible : sans cette ligne, la
            // seule façon de savoir que la banque vient du réseau était de
            // remarquer l'ABSENCE d'un avertissement.
            if (b.loading)
              Text(
                'Lecture de la banque...',
                style: BSType.body(size: 14, color: BSColors.neutral600),
              )
            else if (b.depuisLeBuild)
              Text(
                "Hors ligne. Questions livrées avec l'application, "
                'à rafraîchir dès que le réseau revient',
                style: BSType.body(size: 14, color: BSColors.accent2_800),
              )
            else if (b.horsLigne)
              Text(
                'Hors ligne. Copie du poste, lue ${_quand(b.lastFetch)}',
                style: BSType.body(size: 14, color: BSColors.accent2_800),
              )
            else if (b.total > 0)
              Text(
                'Lue en ligne ${_quand(b.lastFetch)} · ${b.total} questions',
                style: BSType.body(size: 14, color: BSColors.accent700),
              ),
            const SizedBox(width: BSSpace.s2),
            TextButton(
              onPressed: b.loading ? null : b.refresh,
              style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
              child: const Text('Rafraîchir'),
            ),
          ],
        ),
        const SizedBox(height: BSSpace.s3),
        if (b.banque.isEmpty)
          SizedBox(
            width: 820,
            child: Text(
              b.lastError ?? 'Aucune question pour le moment.',
              style: BSType.body(size: 15, color: BSColors.accent2_800),
            ),
          )
        else ...[
          _FiltreBanque(
            titre: 'Dans quoi',
            vide: _categories.isEmpty && _themes.isEmpty,
            quandVide: 'toute la banque',
            options: [
              for (final f in b.banque.categories)
                _OptionFiltre(
                  label: '${f.emoji} ${f.nom}'.trim(),
                  coche: _categories.contains(f.nom),
                  onTap: () => setState(
                    () => _categories.contains(f.nom)
                        ? _categories.remove(f.nom)
                        : _categories.add(f.nom),
                  ),
                ),
              for (final f in b.banque.themes)
                _OptionFiltre(
                  label: '${f.emoji} ${f.nom}'.trim(),
                  coche: _themes.contains(f.nom),
                  traversant: true,
                  onTap: () => setState(
                    () => _themes.contains(f.nom)
                        ? _themes.remove(f.nom)
                        : _themes.add(f.nom),
                  ),
                ),
            ],
          ),
          const SizedBox(height: BSSpace.s2),
          _FiltreBanque(
            titre: 'Pour qui',
            vide: _tranches.isEmpty,
            quandVide: 'tout le monde',
            options: [
              for (final t in Tranche.values)
                _OptionFiltre(
                  label: kNomsTranches[t]!,
                  coche: _tranches.contains(t),
                  onTap: () => setState(
                    () => _tranches.contains(t)
                        ? _tranches.remove(t)
                        : _tranches.add(t),
                  ),
                ),
            ],
          ),
          const SizedBox(height: BSSpace.s2),
          _FiltreBanque(
            titre: 'Difficulté',
            vide: _niveaux.isEmpty,
            quandVide: 'tous les niveaux',
            options: [
              for (final n in kNomsNiveaux.keys)
                _OptionFiltre(
                  label: kNomsNiveaux[n]!,
                  coche: _niveaux.contains(n),
                  onTap: () => setState(
                    () => _niveaux.contains(n)
                        ? _niveaux.remove(n)
                        : _niveaux.add(n),
                  ),
                ),
            ],
          ),
          const SizedBox(height: BSSpace.s3),
          Row(
            children: [
              SizedBox(
                width: 84,
                child: Text(
                  'Contient',
                  style: BSType.body(size: 14, color: BSColors.neutral600),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (v) => setState(() => _recherche = v.trim()),
                  style: BSType.body(size: 15, color: BSColors.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'un mot de la question ou de la réponse',
                    hintStyle: BSType.body(
                      size: 14,
                      color: BSColors.neutral500,
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: BSColors.divider),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: BSColors.divider),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: BSSpace.s3),
              Text(
                '${trouvees.length} question${trouvees.length > 1 ? 's' : ''}',
                style: BSType.body(
                  size: 15,
                  color: BSColors.text,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: BSSpace.s4),
          if (trouvees.isEmpty)
            Text(
              'Aucune question ne répond à ces critères.',
              style: BSType.body(size: 15, color: BSColors.neutral600),
            )
          else ...[
            for (final q in trouvees.take(_plafond)) _LigneBanque(q),
            if (trouvees.length > _plafond) ...[
              const SizedBox(height: BSSpace.s2),
              Text(
                'et ${trouvees.length - _plafond} autres. Affinez les critères '
                'pour les voir.',
                style: BSType.body(
                  size: 14,
                  color: BSColors.neutral600,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ],
      ],
    );
  }
}

// Une question de la banque, en lecture. L'énoncé et la réponse d'abord,
// parce que c'est ce qu'on vient vérifier ; le classement en petit à côté,
// parce qu'on le consulte plus rarement.
class _LigneBanque extends StatelessWidget {
  const _LigneBanque(this.q);

  final QuizQuestion q;

  @override
  Widget build(BuildContext context) {
    final marques = [
      q.category,
      if (q.niveau != null) kNomsNiveaux[q.niveau]!,
      for (final t in Tranche.values)
        if (q.ages.contains(t)) kNomsTranches[t]!,
      ...q.themes,
    ];
    return Container(
      width: 900,
      margin: const EdgeInsets.only(bottom: BSSpace.s3),
      padding: const EdgeInsets.only(top: BSSpace.s2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: BSColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            q.question,
            style: BSType.body(size: 16, color: BSColors.text),
          ),
          const SizedBox(height: 2),
          SelectableText(
            q.answer,
            style: BSType.body(
              size: 16,
              color: BSColors.accent700,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            marques.join(' · '),
            style: BSType.body(size: 13, color: BSColors.neutral600),
          ),
        ],
      ),
    );
  }
}

// Les mêmes pastilles que dans l'écran Partie, pour que le fureteur et le
// tirage se lisent pareil. Dupliquées plutôt que partagées : les deux écrans
// n'ont pas le même propriétaire, et un widget commun les aurait couplés pour
// économiser trente lignes.
class _OptionFiltre {
  const _OptionFiltre({
    required this.label,
    required this.coche,
    required this.onTap,
    this.traversant = false,
  });
  final String label;
  final bool coche;
  final VoidCallback onTap;
  final bool traversant;
}

class _FiltreBanque extends StatelessWidget {
  const _FiltreBanque({
    required this.titre,
    required this.options,
    required this.vide,
    required this.quandVide,
  });

  final String titre;
  final List<_OptionFiltre> options;
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
            child: Text(
              titre,
              style: BSType.body(size: 14, color: BSColors.neutral600),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: BSSpace.s2,
            runSpacing: BSSpace.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final o in options)
                InkWell(
                  onTap: o.onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: o.coche
                          ? (o.traversant ? BSColors.accent2 : BSColors.accent)
                          : Colors.transparent,
                      border: Border.all(
                        color: o.coche
                            ? (o.traversant
                                  ? BSColors.accent2
                                  : BSColors.accent)
                            : BSColors.divider,
                        width: o.coche ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      o.label,
                      style:
                          BSType.body(
                            size: 14,
                            color: o.coche ? BSColors.bg : BSColors.text,
                          ).copyWith(
                            fontWeight: o.coche
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                    ),
                  ),
                ),
              if (vide)
                Padding(
                  padding: const EdgeInsets.only(left: BSSpace.s2, top: 7),
                  child: Text(
                    quandVide,
                    style: BSType.body(
                      size: 13,
                      color: BSColors.neutral500,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// L'heure seule quand c'est aujourd'hui, la date en plus sinon : une copie
// hors ligne peut remonter à des semaines, et « lue à 10:39 » laisserait
// croire à ce matin.
String _quand(DateTime? moment) {
  if (moment == null) return 'à une date inconnue';
  String deux(int n) => n.toString().padLeft(2, '0');
  final heure = 'à ${deux(moment.hour)}:${deux(moment.minute)}';
  final maintenant = DateTime.now();
  final memeJour =
      moment.year == maintenant.year &&
      moment.month == maintenant.month &&
      moment.day == maintenant.day;
  return memeJour
      ? heure
      : 'le ${deux(moment.day)}/${deux(moment.month)} $heure';
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
          top: BorderSide(
            color: file.valid ? BSColors.text : BSColors.neutral400,
            width: 2,
          ),
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
          Text(
            _dateLabel(file.modified),
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
    required this.onUseForGame,
    required this.onExport,
    required this.onDelete,
    required this.pourLaPartie,
  });

  final Questionnaire questionnaire;
  final bool dirty;
  final VoidCallback onBack;
  final bool saved;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onRename;
  final VoidCallback onUseForGame;
  final VoidCallback onExport;
  final VoidCallback? onDelete;
  // Arrive depuis le lancement d'une partie : on ne vient chercher qu'une
  // chose, le questionnaire a jouer. Tout ce qui touche a la GESTION des
  // fichiers (dupliquer, exporter, supprimer) est du bruit a ce moment-la,
  // et « Utiliser pour la partie » devient l'action principale.
  final bool pourLaPartie;

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
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Utiliser pour la partie'),
                    )
                  else ...[
                    if (dirty)
                      Padding(
                        padding: const EdgeInsets.only(right: BSSpace.s2),
                        child: Text(
                          'Non enregistré',
                          style: BSType.body(
                            size: 14,
                            color: BSColors.accent2_800,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: BSColors.accent,
                        foregroundColor: BSColors.bg,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Enregistrer'),
                    ),
                    if (saved) ...[
                      const SizedBox(width: BSSpace.s2),
                      TextButton(
                        onPressed: onRename,
                        style: TextButton.styleFrom(
                          foregroundColor: BSColors.accent700,
                        ),
                        child: const Text('Renommer le fichier'),
                      ),
                    ],
                    const SizedBox(width: BSSpace.s2),
                    // Mettre en jeu reste possible sans enregistrer : on retouche
                    // souvent une question deux minutes avant de lancer la manche,
                    // et exiger un Enregistrer d'abord ferait perdre ce temps-là
                    // pour rien.
                    OutlinedButton(
                      onPressed: onUseForGame,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BSColors.text,
                        side: const BorderSide(color: BSColors.divider),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Utiliser pour la partie'),
                    ),
                    const SizedBox(width: BSSpace.s2),
                    TextButton(
                      onPressed: onExport,
                      style: TextButton.styleFrom(
                        foregroundColor: BSColors.accent700,
                      ),
                      child: const Text('Exporter'),
                    ),
                    if (onDelete != null)
                      TextButton(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: BSColors.neutral600,
                        ),
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
                  SizedBox(
                    width: 240,
                    child: Text('CATÉGORIE', style: BSType.sectionKicker()),
                  ),
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
            key: ValueKey(
              '${identityHashCode(questionnaire)}-${identityHashCode(questionnaire.questions[i])}',
            ),
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
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CategoryField(
                    value: question.category,
                    onChanged: (v) {
                      question.category = v;
                      onChanged();
                    },
                  ),
                  _NiveauField(
                    value: question.niveau,
                    onChanged: (v) {
                      question.niveau = v;
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
            // La largeur reste réservée même quand la croix est absente :
            // les lignes gardent l'alignement de l'en-tête de colonnes.
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

// Le niveau d'une question, sous sa catégorie : les trois mots côte à
// côte, celui qui est retenu souligné, et un second clic le retire. Trois
// options ne méritent ni menu ni boîte.
class _NiveauField extends StatelessWidget {
  const _NiveauField({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
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
                  style:
                      BSType.body(
                        size: 13,
                        color: value == entry.key
                            ? BSColors.text
                            : BSColors.neutral500,
                      ).copyWith(
                        decoration: value == entry.key
                            ? TextDecoration.underline
                            : null,
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
                child: Text(
                  name,
                  style: BSType.body(size: 15, color: BSColors.text),
                ),
              ),
          ],
          icon: const Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: BSColors.neutral500,
          ),
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

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
