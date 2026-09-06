import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/broadsheet/ouvrir_navigateur.dart';

// LE BOGUE QUI A COÛTÉ UNE PREMIÈRE CONNEXION À SPOTIFY.
//
// « cmd /c start » coupait l'adresse d'autorisation à son premier « & »,
// parce que c'est le séparateur de commandes de cmd. Le navigateur
// s'ouvrait sur une adresse tronquée après client_id, et Spotify répondait
// « response_type must be code » : un message qui accuse le code alors que
// le fautif est le shell.
//
// Ça n'a pas paru pendant des mois : le seul appelant d'alors ouvrait des
// adresses de téléchargement, sans le moindre paramètre.

void main() {
  test('les séparateurs de commandes de cmd sont neutralisés', () {
    expect(
      echapperPourCmd(
          'https://accounts.spotify.com/authorize?client_id=abc&response_type=code'),
      'https://accounts.spotify.com/authorize?client_id=abc^&response_type=code',
    );
  });

  test('tous les « & » y passent, pas seulement le premier', () {
    // L'adresse d'autorisation en porte six.
    expect(echapperPourCmd('a?x=1&y=2&z=3&w=4'), 'a?x=1^&y=2^&z=3^&w=4');
  });

  test('les autres métacaractères de cmd aussi', () {
    // Un « | » dans une adresse redirigerait la sortie, un « > » écrirait un
    // fichier. Rien de tout ça n'a sa place dans une barre d'adresse.
    expect(echapperPourCmd('a|b>c<d^e(f)'), 'a^|b^>c^<d^^e^(f^)');
  });

  test('une adresse ordinaire ressort intacte', () {
    // Celle de l'avis de mise à jour, qui n'a jamais rien eu à échapper.
    const zip = 'https://buzzer.sd6tools.net/buzzer-console-2.1.0-windows.zip';
    expect(echapperPourCmd(zip), zip);
  });
}
