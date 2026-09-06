import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:buzzer_companion/musique/spotify_api.dart';

// Le réseau n'est jamais testé dans ce projet, et ça se défend : la banque
// et la vérification de version se contentent d'échouer en silence. Spotify
// est différent, parce que ses réponses ont des formes qu'on n'invente pas :
// un 204 vide qui veut dire « rien ne joue », un null au milieu de la liste
// des listes de lecture, une pagination qui cache la moitié d'un compte.
// C'est ce décodage-là qui est vérifié ici, pas le réseau.

ApiSpotify _api(MockClient client) =>
    ApiSpotify(client: client, jeton: () async => 'jeton-bidon');

// Une réponse en VRAIS octets UTF-8. http.Response(String) encode en
// latin-1 faute d'en-tête de charset, et « Dégénérations » y perdrait ses
// accents : le test mentirait sur ce que Spotify envoie vraiment.
http.Response _rep(Object json) =>
    http.Response.bytes(utf8.encode(jsonEncode(json)), 200);

void main() {
  test('les listes de lecture suivent la pagination', () {
    // Le piège : s'arrêter à la première page ferait disparaître des listes
    // sans le dire, sur un compte qui en a plus de cinquante.
    final client = MockClient((r) async {
      if (r.url.query.contains('offset=50')) {
        return _rep({
          'items': [
            {
              'id': 'b',
              'name': 'Deuxième',
              'owner': {'display_name': 'Marc'},
              'tracks': {'total': 12},
            }
          ],
          'next': null,
        });
      }
      return _rep({
        'items': [
          {
            'id': 'a',
            'name': 'Première',
            'owner': {'display_name': 'Marc'},
            'tracks': {'total': 40},
          },
          // Une liste supprimée mais encore suivie : Spotify laisse un
          // null dans le tableau.
          null,
        ],
        'next': 'https://api.spotify.com/v1/me/playlists?limit=50&offset=50',
      });
    });

    expectLater(
      _api(client).listerPlaylists().then((l) => l.map((p) => p.nom).toList()),
      completion(['Première', 'Deuxième']),
    );
  });

  test('un 204 veut dire que rien ne joue, pas une erreur', () async {
    final client = MockClient((_) async => http.Response('', 204));
    expect(await _api(client).lectureEnCours(), isNull);
  });

  test('la piste en cours se lit avec ses artistes et sa pochette', () async {
    final client = MockClient((_) async => _rep({
          'is_playing': true,
          'currently_playing_type': 'track',
          'item': {
            'id': 'p1',
            'name': 'Dégénérations',
            'artists': [
              {'name': 'Mes Aïeux'},
              {'name': "Quelqu'un d'autre"},
            ],
            'album': {
              'images': [
                {'url': 'https://exemple/640.jpg', 'width': 640},
                {'url': 'https://exemple/300.jpg', 'width': 300},
                {'url': 'https://exemple/64.jpg', 'width': 64},
              ],
            },
          },
        }));

    final l = (await _api(client).lectureEnCours())!;
    expect(l.titre, 'Dégénérations');
    expect(l.artiste, "Mes Aïeux, Quelqu'un d'autre");
    // Ni la grande (inutile à 96 px) ni la petite (floue sur un projecteur).
    expect(l.pochetteUrl, 'https://exemple/300.jpg');
    expect(l.enLecture, isTrue);
  });

  test('une publicité ne monte pas sur l\'écran public', () async {
    final client = MockClient((_) async => _rep({
          'is_playing': true,
          'currently_playing_type': 'ad',
          'item': {'id': 'x', 'name': 'Achetez ceci'},
        }));
    expect(await _api(client).lectureEnCours(), isNull);
  });

  test('un balado garde son titre et se passe d\'artiste', () async {
    final client = MockClient((_) async => _rep({
          'is_playing': true,
          'currently_playing_type': 'episode',
          'item': {'id': 'e1', 'name': 'Un épisode'},
        }));
    final l = (await _api(client).lectureEnCours())!;
    expect(l.titre, 'Un épisode');
    expect(l.artiste, isEmpty);
    expect(l.pochetteUrl, isNull);
  });

  test('le 404 parle d\'appareil, pas de code HTTP', () async {
    final client = MockClient((_) async => http.Response('', 404));
    await expectLater(
      _api(client).lire(contextUri: 'spotify:playlist:x'),
      throwsA(isA<ErreurSpotify>()
          .having((e) => e.statut, 'statut', 404)
          .having((e) => e.message, 'message', contains('appareil'))),
    );
  });

  test('le 429 rapporte le délai demandé', () async {
    final client = MockClient(
        (_) async => http.Response('', 429, headers: {'retry-after': '7'}));
    await expectLater(
      _api(client).appareils(),
      throwsA(isA<ErreurSpotify>().having(
          (e) => e.reessayerDans, 'délai', const Duration(seconds: 7))),
    );
  });

  test('mettre en pause ce qui est déjà en pause ne se plaint pas', () async {
    // Spotify répond 403 « Restriction violated ». Il n'y a rien à corriger,
    // et un message rouge en pleine soirée pour ça serait du bruit.
    final client = MockClient((_) async => http.Response('', 403));
    await _api(client).pause();
  });

  test('la commande de lecture cible l\'appareil demandé', () async {
    late Uri vue;
    late String corps;
    final client = MockClient((r) async {
      vue = r.url;
      corps = r.body;
      return http.Response('', 204);
    });
    await _api(client)
        .lire(contextUri: 'spotify:playlist:abc', appareilId: 'dev1');
    expect(vue.queryParameters['device_id'], 'dev1');
    expect(jsonDecode(corps), {'context_uri': 'spotify:playlist:abc'});
  });

  test('l\'aléatoire garde son paramètre en ajoutant l\'appareil', () async {
    // Le piège : coller « ?device_id » sur une adresse qui a déjà un « ? »
    // donnerait une URL invalide et un aléatoire qui ne s'active jamais.
    late Uri vue;
    final client = MockClient((r) async {
      vue = r.url;
      return http.Response('', 204);
    });
    await _api(client).melanger(true, appareilId: 'dev1');
    expect(vue.queryParameters['state'], 'true');
    expect(vue.queryParameters['device_id'], 'dev1');
  });
}
