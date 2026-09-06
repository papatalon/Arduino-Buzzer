import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/musique/pkce.dart';

// PKCE se trompe en silence, et c'est ce qui le rend dangereux : un défi mal
// calculé ne se voit pas à la connexion (Spotify accepte la demande), il se
// voit à l'échange du code, sous la forme d'un « invalid_grant » qu'on
// mettrait des heures à attribuer au bon coupable.
//
// Le piège concret : base64url renvoie du remplissage « = » que Spotify
// refuse. Le vecteur de la RFC 7636 (annexe B) l'attrape d'un coup.

void main() {
  test('le défi suit le vecteur de la RFC 7636', () {
    expect(
      defiDepuis('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('le défi ne porte aucun remplissage', () {
    for (var i = 0; i < 20; i++) {
      expect(defiDepuis(genererVerificateur()), isNot(contains('=')));
    }
  });

  test('le vérificateur reste dans les bornes et dans l\'alphabet', () {
    final permis = RegExp(r'^[A-Za-z0-9\-._~]+$');
    for (var i = 0; i < 20; i++) {
      final v = genererVerificateur();
      expect(v.length, inInclusiveRange(43, 128));
      expect(permis.hasMatch(v), isTrue, reason: v);
    }
  });

  test('deux connexions ne partagent ni vérificateur ni témoin', () {
    // Un témoin constant laisserait n'importe quelle page ouverte sur le
    // poste répondre à la place de Spotify.
    expect(genererVerificateur(), isNot(genererVerificateur()));
    expect(genererEtat(), isNot(genererEtat()));
  });
}
