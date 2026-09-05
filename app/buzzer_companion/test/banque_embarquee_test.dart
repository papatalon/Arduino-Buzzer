import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzer_companion/questionnaires/catalogue.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';

// LA COPIE DES QUESTIONS LIVRÉE AVEC L'APPLICATION.
//
// Ce qui se joue ici ne se voit qu'une fois : une installation neuve, dans un
// sous-sol sans wifi, un soir de party. Le cache disque ne se remplit qu'après
// une première lecture en ligne réussie ; sans cette copie, l'écran serait
// vide et le tirage n'aurait rien où piocher. Personne ne s'en apercevrait
// avant la soirée.
//
// Ces tests portent sur le CONTRAT entre le générateur et l'application : le
// fichier existe, il porte les deux moitiés, et l'application sait les lire
// sans les ré-encoder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, dynamic>> lireBanque() async {
    final brut = await rootBundle.loadString('assets/questions/banque.json');
    return jsonDecode(brut) as Map<String, dynamic>;
  }

  test("l'asset existe et annonce son format", () async {
    final banque = await lireBanque();
    expect(banque['format'], 'buzzer-banque');
  });

  test('le catalogue embarqué se lit sans passer par une chaîne', () async {
    final banque = await lireBanque();
    final cat = Catalogue.fromMap(banque['catalogue'] as Map<String, dynamic>);
    expect(cat.entries, isNotEmpty);
    expect(cat.collections, isNotEmpty);
  });

  test('chaque questionnaire annoncé au catalogue est réellement embarqué',
      () async {
    final banque = await lireBanque();
    final cat = Catalogue.fromMap(banque['catalogue'] as Map<String, dynamic>);
    final embarques = (banque['questionnaires'] as Map).keys.toSet();
    // Le piège : un catalogue qui annonce 283 fichiers alors que l'asset n'en
    // porte que 280. Le manque ne se verrait qu'au tirage, sur les trois
    // questionnaires absents, et seulement hors ligne.
    final manquants =
        cat.entries.map((e) => e.id).where((id) => !embarques.contains(id));
    expect(manquants, isEmpty, reason: 'annoncés au catalogue mais absents');
  });

  test('un questionnaire embarqué se décode et porte ses questions', () async {
    final banque = await lireBanque();
    final tous = banque['questionnaires'] as Map;
    final premier = tous.values.first as Map<String, dynamic>;
    final q = Questionnaire.fromMap(premier);
    expect(q.questions, isNotEmpty);
    expect(q.questions.first.question, isNotEmpty);
  });

  test('les deux axes de classement survivent au voyage', () async {
    final banque = await lireBanque();
    final tous = banque['questionnaires'] as Map;
    // Le niveau et les tranches sont ce qui rend le tirage utile. S'ils se
    // perdaient dans l'asset, les filtres ne trouveraient rien hors ligne
    // sans qu'aucune erreur ne le dise.
    var avecNiveau = 0;
    var avecTranches = 0;
    for (final brut in tous.values) {
      for (final q in Questionnaire.fromMap(brut as Map<String, dynamic>).questions) {
        if (q.niveau != null) avecNiveau++;
        if (q.ages.isNotEmpty) avecTranches++;
      }
    }
    expect(avecNiveau, greaterThan(1000));
    expect(avecTranches, greaterThan(1000));
  });
}
