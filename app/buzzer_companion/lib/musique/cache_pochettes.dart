import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// LES POCHETTES DESCENDENT SUR LE DISQUE, ET C'EST L'ADRESSE DU FICHIER QUI
// VOYAGE VERS L'ÉCRAN PUBLIC.
//
// La fenêtre du pop-out tourne sur un moteur Flutter séparé qui n'a jamais
// fait de réseau, et qui ne doit pas commencer : une salle sans Wi-Fi fiable
// y afficherait une case vide en plein milieu de l'écran d'attente. Même
// raisonnement que le logo de la soirée (voir EventLogo) : les deux fenêtres
// tournent sur la même machine, donc un chemin suffit à les mettre d'accord,
// sans copier d'octets dans chaque instantané.
//
// Une pochette pèse une vingtaine de kilo-octets et une soirée en voit une
// cinquantaine. Le ménage garde les dernières et rien de plus.
class CachePochettes {
  CachePochettes({http.Client? client, Directory? dossier})
      : _client = client ?? http.Client(),
        // Les tests passent un dossier temporaire ; en vrai il est découvert
        // au premier usage, via path_provider.
        // ignore: prefer_initializing_formals
        _dossier = dossier;

  final http.Client _client;
  Directory? _dossier;

  Future<Directory> _dir() async {
    final connu = _dossier;
    if (connu != null) {
      if (!connu.existsSync()) connu.createSync(recursive: true);
      return connu;
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}pochettes');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dossier = dir;
    return dir;
  }

  /// Le chemin local de la pochette, ou null si elle n'a pas pu descendre.
  ///
  /// Null n'est pas une panne : le bandeau montre alors le titre et
  /// l'artiste seuls, ce qui reste juste. Rejouer une piste déjà vue ne
  /// retélécharge rien, et une soirée hors ligne garde ce qu'elle a.
  Future<String?> chemin({required String idPiste, required String url}) async {
    try {
      final dir = await _dir();
      final fichier =
          File('${dir.path}${Platform.pathSeparator}$idPiste.jpg');
      if (fichier.existsSync() && fichier.lengthSync() > 0) {
        return fichier.path;
      }

      final r = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;

      // ÉCRITURE EN DEUX TEMPS. Le pop-out relit le chemin dès qu'il arrive
      // dans l'instantané : un fichier à moitié écrit lui donnerait une
      // image tronquée, et c'est le genre de chose qu'on ne reproduit
      // jamais en développement, seulement en salle.
      final part = File('${fichier.path}.part');
      await part.writeAsBytes(r.bodyBytes, flush: true);
      await part.rename(fichier.path);
      return fichier.path;
    } catch (_) {
      // Hors ligne, disque plein, adresse morte : le texte suffit.
      return null;
    }
  }

  /// Garde les [garder] pochettes les plus récentes, jette le reste.
  ///
  /// Appelé au démarrage plutôt qu'à chaque piste : c'est du ménage, pas une
  /// urgence, et le faire en pleine soirée ne servirait à rien.
  Future<void> menage({int garder = 40}) async {
    try {
      final dir = await _dir();
      final fichiers = dir.listSync().whereType<File>().toList();
      // Les fragments d'un téléchargement interrompu ne servent plus à rien
      // et ne seront jamais relus : ils portent le nom d'une pochette qui
      // n'a pas fini de descendre.
      for (final f in fichiers.where((f) => f.path.endsWith('.part'))) {
        f.deleteSync();
      }
      final images = fichiers.where((f) => f.path.endsWith('.jpg')).toList()
        ..sort((a, b) =>
            b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final f in images.skip(garder)) {
        f.deleteSync();
      }
    } catch (_) {
      // Le ménage rate en silence : ce n'est pas une raison de retarder une
      // soirée.
    }
  }
}
