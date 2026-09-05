import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/questionnaires/banque.dart';

// LA BANQUE LIVRÉE AVEC L'APPLICATION.
//
// Ce qui se joue ici ne se voit qu'une fois : une installation neuve, dans un
// sous-sol sans wifi, un soir de party. Le cache disque ne se remplit qu'après
// une première lecture en ligne réussie ; sans cette copie, l'écran serait
// vide et le tirage n'aurait rien où piocher. Personne ne s'en apercevrait
// avant la soirée.
//
// Ces tests portent sur le CONTRAT entre le générateur et l'application.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Banque> lire() async =>
      Banque.decode(await rootBundle.loadString(kAssetBanque));

  test("l'asset existe et se décode", () async {
    final b = await lire();
    expect(b.questions, isNotEmpty);
  });

  test('les facettes sont là pour dessiner les pastilles', () async {
    final b = await lire();
    expect(b.categories, isNotEmpty);
    expect(b.themes, isNotEmpty);
    for (final f in [...b.categories, ...b.themes]) {
      expect(f.nom, isNotEmpty);
      expect(f.questions, greaterThan(0));
    }
  });

  test('chaque catégorie annoncée porte réellement ses questions', () async {
    final b = await lire();
    // Le piège : une facette qui annonce 300 questions alors que la banque
    // n'en porte que 280 sous ce nom. Le manque ne se verrait qu'au tirage.
    for (final f in b.categories) {
      final reelles = b.questions.where((q) => q.category == f.nom).length;
      expect(reelles, f.questions, reason: 'catégorie « ${f.nom} »');
    }
  });

  test('chaque thématique annoncée porte réellement ses questions', () async {
    final b = await lire();
    for (final f in b.themes) {
      final reelles = b.questions.where((q) => q.themes.contains(f.nom)).length;
      expect(reelles, f.questions, reason: 'thématique « ${f.nom} »');
    }
  });

  test('les deux axes de classement survivent au voyage', () async {
    final b = await lire();
    // Le niveau et les tranches sont ce qui rend le tirage utile. S'ils se
    // perdaient dans l'asset, les filtres ne trouveraient rien hors ligne
    // sans qu'aucune erreur ne le dise.
    expect(b.questions.where((q) => q.niveau != null).length, greaterThan(3000));
    expect(b.questions.where((q) => q.ages.isNotEmpty).length, greaterThan(500));
  });

  test("une question sans « ages » vise tout le monde, pas personne", () async {
    final b = await lire();
    // Le générateur OMET le champ quand la question vise les quatre tranches.
    // L'ensemble vide doit donc vouloir dire « tout le monde » : le lire
    // comme « aucune tranche » écarterait la moitié de la banque au premier
    // filtre d'âge.
    final sansAges = b.questions.where((q) => q.ages.isEmpty);
    expect(sansAges, isNotEmpty);
  });

  test('aucune question sans énoncé', () async {
    final b = await lire();
    expect(b.questions.where((q) => !q.isUsable), isEmpty);
  });
}
