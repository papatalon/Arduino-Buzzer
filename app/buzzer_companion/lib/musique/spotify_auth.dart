import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../broadsheet/ouvrir_navigateur.dart';
import 'jetons_spotify.dart';
import 'pkce.dart';
import 'spotify_api.dart';

// LA CONNEXION À SPOTIFY PASSE PAR LE NAVIGATEUR, PUIS REVIENT ICI.
//
// Spotify n'accepte de renvoyer l'animateur que vers une adresse enregistrée
// d'avance dans son tableau de bord. Pour une application de bureau, la
// seule adresse permise sans certificat est l'adresse de bouclage :
// http://127.0.0.1:PORT/callback. « localhost » est refusé par Spotify, et
// une adresse sans port ni chemin l'est aussi.
//
// D'où un vrai serveur HTTP, le temps d'une connexion, sur un port FIXE :
// l'adresse doit être enregistrée à l'identique, donc pas de port tiré au
// hasard. Trois ports plutôt qu'un, parce qu'un poste où le premier est déjà
// pris ne doit pas rester sans musique ; les trois s'enregistrent d'un coup
// dans le tableau de bord.

class ErreurAuthentification implements Exception {
  ErreurAuthentification(this.message, {this.revoque = false});
  final String message;

  /// Vrai quand Spotify a répudié le jeton de rafraîchissement : il ne sert
  /// plus à rien de le garder, il faut repasser par le navigateur.
  final bool revoque;

  @override
  String toString() => message;
}

class AuthentificationSpotify {
  AuthentificationSpotify({http.Client? client, this.ouvrir})
      : client = client ?? http.Client();

  final http.Client client;

  /// Injecté par les tests, qui ne veulent pas d'un vrai navigateur.
  final Future<bool> Function(String url)? ouvrir;

  /// Les trois adresses à enregistrer dans le tableau de bord Spotify.
  static const portsCandidats = [51234, 51235, 51236];

  static String uriDeRetour(int port) => 'http://127.0.0.1:$port/callback';

  /// Les trois adresses à copier telles quelles, pour l'écran d'aide.
  static List<String> get urisAEnregistrer =>
      [for (final p in portsCandidats) uriDeRetour(p)];

  static const _autorisation = 'https://accounts.spotify.com/authorize';
  static const _jetonUrl = 'https://accounts.spotify.com/api/token';

  HttpServer? _serveur;

  /// L'adresse d'autorisation, quand le navigateur n'a pas pu être ouvert.
  /// L'écran la propose alors au presse-papiers.
  String? urlDeSecours;

  /// Ouvre le navigateur, attend le retour, échange le code.
  ///
  /// [delai] borne l'attente : un animateur qui abandonne à mi-chemin ne doit
  /// pas laisser un serveur ouvert sur son poste pour le reste de la soirée.
  Future<JetonsSpotify> connecter({
    required String clientId,
    Duration delai = const Duration(minutes: 3),
  }) async {
    final verificateur = genererVerificateur();
    final temoin = genererEtat();
    urlDeSecours = null;

    final serveur = await _ecouter();
    _serveur = serveur;
    final retour = uriDeRetour(serveur.port);

    final url = Uri.parse(_autorisation).replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': retour,
      'code_challenge_method': 'S256',
      'code_challenge': defiDepuis(verificateur),
      'state': temoin,
      'scope': kScopesSpotify,
    }).toString();

    try {
      final ouvert = await (ouvrir ?? ouvrirDansLeNavigateur)(url);
      if (!ouvert) urlDeSecours = url;

      final code = await _attendreLeCode(serveur, temoin).timeout(
        delai,
        onTimeout: () => throw ErreurAuthentification(
            "Spotify n'a pas répondu à temps. Reprenez la connexion quand "
            'vous voulez.'),
      );
      return await _echanger(
          clientId: clientId, code: code, retour: retour, verificateur: verificateur);
    } finally {
      // UN SERVEUR NON FERMÉ GARDE LE PORT pour toute la session : la
      // deuxième tentative de connexion échouerait alors sur un port occupé,
      // par notre faute. Fermé dans tous les cas, y compris l'annulation.
      await serveur.close(force: true);
      _serveur = null;
      urlDeSecours = null;
    }
  }

  /// Ferme le serveur : l'attente en cours se termine en erreur.
  Future<void> annuler() async {
    await _serveur?.close(force: true);
    _serveur = null;
  }

  Future<HttpServer> _ecouter() async {
    for (final port in portsCandidats) {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } on SocketException {
        // Port pris par autre chose : on essaie le suivant.
      }
    }
    throw ErreurAuthentification(
        'Aucun des ports ${portsCandidats.join(', ')} n\'est libre sur ce '
        'poste. Fermez ce qui les occupe, puis reprenez.');
  }

  Future<String> _attendreLeCode(HttpServer serveur, String temoin) async {
    await for (final requete in serveur) {
      if (requete.uri.path != '/callback') {
        // Le navigateur demande souvent /favicon.ico en chemin : ce n'est
        // pas le retour de Spotify, on continue d'attendre.
        requete.response.statusCode = HttpStatus.notFound;
        await requete.response.close();
        continue;
      }

      final params = requete.uri.queryParameters;
      final erreur = params['error'];
      final code = params['code'];

      if (params['state'] != temoin) {
        // Le témoin ne colle pas : cette réponse ne vient pas de la demande
        // qu'on a faite. N'importe quelle page ouverte sur le poste peut
        // frapper cette adresse.
        await _repondre(requete, 400, 'Demande inconnue',
            'Cette réponse ne vient pas de la console. Reprenez la connexion '
            'depuis la console du Buzzer.');
        throw ErreurAuthentification(
            'La réponse de Spotify ne correspond pas à la demande. Reprenez '
            'la connexion.');
      }

      if (erreur != null) {
        await _repondre(requete, 200, 'Connexion refusée',
            'Vous pouvez fermer cet onglet et revenir à la console.');
        throw ErreurAuthentification(erreur == 'access_denied'
            ? 'Vous avez refusé la connexion à Spotify.'
            : 'Spotify a refusé la connexion ($erreur).');
      }

      if (code == null) {
        await _repondre(requete, 400, 'Réponse incomplète',
            'Reprenez la connexion depuis la console du Buzzer.');
        throw ErreurAuthentification('Spotify a répondu sans code.');
      }

      await _repondre(requete, 200, 'Connexion réussie',
          'Vous pouvez fermer cet onglet et revenir à la console du Buzzer.');
      return code;
    }
    // Le flux se termine quand le serveur ferme : c'est l'annulation.
    throw ErreurAuthentification('Connexion annulée.');
  }

  // La seule page web de tout le projet. Sobre à dessein : elle s'affiche
  // dans le navigateur de l'animateur, pas dans le design system, et elle
  // n'a qu'une phrase à dire. Aucun script, aucune ressource externe : le
  // poste peut très bien ne pas avoir de Wi-Fi une fois le retour reçu.
  Future<void> _repondre(
      HttpRequest requete, int statut, String titre, String ligne) async {
    requete.response
      ..statusCode = statut
      ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
      ..write('<!doctype html><html lang="fr"><head>'
          '<meta charset="utf-8"><title>$titre</title></head>'
          '<body style="margin:0;background:#F3F2F2;color:#201E1D;'
          'font-family:Georgia,serif;display:flex;align-items:center;'
          'justify-content:center;height:100vh">'
          '<div style="text-align:center">'
          '<div style="width:96px;height:4px;background:#D6006C;'
          'margin:0 auto 28px"></div>'
          '<h1 style="font-size:36px;margin:0 0 12px">$titre</h1>'
          '<p style="font-size:18px;color:#5A5654;margin:0">$ligne</p>'
          '</div></body></html>');
    await requete.response.close();
  }

  Future<JetonsSpotify> _echanger({
    required String clientId,
    required String code,
    required String retour,
    required String verificateur,
  }) =>
      _demanderJetons({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': retour,
        'client_id': clientId,
        'code_verifier': verificateur,
      }, clientId: clientId);

  /// Renouvelle le jeton d'accès sans repasser par le navigateur.
  Future<JetonsSpotify> rafraichir({
    required String clientId,
    required String refresh,
  }) =>
      _demanderJetons({
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'client_id': clientId,
      }, clientId: clientId, refreshPrecedent: refresh);

  Future<JetonsSpotify> _demanderJetons(
    Map<String, String> corps, {
    required String clientId,
    String? refreshPrecedent,
  }) async {
    final http.Response r;
    try {
      r = await client
          .post(Uri.parse(_jetonUrl),
              headers: const {
                'Content-Type': 'application/x-www-form-urlencoded'
              },
              body: corps)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw ErreurAuthentification(messageErreurReseau(e));
    }

    final json = _lireJson(r);
    if (r.statusCode != 200) {
      throw ErreurAuthentification(_messageDuRefus(json),
          revoque: json['error'] == 'invalid_grant');
    }
    try {
      return JetonsSpotify.decode(json,
          maintenant: DateTime.now(), refreshPrecedent: refreshPrecedent);
    } on FormatException {
      throw ErreurAuthentification(
          "Spotify n'a pas renvoyé de quoi rester connecté. Reprenez la "
          'connexion.');
    }
  }

  Map<String, dynamic> _lireJson(http.Response r) {
    try {
      final decode = jsonDecode(utf8.decode(r.bodyBytes));
      return decode is Map<String, dynamic> ? decode : const {};
    } catch (_) {
      return const {};
    }
  }

  // Les refus de Spotify arrivent en anglais et en jargon. Ceux qui comptent
  // ont chacun une cause concrète et un geste à poser dans le tableau de
  // bord : les laisser tels quels ferait chercher l'animateur pour rien.
  String _messageDuRefus(Map<String, dynamic> json) {
    final code = json['error'] as String?;
    final detail = json['error_description'] as String?;
    return switch (code) {
      'invalid_client' =>
        'Client ID inconnu de Spotify. Vérifiez-le dans le tableau de bord.',
      'invalid_grant' =>
        'La connexion à Spotify a été révoquée. Reconnectez-vous.',
      'invalid_request' when detail != null && detail.contains('redirect') =>
        "L'adresse de retour n'est pas enregistrée. Ajoutez les trois "
            'adresses ${urisAEnregistrer.join(', ')} dans le tableau de bord.',
      _ => detail == null
          ? 'Spotify a refusé la connexion.'
          : 'Spotify a refusé la connexion : $detail',
    };
  }
}
