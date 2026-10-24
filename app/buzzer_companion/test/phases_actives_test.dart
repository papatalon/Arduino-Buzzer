import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzzer_companion/jeu/phases_actives.dart';

// Les cases du déroulé, relues à la soirée suivante. Un jeu décoché ne doit
// pas entraîner les autres : Classique sans buzzer et Pénalité avec, c'est
// deux parties différentes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sans rien de sauvegardé, tout est coché', () async {
    SharedPreferences.setMockInitialValues({});
    final phases = List.generate(5, (_) => PhasesActives());
    await ReglagesPhases.charger(phases);

    for (final p in phases) {
      for (final etape in EtapeDePartie.values) {
        expect(p.estActive(etape), isTrue);
      }
    }
  });

  test('une case décochée ne concerne que son jeu', () async {
    SharedPreferences.setMockInitialValues({});
    final phases = List.generate(5, (_) => PhasesActives());
    phases[0].definir(EtapeDePartie.buzzer, false);
    phases[1].definir(EtapeDePartie.reponses, false);
    phases[1].definir(EtapeDePartie.finale, false);
    await ReglagesPhases.enregistrer(phases);

    final relu = List.generate(5, (_) => PhasesActives());
    await ReglagesPhases.charger(relu);

    expect(relu[0].buzzer, isFalse);
    expect(relu[0].reponses, isTrue);
    expect(relu[0].finale, isTrue);
    expect(relu[1].reponses, isFalse);
    expect(relu[1].finale, isFalse);
    expect(relu[1].buzzer, isTrue);
    expect(relu[2].demarrage, isTrue);
  });
}
