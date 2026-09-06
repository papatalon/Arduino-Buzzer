import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzzer_companion/questionnaires/criteres_tirage.dart';
import 'package:buzzer_companion/questionnaires/questionnaire.dart';

// CE QU'ON A DEMANDÉ AU DERNIER TIRAGE.
//
// Ce qui se joue ici se voit à un seul moment : la deuxième manche de la
// soirée, quand la salle attend et que l'animateur veut relancer la même
// chose. Recocher quatre cases devant tout le monde était la corvée à
// supprimer ; se retrouver avec une thématique fantôme qui ne laisse plus
// passer aucune question en serait une pire, parce que rien à l'écran ne
// dirait d'où vient le blocage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les critères se relisent tels qu\'on les a laissés', () async {
    SharedPreferences.setMockInitialValues({});
    final c = CriteresTirage();
    c.basculerTheme('Musique');
    c.basculerTheme('Québec');
    c.basculerTranche(Tranche.enfants);
    c.basculerNiveau(1);
    c.reglerNombre(12);
    // Les écritures partent en arrière-plan : on laisse la boucle tourner.
    await Future<void>.delayed(Duration.zero);

    final relu = CriteresTirage();
    await relu.load();
    expect(relu.themes, {'Musique', 'Québec'});
    expect(relu.tranches, {Tranche.enfants});
    expect(relu.niveaux, {1});
    expect(relu.nombre, 12);
  });

  test('sans rien de sauvegardé, tout est ouvert et la manche fait 20', () async {
    SharedPreferences.setMockInitialValues({});
    final c = CriteresTirage();
    await c.load();
    expect(c.themes, isEmpty);
    expect(c.tranches, isEmpty);
    expect(c.niveaux, isEmpty);
    expect(c.nombre, CriteresTirage.nombreParDefaut);
  });

  test('une thématique disparue de la banque se décoche toute seule', () async {
    SharedPreferences.setMockInitialValues({});
    final c = CriteresTirage();
    c.basculerTheme('Musique');
    c.basculerTheme('Sports d\'hiver'); // fusionnée depuis, elle n'existe plus
    c.oublierThemesInconnus(['Musique', 'Sports', 'Histoire']);
    expect(c.themes, {'Musique'});
    await Future<void>.delayed(Duration.zero);

    // Et l'oubli est écrit : elle ne revient pas au prochain démarrage.
    final relu = CriteresTirage();
    await relu.load();
    expect(relu.themes, {'Musique'});
  });

  test('un nombre hors bornes ne peut pas passer', () async {
    SharedPreferences.setMockInitialValues({
      // Le firmware plafonne à 99 (QCOUNT_MAX), et zéro question ne fait pas
      // une manche.
      'tirage_nombre': 400,
      'tirage_niveaux': ['2', '9', 'bidon'],
      'tirage_tranches': ['ados', 'martiens'],
    });
    final c = CriteresTirage();
    await c.load();
    expect(c.nombre, CriteresTirage.nombreParDefaut);
    expect(c.niveaux, {2});
    expect(c.tranches, {Tranche.ados});
  });
}
