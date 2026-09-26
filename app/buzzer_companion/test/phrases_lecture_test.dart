import 'dart:math';

import 'package:buzzer_companion/jeu/phrases_lecture.dart';
import 'package:flutter_test/flutter_test.dart';

// Les phrases de lecture sont du contenu, comme celles de l'écran d'attente,
// et elles se dégradent de la même façon quand on en ajoute vingt d'un coup.
// Deux règles leur sont propres, parce qu'elles s'affichent à l'endroit exact
// où la question va apparaître.
void main() {
  test('aucune phrase répétée', () {
    final doublons = <String>[];
    final vues = <String>{};
    for (final phrase in phrasesLecture) {
      if (!vues.add(phrase)) doublons.add(phrase);
    }
    expect(doublons, isEmpty, reason: 'la salle verrait deux fois la même');
  });

  // Même mesure que pour l'écran d'attente : deux phrases qui partagent la
  // moitié de leurs mots pleins se lisent comme la même, dite deux fois.
  test('aucune phrase quasi identique à une autre', () {
    Set<String> motsPleins(String p) => RegExp(r"[a-zàâäéèêëîïôöùûüçœ']+")
        .allMatches(p.toLowerCase())
        .map((m) => m.group(0)!)
        .where((m) => m.length > 3)
        .toSet();

    final trop = <String>[];
    for (var i = 0; i < phrasesLecture.length; i++) {
      for (var j = i + 1; j < phrasesLecture.length; j++) {
        final a = motsPleins(phrasesLecture[i]);
        final b = motsPleins(phrasesLecture[j]);
        if (a.isEmpty || b.isEmpty) continue;
        if (a.intersection(b).length / a.union(b).length >= 0.45) {
          trop.add('${phrasesLecture[i]} / ${phrasesLecture[j]}');
        }
      }
    }
    expect(trop, isEmpty);
  });

  test('assez courtes pour tenir en deux lignes', () {
    expect(phrasesLecture.where((p) => p.length > 66).toList(), isEmpty);
  });

  // PROPRE À LA LECTURE. La phrase occupe la place de la question : si elle
  // finit par un « ? », la salle la prend pour la question et quelqu'un
  // buzze dessus.
  test('aucune ne ressemble à une question', () {
    expect(phrasesLecture.where((p) => p.contains('?')).toList(), isEmpty);
  });

  // PROPRE À LA LECTURE. Les buzzers sont armés ou verrouillés selon le
  // réglage : une phrase qui parle du bouton dirait quelque chose de faux
  // une fois sur deux. Plus simple et plus sûr de ne jamais en parler.
  test('neutres sur ce que les buzzers permettent', () {
    const interdits = ['bouton', 'buzz', 'appuy', 'touch', 'verrou', 'bloqu'];
    final fautives = [
      for (final p in phrasesLecture)
        if (interdits.any(p.toLowerCase().contains)) p,
    ];
    expect(fautives, isEmpty);
  });

  test('rien qui contredise l\'objet sur la table', () {
    for (final phrase in phrasesLecture) {
      final m = phrase.toLowerCase();
      expect(m, isNot(contains('pouce')), reason: phrase);
      expect(m, isNot(contains('manette')), reason: phrase);
    }
  });

  test('aucun chiffre', () {
    for (final phrase in phrasesLecture) {
      expect(phrase, isNot(matches(RegExp(r'\d'))), reason: phrase);
    }
  });

  test('pas de tiret cadratin', () {
    for (final phrase in phrasesLecture) {
      expect(phrase, isNot(contains('—')), reason: phrase);
    }
  });

  // Une partie pose une vingtaine de questions, une soirée trois ou quatre
  // parties. En deçà, le sac se vide avant la fin de la première partie.
  test('assez de phrases pour plus d\'une partie sans redite', () {
    expect(phrasesLecture.length, greaterThanOrEqualTo(40));
  });

  group('le tirage', () {
    test('toutes les phrases passent avant qu\'une seule revienne', () {
      final tirage = TirageLecture(hasard: Random(7));
      final premierTour = [
        for (var i = 0; i < phrasesLecture.length; i++) tirage.suivante(),
      ];
      expect(premierTour.toSet(), phrasesLecture.toSet());
    });

    // Au changement de sac, la dernière de l'ancien pourrait sortir en tête
    // du nouveau : la même phrase deux questions de suite.
    test('jamais deux fois la même d\'affilée, même en changeant de sac', () {
      for (var graine = 0; graine < 200; graine++) {
        final tirage = TirageLecture(hasard: Random(graine));
        String? avant;
        for (var i = 0; i < phrasesLecture.length * 3; i++) {
          final p = tirage.suivante();
          expect(p, isNot(avant), reason: 'graine $graine, tirage $i');
          avant = p;
        }
      }
    });
  });
}
