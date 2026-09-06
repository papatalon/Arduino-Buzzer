import 'dart:io';

import 'package:flutter/foundation.dart';

// Ouvre une adresse dans le navigateur du poste.
//
// PAS PAR « cmd /c start ». C'est ce qu'on faisait, et ça marchait tant
// qu'on n'ouvrait que des adresses de téléchargement, sans paramètres.
// L'adresse d'autorisation de Spotify en porte six, séparés par des « & »,
// et « & » est le séparateur de commandes de cmd : le navigateur ne
// recevait que le premier paramètre, et Spotify répondait
// « response_type must be code » sur une adresse tronquée. Le piège est
// invisible tant qu'aucune adresse ne contient de « & ».
//
// rundll32 ne passe par aucun shell : l'adresse arrive entière, quels que
// soient ses caractères. Le repli garde cmd, avec les métacaractères
// échappés, pour le cas très improbable où rundll32 manquerait.
//
// Rend faux plutôt que de lever : les deux appelants (l'avis de mise à jour
// et la connexion à Spotify) ont chacun leur repli, et ce n'est pas à cette
// fonction de choisir lequel.
Future<bool> ouvrirDansLeNavigateur(String url) async {
  if (url.isEmpty) return false;
  try {
    final r = await Process.run(
        'rundll32', ['url.dll,FileProtocolHandler', url]);
    if (r.exitCode == 0) return true;
  } catch (_) {
    // On tente le repli.
  }
  try {
    // La chaîne vide après « start » est le titre de fenêtre, obligatoire :
    // sinon une adresse entre guillemets est prise pour un titre et rien ne
    // s'ouvre.
    final r =
        await Process.run('cmd', ['/c', 'start', '', echapperPourCmd(url)]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Neutralise les métacaractères de cmd dans une adresse.
///
/// Pure et exposée pour être testée : c'est le genre de bogue qui ne se voit
/// que dans un navigateur qui s'ouvre sur la mauvaise page, et qu'on met une
/// heure à attribuer au bon coupable.
@visibleForTesting
String echapperPourCmd(String url) =>
    url.replaceAllMapped(RegExp(r'[&|<>^()]'), (m) => '^${m[0]}');
