import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/audio/sonorisation.dart';
import 'package:buzzer_companion/audio/sound_engine.dart';
import 'package:buzzer_companion/audio/sound_library.dart';
import 'package:buzzer_companion/ble_link_service.dart';

// L'OUVERTURE D'UNE PARTIE DOIT COUPER LA MUSIQUE D'AMBIANCE, quelle que
// soit la sortie audio.
//
// C'est tout l'intérêt de mettre le crochet ici plutôt que dans les moteurs
// de jeu : Sonorisation est la seule à voir passer l'ouverture dans les deux
// cas, haut-parleurs du PC comme haut-parleur du buzzer. Le brancher sur une
// seule des deux branches laisserait la musique jouer par-dessus la première
// question la moitié du temps, et ce serait invisible en développement, où
// la sortie ne change jamais.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Sonorisation sons;
  late BleLinkService ble;
  var ouvertures = 0;

  setUp(() {
    ouvertures = 0;
    ble = BleLinkService();
    sons = Sonorisation(
      locale: SoundEngine(library: SoundLibrary(), onBusyChanged: (_) {}),
      ble: ble,
    );
    sons.surOuverture = () => ouvertures++;
  });

  test('le son sortant du PC, l\'ouverture est annoncée', () {
    ble.appHandlesSound = true;
    sons.intro();
    expect(ouvertures, 1);
  });

  test('le son sortant du buzzer, elle l\'est aussi', () {
    ble.appHandlesSound = false;
    sons.intro();
    expect(ouvertures, 1);
  });

  test('les autres sons ne coupent rien', () {
    // Une bonne réponse, une mauvaise, l'attente : la musique d'ambiance
    // est déjà coupée depuis l'ouverture, et la recouper à chaque son
    // enverrait une commande à Spotify toutes les dix secondes.
    ble.appHandlesSound = false;
    sons.bonneReponse();
    sons.mauvaiseReponse();
    sons.attente();
    expect(ouvertures, 0);
  });

  test('sans crochet branché, rien ne casse', () {
    // L'écran public construit sa propre Sonorisation dans certains tests,
    // sans musique d'ambiance derrière.
    ble.appHandlesSound = false;
    sons.surOuverture = null;
    sons.intro();
  });
}
