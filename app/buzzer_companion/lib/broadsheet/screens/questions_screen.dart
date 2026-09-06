import 'package:flutter/material.dart';

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
// jouer, selon la thématique, la tranche d'âge et le niveau demandés. Un
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
  // L'onglet ouvert. Vit ici plutôt que dans la bibliothèque : ouvrir un
  // questionnaire puis revenir doit ramener là où on était, et un état porté
  // par un widget détruit à l'ouverture de l'éditeur repartirait à zéro.
  bool _surLaBanque = false;
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
            surLaBanque: _surLaBanque,
            onOnglet: (v) => setState(() => _surLaBanque = v),
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
          // LES SUGGESTIONS VIENNENT DE LA BANQUE, PAS DU BUZZER. Elles
          // puisaient dans les dix noms compilés dans le Mega, qui sont les
          // thématiques des questions DU BUZZER et n'ont rien à voir avec
          // celles de la banque : neuf manquaient à l'appel, dont Disney,
          // Voyages et Spécial Noël.
          themes: [for (final t in widget.banque.banque.themes) t.nom],
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

// DEUX ONGLETS, parce que ce sont deux tâches et non deux sections d'une
// même page.
//
// Elles étaient empilées : on descendait ses questionnaires, puis le chemin
// du dossier, puis la banque. Personne ne fait les deux à la fois, et celui
// qui vient consulter la banque commençait par défiler devant une section
// vide qui ne le concernait pas. Pire, la banque a besoin de toute la hauteur
// disponible : empilée, elle en recevait ce qui restait.
//
// « MES QUESTIONNAIRES » est le dossier de l'opérateur : ses fichiers à lui,
// modifiables, jamais publiés, et les seuls qu'on mette en jeu tels quels.
// C'est aussi le seul endroit où il peut perdre du travail, donc il ouvre par
// défaut.
//
// LA BANQUE se consulte, ne se joue pas fichier par fichier. Elle a remplacé
// les 283 questionnaires prédécoupés : on compose sa manche au moment de
// jouer, dans l'écran Partie. Ce qu'on vient chercher ici, c'est vérifier une
// question, voir ce qu'une thématique contient avant une soirée, ou juste
// lire. Le fureteur est donc en lecture seule et n'a aucun bouton « jouer » :
// il n'aurait aucun sens de mettre en jeu une liste filtrée depuis une
// bibliothèque alors que le tirage fait exactement cela, en mieux.
class _Library extends StatelessWidget {
  const _Library({
    required this.store,
    required this.banque,
    required this.pourLaPartie,
    required this.surLaBanque,
    required this.onOnglet,
    required this.onRetourPartie,
    required this.onNew,
    required this.onOpen,
    required this.onImport,
  });

  final QuestionnaireStore store;
  final BanqueStore banque;
  final bool pourLaPartie;
  final bool surLaBanque;
  final ValueChanged<bool> onOnglet;
  final VoidCallback onRetourPartie;
  final VoidCallback onNew;
  final ValueChanged<QuestionnaireFile> onOpen;
  final VoidCallback onImport;

  // Arrivé depuis le lancement d'une partie, on vient chercher un fichier à
  // jouer : la banque ne se joue pas fichier par fichier, l'onglet n'aurait
  // rien à offrir.
  bool get _banqueVisible => !pourLaPartie && surLaBanque;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._bandeauPartie(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Questions', style: BSType.buzzerNameConsole(size: 26)),
            const SizedBox(width: BSSpace.s6),
            if (!pourLaPartie)
              _Segmente(
                options: const ['Mes questionnaires', 'La banque'],
                choisi: surLaBanque ? 1 : 0,
                onChoisir: (i) => onOnglet(i == 1),
              ),
          ],
        ),
        const SizedBox(height: BSSpace.s3),
        Container(height: 2, color: BSColors.text),
        const SizedBox(height: BSSpace.s4),
        // La banque prend toute la hauteur qui reste : c'est une liste de
        // trois mille lignes, et lui en donner une part fixe la condamnait à
        // se lire par la fenêtre d'une enveloppe.
        if (_banqueVisible)
          Expanded(child: _FureteurBanque(banque: banque))
        else
          Expanded(
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._mesQuestionnaires(),
                    const SizedBox(height: BSSpace.s8),
                    ..._reglages(),
                    const SizedBox(height: BSSpace.s8),
                  ],
                ),
              ),
            ),
          ),
      ],
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
            BSSpace.s3, BSSpace.s2, BSSpace.s2, BSSpace.s2),
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
          _boutonPlein('Nouveau', onNew),
          const SizedBox(width: BSSpace.s2),
          _boutonContour('Importer', onImport),
          const SizedBox(width: BSSpace.s4),
          Expanded(
            child: Text(
              fichiers.isEmpty
                  // L'état vide dit quoi faire, et il est le seul texte
                  // d'explication de l'onglet : une fois qu'il y a des cartes,
                  // il n'y a plus rien à expliquer.
                  ? 'Rien ici encore. « Nouveau » ouvre un questionnaire vide, '
                      '« Importer » reprend un fichier reçu de quelqu\'un d\'autre.'
                  : '${fichiers.length} questionnaire'
                      '${fichiers.length > 1 ? 's' : ''}, à vous, jamais publiés, '
                      'et qui se mettent en jeu tels quels.',
              style: BSType.body(size: 16, color: BSColors.neutral600),
            ),
          ),
        ],
      ),
      if (fichiers.isNotEmpty) ...[
        const SizedBox(height: BSSpace.s6),
        Wrap(
          spacing: BSSpace.s6,
          runSpacing: BSSpace.s6,
          children: [
            for (final f in fichiers)
              _QuestionnaireCard(file: f, onTap: () => onOpen(f)),
          ],
        ),
      ],
    ];
  }

  List<Widget> _reglages() {
    return [
      Container(height: 1, color: BSColors.divider),
      const SizedBox(height: BSSpace.s3),
      Text('LE DOSSIER', style: BSType.sectionKicker()),
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
                style:
                    TextButton.styleFrom(foregroundColor: BSColors.neutral600),
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

// Le contrôle segmenté du design system (`.seg` de styles.css) : un cadre,
// des options séparées par un filet, celle qui est retenue en aplat d'accent.
// Sans coins arrondis, comme tout le reste de la console.
//
// Deux onglets ne méritent pas un TabBar : celui de Material apporte un
// indicateur animé, un défilement et un thème à mater, pour un choix entre
// deux mots.
class _Segmente extends StatelessWidget {
  const _Segmente({
    required this.options,
    required this.choisi,
    required this.onChoisir,
  });

  final List<String> options;
  final int choisi;
  final ValueChanged<int> onChoisir;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: BSColors.divider)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                color: i == choisi ? BSColors.accent : Colors.transparent,
                border: i == 0
                    ? null
                    : const Border(
                        left: BorderSide(color: BSColors.divider),
                      ),
              ),
              child: InkWell(
                onTap: () => onChoisir(i),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Text(
                    options[i],
                    style: BSType.body(
                      size: 15,
                      color: i == choisi ? BSColors.bg : BSColors.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- Fureteur de banque

// LIRE LA BANQUE, sans la jouer.
//
// Trois usages : vérifier une question dont on doute, voir ce qu'une
// thématique contient avant une soirée, et compter ce qu'un filtre laisse. Le
// premier est de loin le plus fréquent, donc la recherche est en tête.
//
// LES CRITÈRES SONT EN COLONNE, à gauche, et non en rangées au-dessus de la
// liste. Deux tentatives ont échoué avant celle-là, et pour la même raison :
// dix-neuf critères qui se replient en rangées donnent un pavé au bord droit
// déchiqueté, qui prend le tiers haut de l'écran et pèse plus lourd que le
// contenu qu'il sert à trouver. Encadrés ou en toutes lettres, c'était le
// même pavé.
//
// En colonne, chaque critère tient sur sa ligne, les compteurs s'alignent et
// se lisent d'un coup d'œil, et la liste récupère toute la hauteur de la
// fenêtre. C'est la mise en page des catalogues, pour la raison qui les y a
// menés.
//
// LES RÉPONSES SONT VISIBLES. C'est une bibliothèque, pas une partie : les
// cacher obligerait à cliquer trois mille fois pour vérifier une chose.
class _FureteurBanque extends StatefulWidget {
  const _FureteurBanque({required this.banque});

  final BanqueStore banque;

  @override
  State<_FureteurBanque> createState() => _FureteurBanqueState();
}

class _FureteurBanqueState extends State<_FureteurBanque> {
  static const _largeurFacettes = 258.0;

  // Largeurs des colonnes de droite. Fixes, donc les valeurs s'alignent d'une
  // ligne à l'autre et se lisent en colonne plutôt qu'une par une.
  static const _lNumero = 46.0;
  static const _lThematiques = 180.0;
  static const _lClassement = 190.0;

  // UNE SEULE LISTE DE FACETTES : vingt thématiques, onze déclarées par le
  // fichier de la question et neuf qui traversent. Le furetage se filtre donc
  // sur un seul axe.
  final Set<String> _themes = {};
  final Set<Tranche> _tranches = {};
  final Set<int> _niveaux = {};
  final _recherche = TextEditingController();
  final _defilementListe = ScrollController();
  final _defilementFacettes = ScrollController();

  @override
  void dispose() {
    _recherche.dispose();
    _defilementListe.dispose();
    _defilementFacettes.dispose();
    super.dispose();
  }

  // Sans accents et sans casse : on tape « quebec » et on trouve « Québec ».
  static String _plat(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c');

  bool _retenue(QuizQuestion q) =>
      _parTheme(q) &&
      _parNiveau(q) &&
      _parTranche(q) &&
      _parMot(q);

  bool _parTheme(QuizQuestion q) =>
      _themes.isEmpty || q.themes.any(_themes.contains);
  // Une question qui ne se prononce pas passe : un questionnaire écrit à la
  // main ne cote rien, et l'écarter reviendrait à le punir de son silence.
  bool _parNiveau(QuizQuestion q) =>
      _niveaux.isEmpty || q.niveau == null || _niveaux.contains(q.niveau);
  bool _parTranche(QuizQuestion q) =>
      _tranches.isEmpty ||
      q.ages.isEmpty ||
      q.ages.intersection(_tranches).isNotEmpty;
  bool _parMot(QuizQuestion q) {
    final mot = _recherche.text.trim();
    return mot.isEmpty ||
        _plat('${q.question} ${q.answer}').contains(_plat(mot));
  }

  void _reinitialiser() => setState(() {
        _themes.clear();
        _tranches.clear();
        _niveaux.clear();
        _recherche.clear();
      });

  bool get _filtre =>
      _themes.isNotEmpty ||
      _tranches.isNotEmpty ||
      _niveaux.isNotEmpty ||
      _recherche.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final b = widget.banque;
    if (b.banque.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          b.lastError ?? 'Aucune question pour le moment.',
          style: BSType.body(size: 15, color: BSColors.accent2_800),
        ),
      );
    }
    final trouvees = b.banque.questions.where(_retenue).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _largeurFacettes, child: _facettes(b)),
        // Un filet, pas une marge : c'est ce qui sépare deux colonnes dans
        // toute la console.
        Container(width: 1, color: BSColors.divider),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: BSSpace.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _recherchePuisCompte(b, trouvees.length),
                const SizedBox(height: BSSpace.s4),
                _enteteColonnes(),
                // LES CRITÈRES RESTENT EN PLACE, la liste seule défile. Trois
                // mille questions veut dire défiler longtemps, et devoir
                // remonter toute la page pour décocher une case ferait perdre
                // sa place à chaque fois.
                Expanded(
                  child: trouvees.isEmpty
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: BSSpace.s3),
                            child: Text(
                              'Aucune question ne répond à ces critères.',
                              style: BSType.body(
                                  size: 15, color: BSColors.neutral600),
                            ),
                          ),
                        )
                      // Construite à la demande : la liste porte les 3684
                      // questions sans que rien ne rame, donc plus de plafond
                      // arbitraire qui coupait à soixante et laissait deviner
                      // le reste.
                      : Scrollbar(
                          controller: _defilementListe,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _defilementListe,
                            primary: false,
                            padding: const EdgeInsets.only(right: BSSpace.s3),
                            itemCount: trouvees.length,
                            itemBuilder: (context, i) => _LigneBanque(
                              question: trouvees[i],
                              rang: i + 1,
                              largeurNumero: _lNumero,
                              largeurThematiques: _lThematiques,
                              largeurClassement: _lClassement,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------- Les facettes

  // CHAQUE COMPTEUR DIT CE QUE CE CRITÈRE-LÀ DONNERAIT, SEUL. C'est la seule
  // règle qui se tienne : un compteur qui suivrait les autres cases cochées
  // afficherait zéro partout dès qu'on croise deux critères, et un compteur
  // « nombre de questions portant cette étiquette » mentirait pour les
  // niveaux et les tranches, où une question muette passe tous les filtres.
  // Ici le chiffre à côté de « facile » est exactement ce qu'on obtient en
  // cliquant « facile » sur une banque vierge.
  Widget _facettes(BanqueStore b) {
    final qs = b.banque.questions;
    return Scrollbar(
      controller: _defilementFacettes,
      child: SingleChildScrollView(
        controller: _defilementFacettes,
        padding: const EdgeInsets.only(right: BSSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionFacette(
              titre: 'THÉMATIQUES',
              indice: _themes.isEmpty ? 'toutes' : null,
              // UNE SEULE SECTION : les onze déclarées par un fichier ouvrent
              // la liste, et les neuf qui
              // traversent la banque suivent. « Musique » et « Spécial Noël »
              // se cochent donc au même endroit, ce que le tirage faisait
              // déjà en les réunissant dans un seul OU.
              teinte: BSColors.accent2_700,
              rangees: [
                for (final f in b.banque.themes)
                  _Facette(
                    label: f.nom,
                    emoji: f.emoji,
                    compte: f.questions,
                    coche: _themes.contains(f.nom),
                    onTap: () => setState(() => _themes.contains(f.nom)
                        ? _themes.remove(f.nom)
                        : _themes.add(f.nom)),
                  ),
              ],
            ),
            _SectionFacette(
              titre: 'POUR QUI',
              indice: _tranches.isEmpty ? 'tout le monde' : null,
              rangees: [
                for (final t in Tranche.values)
                  _Facette(
                    label: kNomsTranches[t]!,
                    compte: qs
                        .where((q) => q.ages.isEmpty || q.ages.contains(t))
                        .length,
                    coche: _tranches.contains(t),
                    onTap: () => setState(() => _tranches.contains(t)
                        ? _tranches.remove(t)
                        : _tranches.add(t)),
                  ),
              ],
            ),
            _SectionFacette(
              titre: 'DIFFICULTÉ',
              indice: _niveaux.isEmpty ? 'tous niveaux' : null,
              rangees: [
                for (final n in kNomsNiveaux.keys)
                  _Facette(
                    label: kNomsNiveaux[n]!,
                    compte: qs
                        .where((q) => q.niveau == null || q.niveau == n)
                        .length,
                    coche: _niveaux.contains(n),
                    onTap: () => setState(() => _niveaux.contains(n)
                        ? _niveaux.remove(n)
                        : _niveaux.add(n)),
                  ),
              ],
            ),
            const SizedBox(height: BSSpace.s6),
          ],
        ),
      ),
    );
  }

  // LA RECHERCHE D'ABORD. Sur les trois raisons de venir ici, « je veux
  // revérifier cette question-là » est de loin la plus fréquente, et elle ne
  // passe pas par les critères.
  //
  // La provenance de la banque partage cette ligne au lieu d'avoir la sienne :
  // c'est une information qu'on vérifie une fois, pas un contrôle.
  Widget _recherchePuisCompte(BanqueStore b, int trouvees) {
    final total = b.total;
    return Row(
      children: [
        SizedBox(
          width: 400,
          child: TextField(
            controller: _recherche,
            onChanged: (_) => setState(() {}),
            style: BSType.body(size: 16, color: BSColors.text),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: BSSpace.s2, vertical: BSSpace.s2),
              hintText: 'Chercher un mot de la question ou de la réponse',
              hintStyle: BSType.body(size: 16, color: BSColors.neutral500),
              border: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: BSColors.divider)),
              enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: BSColors.divider)),
              focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: BSColors.accent, width: 2)),
            ),
          ),
        ),
        const SizedBox(width: BSSpace.s4),
        // Le compte vivant. C'est la seule réponse à « est-ce que mon filtre
        // a du sens », et il doit se lire sans le chercher.
        Text('$trouvees', style: BSType.buzzerNameConsole(size: 26)),
        const SizedBox(width: BSSpace.s1),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            trouvees == total ? 'questions, tout' : 'sur $total',
            style: BSType.body(size: 15, color: BSColors.neutral600),
          ),
        ),
        if (_filtre)
          TextButton(
            onPressed: _reinitialiser,
            style: TextButton.styleFrom(foregroundColor: BSColors.neutral700),
            child: const Text('Tout effacer'),
          ),
        // TOUTE LA PLACE QUI RESTE, À DROITE, ET TRONQUÉE PLUTÔT QUE DÉBORDÉE.
        //
        // Ce libellé grandit tout seul, sans qu'on y touche : « Lue en ligne à
        // 21:34 » devient « Lue en ligne le 05/09 à 21:34 » dès le lendemain,
        // et la version hors ligne fait le double. La rangée était rigide
        // (champ de 400 px, compte, Spacer) : elle débordait de 3,6 px le
        // lendemain d'une lecture et de 116 px hors ligne, avec les rayures
        // jaunes de Flutter par-dessus l'écran.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _provenance(b, total),
          ),
        ),
        const SizedBox(width: BSSpace.s2),
        TextButton(
          onPressed: b.loading ? null : b.refresh,
          style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
          child: const Text('Rafraîchir'),
        ),
      ],
    );
  }

  // D'où vient cette liste, dit en clair. « Rien ne signale un problème » est
  // une preuve trop faible : sans cette ligne, la seule façon de savoir que la
  // banque vient du réseau était de remarquer l'ABSENCE d'un avertissement.
  //
  // Une seule ligne, jamais deux : sur cette rangée, un retour à la ligne
  // pousserait le champ de recherche et le compte vers le bas.
  Widget _provenance(BanqueStore b, int total) {
    final (String texte, Color couleur) = switch (b) {
      _ when b.loading => ('Lecture de la banque...', BSColors.neutral600),
      _ when b.depuisLeBuild => (
          "Hors ligne. Questions livrées avec l'application",
          BSColors.accent2_800
        ),
      _ when b.horsLigne => (
          'Hors ligne. Copie du poste, lue ${_quand(b.lastFetch)}',
          BSColors.accent2_800
        ),
      _ when total > 0 => (
          'Lue en ligne ${_quand(b.lastFetch)}',
          BSColors.neutral600
        ),
      _ => ('', BSColors.neutral600),
    };
    if (texte.isEmpty) return const SizedBox.shrink();
    return Text(
      texte,
      textAlign: TextAlign.right,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: BSType.body(size: 14, color: couleur),
    );
  }

  // En-têtes de colonnes : inutiles avec cinq lignes, indispensables avec
  // trois mille, quand « facile » et « ados » ne sont plus que deux colonnes
  // de texte gris.
  Widget _enteteColonnes() {
    return Padding(
      padding: const EdgeInsets.only(bottom: BSSpace.s1),
      child: Row(
        children: [
          const SizedBox(width: _lNumero),
          Expanded(
            child: Text('QUESTION ET RÉPONSE', style: BSType.sectionKicker()),
          ),
          SizedBox(
            width: _lThematiques,
            child: Text('THÉMATIQUES', style: BSType.sectionKicker()),
          ),
          SizedBox(
            width: _lClassement,
            child: Text('NIVEAU ET TRANCHES', style: BSType.sectionKicker()),
          ),
        ],
      ),
    );
  }
}

// Un critère de la colonne de gauche.
class _Facette {
  const _Facette({
    required this.label,
    required this.compte,
    required this.coche,
    required this.onTap,
    this.emoji,
  });
  final String label;
  final String? emoji;
  // Ce que ce critère donnerait SEUL, et non ce qu'il reste après les autres.
  final int compte;
  final bool coche;
  final VoidCallback onTap;
}

class _SectionFacette extends StatelessWidget {
  const _SectionFacette({
    required this.titre,
    required this.rangees,
    this.indice,
    this.teinte = BSColors.accent700,
  });

  final String titre;
  final List<_Facette> rangees;
  // Ce que « rien de coché » veut dire, montré seulement dans ce cas. Dès
  // qu'un critère est retenu, il se voit à sa couleur et l'indice n'a plus
  // rien à dire.
  final String? indice;
  final Color teinte;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              top: BSSpace.s4, bottom: BSSpace.s1, left: 6),
          child: Row(
            children: [
              Text(titre, style: BSType.sectionKicker()),
              if (indice != null) ...[
                const Spacer(),
                Text(indice!,
                    style: BSType.body(size: 13, color: BSColors.neutral500)
                        .copyWith(fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
        Container(height: 1, color: BSColors.divider),
        for (final f in rangees) _RangeeFacette(facette: f, teinte: teinte),
      ],
    );
  }
}

// Une ligne : le nom à gauche, le compte aligné à droite. Rien d'autre.
//
// C'est l'alignement des compteurs qui fait tout le travail : en rangées
// repliées ils tombaient n'importe où et il fallait les lire un par un, alors
// qu'en colonne on voit d'un coup que Culture pop et Musique mènent à 428.
class _RangeeFacette extends StatefulWidget {
  const _RangeeFacette({required this.facette, required this.teinte});

  final _Facette facette;
  final Color teinte;

  @override
  State<_RangeeFacette> createState() => _RangeeFacetteState();
}

class _RangeeFacetteState extends State<_RangeeFacette> {
  bool _survole = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.facette;
    final couleur = f.coche ? widget.teinte : BSColors.text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _survole = true),
      onExit: (_) => setState(() => _survole = false),
      child: GestureDetector(
        onTap: f.onTap,
        child: Container(
          // Le survol du design system : 7 % du texte sur transparent.
          color: _survole
              ? BSColors.text.withValues(alpha: 0.07)
              : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Row(
            children: [
              // Le trait de sélection tient lieu de case à cocher : présent
              // ou absent, il se repère en balayant la colonne, ce qu'une
              // simple mise en couleur ne donne pas.
              Container(
                width: 3,
                height: 15,
                color: f.coche ? widget.teinte : Colors.transparent,
              ),
              const SizedBox(width: 7),
              if (f.emoji != null && f.emoji!.isNotEmpty) ...[
                Text(f.emoji!, style: BSType.body(size: 14)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  f.label,
                  overflow: TextOverflow.ellipsis,
                  style: BSType.body(size: 14, color: couleur).copyWith(
                    fontWeight: f.coche ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: BSSpace.s2),
              Text(
                '${f.compte}',
                style: BSType.body(
                  size: 13,
                  color: f.coche ? widget.teinte : BSColors.neutral500,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Une question de la banque, en lecture, sur une ligne de grille.
//
// L'ÉNONCÉ ET LA RÉPONSE À GAUCHE, le classement dans des colonnes fixes à
// droite. Les trois lignes empilées de la première version faisaient
// cinquante pixels chacune, coûtaient trois fois la hauteur, et ne
// s'alignaient sur rien : pour comparer le niveau de deux questions il
// fallait le chercher deux fois.
//
// La réponse est en italique magenta, comme sur l'écran public et dans la
// revue. C'était du gras bleu, plus fort que la question, ce qui inversait
// l'ordre de lecture : on vient ici lire des questions.
class _LigneBanque extends StatelessWidget {
  const _LigneBanque({
    required this.question,
    required this.rang,
    required this.largeurNumero,
    required this.largeurThematiques,
    required this.largeurClassement,
  });

  final QuizQuestion question;
  final int rang;
  final double largeurNumero;
  final double largeurThematiques;
  final double largeurClassement;

  @override
  Widget build(BuildContext context) {
    final q = question;
    // Une case vide se lit comme une donnée manquante. « Tout le monde » dit
    // la même chose que l'absence de tranches, mais le dit.
    final tranches = q.ages.isEmpty
        ? 'tout le monde'
        : [
            for (final t in Tranche.values)
              if (q.ages.contains(t)) kNomsTranches[t]!,
          ].join(', ');
    final classement = [
      if (q.niveau != null) kNomsNiveaux[q.niveau]!,
      tranches,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: BSSpace.s2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BSColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: largeurNumero,
            child: Padding(
              padding: const EdgeInsets.only(right: BSSpace.s2),
              child: Text(
                '$rang',
                textAlign: TextAlign.right,
                style: BSType.body(size: 13, color: BSColors.neutral500)
                    .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: BSSpace.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(q.question,
                      style: BSType.body(size: 16, color: BSColors.text)),
                  SelectableText(
                    q.answer,
                    style: BSType.body(size: 16, color: BSColors.accent2_700)
                        .copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
          // TOUTES LES THÉMATIQUES DU MÊME CÔTÉ ET DE LA MÊME COULEUR.
          //
          // L'étiquette du fichier s'affichait au-dessus, en gris, et les
          // autres en dessous, en magenta. Deux natures, deux couleurs :
          // c'était vrai quand elle était l'autre axe du classement. Depuis
          // qu'il n'y a plus qu'un axe, « Sports » en gris
          // au-dessus de « Québec » en magenta faisait croire à deux sortes
          // d'étiquettes alors que le tirage les traite pareil.
          //
          // Celle du fichier vient en tête : le générateur la place là, et
          // c'est elle qui sert d'étiquette à l'écran et au tirage.
          SizedBox(
            width: largeurThematiques,
            child: Text(
              q.themes.join(', '),
              style: BSType.body(size: 14, color: BSColors.accent2_700),
            ),
          ),
          SizedBox(
            width: largeurClassement,
            child: Text(classement,
                style: BSType.body(size: 14, color: BSColors.neutral600)),
          ),
        ],
      ),
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
    required this.themes,
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
  // Les noms proposés sous le champ Thématique de chaque ligne.
  final List<String> themes;
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
              // trente, quand l'étiquette n'est plus qu'une colonne de texte
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
            themes: themes,
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
    required this.themes,
    required this.question,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final List<String> themes;
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
            // Thématique libre, avec les dix du firmware en suggestion : un
            // questionnaire écrit à la main invente les siennes (« Films de
            // Noël »), mais autant ne pas retaper « Histoire ». Elle prend la
            // PREMIÈRE place de « themes », celle qui sert d'étiquette.
            SizedBox(
              width: 240,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ThemeField(
                    suggestions: themes,
                    value: question.etiquette,
                    onChanged: (v) {
                      final reste = question.themes.skip(1).toList();
                      question.themes = {
                        if (v.trim().isNotEmpty) v.trim(),
                        ...reste,
                      };
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

// Le niveau d'une question, sous sa thématique : les trois mots côte à
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

class _ThemeField extends StatelessWidget {
  const _ThemeField(
      {required this.value,
      required this.onChanged,
      required this.suggestions});

  // Les thématiques de la banque. Vide tant qu'elle n'est pas chargée : le
  // champ reste libre, on tape ce qu'on veut.
  final List<String> suggestions;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Field(
            value: value,
            hint: 'Thématique',
            style: BSType.body(size: 15, color: BSColors.neutral700),
            onChanged: onChanged,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Thématiques courantes',
          color: BSColors.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          onSelected: onChanged,
          itemBuilder: (context) => [
            for (final name in suggestions)
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
