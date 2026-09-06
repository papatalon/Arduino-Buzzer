import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:buzzer_companion/musique/spotify_auth.dart';

// Le retour de Spotify passe par un vrai serveur local. Ce qui se teste ici
// n'est pas le réseau mais deux choses qui ne se voient pas autrement :
// le témoin qui doit correspondre (sans lui, n'importe quelle page ouverte
// sur le poste pourrait répondre à la place de Spotify), et le port qui doit
// être rendu à la fin (un serveur oublié rendrait la deuxième connexion de
// la soirée impossible, par notre faute).

http.Response _rep(Object json, [int statut = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(json)), statut);

// Frappe l'adresse de retour comme le ferait le navigateur, en reprenant le
// témoin de l'URL d'autorisation.
Future<void> _repondreCommeSpotify(String urlAutorisation,
    {String? code, String? temoin, String? erreur}) async {
  final auth = Uri.parse(urlAutorisation);
  final retour = Uri.parse(auth.queryParameters['redirect_uri']!);
  final client = HttpClient();
  final req = await client.getUrl(retour.replace(queryParameters: {
    'state': temoin ?? auth.queryParameters['state']!,
    'code': ?code,
    'error': ?erreur,
  }));
  final rep = await req.close();
  await rep.drain<void>();
  client.close();
}

void main() {
  test('les trois adresses de retour sont celles du tableau de bord', () {
    expect(AuthentificationSpotify.uriDeRetour(51234),
        'http://127.0.0.1:51234/callback');
    // « localhost » est refusé par Spotify, et une adresse sans port ni
    // chemin aussi : c'est exactement ce que l'écran d'aide fait copier.
    expect(AuthentificationSpotify.urisAEnregistrer, [
      'http://127.0.0.1:51234/callback',
      'http://127.0.0.1:51235/callback',
      'http://127.0.0.1:51236/callback',
    ]);
  });

  test('une connexion complète rend les deux jetons', () async {
    late String corpsVu;
    final auth = AuthentificationSpotify(
      client: MockClient((r) async {
        corpsVu = r.body;
        return _rep({
          'access_token': 'acces1',
          'refresh_token': 'refresh1',
          'expires_in': 3600,
        });
      }),
      ouvrir: (url) async {
        // Le « navigateur » répond tout de suite, comme Spotify le ferait.
        unawaited(_repondreCommeSpotify(url, code: 'abc'));
        return true;
      },
    );

    final jetons = await auth.connecter(clientId: 'cid');
    expect(jetons.acces, 'acces1');
    expect(jetons.rafraichissement, 'refresh1');
    // Le vérificateur ne part QU'À l'échange : c'est tout l'intérêt de PKCE.
    expect(corpsVu, contains('code_verifier='));
    expect(corpsVu, contains('grant_type=authorization_code'));
  });

  test('le port est rendu une fois la connexion faite', () async {
    // Le piège : un serveur laissé ouvert rendrait la connexion suivante
    // impossible, et on accuserait Spotify.
    final auth = AuthentificationSpotify(
      client: MockClient((_) async => _rep({
            'access_token': 'a',
            'refresh_token': 'r',
            'expires_in': 3600,
          })),
      ouvrir: (url) async {
        unawaited(_repondreCommeSpotify(url, code: 'abc'));
        return true;
      },
    );
    await auth.connecter(clientId: 'cid');

    final reprise =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 51234);
    await reprise.close(force: true);
  });

  test('un témoin qui ne colle pas fait échouer la connexion', () async {
    final auth = AuthentificationSpotify(
      client: MockClient((_) async => _rep(const {})),
      ouvrir: (url) async {
        unawaited(_repondreCommeSpotify(url, code: 'abc', temoin: 'pas-le-bon'));
        return true;
      },
    );
    await expectLater(
      auth.connecter(clientId: 'cid'),
      throwsA(isA<ErreurAuthentification>()),
    );
  });

  test('un refus de l\'animateur se dit en clair', () async {
    final auth = AuthentificationSpotify(
      client: MockClient((_) async => _rep(const {})),
      ouvrir: (url) async {
        unawaited(_repondreCommeSpotify(url, erreur: 'access_denied'));
        return true;
      },
    );
    await expectLater(
      auth.connecter(clientId: 'cid'),
      throwsA(isA<ErreurAuthentification>()
          .having((e) => e.message, 'message', contains('refusé'))),
    );
  });

  test('le navigateur qui ne s\'ouvre pas laisse une adresse à copier',
      () async {
    String? vue;
    final auth = AuthentificationSpotify(
      client: MockClient((_) async => _rep(const {})),
      ouvrir: (url) async {
        vue = url;
        return false;
      },
    );
    // Personne ne répondra : on coupe court.
    await expectLater(
      auth.connecter(clientId: 'cid', delai: const Duration(milliseconds: 200)),
      throwsA(isA<ErreurAuthentification>()),
    );
    expect(vue, contains('code_challenge_method=S256'));
    expect(vue, contains('client_id=cid'));
  });

  test('un Client ID inconnu se nomme, plutôt que de sortir en jargon',
      () async {
    final auth = AuthentificationSpotify(
      client: MockClient((_) async => _rep(
          const {'error': 'invalid_client', 'error_description': 'Invalid client'},
          400)),
      ouvrir: (url) async {
        unawaited(_repondreCommeSpotify(url, code: 'abc'));
        return true;
      },
    );
    await expectLater(
      auth.connecter(clientId: 'mauvais'),
      throwsA(isA<ErreurAuthentification>()
          .having((e) => e.message, 'message', contains('Client ID'))),
    );
  });

  test('un jeton de rafraîchissement répudié se signale comme tel', () async {
    // C'est le seul cas où il faut effacer ce qu'on a gardé : réessayer
    // avec le même jeton échouera toujours.
    final auth = AuthentificationSpotify(
      client: MockClient((_) async => _rep(const {'error': 'invalid_grant'}, 400)),
    );
    await expectLater(
      auth.rafraichir(clientId: 'cid', refresh: 'vieux'),
      throwsA(isA<ErreurAuthentification>()
          .having((e) => e.revoque, 'révoqué', isTrue)),
    );
  });

  test('un rafraîchissement sans nouveau jeton garde l\'ancien', () async {
    final auth = AuthentificationSpotify(
      client: MockClient((_) async =>
          _rep({'access_token': 'a2', 'expires_in': 3600})),
    );
    final j = await auth.rafraichir(clientId: 'cid', refresh: 'garde-moi');
    expect(j.rafraichissement, 'garde-moi');
  });
}
