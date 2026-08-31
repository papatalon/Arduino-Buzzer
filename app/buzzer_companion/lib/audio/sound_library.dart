import 'package:flutter/services.dart';

// Dossiers de la bibliotheque, dans le meme ordre que les constantes
// *_FOLDER de Mp3.h cote firmware (1-based la-bas). Les noms viennent de
// la bibliotheque du client, conservee telle quelle.
enum SoundFolder {
  intro('01_Intro'),
  buzzer('02_Buzzer'),
  good('03_Good'),
  bad('04_Bad'),
  waiting('05_Waiting'),
  divers('06_Divers');

  const SoundFolder(this.dirName);
  final String dirName;
}

// Index de la bibliotheque de sons embarquee dans l'app.
//
// Le compte de fichiers est lu a l'execution depuis le manifeste d'assets,
// jamais code en dur : c'est la demande explicite du client — ajouter un
// son doit suffire, sans reflasher le Mega ni mettre a jour sa carte SD.
// Les constantes *_FILE_COUNT du firmware deviennent donc caduques des que
// l'app pilote le son.
//
// L'ordre est alphabetique, ce qui correspond au prefixe numerique des
// fichiers ("001_...", "002-...") : l'index N designe donc le Nieme
// fichier, meme convention que la numerotation du DFPlayer.
class SoundLibrary {
  final Map<SoundFolder, List<String>> _byFolder = {};

  bool get isLoaded => _byFolder.isNotEmpty;

  Future<void> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final all = manifest.listAssets();
    for (final folder in SoundFolder.values) {
      final prefix = 'assets/sounds/${folder.dirName}/';
      final files = all.where((a) => a.startsWith(prefix)).toList()..sort();
      _byFolder[folder] = files;
    }
  }

  int count(SoundFolder folder) => _byFolder[folder]?.length ?? 0;

  // Chemin de l'asset pour un index 0-based, ou null si hors bornes.
  String? assetPath(SoundFolder folder, int index) {
    final files = _byFolder[folder];
    if (files == null || index < 0 || index >= files.length) return null;
    return files[index];
  }

  // Nom lisible d'un son, pour l'ecran des buzzers : on retire le chemin,
  // l'extension et le prefixe numerique ("003-castle-clear.mp3" ->
  // "castle-clear"), qui n'apporte rien a l'operateur.
  String displayName(SoundFolder folder, int index) {
    final path = assetPath(folder, index);
    if (path == null) return '';
    var name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name.replaceFirst(RegExp(r'^\d+[_-]?'), '').trim();
  }
}
