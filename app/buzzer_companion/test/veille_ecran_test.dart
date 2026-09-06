import 'package:buzzer_companion/popout/veille_ecran.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

// Les drapeaux de l'API Windows, redits ici : un test qui les relirait
// depuis le code testé ne vérifierait plus rien.
const esContinuous = 0x80000000;
const esSystemRequired = 0x1;
const esDisplayRequired = 0x2;
const verrou = esContinuous | esSystemRequired | esDisplayRequired;

void main() {
  // Les deux appels Windows sont remplacés par des carnets. L'ENTRÉE INERTE
  // DOIT ÊTRE REMPLACÉE, pas seulement observée : ces tests tournent sur le
  // vrai Windows du poste de développement, et une suite qui injecterait des
  // entrées irait déranger la session de qui la lance.
  ({VeilleEcran veille, List<int> etats, List<int> signaux}) sujet() {
    final etats = <int>[];
    final signaux = <int>[];
    return (
      veille: VeilleEcran(
        poser: (d) {
          etats.add(d);
          return d;
        },
        signaler: () {
          signaux.add(1);
          return 1;
        },
        actif: true,
      ),
      etats: etats,
      signaux: signaux,
    );
  }

  test('ouvrir l\'écran public pose le verrou complet', () {
    final s = sujet();
    s.veille.interdireLaVeille();
    expect(s.etats, [verrou]);
    expect(s.veille.tientLEcranAllume, isTrue);
  });

  // La deuxième parade, celle que SetThreadExecutionState ne couvre pas :
  // sans elle, un poste avec un économiseur d'écran configuré le verrait
  // passer devant la projection.
  test('l\'entrée inerte part avec le verrou', () {
    final s = sujet();
    s.veille.interdireLaVeille();
    expect(s.signaux, hasLength(1));
  });

  // Le verrou se réarme tout seul : l'état Windows est attaché au fil
  // d'exécution qui appelle, et rien ne garantit que l'isolat y reste. Le
  // même battement sert à l'entrée inerte, qui doit revenir avant le délai
  // le plus court que Windows accepte, une minute.
  test('les deux parades se réarment pendant que la fenêtre est ouverte', () {
    fakeAsync((async) {
      final s = sujet();
      s.veille.interdireLaVeille();
      async.elapse(VeilleEcran.intervalleRearmement * 3);
      expect(s.etats, [verrou, verrou, verrou, verrou]);
      expect(s.signaux, hasLength(4));
      expect(VeilleEcran.intervalleRearmement, lessThan(const Duration(minutes: 1)));
    });
  });

  // Le drapeau seul, sans les deux autres : c'est la façon documentée
  // d'effacer l'état plutôt que d'en poser un nouveau.
  test('fermer relâche le système avec ES_CONTINUOUS seul', () {
    final s = sujet();
    s.veille.interdireLaVeille();
    s.veille.permettreLaVeille();
    expect(s.etats.last, esContinuous);
    expect(s.veille.tientLEcranAllume, isFalse);
  });

  // Une console laissée ouverte toute la nuit ne doit ni retenir un portable
  // éveillé ni empêcher la session de se verrouiller : après la fermeture,
  // plus rien ne part, entrée inerte comprise.
  test('plus rien ne part après la fermeture', () {
    fakeAsync((async) {
      final s = sujet();
      s.veille.interdireLaVeille();
      s.veille.permettreLaVeille();
      final etatsApres = s.etats.length;
      final signauxApres = s.signaux.length;
      async.elapse(VeilleEcran.intervalleRearmement * 5);
      expect(s.etats.length, etatsApres);
      expect(s.signaux.length, signauxApres);
    });
  });

  // L'écran public se rouvre parfois sur une fenêtre déjà là (open() sur un
  // contrôleur existant) : le verrou ne doit pas se dédoubler, sinon deux
  // minuteurs tournent et un seul est annulé.
  test('demander deux fois ne pose qu\'un seul verrou', () {
    fakeAsync((async) {
      final s = sujet();
      s.veille.interdireLaVeille();
      s.veille.interdireLaVeille();
      expect(s.etats, [verrou]);
      async.elapse(VeilleEcran.intervalleRearmement);
      expect(s.etats, [verrou, verrou]);
      s.veille.permettreLaVeille();
      async.elapse(VeilleEcran.intervalleRearmement * 3);
      expect(s.etats.last, esContinuous);
    });
  });

  // Relâcher sans avoir posé ne doit rien envoyer : ça effacerait le verrou
  // d'un autre logiciel de présentation qui, lui, en a besoin.
  test('relâcher sans avoir posé ne parle pas à Windows', () {
    final s = sujet();
    s.veille.permettreLaVeille();
    expect(s.etats, isEmpty);
    expect(s.signaux, isEmpty);
  });

  // Hors Windows, la classe existe mais se tait : ni l'API d'alimentation ni
  // l'entrée inerte n'ont d'équivalent, et l'app vise aussi iOS à terme.
  test('inactif ailleurs que sous Windows', () {
    final etats = <int>[];
    final signaux = <int>[];
    final veille = VeilleEcran(
      poser: (d) {
        etats.add(d);
        return d;
      },
      signaler: () {
        signaux.add(1);
        return 1;
      },
      actif: false,
    );
    veille.interdireLaVeille();
    expect(etats, isEmpty);
    expect(signaux, isEmpty);
    expect(veille.tientLEcranAllume, isFalse);
  });
}
