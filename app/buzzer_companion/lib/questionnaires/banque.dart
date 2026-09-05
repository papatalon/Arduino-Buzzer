import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'questionnaire.dart';

// LA BANQUE DE QUESTIONS : un seul fichier, chaque question une fois.
//
// Ce qui a remplacé 283 questionnaires prédécoupés. Le découpage servait à
// choisir un questionnaire tout fait dans une bibliothèque ; on compose
// maintenant la manche au moment de jouer, selon la pièce qu'on a devant soi,
// et une liste plate suffit. « Histoire 07 sur 11 » ne voulait rien dire pour
// personne.
//
// TROIS PROVENANCES, dans cet ordre.
//
//   1. Le RÉSEAU, seul à pouvoir être plus récent. Ce qu'il donne est écrit
//      sur le disque, pour que le prochain démarrage sans wifi en profite.
//   2. Le CACHE DISQUE, écrit par la dernière lecture réussie.
//   3. La COPIE EMBARQUÉE dans le build, plancher d'une installation neuve
//      dans une salle sans réseau. Sans elle, l'écran serait vide et le
//      tirage n'aurait rien où piocher, ce dont personne ne s'apercevrait
//      avant la soirée.
//
// Le fichier fait moins de 600 ko : on le lit en entier, une fois. C'est ce
// qui permet au tirage de filtrer sur n'importe quelle combinaison de
// critères sans se demander quels fichiers aller chercher.

const kBanqueUrl = 'https://buzzer.sd6tools.net';
const kFormatBanque = 'buzzer-banque';
const kAssetBanque = 'assets/questions/banque.json';

// Une catégorie ou une thématique, avec de quoi dessiner sa pastille.
class Facette {
  const Facette({
    required this.nom,
    required this.emoji,
    required this.questions,
    this.note = '',
  });

  final String nom;
  final String emoji;
  final int questions;
  final String note;

  factory Facette.fromJson(Map<String, dynamic> json) => Facette(
        nom: (json['nom'] as String?)?.trim() ?? '',
        emoji: (json['emoji'] as String?)?.trim() ?? '',
        questions: (json['questions'] as num?)?.toInt() ?? 0,
        note: (json['note'] as String?)?.trim() ?? '',
      );
}

class Banque {
  const Banque({
    required this.questions,
    required this.categories,
    required this.themes,
  });

  final List<QuizQuestion> questions;
  // Les catégories du firmware : Histoire, Musique, Québec...
  final List<Facette> categories;
  // Les découpes qui TRAVERSENT les catégories : « Spécial Noël » prend le
  // renne dans Culture générale, la bûche dans Bouffe et les chants dans
  // Musique. C'est ce qu'aucune catégorie ne sait faire, et la raison pour
  // laquelle elles ont survécu à la disparition des fichiers.
  final List<Facette> themes;

  static const vide = Banque(questions: [], categories: [], themes: []);

  bool get isEmpty => questions.isEmpty;

  factory Banque.decode(String raw) {
    final dynamic parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException("Ce n'est pas une banque de questions.");
    }
    return Banque.fromMap(parsed);
  }

  // La copie embarquée est déjà décodée quand on arrive ici : la ré-encoder
  // pour la redécoder serait absurde sur 570 ko.
  factory Banque.fromMap(Map<String, dynamic> parsed) {
    if (parsed['format'] != kFormatBanque) {
      throw const FormatException(
        "L'adresse ne renvoie pas une banque de questions Buzzer.",
      );
    }
    List<Facette> facettes(Object? brut) => [
          if (brut is List)
            for (final f in brut)
              if (f is Map<String, dynamic>) Facette.fromJson(f),
        ];
    final brutQuestions = parsed['questions'];
    return Banque(
      questions: [
        if (brutQuestions is List)
          for (final q in brutQuestions)
            if (q is Map<String, dynamic>) QuizQuestion.fromJson(q),
      ],
      categories: facettes(parsed['categories']),
      themes: facettes(parsed['themes']),
    );
  }
}

class BanqueStore extends ChangeNotifier {
  Banque banque = Banque.vide;

  static const baseUrl = kBanqueUrl;

  bool loading = false;
  String? lastError;

  // Ce qui est affiché ne vient pas du réseau. Deux nuances, parce qu'elles
  // n'appellent pas le même geste : un cache disque date de la dernière
  // lecture réussie, la copie embarquée date de l'installation.
  bool horsLigne = false;
  bool depuisLeBuild = false;

  DateTime? lastFetch;

  Directory? _dir;

  int get total => banque.questions.length;

  Future<void> init() async {
    // Le disque d'abord : l'écran s'affiche tout de suite, même sans réseau.
    await _lireCache();
    if (banque.isEmpty) await _lireEmbarquee();
    await refresh();
  }

  Future<Directory> _ensureDir() async {
    final connu = _dir;
    if (connu != null) return connu;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}banque');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  File _fichier(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}banque.json');

  Future<void> _lireCache() async {
    try {
      final fichier = _fichier(await _ensureDir());
      if (!fichier.existsSync()) return;
      banque = Banque.decode(await fichier.readAsString());
      horsLigne = true;
      depuisLeBuild = false;
      // La date du FICHIER, pas maintenant : ce qu'on montre date de la
      // dernière lecture réussie, qui peut remonter à des semaines.
      lastFetch = fichier.lastModifiedSync();
      notifyListeners();
    } catch (_) {
      // Cache illisible : la copie embarquée prendra le relais.
    }
  }

  Future<void> _lireEmbarquee() async {
    try {
      banque = Banque.decode(await rootBundle.loadString(kAssetBanque));
      horsLigne = true;
      depuisLeBuild = true;
      lastFetch = null;
      notifyListeners();
    } catch (_) {
      // Pas d'asset : build fait sans, ou fichier illisible. On continue
      // sans plancher plutôt que d'empêcher le démarrage.
    }
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      final reponse = await http
          .get(Uri.parse('$baseUrl/banque.json'))
          .timeout(const Duration(seconds: 20));
      if (reponse.statusCode != 200) {
        throw HttpException('Le serveur a répondu ${reponse.statusCode}.');
      }
      // utf8.decode explicite : sans en-tête de charset, http retomberait sur
      // latin-1 et « Géographie » arriverait en « GÃ©ographie ».
      final contenu = utf8.decode(reponse.bodyBytes);
      banque = Banque.decode(contenu);
      horsLigne = false;
      depuisLeBuild = false;
      lastFetch = DateTime.now();
      lastError = null;
      // Écrit tout de suite : c'est ce qui fait qu'un redémarrage sans wifi
      // retrouve les questions d'aujourd'hui et non celles du build.
      await _ecrireCache(contenu);
    } catch (e) {
      lastError = _messageErreur(e);
      // On garde ce qui est déjà affiché : une banque en cache vaut mieux
      // qu'un écran vide parce que le wifi de la salle est tombé.
      horsLigne = !banque.isEmpty;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _ecrireCache(String contenu) async {
    try {
      await _fichier(await _ensureDir()).writeAsString(contenu);
    } catch (_) {
      // Disque plein ou dossier en lecture seule : la banque est en mémoire,
      // la soirée peut se jouer. Le prochain démarrage retombera sur la
      // copie embarquée, ce qui reste jouable.
    }
  }

  String _messageErreur(Object e) {
    if (e is SocketException) {
      return 'Banque injoignable : $baseUrl. Les questions livrées avec '
          "l'application restent disponibles.";
    }
    if (e is FormatException) return e.message;
    if (e is HttpException) return '${e.message} ($baseUrl/banque.json)';
    return 'Impossible de lire la banque : $e';
  }
}
