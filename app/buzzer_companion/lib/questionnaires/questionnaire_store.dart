import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'questionnaire.dart';

// Un questionnaire tel qu'il apparaît dans la liste, sans son contenu : la
// liste se dessine à partir des noms de fichiers et de leur date, sans avoir
// à ouvrir et parser chaque fichier à chaque affichage.
class QuestionnaireFile {
  const QuestionnaireFile({
    required this.path,
    required this.name,
    required this.modified,
    required this.title,
    required this.questionCount,
    required this.valid,
    this.niveaux = const {},
  });

  final String path;
  final String name;      // nom du fichier sans .json
  final DateTime modified;
  // Combien de questions de chaque niveau, lu dans le fichier comme le titre.
  final Map<int, int> niveaux;
  String? get etiquetteNiveau => etiquetteDesNiveaux(niveaux);
  // Titre et compte lus DANS le fichier : choisir entre « Noel.json » et
  // « Noel2.json » sans les ouvrir est impossible, alors qu'entre « Spécial
  // Noël, 24 questions » et « Noël, brouillon, 3 questions » c'est immédiat.
  final String title;
  final int questionCount;
  // Faux pour un fichier .json qui n'est pas un questionnaire, ou abîmé : il
  // reste visible (sinon on le chercherait sans le trouver) mais annoncé
  // comme tel.
  final bool valid;

  String get displayTitle => title.isNotEmpty ? title : name;
}

// Le nom sous lequel la bibliothèque regroupe ce dossier, et l'origine
// inscrite sur un questionnaire mis en jeu. Depuis que les questionnaires
// prédécoupés ont laissé la place à la banque, c'est la seule provenance
// possible pour un fichier : un questionnaire n'a donc plus de collection à
// lui, et l'éditeur n'en demande plus.
const kPersonnalise = 'Personnalisé';
const kEmojiPersonnalise = '✏️';

// Les questionnaires vivent dans un dossier CHOISI par l'opérateur, et non
// dans un recoin de données d'application : il doit pouvoir les copier sur
// une clé, les envoyer par courriel, ou en écrire un à la main.
//
// Le dossier est un réglage, pas une constante. On ne sait pas sur quel
// poste l'application tournera, et le Documents par défaut peut très bien
// être un OneDrive d'entreprise, où des questionnaires de party n'ont rien
// à faire. Le choix est retenu d'une session à l'autre.
//
// Faute de choix, on retombe sur Documents/Buzzer/Questionnaires, demandé au
// système (path_provider) plutôt que reconstruit à partir du profil : là où
// OneDrive redirige Documents, un chemin deviné pointe à côté et l'opérateur
// ne retrouve jamais ses fichiers.
const _folderKey = 'questionnaires_folder';

class QuestionnaireStore extends ChangeNotifier {
  static const _folderName = 'Buzzer';
  static const _subFolderName = 'Questionnaires';

  Directory? _dir;
  String? _chosenPath;
  List<QuestionnaireFile> files = [];
  String? lastError;

  String get folderPath => _dir?.path ?? _chosenPath ?? '';

  // Vrai quand l'opérateur a choisi lui-même : sert à proposer le retour au
  // dossier par défaut, et seulement dans ce cas.
  bool get usesCustomFolder => _chosenPath != null;

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_folderKey);
    if (saved != null && saved.isNotEmpty) {
      _chosenPath = saved;
    }
    await refresh();
  }

  // Le dossier choisi peut avoir disparu depuis (clé USB retirée, partage
  // réseau hors ligne, dossier supprimé). On le dit au lieu de recréer
  // silencieusement une arborescence ailleurs, ce qui donnerait l'impression
  // que tous les questionnaires se sont volatilisés.
  Future<Directory> _ensureDir() async {
    final existing = _dir;
    if (existing != null) return existing;

    final chosen = _chosenPath;
    if (chosen != null) {
      final dir = Directory(chosen);
      if (!dir.existsSync()) {
        throw FileSystemException('Dossier introuvable', chosen);
      }
      _dir = dir;
      return dir;
    }

    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}${Platform.pathSeparator}$_folderName'
        '${Platform.pathSeparator}$_subFolderName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  Future<void> chooseFolder() async {
    final picked = await getDirectoryPath(confirmButtonText: 'Utiliser ce dossier');
    if (picked == null) return;
    _chosenPath = picked;
    _dir = null;   // sera revalidé au prochain accès
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderKey, picked);
    await refresh();
  }

  Future<void> useDefaultFolder() async {
    _chosenPath = null;
    _dir = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_folderKey);
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final dir = await _ensureDir();
      final found = <QuestionnaireFile>[];
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last;
        // Chaque fichier est lu au passage. Ce sont quelques kilo-octets et
        // une poignée de fichiers : le coût est nul, et la liste devient
        // vraiment renseignée plutôt qu'une suite de noms de fichiers.
        String title = '';
        int count = 0;
        bool valid = true;
        var niveaux = const <int, int>{};
        try {
          final parsed = Questionnaire.decode(entity.readAsStringSync());
          title = parsed.title;
          count = parsed.questions.length;
          niveaux = parsed.niveaux;
        } catch (_) {
          valid = false;
        }
        found.add(QuestionnaireFile(
          path: entity.path,
          name: name.substring(0, name.length - 5),
          modified: entity.statSync().modified,
          title: title,
          questionCount: count,
          valid: valid,
          niveaux: niveaux,
        ));
      }
      // Le plus récemment retouché en premier : c'est presque toujours celui
      // qu'on rouvre. Ce dossier ne contient que du travail de l'opérateur,
      // alors la date de modification reprend tout son sens.
      found.sort((a, b) => b.modified.compareTo(a.modified));
      files = found;
      lastError = null;
    } on FileSystemException catch (e) {
      files = [];
      lastError = "Dossier introuvable : ${e.path}. Il a peut-être été déplacé, "
          'ou se trouve sur un disque non branché.';
    } catch (e) {
      files = [];
      lastError = "Impossible de lire le dossier des questionnaires : $e";
    }
    notifyListeners();
  }

  int get questionCount => files.fold(0, (somme, f) => somme + f.questionCount);

  Future<Questionnaire?> load(String path) async {
    try {
      final raw = await File(path).readAsString();
      lastError = null;
      return Questionnaire.decode(raw);
    } on FormatException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = "Impossible d'ouvrir ce fichier : $e";
    }
    notifyListeners();
    return null;
  }

  // Le nom de fichier vient du titre : on retrouve un questionnaire par son
  // nom dans l'explorateur sans avoir à l'ouvrir. Renvoie le chemin écrit,
  // ou null en cas d'échec.
  Future<String?> save(Questionnaire questionnaire, {String? existingPath}) async {
    try {
      final dir = await _ensureDir();
      final path = existingPath ??
          '${dir.path}${Platform.pathSeparator}${_fileNameFor(questionnaire.title)}.json';
      await File(path).writeAsString(questionnaire.encode());
      lastError = null;
      await refresh();
      return path;
    } catch (e) {
      lastError = "Enregistrement impossible : $e";
      notifyListeners();
      return null;
    }
  }

  // Écrit une copie d'un questionnaire à côté de l'original. Le nom est rendu
  // unique au lieu d'écraser : dupliquer deux fois « Party de Noël » doit
  // donner deux fichiers, pas un seul écrasé sans avertissement.
  Future<String?> duplicate(Questionnaire source) async {
    try {
      final dir = await _ensureDir();
      final copie = source.copy();
      final base = _fileNameFor(copie.title);
      var chemin = '${dir.path}${Platform.pathSeparator}$base.json';
      var n = 2;
      while (File(chemin).existsSync()) {
        chemin = '${dir.path}${Platform.pathSeparator}$base ($n).json';
        n++;
      }
      await File(chemin).writeAsString(copie.encode());
      lastError = null;
      await refresh();
      return chemin;
    } catch (e) {
      lastError = "Duplication impossible : $e";
      notifyListeners();
      return null;
    }
  }

  Future<bool> delete(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
      lastError = null;
      await refresh();
      return true;
    } catch (e) {
      lastError = "Suppression impossible : $e";
      notifyListeners();
      return false;
    }
  }

  // Copie un fichier venu d'ailleurs (clé USB, courriel) dans le dossier, en
  // le validant au passage : un fichier illisible n'a pas à entrer dans la
  // bibliothèque et à échouer plus tard, au pire moment.
  Future<String?> import() async {
    const typeGroup = XTypeGroup(label: 'Questionnaires', extensions: ['json']);
    final picked = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (picked == null) return null;
    final questionnaire = await load(picked.path);
    if (questionnaire == null) return null;   // lastError est déjà posé
    final name = picked.name.toLowerCase().endsWith('.json')
        ? picked.name.substring(0, picked.name.length - 5)
        : picked.name;
    if (questionnaire.title.isEmpty) questionnaire.title = name;
    return save(questionnaire);
  }

  Future<void> export(Questionnaire questionnaire) async {
    final location = await getSaveLocation(
      suggestedName: '${_fileNameFor(questionnaire.title)}.json',
      acceptedTypeGroups: const [XTypeGroup(label: 'Questionnaires', extensions: ['json'])],
    );
    if (location == null) return;
    try {
      await File(location.path).writeAsString(questionnaire.encode());
      lastError = null;
    } catch (e) {
      lastError = "Export impossible : $e";
    }
    notifyListeners();
  }

  // Windows refuse \ / : * ? " < > | dans un nom de fichier, et un titre est
  // du texte libre : sans ce nettoyage, « Cinéma : les années 90 » ferait
  // échouer l'enregistrement sans que la cause soit devinable.
  static String _fileNameFor(String title) {
    final cleaned = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Questionnaire' : cleaned;
  }
}
