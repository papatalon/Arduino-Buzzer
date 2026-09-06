import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzzer_companion/musique/ambiance_spotify.dart';

// LA MUSIQUE D'AMBIANCE NE DOIT JAMAIS RETARDER UNE SOIRÉE.
//
// Deux choses se vérifient ici, et elles ne se voient pas autrement : ce
// qu'on retient d'une soirée à l'autre (le Client ID et la liste choisie,
// pour ne pas refaire la configuration devant la salle), et le fait que
// l'ouverture d'une partie coupe la musique TOUT DE SUITE, sans attendre
// que Spotify réponde. Le son s'arrête en une fraction de seconde ; un
// bandeau qui survivrait deux secondes de plus sur l'écran public se
// remarquerait.

// Un client qui n'ira jamais nulle part : aucun de ces tests ne parle à
// Spotify.
AmbianceSpotify _ambiance() => AmbianceSpotify(
      client: MockClient((_) async => http.Response('', 500)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le Client ID et la liste choisie survivent à la fermeture', () async {
    SharedPreferences.setMockInitialValues({});
    final a = _ambiance();
    await a.reglerClientId('  mon-client-id  ');
    await a.choisirPlaylist('37i9');
    await a.basculerAleatoire();
    // Le Client ID arrive souvent collé du tableau de bord, avec des
    // espaces autour : Spotify le refuserait tel quel.
    expect(a.clientId, 'mon-client-id');
    a.dispose();

    SharedPreferences.setMockInitialValues({
      'spotify_client_id': 'mon-client-id',
      'spotify_playlist_id': '37i9',
      'spotify_aleatoire': true,
    });
    final relu = _ambiance();
    await relu.load();
    expect(relu.clientId, 'mon-client-id');
    expect(relu.playlistChoisieId, '37i9');
    expect(relu.aleatoire, isTrue);
    relu.dispose();
  });

  test('sans jeton retenu, on reste déconnecté et silencieux', () async {
    SharedPreferences.setMockInitialValues({});
    final a = _ambiance();
    await a.load();
    expect(a.etat, EtatAmbiance.deconnecte);
    expect(a.derniereErreur, isNull);
    expect(a.piste.quelqueChose, isFalse);
    a.dispose();
  });

  test('se connecter sans Client ID ne fait rien du tout', () async {
    // Le bouton est désactivé, mais rien n'empêchera un jour un appel
    // ailleurs : ouvrir un navigateur sur une adresse sans client_id
    // afficherait une erreur Spotify incompréhensible.
    SharedPreferences.setMockInitialValues({});
    final a = _ambiance();
    await a.load();
    await a.connecter();
    expect(a.etat, EtatAmbiance.deconnecte);
    a.dispose();
  });

  test('le départ d\'une partie coupe la musique sans attendre Spotify',
      () async {
    SharedPreferences.setMockInitialValues({});
    final a = _ambiance();
    await a.load();
    a.reprendrePourTest(
      etat: EtatAmbiance.enLecture,
      titre: 'Dégénérations',
      artiste: 'Mes Aïeux',
    );
    expect(a.piste.quelqueChose, isTrue);

    // Synchrone : le bandeau public disparaît dans le même battement.
    a.pauserPourLaPartie();
    expect(a.etat, EtatAmbiance.enPause);
    expect(a.piste.quelqueChose, isFalse);
    expect(a.enPausePourLaPartie, isTrue);
    a.dispose();
  });

  test('rien à couper quand rien ne joue', () async {
    SharedPreferences.setMockInitialValues({});
    final a = _ambiance();
    await a.load();
    a.pauserPourLaPartie();
    // Surtout pas « en pause pour la partie » : le message qui va avec
    // dirait à l'animateur de cliquer Lire pour rien.
    expect(a.enPausePourLaPartie, isFalse);
    expect(a.etat, EtatAmbiance.deconnecte);
    a.dispose();
  });
}
