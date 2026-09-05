import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'questionnaire.dart';

// Le catalogue publié en ligne, et sa copie locale.
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

// L'adresse du catalogue est INTERNE : pas un réglage, pas de champ dans
// l'écran. L'opérateur anime une soirée, il n'a aucune raison de décider où
// l'application va chercher ses questionnaires, et un mauvais collage dans un
// champ de saisie viderait la bibliothèque sans qu'il sache pourquoi.
//
// L'adresse du projet Cloudflare Pages (arduino-buzzer.pages.dev) sert le
// même site et reste valable : c'est le repli si le domaine personnalisé
// pose problème un jour.
const kCatalogueUrl = 'https://buzzer.sd6tools.net';

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
    this.niveaux = const {},
  });

  final String id;
  final String title;
  final String note;
  final String collection;
  final String emoji;
  final int questionCount;
  // Combien de questions de chaque niveau, tel que l'index l'annonce : la
  // fiche dit « facile » ou « difficile » sans avoir téléchargé le fichier.
  final Map<int, int> niveaux;
  final int bytes;
  // Empreinte du contenu publié. Comparée à celle enregistrée au moment du
  // téléchargement : c'est ce qui distingue « j'ai ce questionnaire » de
  // « j'ai une VIEILLE version de ce questionnaire ».
  final String fingerprint;

  String? get etiquetteNiveau => etiquetteDesNiveaux(niveaux);

  factory CatalogueEntry.fromJson(Map<String, dynamic> json) {
    final rawNiveaux = json['niveaux'];
    return CatalogueEntry(
      id: (json['id'] as String?)?.trim() ?? '',
      title: (json['titre'] as String?)?.trim() ?? '',
      note: (json['note'] as String?)?.trim() ?? '',
      collection: (json['collection'] as String?)?.trim() ?? '',
      emoji: (json['emoji'] as String?)?.trim() ?? '',
      questionCount: (json['questions'] as num?)?.toInt() ?? 0,
      niveaux: {
        if (rawNiveaux is Map)
          for (final e in rawNiveaux.entries)
            if (niveauDepuisJson(e.key) != null && e.value is num)
              niveauDepuisJson(e.key)!: (e.value as num).toInt(),
      },
      bytes: (json['octets'] as num?)?.toInt() ?? 0,
      fingerprint: (json['empreinte'] as String?)?.trim() ?? '',
    );
  }
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
    return Catalogue.fromMap(parsed);
  }

  // La copie embarquée porte le catalogue DÉJÀ décodé, à l'intérieur d'un
  // fichier plus gros : le ré-encoder pour le redécoder serait absurde.
  factory Catalogue.fromMap(Map<String, dynamic> parsed) {
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

  static const baseUrl = kCatalogueUrl;
  String? lastError;
  bool loading = false;
  // Vrai quand le catalogue affiché vient du disque et non du réseau : à dire
  // à l'opérateur, sinon il croit voir le catalogue à jour.
  bool horsLigne = false;

  // Vrai quand ce qui est affiché vient de la copie livrée avec l'application
  // et non du réseau ni du cache. Distinct de [horsLigne] : un cache disque
  // date de la dernière lecture réussie, la copie embarquée date du build.
  // L'opérateur doit pouvoir faire la différence entre « ma liste a trois
  // jours » et « ma liste a l'âge de mon installation ».
  bool depuisLeBuild = false;

  // Quand le catalogue affiché a été obtenu. Affiché en clair, parce que
  // « rien ne signale un problème » est une preuve trop faible : sans cette
  // heure, la seule façon de savoir que la liste vient bien du réseau était
  // de remarquer l'ABSENCE d'un avertissement.
  DateTime? lastFetch;

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
    await _readLocalState();
    // Le disque d'abord : la bibliothèque s'affiche tout de suite, même sans
    // réseau, puis se met à jour quand la requête revient.
    await _readCachedCatalogue();
    // Rien en cache : une installation neuve dans une salle sans wifi. La
    // copie livrée avec l'application prend le relais, sinon l'écran serait
    // vide et le tirage n'aurait rien où piocher.
    if (catalogue.isEmpty) await _readCatalogueEmbarque();
    await refresh();
  }

  // --- La copie embarquée dans le build
  //
  // Un seul fichier d'assets porte le catalogue ET les 283 questionnaires.
  // Il est lu PARESSEUSEMENT : 1,1 Mo de JSON à analyser au démarrage pour
  // rien, alors que la plupart des lancements se font avec du réseau.
  Map<String, dynamic>? _banque;
  bool _banqueLue = false;

  Future<Map<String, dynamic>?> _lireBanque() async {
    if (_banqueLue) return _banque;
    _banqueLue = true;
    try {
      final brut = await rootBundle.loadString('assets/questions/banque.json');
      final decode = jsonDecode(brut);
      if (decode is Map<String, dynamic>) _banque = decode;
    } catch (_) {
      // Pas d'asset : le build a été fait sans, ou le fichier est illisible.
      // On continue sans plancher plutôt que d'empêcher le démarrage.
    }
    return _banque;
  }

  // Écrire le cache ne doit jamais faire échouer une lecture réussie : le
  // questionnaire est déjà en main, un disque plein ne doit pas priver
  // l'animateur de sa manche.
  Future<void> _garderEnCache(Directory dir, String id, String contenu) async {
    try {
      final fichier = _fichierCache(dir, id);
      await fichier.parent.create(recursive: true);
      await fichier.writeAsString(contenu);
    } catch (_) {}
  }

  Future<Questionnaire?> _lireCache(Directory dir, String id) async {
    try {
      final fichier = _fichierCache(dir, id);
      if (!fichier.existsSync()) return null;
      return Questionnaire.decode(await fichier.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<Questionnaire?> _questionnaireEmbarque(String id) async {
    final banque = await _lireBanque();
    final tous = banque?['questionnaires'];
    if (tous is! Map) return null;
    final brut = tous[id];
    if (brut is! Map<String, dynamic>) return null;
    try {
      return Questionnaire.fromMap(brut);
    } catch (_) {
      return null;
    }
  }

  Future<void> _readCatalogueEmbarque() async {
    final banque = await _lireBanque();
    final brut = banque?['catalogue'];
    if (brut is! Map<String, dynamic>) return;
    try {
      catalogue = Catalogue.fromMap(brut);
      horsLigne = true;
      depuisLeBuild = true;
      lastFetch = null;
      notifyListeners();
    } catch (_) {
      // Asset mal formé : on laisse le réseau tenter sa chance.
    }
  }

  // Une requête, avec reprise sur 429 (« trop de requêtes »).
  //
  // Rapatrier une collection enchaîne jusqu'à seize téléchargements. Les
  // fichiers sont maintenant gardés au bord du réseau (voir site/_headers),
  // mais un cache froid laisse passer la rafale jusqu'à l'origine Cloudflare
  // Pages, qui la refuse au-delà d'un certain débit. Abandonner au premier
  // refus laisserait une collection à moitié synchronisée sans que
  // l'opérateur comprenne pourquoi.
  //
  // On respecte Retry-After quand le serveur le donne, sinon une attente qui
  // s'allonge. Trois essais : au-delà, ce n'est plus une rafale, c'est un
  // vrai problème qu'il vaut mieux annoncer.
  Future<http.Response> _get(Uri url, {Duration? delai}) async {
    const essais = 3;
    for (var i = 0; ; i++) {
      final reponse =
          await http.get(url).timeout(delai ?? const Duration(seconds: 20));
      if (reponse.statusCode != 429 || i >= essais - 1) return reponse;
      final apres = int.tryParse(reponse.headers['retry-after'] ?? '');
      await Future<void>.delayed(apres != null
          ? Duration(seconds: apres.clamp(1, 10))
          : Duration(milliseconds: 400 * (i + 1)));
    }
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

  // LE CACHE OPPORTUNISTE, dans un dossier à part.
  //
  // Ce que le réseau a servi pendant une partie est gardé ici, pour qu'un
  // redémarrage sans wifi retrouve la DERNIÈRE version des questions plutôt
  // que celle du build. Séparé de « q/ » à dessein : « q/ » est ce que
  // l'opérateur a délibérément mis de côté, et c'est ce que les nuages de la
  // bibliothèque montrent. Mélanger les deux ferait grimper le compteur
  // « sur ce poste » tout seul, et l'opérateur ne saurait plus ce qu'il a
  // choisi de garder. Le cache, lui, ne se montre pas : c'est un cache.
  File _fichierCache(Directory dir, String id) =>
      File('${dir.path}${Platform.pathSeparator}cache'
          '${Platform.pathSeparator}$id.json');

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
      // La date du FICHIER, pas maintenant : ce qu'on affiche date de la
      // dernière lecture réussie, qui peut remonter à des semaines.
      lastFetch = fichier.lastModifiedSync();
      notifyListeners();
    } catch (_) {
      // Cache illisible : on attend le réseau.
    }
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      final reponse = await _get(Uri.parse('$baseUrl/catalogue.json'),
          delai: const Duration(seconds: 12));
      if (reponse.statusCode != 200) {
        throw HttpException('Le serveur a répondu ${reponse.statusCode}.');
      }
      // utf8.decode explicite : sans en-tête de charset, http retomberait sur
      // latin-1 et « Géographie » arriverait en « GÃ©ographie ».
      catalogue = Catalogue.decode(utf8.decode(reponse.bodyBytes));
      horsLigne = false;
      depuisLeBuild = false;
      lastFetch = DateTime.now();
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
      final reponse = await _get(Uri.parse('$baseUrl/q/${entry.id}.json'));
      if (reponse.statusCode != 200) {
        throw HttpException('Le serveur a répondu ${reponse.statusCode}.');
      }
      final contenu = utf8.decode(reponse.bodyBytes);
      // Validé avant d'être écrit : un fichier illisible n'a pas à entrer
      // dans la réserve et à échouer plus tard, au pire moment.
      Questionnaire.decode(contenu);

      // L'empreinte de ce qu'on a REÇU, comparée à celle annoncée. Sans ce
      // contrôle, un cache qui sert une version périmée serait enregistré
      // comme étant à jour : le fichier ne correspondrait plus à son
      // empreinte, et l'application ne le saurait jamais.
      final recue = sha1.convert(reponse.bodyBytes).toString();
      if (entry.fingerprint.isNotEmpty && recue != entry.fingerprint) {
        throw const FormatException(
          "le contenu reçu ne correspond pas à celui annoncé par le catalogue "
          "(copie périmée servie par un cache ?). Réessayez dans un moment.",
        );
      }
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
  // Une lecture en ligne n'apparaît PAS comme locale : un simple coup d'œil
  // dans la bibliothèque ne doit pas faire grimper le compteur « sur ce
  // poste » ni remplir un nuage que l'opérateur n'a pas cliqué. Elle est en
  // revanche gardée dans un cache invisible quand [garder] le demande, pour
  // qu'un redémarrage sans wifi retrouve la dernière version reçue.
  //
  // L'ORDRE : ce que l'opérateur a synchronisé, puis le réseau, puis le cache
  // de la dernière partie, puis la copie livrée avec l'application. Le réseau
  // passe avant les deux caches parce qu'il est le seul à pouvoir être plus
  // récent ; les deux caches se departagent par leur âge, celui d'une partie
  // jouée valant toujours mieux que celui du build.
  Future<Questionnaire?> load(CatalogueEntry entry, {bool garder = false}) async {
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
        final reponse = await _get(Uri.parse('$baseUrl/q/${entry.id}.json'));
        if (reponse.statusCode != 200) {
          throw HttpException('Le serveur a répondu ${reponse.statusCode}.');
        }
        final contenu = utf8.decode(reponse.bodyBytes);
        final charge = Questionnaire.decode(contenu);
        if (garder) await _garderEnCache(dir, entry.id, contenu);
        lastError = null;
        return charge;
      } on Object {
        // Le réseau a échoué. Le cache de la dernière partie d'abord, puis la
        // copie livrée avec l'application : c'est ce qui fait tenir le tirage
        // dans un sous-sol sans wifi, sur un poste où rien n'a été
        // synchronisé à l'avance.
        final repli = await _lireCache(dir, entry.id) ??
            await _questionnaireEmbarque(entry.id);
        if (repli != null) {
          lastError = null;
          return repli;
        }
        rethrow;
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
