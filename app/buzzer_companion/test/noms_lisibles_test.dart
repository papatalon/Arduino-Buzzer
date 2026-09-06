import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/audio/sound_library.dart';

// LES NOMS DE SONS SE LISENT DEVANT UNE SALLE.
//
// L'ecran public en montre une grille entiere pendant qu'une equipe choisit
// le sien : « i-am-groot-1-101soundboards » y a l'air d'un bogue. Les
// fichiers, eux, ne se renomment pas (leur rang donne le numero DFPlayer de
// la carte SD), donc tout se joue dans nomLisible.
//
// Les cas ci-dessous sont de VRAIS noms de la bibliotheque, copies tels
// quels : une regle de nettoyage ne vaut que contre les fichiers qu'elle
// aura vraiment a nettoyer.
void main() {
  test('le rang du dossier disparait', () {
    expect(nomLisible('003_castle-clear.mp3', 2), 'Castle clear');
    expect(nomLisible('002-benny-hill-101soundboards.mp3', 1), 'Benny hill');
  });

  test('la provenance du fournisseur disparait', () {
    expect(nomLisible('006_air-horn-101soundboards.mp3', 5), 'Air horn');
    expect(nomLisible('027_tada-101soundboards.mp3', 26), 'Tada');
  });

  test('les tirets deviennent des espaces', () {
    expect(
      nomLisible('011_fart-sound-effect-bomb-fart-sound-101soundboards.mp3', 10),
      'Fart sound effect bomb fart sound',
    );
    expect(nomLisible('024_ring-a-ding-ding-101soundboards.mp3', 23),
        'Ring a ding ding');
  });

  test('le numero de prise du fournisseur disparait', () {
    expect(nomLisible('012_goat-1-101soundboards.mp3', 11), 'Goat');
    expect(nomLisible('014_horse-8-101soundboards.mp3', 13), 'Horse');
    expect(nomLisible('015_i-am-groot-1-101soundboards.mp3', 14), 'I am groot');
    expect(nomLisible('004_acid-logo-3-101soundboards.mp3', 3), 'Acid logo');
  });

  // Un nombre a la fin n'est pas toujours un numero de prise. Une annee ou un
  // identifiant fait partie du nom, et le manger rendrait deux sons
  // impossibles a distinguer.
  test('une annee ou un identifiant reste entier', () {
    expect(nomLisible('014_jeopardy-1998.mp3', 13), 'Jeopardy 1998');
    expect(nomLisible('002_buzzer-4-183895.mp3', 1), 'Buzzer 4 183895');
  });

  test('un nom deja propre est laisse tranquille', () {
    expect(nomLisible('001_Catchphrase Buzzer.mp3', 0), 'Catchphrase Buzzer');
    expect(nomLisible('001_Quiz Round Intro.mp3', 0), 'Quiz Round Intro');
  });

  // Un fichier qui ne porte QUE la provenance ne laisse rien apres nettoyage,
  // et le numero du son est alors tout ce qu'on peut honnetement en dire.
  //
  // Deux sons de buzzer etaient dans ce cas ; le client les a ecoutes et ils
  // portent maintenant leur nom (voir plus bas). La regle reste : la
  // bibliotheque se remplit de fichiers telecharges, et le prochain arrivera
  // avec le meme nom vide.
  test('un nom qui ne laisse rien retombe sur son numero', () {
    expect(nomLisible('002-101soundboards.mp3', 1), 'Son 2');
    expect(nomLisible('017-101soundboards.mp3', 16), 'Son 17');
  });

  // Nommes a l'oreille par le client, faute de nom exploitable dans le
  // fichier. Les capitales de R2D2 sont dans le nom du fichier : le
  // nettoyage ne met une majuscule qu'au premier caractere, il ne peut pas
  // deviner un nom propre.
  test('les sons nommes a la main se lisent tels quels', () {
    expect(nomLisible('002_R2D2.mp3', 1), 'R2D2');
    expect(nomLisible('003_miaou.mp3', 2), 'Miaou');
    expect(nomLisible('035_C3PO.mp3', 34), 'C3PO');
  });

  test('un chiffre en tete du nom survit', () {
    expect(nomLisible('018_1-wheel-of-fortune.mp3', 17), '1 wheel of fortune');
    expect(nomLisible('007_30s-countdown.mp3', 6), '30s countdown');
  });
}
