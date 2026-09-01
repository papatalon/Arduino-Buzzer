import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'questionnaires/catalogue.dart';

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
// Trois conditions.
//
// « local > 0 » : sans version locale connue, comparer n'a aucun sens et
// l'avis serait tiré au hasard. init() s'arrête déjà avant d'interroger le
// site dans ce cas, mais la règle ne doit pas dépendre d'un ordre
// d'exécution qu'un remaniement pourrait changer.
//
// « ferme < publie » : la fermeture vaut POUR CETTE VERSION-LÀ. C'est la
// condition qu'on croit avoir écrite alors qu'on a écrit autre chose. Un
// simple booléen « déjà fermé » ferait taire toutes les versions à venir, et
// l'opérateur ne reverrait plus jamais d'avis de mise à jour.
bool doitAnnoncer({required int local, required int publie, required int ferme}) =>
    local > 0 && publie > local && ferme < publie;

class VersionCheck extends ChangeNotifier {
  int _localBuild = 0;
  String localVersion = '';

  int _latestBuild = 0;
  String latestVersion = '';
  String? notesUrl;
  String? downloadUrl;

  // Build dont l'opérateur a fermé le bandeau. Retenu pour que la fermeture
  // tienne d'une séance à l'autre, mais rattaché À CETTE VERSION-LÀ : la
  // suivante s'annoncera de nouveau. Un « ne plus jamais me le dire » global
  // ferait taire toutes les versions à venir.
  int _dismissedBuild = 0;

  bool get updateAvailable => _latestBuild > _localBuild;
  bool get shouldShow => doitAnnoncer(
        local: _localBuild,
        publie: _latestBuild,
        ferme: _dismissedBuild,
      );

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      localVersion = info.version;
      _localBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // Sans version locale, toute comparaison serait un mensonge : on se
      // tait plutôt que d'annoncer une mise à jour au hasard.
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _dismissedBuild = prefs.getInt(_dismissedKey) ?? 0;

    try {
      final reponse = await http
          .get(Uri.parse('$kCatalogueUrl/version.json'))
          .timeout(const Duration(seconds: 10));
      if (reponse.statusCode != 200) return;
      final parsed = jsonDecode(utf8.decode(reponse.bodyBytes));
      if (parsed is! Map<String, dynamic>) return;
      if (parsed['format'] != 'buzzer-version') return;

      _latestBuild = (parsed['build'] as num?)?.toInt() ?? 0;
      latestVersion = (parsed['version'] as String?)?.trim() ?? '';
      notesUrl = (parsed['notes'] as String?)?.trim();
      downloadUrl = (parsed['telechargement'] as String?)?.trim();
      notifyListeners();
    } on SocketException {
      // Hors ligne : silence.
    } catch (_) {
      // Fichier absent ou illisible : silence.
    }
  }

  Future<void> dismiss() async {
    _dismissedBuild = _latestBuild;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedKey, _latestBuild);
  }
}
