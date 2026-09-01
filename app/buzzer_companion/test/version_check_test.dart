import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/version_check.dart';

// La règle d'annonce d'une mise à jour. Elle se trompe en silence : un
// bandeau qui ne s'affiche jamais ne se remarque pas, et un bandeau qui
// s'affiche toujours finit par être ignoré.

void main() {
  test('rien à annoncer quand on est à jour', () {
    expect(doitAnnoncer(local: 3, publie: 3, ferme: -1), isFalse);
  });

  test("rien à annoncer quand on est en avance sur ce qui est publié", () {
    // Arrive sur le poste de développement, qui construit avant de publier.
    expect(doitAnnoncer(local: 4, publie: 3, ferme: -1), isFalse);
  });

  test('une version plus récente est annoncée', () {
    expect(doitAnnoncer(local: 3, publie: 4, ferme: -1), isTrue);
  });

  test('la fermeture fait taire CETTE version', () {
    expect(doitAnnoncer(local: 3, publie: 4, ferme: 4), isFalse);
  });

  test('mais pas la suivante', () {
    // Le piège que la règle existe pour éviter : un simple booléen « déjà
    // fermé » ferait taire toutes les versions à venir, et l'opérateur ne
    // reverrait plus jamais d'avis de mise à jour.
    expect(doitAnnoncer(local: 3, publie: 5, ferme: 4), isTrue);
  });

  test('une fermeture plus ancienne ne masque rien', () {
    expect(doitAnnoncer(local: 3, publie: 4, ferme: 2), isTrue);
  });

  test('sans version publiée connue, on se tait', () {
    // Site injoignable ou fichier illisible : les champs restent à zéro.
    expect(doitAnnoncer(local: 3, publie: null, ferme: -1), isFalse);
  });

  test('sans version locale connue, on se tait aussi', () {
    // Si la lecture de la version embarquée échoue, tout est à zéro : rien
    // ne doit s'annoncer, sinon l'avis serait tiré au hasard.
    expect(doitAnnoncer(local: null, publie: null, ferme: -1), isFalse);
    // Et surtout pas quand le site, lui, a répondu : c'est le cas où la
    // règle annoncerait une mise à jour sans savoir depuis quoi.
    expect(doitAnnoncer(local: null, publie: 5, ferme: -1), isFalse);
  });
}
