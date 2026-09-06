import 'package:buzzer_companion/popout/phrases_attente.dart';
import 'package:flutter_test/flutter_test.dart';

// La liste d'attente est du contenu, pas du code : elle grossit par lots,
// souvent tard, souvent à plusieurs. Ces tests ne jugent pas l'humour, ils
// tiennent les trois choses qui se dégradent en silence quand on ajoute
// vingt phrases d'un coup.
void main() {
  test('aucune phrase répétée', () {
    final vues = <String, int>{};
    final doublons = <String>[];
    for (final phrase in phrasesAttente) {
      if (vues.containsKey(phrase)) doublons.add(phrase);
      vues[phrase] = (vues[phrase] ?? 0) + 1;
    }
    expect(doublons, isEmpty, reason: 'la salle verrait deux fois la même');
  });

  // Le vrai risque n'est pas la phrase copiée deux fois : c'est la variante
  // de la voisine, écrite six mois plus tard sans se souvenir de l'autre.
  // Deux phrases qui partagent la moitié de leurs mots pleins se lisent
  // comme un bégaiement quand la rotation les met à neuf secondes d'écart.
  // Le seuil laisse passer les mots du domaine, qui reviennent forcément :
  // bouton, réponse, pointage, salle.
  test('aucune phrase quasi identique à une autre', () {
    Set<String> motsPleins(String p) => RegExp(r"[a-zàâäéèêëîïôöùûüçœ']+")
        .allMatches(p.toLowerCase())
        .map((m) => m.group(0)!)
        .where((m) => m.length > 3)
        .toSet();

    final trop = <String>[];
    for (var i = 0; i < phrasesAttente.length; i++) {
      for (var j = i + 1; j < phrasesAttente.length; j++) {
        final a = motsPleins(phrasesAttente[i]);
        final b = motsPleins(phrasesAttente[j]);
        if (a.isEmpty || b.isEmpty) continue;
        final proximite = a.intersection(b).length / a.union(b).length;
        if (proximite >= 0.45) {
          trop.add('${phrasesAttente[i]} / ${phrasesAttente[j]}');
        }
      }
    }
    expect(trop, isEmpty);
  });

  // La boîte fait 1080 de large sur 150 de haut, à 62 pixels de corps : au
  // delà d'une soixantaine de caractères, la troisième ligne est coupée net
  // et la salle lit une phrase sans fin. C'est la limite qui a été tenue
  // pour les premières, et elle vaut pour les suivantes.
  test('assez courtes pour tenir en deux lignes', () {
    final tropLongues = phrasesAttente.where((p) => p.length > 66).toList();
    expect(tropLongues, isEmpty);
  });

  // Les buzzers sont de gros boutons qu'on abat avec la main. Parler de
  // pouce ou de manette sonne faux devant l'objet posé sur la table, et
  // c'est l'erreur qui revient le plus souvent quand on écrit vite.
  test('rien qui contredise l\'objet sur la table', () {
    for (final phrase in phrasesAttente) {
      final minuscules = phrase.toLowerCase();
      expect(minuscules, isNot(contains('pouce')), reason: phrase);
      expect(minuscules, isNot(contains('manette')), reason: phrase);
      expect(minuscules, isNot(contains('gâchette')), reason: phrase);
    }
  });

  // Aucun chiffre : annoncer quoi que ce soit de chiffré avant le début de
  // la partie serait faux, et c'est exactement ce que l'écran d'attente a
  // été refait pour ne plus faire.
  test('aucun chiffre', () {
    for (final phrase in phrasesAttente) {
      expect(phrase, isNot(matches(RegExp(r'\d'))), reason: phrase);
    }
  });

  // Le tiret cadratin ne s'écrit nulle part dans l'application, ponctuation
  // comprise.
  test('pas de tiret cadratin', () {
    for (final phrase in phrasesAttente) {
      expect(phrase, isNot(contains('—')), reason: phrase);
    }
  });

  test('assez de phrases pour une soirée complète', () {
    expect(phrasesAttente.length, greaterThanOrEqualTo(100));
  });
}
