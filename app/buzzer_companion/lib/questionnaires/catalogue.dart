import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'questionnaire.dart';

// Le catalogue publié sur buzzer.sd6tools.net, et sa copie locale.
//
// Deux idées à garder en tête en lisant ce fichier.
//
// 1. L'INDEX SUFFIT POUR DESSINER LA BIBLIOTHÈQUE. Un seul fichier de ~30 Ko
//    porte les titres, les collections, les emoji et le nombre de questions
//    des 125 questionnaires. On affiche donc tout le catalogue, y compris ce
//    qui n'a jamais été rapatrié, et l'opérateur décide ensuite quoi garder
//    localement. Sans cet index il faudrait tout télécharger pour savoir ce
//    qui existe, ce qui viderait de son sens le choix de synchroniser.
//
// 2. LE CATALOGUE EST EN LECTURE SEULE, ET SA COPIE LOCALE VIT AILLEURS que
//    les questionnaires personnels. Le dossier de données de l'application
//    (%appdata%) reçoit le catalogue ; le dossier choisi par l'opérateur ne
//    contient que ce qu'il a écrit lui-même. Mélanger les deux ferait qu'une
//    régénération du catalogue écraserait son travail, ou qu'un de ses
//    fichiers disparaîtrait en même temps qu'une collection retirée.

const kCatalogueUrlParDefaut = 'https://buzzer.sd6tools.net';
const _urlKey = 'catalogue_url';

const kCatalogueFormat = 'buzzer-catalogue';

class CatalogueEntry {
  const CatalogueEntry({
    required this.id,
    required this.title,
    required this.note,
    required this.collection,
    required this.emoji,
    required this.questionCount,
    required this.bytes,
    required this.fingerprint,
  });

  final String id;
  final String title;
  final String note;
  final String collection;
  final String emoji;
  final int questionCount;
  final int bytes;
  // Empreinte du contenu publié. Comparée à celle enregistrée au moment du
  // téléchargement : c'est ce qui distingue « j'ai ce questionnaire » de
  // « j'ai une VIEILLE version de ce questionnaire ».
  final String fingerprint;

  factory CatalogueEntry.fromJson(Map<String, dynamic> json) => CatalogueEntry(
        id: (json['id'] as String?)?.trim() ?? '',
        title: (json['titre'] as String?)?.trim() ?? '',
        note: (json['note'] as String?)?.trim() ?? '',
        collection: (json['collection'] as String?)?.trim() ?? '',
        emoji: (json['emoji'] as String?)?.trim() ?? '',
        questionCount: (json['questions'] as num?)?.toInt() ?? 0,
        bytes: (json['octets'] as num?)?.toInt() ?? 0,
        fingerprint: (json['empreinte'] as String?)?.trim() ?? '',
      );
}

class CatalogueCollection {
  const CatalogueCollection({
    required this.name,
    required this.emoji,
    required this.fileCount,
    required this.questionCount,
  });

  final String name;
  final String emoji;
  final int fileCount;
  final int questionCount;
}

// Où en est une collection du côté local. Trois états, parce que « une partie
// est là » est le cas normal quand on a choisi trois manches sur huit, et
// qu'un nuage à deux états le mentirait.
enum SyncState { absent, partiel, complet }

class Catalogue {
  const Catalogue({required this.entries, required this.collections});

  final List<CatalogueEntry> entries;
  final List<CatalogueCollection> collections;

  static const vide = Catalogue(entries: [], collections: []);

  bool get isEmpty => entries.isEmpty;

  factory Catalogue.decode(String raw) {
    final dynamic parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException("Ce n'est pas un catalogue.");
    }
    if (parsed['format'] != kCatalogueFormat) {
      throw const FormatException(
        "L'adresse ne renvoie pas un catalogue de questionnaires Buzzer.",
      );
    }
    final rawEntries = parsed['questionnaires'];
    final rawCollections = parsed['collections'];
    return Catalogue(
      entries: [
        if (rawEntries is List)
          for (final e in rawEntries)
            if (e is Map<String, dynamic>) CatalogueEntry.fromJson(e),
      ],
      collections: [
        if (rawCollections is List)
          for (final c in rawCollections)
            if (c is Map<String, dynamic>)
              CatalogueCollection(
                name: (c['nom'] as String?)?.trim() ?? '',
                emoji: (c['emoji'] as String?)?.trim() ?? '',
                fileCount: (c['questionnaires'] as num?)?.toInt() ?? 0,
                questionCount: (c['questions'] as num?)?.toInt() ?? 0,
              ),
      ],
    );
  }
}

class CatalogueStore extends ChangeNotifier {
  Catalogue catalogue = Catalogue.vide;

  // id -> empreinte au moment du téléchargement. La présence d'une clé vaut
  // « ce questionnaire est local ».
  Map<String, String> _local = {};

  final Set<String> _enCours = {};

  String baseUrl = kCatalogueUrlParDefaut;
  String? lastError;
  bool loading = false;
  // Vrai quand le catalogue affiché vient du disque et non du réseau : à dire
  // à l'opérateur, sinon il croit voir le catalogue à jour.
  bool horsLigne = false;

  Directory? _dir;

  bool estLocal(String id) => _local.containsKey(id);
  bool estEnCours(String id) => _enCours.contains(id);

  // Local mais l'empreinte publiée a changé : la copie est périmée.
  bool estPerime(CatalogueEntry entry) {
    final empreinte = _local[entry.id];
    return empreinte != null &&
        entry.fingerprint.isNotEmpty &&
        empreinte != entry.fingerprint;
  }

  int get localCount => _local.length;

  List<CatalogueEntry> entriesOf(String collection) =>
      catalogue.entries.where((e) => e.collection == collection).toList();

  SyncState stateOf(String collection) {
    final entries = entriesOf(collection);
    if (entries.isEmpty) return SyncState.absent;
    final locales = entries.where((e) => estLocal(e.id)).length;
    if (locales == 0) return SyncState.absent;
    return locales == entries.length ? SyncState.complet : SyncState.partiel;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_urlKey);
    if (saved != null && saved.trim().isNotEmpty) baseUrl = saved.trim();
    await _readLocalState();
    // Le disque d'abord : la bibliothèque s'affiche tout de suite, même sans
    // réseau, puis se met à jour quand la requête revient.
    await _readCachedCatalogue();
    await refresh();
  }

  Future<void> setBaseUrl(String url) async {
    final propre = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (propre.isEmpty || propre == baseUrl) return;
    baseUrl = propre;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, propre);
    await refresh();
  }

  Future<Directory> _ensureDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    // getApplicationSupportDirectory, et non le dossier des questionnaires
    // personnels : c'est une réserve gérée par l'application, pas un dossier
    // que l'opérateur ouvre dans l'explorateur.
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}catalogue');
    if (!dir.existsSync()) dir.create(recursive: true);
    final q = Directory('${dir.path}${Platform.pathSeparator}q');
    if (!q.existsSync()) q.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  String get cachePath => _dir?.path ?? '';

  File _fichierLocal(Directory dir, String id) =>
      File('${dir.path}${Platform.pathSeparator}q${Platform.pathSeparator}$id.json');

  File _fichierEtat(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}local.json');

  File _fichierCatalogue(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}catalogue.json');

  Future<void> _readLocalState() async {
    try {
      final dir = await _ensureDir();
      final fichier = _fichierEtat(dir);
      if (!fichier.existsSync()) return;
      final parsed = jsonDecode(await fichier.readAsString());
      if (parsed is Map) {
        _local = {
          for (final e in parsed.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String,
        };
      }
      // Un fichier disparu (ménage manuel dans %appdata%) ne doit pas rester
      // annoncé comme local : on croirait l'avoir et l'ouverture échouerait.
      _local.removeWhere((id, _) => !_fichierLocal(dir, id).existsSync());
    } catch (_) {
      _local = {};
    }
  }

  Future<void> _writeLocalState() async {
    try {
      final dir = await _ensureDir();
      await _fichierEtat(dir).writeAsString(jsonEncode(_local));
    } catch (_) {
      // Sans état écrit, la prochaine ouverture reconstruira à partir des
      // fichiers présents : on perd les empreintes, pas les questionnaires.
    }
  }

  Future<void> _readCachedCatalogue() async {
    try {
      final dir = await _ensureDir();
      final fichier = _fichierCatalogue(dir);
      if (!fichier.existsSync()) return;
      catalogue = Catalogue.decode(await fichier.readAsString());
      horsLigne = true;
      notifyListeners();
    } catch (_) {
      // Cache illisible : on attend le réseau.
    }
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      final reponse = await http
          .get(Uri.parse('$baseUrl/catalogue.json'))
          .timeout(const Duration(seconds: 12));
      if (reponse.statusCode != 200) {
        throw HttpException('Le serveur a répondu ${reponse.statusCode}.');
      }
      // utf8.decode explicite : sans en-tête de charset, http retomberait sur
      // latin-1 et « Géographie » arriverait en « GÃ©ographie ».
      catalogue = Catalogue.decode(utf8.decode(reponse.bodyBytes));
      horsLigne = false;
      lastError = null;
      final dir = await _ensureDir();
      await _fichierCatalogue(dir).writeAsString(utf8.decode(reponse.bodyBytes));
    } catch (e) {
      lastError = _messageErreur(e);
      // On garde ce qui est déjà affiché : un catalogue en cache vaut mieux
      // qu'un écran vide parce que le wifi de la salle est tombé.
      horsLigne = catalogue.isEmpty ? false : true;
    }
    loading = false;
    notifyListeners();
  }

  String _messageErreur(Object e) {
    if (e is SocketException) {
      return "Catalogue injoignable : $baseUrl. Vérifiez la connexion, ou "
          "l'adresse si le site vient d'être publié.";
    }
    if (e is FormatException) return e.message;
    if (e is HttpException) return '${e.message} ($baseUrl/catalogue.json)';
    return "Impossible de lire le catalogue : $e";
  }

  // --- Synchronisation

  Future<void> sync(CatalogueEntry entry) async {
    if (_enCours.contains(entry.id)) return;
    _enCours.add(entry.id);
    notifyListeners();
    try {
      final reponse = await http
          .get(Uri.parse('$baseUrl/q/${entry.id}.json'))
          .timeout(const Duration(seconds: 20));
      if (reponse.statusCode != 200) {
        throw HttpException('Le serveur a répondu ${reponse.statusCode}.');
      }
      final contenu = utf8.decode(reponse.bodyBytes);
      // Validé avant d'être écrit : un fichier illisible n'a pas à entrer
      // dans la réserve et à échouer plus tard, au pire moment.
      Questionnaire.decode(contenu);
      final dir = await _ensureDir();
      await _fichierLocal(dir, entry.id).writeAsString(contenu);
      _local[entry.id] = entry.fingerprint;
      await _writeLocalState();
      lastError = null;
    } catch (e) {
      lastError = "« ${entry.title} » n'a pas pu être rapatrié : ${_messageErreur(e)}";
    }
    _enCours.remove(entry.id);
    notifyListeners();
  }

  Future<void> unsync(CatalogueEntry entry) async {
    try {
      final dir = await _ensureDir();
      final fichier = _fichierLocal(dir, entry.id);
      if (fichier.existsSync()) await fichier.delete();
      _local.remove(entry.id);
      await _writeLocalState();
      lastError = null;
    } catch (e) {
      lastError = "« ${entry.title} » n'a pas pu être retiré : $e";
    }
    notifyListeners();
  }

  // Une collection d'un coup. Séquentiel et non en parallèle : huit requêtes
  // simultanées vers Cloudflare pour gagner deux secondes ne valent pas le
  // risque de se faire limiter, et le nuage de chaque carte s'allume au fur
  // et à mesure, ce qui montre la progression.
  Future<void> syncCollection(String collection) async {
    for (final entry in entriesOf(collection)) {
      if (!estLocal(entry.id) || estPerime(entry)) await sync(entry);
    }
  }

  Future<void> unsyncCollection(String collection) async {
    for (final entry in entriesOf(collection)) {
      if (estLocal(entry.id)) await unsync(entry);
    }
  }

  // --- Lecture

  final Set<String> _ouvertures = {};

  bool estEnOuverture(String id) => _ouvertures.contains(id);

  // Lit un questionnaire du catalogue, qu'il soit local ou non. Le nuage ne
  // commande PAS la lecture : il commande la copie hors ligne. Tout le
  // catalogue se lit, et l'opérateur choisit ensuite ce qu'il veut garder
  // sous la main pour une salle sans wifi.
  //
  // Une lecture en ligne ne laisse rien derrière elle : le questionnaire
  // n'apparaît pas comme local, sinon un simple coup d'œil remplirait le
  // disque et brouillerait l'état des nuages.
  Future<Questionnaire?> load(CatalogueEntry entry) async {
    try {
      final dir = await _ensureDir();
      final fichier = _fichierLocal(dir, entry.id);
      if (fichier.existsSync()) {
        final charge = Questionnaire.decode(await fichier.readAsString());
        lastError = null;
        return charge;
      }

      _ouvertures.add(entry.id);
      notifyListeners();
      try {
        final reponse = await http
            .get(Uri.parse('$baseUrl/q/${entry.id}.json'))
            .timeout(const Duration(seconds: 20));
        if (reponse.statusCode != 200) {
          throw HttpException('Le serveur a répondu ${reponse.statusCode}.');
        }
        final charge = Questionnaire.decode(utf8.decode(reponse.bodyBytes));
        lastError = null;
        return charge;
      } finally {
        _ouvertures.remove(entry.id);
        notifyListeners();
      }
    } catch (e) {
      lastError = "« ${entry.title} » n'a pas pu être lu : ${_messageErreur(e)}";
      notifyListeners();
      return null;
    }
  }
}
