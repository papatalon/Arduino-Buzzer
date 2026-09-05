import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'questionnaires/banque.dart';

// Sait si une version plus récente de l'application est publiée.
//
// LA COMPARAISON PORTE SUR LE NUMÉRO DE BUILD, un entier qui ne fait que
// monter, jamais sur la version affichée. Comparer « 1.10.0 » et « 1.9.0 »
// comme des chaînes donne la mauvaise réponse, et les comparer correctement
// demande du code sémantique qu'il faut réussir. Un « > » entre deux entiers
// n'a rien à rater. La version lisible voyage quand même, parce que c'est
// elle qu'on montre : « 1.2.0 » veut dire quelque chose là où « build 7 » ne
// dit rien.
//
// La version locale est LUE DANS L'EXÉCUTABLE (package_info_plus) et non
// recopiée dans une constante : une version en double finit toujours par
// diverger, et c'est l'avis de mise à jour qui mentirait.
//
// SILENCIEUX EN CAS D'ÉCHEC. Pas de réseau, site injoignable, fichier
// illisible : on ne dit rien. Personne n'a envie d'un avertissement rouge
// « impossible de vérifier les mises à jour » cinq minutes avant de lancer
// une soirée. L'absence de bandeau ne prouve donc pas qu'on est à jour, et
// c'est le bon compromis pour cette application.

const _dismissedKey = 'version_banner_dismissed_build';

// La règle, isolée de la plomberie réseau pour être vérifiable.
//
// INCONNU SE DIT null, PAS ZÉRO. Une version qu'on n'a pas pu lire et une
// version numérotée zéro sont deux choses différentes, et zéro est un
// numéro de build parfaitement légitime : le premier. Confondre les deux
// faisait taire le bandeau pour quiconque tourne sur un build 0, sans que
// rien ne le signale.
//
// « ferme < publie » : la fermeture vaut POUR CETTE VERSION-LÀ. C'est la
// condition qu'on croit avoir écrite alors qu'on a écrit autre chose. Un
// simple booléen « déjà fermé » ferait taire toutes les versions à venir, et
// l'opérateur ne reverrait plus jamais d'avis de mise à jour.
bool doitAnnoncer({required int? local, required int? publie, required int ferme}) =>
    local != null && publie != null && publie > local && ferme < publie;

class VersionCheck extends ChangeNotifier {
  // null tant qu'on n'a pas pu lire la version embarquee.
  int? _localBuild;
  String localVersion = '';

  // null tant que le site n'a pas repondu.
  int? _latestBuild;
  String latestVersion = '';
  String? notesUrl;
  String? downloadUrl;

  // Build dont l'opérateur a fermé le bandeau. Retenu pour que la fermeture
  // tienne d'une séance à l'autre, mais rattaché À CETTE VERSION-LÀ : la
  // suivante s'annoncera de nouveau. Un « ne plus jamais me le dire » global
  // ferait taire toutes les versions à venir.
  // -1, et non 0 : zéro est un numéro de build légitime, donc il ne peut pas
  // vouloir dire « rien n'a été fermé ».
  int _dismissedBuild = -1;

  bool get shouldShow => doitAnnoncer(
        local: _localBuild,
        publie: _latestBuild,
        ferme: _dismissedBuild,
      );

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      localVersion = info.version;
      _localBuild = int.tryParse(info.buildNumber);
      debugPrint('VersionCheck : locale ${info.version} '
          'build "${info.buildNumber}" lu comme $_localBuild');
    } catch (_) {
      // Sans version locale, toute comparaison serait un mensonge : on se
      // tait plutôt que d'annoncer une mise à jour au hasard.
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _dismissedBuild = prefs.getInt(_dismissedKey) ?? -1;

    try {
      final reponse = await http
          .get(Uri.parse('$kSiteUrl/version.json'))
          .timeout(const Duration(seconds: 10));
      if (reponse.statusCode != 200) return;
      final parsed = jsonDecode(utf8.decode(reponse.bodyBytes));
      if (parsed is! Map<String, dynamic>) return;
      if (parsed['format'] != 'buzzer-version') return;

      _latestBuild = (parsed['build'] as num?)?.toInt();
      latestVersion = (parsed['version'] as String?)?.trim() ?? '';
      notesUrl = (parsed['notes'] as String?)?.trim();
      downloadUrl = (parsed['telechargement'] as String?)?.trim();
      debugPrint('VersionCheck : publiee $latestVersion build $_latestBuild, '
          'fermee $_dismissedBuild, bandeau=$shouldShow');
      notifyListeners();
    } on SocketException {
      // Hors ligne : silence.
    } catch (_) {
      // Fichier absent ou illisible : silence.
    }
  }

  Future<void> dismiss() async {
    _dismissedBuild = _latestBuild ?? _dismissedBuild;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedKey, _dismissedBuild);
  }
}
