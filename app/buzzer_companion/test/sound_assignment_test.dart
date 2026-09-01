import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/audio/sound_engine.dart';
import 'package:buzzer_companion/audio/sound_library.dart';

// Les sons des buzzers sont tires au sort a chaque demarrage et ne sont plus
// conserves. Deux proprietes comptent, et aucune des deux ne se voit avant
// une soiree ratee :
//
//   les quatre buzzers ont des sons DIFFERENTS, sans quoi « Ne buzze pas »
//   est injouable, son mecanisme entier reposant sur le fait que chaque
//   joueur reconnaisse le sien ;
//
//   « Changer » n'attribue jamais a un buzzer le son d'un autre tant qu'il
//   reste des sons libres.
//
// Bibliotheque simulee : le vrai chargement lit le manifeste d'assets, dont
// ces regles ne dependent pas.
class _BibliothequeSimulee extends SoundLibrary {
  _BibliothequeSimulee(this.combien);
  final int combien;

  @override
  int count(SoundFolder folder) => folder == SoundFolder.buzzer ? combien : 0;
}

SoundEngine _moteur(int combien) =>
    SoundEngine(library: _BibliothequeSimulee(combien), onBusyChanged: (_) {});

void main() {
  // SoLoud.instance se construit a l'initialisation d'un champ de
  // SoundEngine et exige un binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le tirage donne quatre sons differents', () {
    final moteur = _moteur(30);
    // Repete : un tirage qui ne produirait des doublons qu'une fois sur dix
    // passerait un essai unique et casserait une soiree sur dix.
    for (var essai = 0; essai < 200; essai++) {
      moteur.shuffleAssignments();
      expect(moteur.assignment.length, 4);
      expect(moteur.assignment.toSet().length, 4,
          reason: 'deux buzzers ont recu le meme son');
    }
  });

  test('deux demarrages ne donnent pas la meme distribution', () {
    // Sur 30 sons, deux tirages identiques sont possibles mais tres
    // improbables ; vingt tirages tous identiques signifieraient que le
    // tirage ne tire rien.
    final moteur = _moteur(30);
    final vus = <String>{};
    for (var i = 0; i < 20; i++) {
      moteur.shuffleAssignments();
      vus.add(moteur.assignment.join(','));
    }
    expect(vus.length, greaterThan(1),
        reason: 'la distribution ne change jamais');
  });

  test('« Changer » evite les sons deja pris', () {
    final moteur = _moteur(6);
    moteur.shuffleAssignments();
    for (var tour = 0; tour < 30; tour++) {
      moteur.cycleAssignment(tour % 4);
      expect(moteur.assignment.toSet().length, 4,
          reason: 'un buzzer a pris le son d\'un autre');
    }
  });

  test('une bibliotheque plus petite que quatre ne fait pas planter', () {
    final moteur = _moteur(2);
    moteur.shuffleAssignments();
    expect(moteur.assignment.length, 4);
    // Des doublons sont inevitables ici, mais les indices doivent rester
    // dans la bibliotheque.
    for (final i in moteur.assignment) {
      expect(i, inInclusiveRange(0, 1));
    }
    moteur.cycleAssignment(0);
    expect(moteur.assignment[0], inInclusiveRange(0, 1));
  });

  test('une bibliotheque vide laisse les assignations intactes', () {
    final moteur = _moteur(0);
    final avant = List<int>.from(moteur.assignment);
    moteur.shuffleAssignments();
    moteur.cycleAssignment(0);
    moteur.setAssignment(0, 5);
    expect(moteur.assignment, avant);
  });
}
