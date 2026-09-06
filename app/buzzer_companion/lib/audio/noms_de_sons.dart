import '../protocol.dart';
import 'sound_engine.dart';
import 'sound_library.dart';

// LE NOM D'UN SON DE BUZZER, TEL QU'ON L'AFFICHE.
//
// Deux écrans le montrent maintenant en même temps : la console de
// l'animateur et l'écran public. Ils doivent dire exactement la même chose,
// sinon l'animateur annonce un son et la salle en lit un autre. C'est
// pourquoi la règle vit ici plutôt que dans un écran.
//
// Deux sources possibles selon qui joue, jamais mélangées : la bibliothèque
// de l'application, ou la carte SD du buzzer telle qu'annoncée par le Mega
// (CFG_SOUND), dont on ne connaît que les numéros.

/// Le son actuellement assigné au [buzzer].
String nomDuSonAssigne({
  required SoundEngine sound,
  required GameState game,
  required bool sonApplication,
  required int buzzer,
}) {
  if (sonApplication) {
    return sound.library.displayName(SoundFolder.buzzer, sound.assignment[buzzer]);
  }
  final duMega = game.buzzerSound[buzzer];
  return duMega == null ? 'Aucun son assigné' : 'Son ${duMega + 1} de la carte SD';
}

/// Le nom qui défile pendant le mélange, pour un [tirage] brut pris dans
/// `AnimationTirage.defilement`.
///
/// L'animation ne sait pas combien de sons existent, ni d'où ils viennent :
/// elle tire un grand nombre quelconque, et c'est ici qu'on le ramène à la
/// taille de la liste. L'effet machine à sous tient à ce que ça défile au
/// rythme du chenillard ; le vrai nom n'apparaît qu'à l'arrêt.
String nomDuSonQuiDefile({
  required SoundEngine sound,
  required bool sonApplication,
  required int tirage,
}) {
  if (sonApplication) {
    final total = sound.library.count(SoundFolder.buzzer);
    return total == 0 ? '...' : sound.library.displayName(SoundFolder.buzzer, tirage % total);
  }
  // Côté carte SD on ne connaît que des numéros : on en fait défiler un dans
  // la même plage que ceux qu'on affiche d'habitude.
  return 'Son ${tirage % 30 + 1} de la carte SD';
}
