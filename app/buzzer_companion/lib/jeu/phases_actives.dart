import 'package:shared_preferences/shared_preferences.dart';

// LES QUATRE ÉTAPES D'UNE PARTIE DE QUIZ qui ont un son automatique.
//
// Démarrage ouvre la soirée. Buzzer arme les boutons. Réponses révèle la
// réponse et joue le son de bonne ou de mauvaise réponse. Final annonce le
// gagnant. La question, elle, n'a pas de son :
// elle n'est pas une case.
//
// Tout est coché tant qu'on n'a rien touché : une partie se joue comme
// avant. Décocher une étape la saute, et le choix est retenu pour CE jeu,
// pas pour les quatre autres.
enum EtapeDePartie {
  demarrage('Démarrage'),
  buzzer('Buzzer'),
  reponses('Réponses'),
  finale('Final');

  const EtapeDePartie(this.libelle);
  final String libelle;
}

class PhasesActives {
  PhasesActives({
    this.demarrage = true,
    this.buzzer = true,
    this.reponses = true,
    this.finale = true,
  });

  bool demarrage;
  bool buzzer;
  bool reponses;
  bool finale;

  bool estActive(EtapeDePartie etape) => switch (etape) {
        EtapeDePartie.demarrage => demarrage,
        EtapeDePartie.buzzer => buzzer,
        EtapeDePartie.reponses => reponses,
        EtapeDePartie.finale => finale,
      };

  void definir(EtapeDePartie etape, bool active) {
    switch (etape) {
      case EtapeDePartie.demarrage:
        demarrage = active;
      case EtapeDePartie.buzzer:
        buzzer = active;
      case EtapeDePartie.reponses:
        reponses = active;
      case EtapeDePartie.finale:
        finale = active;
    }
  }
}

// Retenu d'une soirée à l'autre, une série de cases par jeu de quiz (0 à 4).
//
// Le moteur tient les valeurs, parce que c'est lui qui décide de sauter une
// étape. Ce fichier ne fait que les relire au démarrage et les réécrire
// quand l'animateur coche.
class ReglagesPhases {
  static String _cle(int jeu, EtapeDePartie etape) =>
      'quiz_phase_${jeu}_${etape.name}';

  static Future<void> charger(List<PhasesActives> phases) async {
    final prefs = await SharedPreferences.getInstance();
    for (var jeu = 0; jeu < phases.length; jeu++) {
      final p = phases[jeu];
      for (final etape in EtapeDePartie.values) {
        p.definir(etape, prefs.getBool(_cle(jeu, etape)) ?? true);
      }
    }
  }

  static Future<void> enregistrer(List<PhasesActives> phases) async {
    final prefs = await SharedPreferences.getInstance();
    for (var jeu = 0; jeu < phases.length; jeu++) {
      final p = phases[jeu];
      for (final etape in EtapeDePartie.values) {
        await prefs.setBool(_cle(jeu, etape), p.estActive(etape));
      }
    }
  }
}
