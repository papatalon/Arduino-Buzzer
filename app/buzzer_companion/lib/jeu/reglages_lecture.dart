import 'package:shared_preferences/shared_preferences.dart';

import 'moteur_quiz.dart';

// LES DEUX RÉGLAGES DE LECTURE, retenus d'une soirée à l'autre.
//
// Ils vivent sur le moteur, qui en a besoin à chaque question et que la
// console écoute déjà : aucune dépendance de plus à faire traverser les
// écrans. Ce fichier ne fait que les charger au démarrage et les écrire quand
// l'animateur les change.
//
// C'est ICI que vivent les valeurs par défaut de la soirée, pas dans le
// moteur : la question attend l'animateur, les buzzers restent armés. Le
// moteur garde les siennes pour que ses tests continuent de vérifier les
// règles d'avant.
class ReglagesLecture {
  static const _cleSurAutorisation = 'quiz_question_sur_autorisation';
  static const _cleVerrouilles = 'quiz_buzzers_verrouilles_lecture';

  static const surAutorisationParDefaut = true;
  static const verrouillesParDefaut = false;

  static Future<void> charger(MoteurQuiz moteur) async {
    final prefs = await SharedPreferences.getInstance();
    moteur.reglerLecture(
      surAutorisation:
          prefs.getBool(_cleSurAutorisation) ?? surAutorisationParDefaut,
      verrouiller: prefs.getBool(_cleVerrouilles) ?? verrouillesParDefaut,
    );
  }

  static Future<void> enregistrer(MoteurQuiz moteur) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cleSurAutorisation, moteur.questionSurAutorisation);
    await prefs.setBool(
        _cleVerrouilles, moteur.buzzersVerrouillesPendantLecture);
  }
}
