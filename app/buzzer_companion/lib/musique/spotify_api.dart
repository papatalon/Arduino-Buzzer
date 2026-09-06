import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// L'API Web de Spotify, réduite à ce qu'une soirée demande.
//
// LE CLIENT NE CONNAÎT PAS LES JETONS : il reçoit [jeton], une fonction qui
// en fournit un valide au moment de l'appel. C'est ce qui permet au service
// d'ambiance de rafraîchir sans que chaque méthode d'ici porte la même
// vérification d'expiration.
//
// Toutes les erreurs sortent en [ErreurSpotify] avec un message déjà écrit
// en français : l'écran de l'animateur n'a pas à traduire des codes HTTP, et
// « 404 » ne veut rien dire pour quelqu'un qui cherche pourquoi la musique
// ne part pas.
const _base = 'https://api.spotify.com/v1';

/// Les droits demandés. Lire ce qui joue ne demande pas Premium, mais
/// commander la lecture, oui : c'est Spotify qui tranche, à l'appel.
const kScopesSpotify = 'user-read-playback-state user-modify-playback-state '
    'user-read-currently-playing playlist-read-private '
    'playlist-read-collaborative';

class ErreurSpotify implements Exception {
  ErreurSpotify(this.statut, this.message, {this.reessayerDans});
  final int statut;
  final String message;

  /// Rempli sur un 429 : le temps que Spotify demande d'attendre.
  final Duration? reessayerDans;

  @override
  String toString() => message;
}

/// La traduction des refus de Spotify, en clair.
///
/// Règle pure et testée : c'est le seul endroit qui décide de ces phrases, et
/// elles sont lues en pleine soirée, entre deux questions.
String messageErreurSpotify(int statut) => switch (statut) {
      401 => 'La connexion à Spotify a expiré. Reconnectez-vous.',
      403 => 'Spotify refuse la commande. Il faut un compte Premium, et '
          'certaines pistes ne se pilotent pas à distance.',
      404 => 'Aucun appareil Spotify actif. Ouvrez Spotify et lancez une '
          'piste une fois.',
      429 => 'Spotify demande une pause. La musique reprend dans un moment.',
      >= 500 =>
        "Spotify a un ennui de son côté. Ça revient tout seul d'habitude.",
      _ => 'Spotify a répondu $statut.',
    };

/// Le message d'une panne qui n'est pas un refus de Spotify.
String messageErreurReseau(Object e) => e is SocketException
    ? 'Spotify injoignable. Vérifiez le Wi-Fi ; la partie se joue très bien '
        'sans musique.'
    : "Spotify n'a pas répondu comme prévu.";

class PlaylistSpotify {
  const PlaylistSpotify({
    required this.id,
    required this.nom,
    required this.proprietaire,
    required this.nombrePistes,
  });

  final String id;
  final String nom;
  final String proprietaire;
  final int nombrePistes;

  String get uri => 'spotify:playlist:$id';

  /// Null quand l'entrée n'est pas exploitable.
  ///
  /// Spotify glisse des null dans la liste des listes de lecture (une
  /// playlist supprimée mais encore suivie). Un cast direct planterait
  /// l'écran sur un compte parfaitement ordinaire.
  static PlaylistSpotify? decode(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null) return null;
    final proprio = json['owner'] as Map<String, dynamic>?;
    final pistes = json['tracks'] as Map<String, dynamic>?;
    return PlaylistSpotify(
      id: id,
      nom: json['name'] as String? ?? '(sans nom)',
      proprietaire: proprio?['display_name'] as String? ?? '',
      nombrePistes: pistes?['total'] as int? ?? 0,
    );
  }
}

class AppareilSpotify {
  const AppareilSpotify({
    required this.id,
    required this.nom,
    required this.type,
    required this.actif,
  });

  final String? id;
  final String nom;
  final String type;
  final bool actif;

  factory AppareilSpotify.decode(Map<String, dynamic> json) => AppareilSpotify(
        id: json['id'] as String?,
        nom: json['name'] as String? ?? '(sans nom)',
        type: json['type'] as String? ?? '',
        actif: json['is_active'] as bool? ?? false,
      );
}

/// Ce qui joue en ce moment, tel que la salle le verra.
class LectureSpotify {
  const LectureSpotify({
    required this.idPiste,
    required this.titre,
    required this.artiste,
    required this.pochetteUrl,
    required this.enLecture,
  });

  final String idPiste;
  final String titre;
  final String artiste;
  final String? pochetteUrl;
  final bool enLecture;

  /// Null quand il n'y a rien à montrer : une publicité, ou un type de
  /// contenu qu'on ne sait pas décrire. Mieux vaut un écran d'attente nu
  /// qu'un bandeau qui annonce une réclame à la salle.
  static LectureSpotify? decode(Map<String, dynamic> json) {
    final type = json['currently_playing_type'] as String?;
    if (type == 'ad' || type == 'unknown') return null;
    final item = json['item'] as Map<String, dynamic>?;
    if (item == null) return null;
    final id = item['id'] as String?;
    if (id == null) return null;

    // Un balado n'a pas d'artistes mais un « show » : on garde le titre et
    // on laisse l'artiste vide plutôt que d'inventer.
    final artistes = (item['artists'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map((a) => a['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .join(', ') ??
        '';
    final album = item['album'] as Map<String, dynamic>?;
    final images =
        (album?['images'] as List?)?.whereType<Map<String, dynamic>>();

    return LectureSpotify(
      idPiste: id,
      titre: item['name'] as String? ?? '',
      artiste: artistes,
      pochetteUrl: _pochetteProche(images, 300),
      enLecture: json['is_playing'] as bool? ?? false,
    );
  }

  /// La pochette la plus proche de [vise] pixels.
  ///
  /// Spotify en donne trois (640, 300, 64). La grande pèse pour rien à 96 px
  /// à l'écran, et la petite est floue sur un projecteur.
  static String? _pochetteProche(
      Iterable<Map<String, dynamic>>? images, int vise) {
    if (images == null) return null;
    String? meilleure;
    var ecart = 1 << 30;
    for (final i in images) {
      final url = i['url'] as String?;
      if (url == null) continue;
      final e = ((i['width'] as int? ?? 0) - vise).abs();
      if (e < ecart) {
        ecart = e;
        meilleure = url;
      }
    }
    return meilleure;
  }
}

class ApiSpotify {
  ApiSpotify({required this.client, required this.jeton});

  final http.Client client;

  /// Rend un jeton d'accès valide. Peut rafraîchir en chemin.
  final Future<String> Function() jeton;

  static const _delai = Duration(seconds: 10);

  Future<Map<String, String>> _entetes() async =>
      {'Authorization': 'Bearer ${await jeton()}'};

  Never _lever(http.Response r) {
    final apres = r.headers['retry-after'];
    throw ErreurSpotify(
      r.statusCode,
      messageErreurSpotify(r.statusCode),
      reessayerDans:
          apres == null ? null : Duration(seconds: int.tryParse(apres) ?? 5),
    );
  }

  /// Les listes de lecture du compte, toutes les pages.
  ///
  /// Cinquante par page : un compte qui en a deux cents est banal, et
  /// s'arrêter à la première page ferait disparaître une liste sans rien
  /// dire à personne.
  Future<List<PlaylistSpotify>> listerPlaylists() async {
    final trouvees = <PlaylistSpotify>[];
    var url = '$_base/me/playlists?limit=50';
    // Une borne dure : un « next » qui boucle ne doit pas tourner sans fin
    // pendant la soirée.
    for (var page = 0; page < 20; page++) {
      final r = await client
          .get(Uri.parse(url), headers: await _entetes())
          .timeout(_delai);
      if (r.statusCode != 200) _lever(r);
      final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      for (final item in (json['items'] as List?) ?? const []) {
        if (item is! Map<String, dynamic>) continue;
        final p = PlaylistSpotify.decode(item);
        if (p != null) trouvees.add(p);
      }
      final suivant = json['next'] as String?;
      if (suivant == null) break;
      url = suivant;
    }
    return trouvees;
  }

  Future<List<AppareilSpotify>> appareils() async {
    final r = await client
        .get(Uri.parse('$_base/me/player/devices'), headers: await _entetes())
        .timeout(_delai);
    if (r.statusCode != 200) _lever(r);
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final d in (json['devices'] as List?) ?? const [])
        if (d is Map<String, dynamic>) AppareilSpotify.decode(d),
    ];
  }

  /// Ce qui joue, ou null quand rien ne joue.
  ///
  /// SPOTIFY RÉPOND 204 SANS CORPS quand la lecture est arrêtée : c'est un
  /// succès, pas une erreur, et le décodeur ne doit surtout pas y voir du
  /// JSON vide.
  Future<LectureSpotify?> lectureEnCours() async {
    final r = await client
        .get(Uri.parse('$_base/me/player/currently-playing'),
            headers: await _entetes())
        .timeout(_delai);
    if (r.statusCode == 204 || r.bodyBytes.isEmpty) return null;
    if (r.statusCode != 200) _lever(r);
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return LectureSpotify.decode(json);
  }

  Future<void> lire({String? contextUri, String? appareilId}) async {
    final r = await client
        .put(
          _avecAppareil('$_base/me/player/play', appareilId),
          headers: {
            ...await _entetes(),
            if (contextUri != null) 'Content-Type': 'application/json',
          },
          body:
              contextUri == null ? null : jsonEncode({'context_uri': contextUri}),
        )
        .timeout(_delai);
    _verifierCommande(r);
  }

  Future<void> pause({String? appareilId}) async {
    final r = await client
        .put(_avecAppareil('$_base/me/player/pause', appareilId),
            headers: await _entetes())
        .timeout(_delai);
    // Mettre en pause ce qui est déjà en pause n'est pas une erreur pour
    // l'animateur : Spotify répond 403 « Restriction violated » et il n'y a
    // rien à corriger.
    if (r.statusCode == 403) return;
    _verifierCommande(r);
  }

  Future<void> suivant({String? appareilId}) async {
    final r = await client
        .post(_avecAppareil('$_base/me/player/next', appareilId),
            headers: await _entetes())
        .timeout(_delai);
    _verifierCommande(r);
  }

  Future<void> melanger(bool actif, {String? appareilId}) async {
    final r = await client
        .put(_avecAppareil('$_base/me/player/shuffle?state=$actif', appareilId),
            headers: await _entetes())
        .timeout(_delai);
    _verifierCommande(r);
  }

  static Uri _avecAppareil(String url, String? appareilId) => Uri.parse(
      appareilId == null
          ? url
          : '$url${url.contains('?') ? '&' : '?'}device_id=$appareilId');

  // Les commandes du lecteur répondent 204 sans corps. 202 existe aussi,
  // quand l'appareil est joignable mais lent à obéir.
  void _verifierCommande(http.Response r) {
    if (r.statusCode == 204 || r.statusCode == 200 || r.statusCode == 202) {
      return;
    }
    _lever(r);
  }
}
