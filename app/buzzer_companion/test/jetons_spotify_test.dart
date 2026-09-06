import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/musique/jetons_spotify.dart';

// LE CAS QUI DÉCONNECTE L'ANIMATEUR EN PLEINE SOIRÉE : Spotify ne renvoie
// pas toujours un nouveau jeton de rafraîchissement. Le prendre tel quel
// écrase l'ancien par null, et la connexion meurt à la première heure
// écoulée, sans que rien ne l'explique.

final _midi = DateTime.utc(2026, 9, 6, 12);

void main() {
  test('l\'expiration se calcule depuis le moment de la réponse', () {
    final j = JetonsSpotify.decode(
      const {'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600},
      maintenant: _midi,
    );
    expect(j.expiration, _midi.add(const Duration(hours: 1)));
    expect(j.acces, 'a');
    expect(j.rafraichissement, 'r');
  });

  test('une réponse sans jeton de rafraîchissement garde le précédent', () {
    final j = JetonsSpotify.decode(
      const {'access_token': 'a2', 'expires_in': 3600},
      maintenant: _midi,
      refreshPrecedent: 'ancien',
    );
    expect(j.rafraichissement, 'ancien');
  });

  test('mais un jeton neuf remplace bien l\'ancien', () {
    // La rotation existe : garder l'ancien alors que Spotify en a envoyé un
    // neuf est l'autre moitié du même piège.
    final j = JetonsSpotify.decode(
      const {'access_token': 'a2', 'refresh_token': 'neuf', 'expires_in': 3600},
      maintenant: _midi,
      refreshPrecedent: 'ancien',
    );
    expect(j.rafraichissement, 'neuf');
  });

  test('sans aucun jeton de rafraîchissement, on refuse la réponse', () {
    expect(
      () => JetonsSpotify.decode(
        const {'access_token': 'a', 'expires_in': 3600},
        maintenant: _midi,
      ),
      throwsFormatException,
    );
  });

  test('on rafraîchit une minute avant l\'expiration, pas après', () {
    final j = JetonsSpotify.decode(
      const {'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600},
      maintenant: _midi,
    );
    // Il reste 61 secondes : encore bon.
    expect(j.doitRafraichir(_midi.add(const Duration(seconds: 3539))), isFalse);
    // Il reste 59 secondes : on rafraîchit avant qu'un appel se fasse jeter.
    expect(j.doitRafraichir(_midi.add(const Duration(seconds: 3541))), isTrue);
    // Et bien sûr une fois passé.
    expect(j.doitRafraichir(_midi.add(const Duration(hours: 2))), isTrue);
  });
}
