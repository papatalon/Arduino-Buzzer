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

  // Nom lisible d'un son. Voir [nomLisible] pour le detail du nettoyage.
  String displayName(SoundFolder folder, int index) {
    final path = assetPath(folder, index);
    if (path == null) return '';
    return nomLisible(path.split('/').last, index);
  }
}

// LE NOM D'UN FICHIER DE SON, TEL QU'ON LE MONTRE.
//
// Les fichiers de la bibliotheque du client sont des noms techniques : un
// rang a trois chiffres, des mots colles par des tirets, et pour les trois
// quarts d'entre eux la provenance du fournisseur en suffixe. Rien de tout ca
// ne se lit devant une salle, et l'ecran public en montre maintenant une
// grille entiere.
//
// LES FICHIERS EUX-MEMES NE SE RENOMMENT PAS : leur rang alphabetique donne
// le numero DFPlayer de la carte SD, et renommer un fichier forcerait a
// renumeroter le dossier entier sur les trois copies de la banque. Le
// nettoyage vit donc ici, a l'affichage, et nulle part ailleurs.
//
// Fonction libre plutot que methode : elle ne depend que de la chaine, ce qui
// la rend verifiable sans monter une bibliotheque d'assets.
String nomLisible(String fichier, int index) {
  var nom = fichier;
  final point = nom.lastIndexOf('.');
  if (point > 0) nom = nom.substring(0, point);

  // Le rang dans le dossier : « 003-castle-clear » -> « castle-clear ».
  nom = nom.replaceFirst(RegExp(r'^\d+[_-]?'), '');

  // La provenance, collee a 28 des 35 sons de buzzer. Deux fichiers ne
  // s'appellent QUE comme ca : ils tombent alors sur le repli plus bas.
  nom = nom.replaceFirst(
    RegExp(r'[-_ ]?101soundboards$', caseSensitive: false),
    '',
  );

  nom = nom.replaceAll(RegExp(r'[-_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  // Le numero de prise laisse par le fournisseur (« goat 1 », « horse 8 ») :
  // il ne distingue rien dans la bibliotheque et se lit comme du code. Deux
  // chiffres au plus, pour ne manger ni une annee ni un identifiant :
  // « jeopardy 1998 » et « buzzer 4 183895 » restent entiers.
  nom = nom.replaceFirst(RegExp(r' \d{1,2}$'), '');

  // Il ne reste rien de lisible : le numero du son est alors tout ce qu'on
  // peut honnetement en dire.
  if (nom.isEmpty) return 'Son ${index + 1}';

  // Une seule majuscule, celle du debut. Mettre une capitale a chaque mot
  // ferait un titre anglais la ou la plupart des noms sont des phrases
  // (« I am groot », « Lets go doc »).
  return nom[0].toUpperCase() + nom.substring(1);
}
