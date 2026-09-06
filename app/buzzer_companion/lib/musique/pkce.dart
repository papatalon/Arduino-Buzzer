import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

// PKCE : la preuve qu'on est bien celui qui a demandé le code.
//
// L'application est un exécutable distribué : elle ne peut garder aucun
// secret, et Spotify le sait. PKCE remplace le secret client par un secret
// jetable, tiré à chaque connexion : on envoie l'empreinte SHA-256 du
// vérificateur dans la demande d'autorisation, et le vérificateur lui-même
// seulement au moment d'échanger le code. Quelqu'un qui intercepterait le
// code de retour ne pourrait rien en faire sans le vérificateur.
//
// TOUT EST PUR ICI, sans réseau ni horloge : c'est ce qui rend ces trois
// fonctions testables contre les vecteurs de la RFC 7636.

// L'alphabet imposé par la RFC 7636 (section 4.1) : les caractères non
// réservés d'une URL, donc rien à échapper au passage.
const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// Le secret jetable d'une connexion. 64 caractères, dans les bornes de la
/// RFC (43 à 128).
///
/// [hasard] n'est là que pour les tests : en vrai, on veut [Random.secure],
/// parce qu'un vérificateur prévisible ne prouve plus rien.
String genererVerificateur([Random? hasard]) {
  final r = hasard ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 64; i++) _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
  ]);
}

/// L'empreinte à envoyer dans la demande d'autorisation (méthode S256).
///
/// base64url SANS le remplissage « = » : Spotify refuse le code si les
/// signes d'égalité de fin sont là.
String defiDepuis(String verificateur) {
  final empreinte = sha256.convert(ascii.encode(verificateur));
  return base64Url.encode(empreinte.bytes).replaceAll('=', '');
}

/// Le témoin qui relie la réponse du navigateur à NOTRE demande.
///
/// Sans lui, n'importe quelle page ouverte sur le poste pourrait frapper le
/// serveur local avec un code choisi par elle.
String genererEtat([Random? hasard]) {
  final r = hasard ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 32; i++) _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
  ]);
}
