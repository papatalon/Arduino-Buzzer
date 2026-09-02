import 'dart:async';

import 'package:flutter/foundation.dart';

import '../questionnaires/active_questionnaire.dart';

// Les trois seules choses que le moteur demande au materiel. Un contrat aussi
// etroit se simule en trois lignes dans un test, la ou dependre du service
// Bluetooth complet rendrait les regles du jeu invérifiables.
abstract class CommandesBuzzer {
  /// Accepte le prochain appui parmi ces buzzers (bit 0 = rouge).
  void armer(int masque);

  /// N'accepte plus aucun appui.
  void desarmer();

  /// Allume exactement ces LED.
  void allumerLeds(int masque);
}

// LE MOTEUR DE JEU DE L'APPLICATION.
//
// En mode application, le buzzer n'a plus aucun état de jeu : il arme des
// boutons et rapporte les appuis (voir AppControl côté firmware). Tout le
// reste vit ici : la question courante, qui a buzzé, qui est encore en lice,
// les scores, le chrono, la fin de partie.
//
// POURQUOI CE FICHIER EXISTE. L'application suivait la machine à états du
// Mega et miroitait ses écrans. Elle héritait donc de ce qu'il gardait en
// mémoire, affichait des menus qui n'existent que pour son clavier physique,
// et se retrouvait à annoncer des choses que personne n'avait choisies.
// Corriger cas par cas en découvrait un autre à chaque écran : le partage des
// rôles était le problème, pas les écrans.
//
// LES RÈGLES SONT REPRISES DU FIRMWARE, volontairement à l'identique, parce
// qu'elles ont été jouées et ajustées pendant des soirées. Chaque écart
// serait une régression pour quelqu'un qui connaît le jeu.

enum EtapeQuiz {
  /// Rien en cours. On est au choix du jeu ou avant le lancement.
  repos,

  /// Question posée, buzzers armés, on attend un buzz.
  attente,

  /// Quelqu'un a buzzé, l'animateur juge.
  buzze,

  /// Question tranchée, les scores s'affichent.
  scores,

  /// Personne n'a trouvé : la réponse est révélée avant les scores.
  revelee,

  /// La partie est finie.
  finie,
}

class MoteurQuiz extends ChangeNotifier {
  MoteurQuiz({required this.ble, required this.actif});

  final CommandesBuzzer ble;
  final ActiveQuestionnaire actif;

  EtapeQuiz etape = EtapeQuiz.repos;

  /// Index du jeu choisi (0-4 : Classique, Pénalité, Chrono ×2, Vol).
  int? jeu;

  final List<int> scores = [0, 0, 0, 0];

  /// Buzzers présents, tel que le matériel les rapporte.
  List<bool> presents = [true, true, true, true];

  /// Buzzers encore en lice POUR CETTE QUESTION. Une mauvaise réponse écarte
  /// son auteur jusqu'à la question suivante ; en Vol, seul le joueur désigné
  /// commence en lice.
  final List<bool> enLice = [true, true, true, true];

  /// Qui vient de buzzer, ou null.
  int? buzzeur;

  /// Numéro de la question en cours, à partir de 1.
  int numeroQuestion = 0;

  /// Zéro = sans limite : c'est l'animateur qui arrête.
  int limiteQuestions = 0;

  /// Vrai après une première mauvaise réponse : les suivants jouent sur le
  /// chrono court.
  bool secondeChance = false;

  /// Vol : à qui revient la question.
  int tourVol = 0;

  /// Dernière décision, pour pouvoir la corriger.
  int? dernierJuge;
  bool derniereEtaitBonne = false;

  /// Vrai quand la question s'est terminée sur le chrono.
  bool tempsEcoule = false;

  /// Gagnant de la partie, une fois finie. Null si égalité ou aucun.
  int? gagnant;
  bool egalite = false;

  // --- Chrono ------------------------------------------------------------

  /// Secondes restantes, ou null si aucun chrono ne tourne.
  int? chronoRestant;
  Timer? _chrono;
  int _chronoTotal = 0;

  /// Durées réglées par l'animateur, en secondes. Zéro désactive.
  int chronoPremiere = 0;
  int chronoSuivantes = 0;

  bool get chronoActif => _chrono != null;

  /// Jeux avec chrono : Chrono classique (2), Chrono pénalité (3), Vol (4).
  bool get utiliseChrono => jeu == 2 || jeu == 3 || jeu == 4;

  /// Jeux où une mauvaise réponse coûte un point.
  bool get estPenalite => jeu == 1 || jeu == 3;

  bool get estVol => jeu == 4;

  int get _masqueEnLice {
    var m = 0;
    for (var i = 0; i < 4; i++) {
      if (presents[i] && enLice[i]) m |= 1 << i;
    }
    return m;
  }

  // --- Déroulement -------------------------------------------------------

  void demarrer({required int jeuChoisi, required int limite}) {
    jeu = jeuChoisi;
    limiteQuestions = limite;
    for (var i = 0; i < 4; i++) {
      scores[i] = 0;
    }
    numeroQuestion = 0;
    dernierJuge = null;
    gagnant = null;
    actif.goTo(0);
    egalite = false;
    // Vol : le premier joueur est tiré au sort avant la première question.
    if (estVol) {
      final pool = [for (var i = 0; i < 4; i++) if (presents[i]) i];
      tourVol = pool.isEmpty ? 0 : pool[DateTime.now().microsecond % pool.length];
    }
    questionSuivante();
  }

  void questionSuivante() {
    numeroQuestion++;
    // Le questionnaire suit le moteur, il ne devine plus rien : c'est ici
    // qu'on decide de passer a la suivante, donc c'est ici qu'on le dit.
    actif.goTo(numeroQuestion - 1);
    buzzeur = null;
    secondeChance = false;
    tempsEcoule = false;
    dernierJuge = null;

    // Vol : seul le joueur désigné peut répondre en premier. Les autres
    // n'entrent qu'après son échec, c'est tout le sel du jeu.
    for (var i = 0; i < 4; i++) {
      enLice[i] = presents[i] && (!estVol || i == tourVol);
    }

    etape = EtapeQuiz.attente;
    _armer();

    // Le chrono des réponses suivantes part tout seul : la question est déjà
    // connue. Celui de la première attend le « top » de l'animateur, qui
    // vient de la lire à voix haute.
    _arreterChrono();
    notifyListeners();
  }

  void _armer() {
    ble.armer(_masqueEnLice);
    ble.allumerLeds(0);
  }

  /// Le matériel rapporte un appui. [ms] est mesuré sur le Mega, donc sans la
  /// gigue du Bluetooth.
  void surBuzz(int qui, int ms) {
    if (etape != EtapeQuiz.attente) return;
    if (qui < 0 || qui > 3 || !presents[qui] || !enLice[qui]) return;
    buzzeur = qui;
    etape = EtapeQuiz.buzze;
    _arreterChrono();
    // Le firmware a déjà allumé la LED du buzzeur ; on la garde seule.
    ble.allumerLeds(1 << qui);
    notifyListeners();
  }

  void bonneReponse() {
    final qui = buzzeur;
    if (qui == null || etape != EtapeQuiz.buzze) return;
    scores[qui]++;
    dernierJuge = qui;
    derniereEtaitBonne = true;
    if (estVol) tourVol = _prochainPresent(tourVol);
    _versScores();
  }

  void mauvaiseReponse() {
    final qui = buzzeur;
    if (qui == null || etape != EtapeQuiz.buzze) return;
    if (estPenalite) scores[qui]--;
    dernierJuge = qui;
    derniereEtaitBonne = false;

    final premiereTentative = !secondeChance;
    secondeChance = true;
    enLice[qui] = false;

    // Vol : le joueur désigné vient d'échouer, la question s'ouvre aux
    // autres. Un voleur qui échoue à son tour reste écarté.
    if (estVol && premiereTentative && qui == tourVol) {
      for (var i = 0; i < 4; i++) {
        if (i != tourVol) enLice[i] = presents[i];
      }
    }

    buzzeur = null;
    ble.allumerLeds(0);

    // Plus personne en lice : la question est close.
    if (_masqueEnLice == 0) {
      _versRevelation();
      return;
    }

    etape = EtapeQuiz.attente;
    _armer();
    // Les suivants jouent sur le chrono court, qui part tout de suite.
    if (utiliseChrono && chronoSuivantes > 0) {
      _lancerChrono(chronoSuivantes);
    }
    notifyListeners();
  }

  /// Question abandonnée : personne ne marque.
  void passer() {
    _arreterChrono();
    buzzeur = null;
    dernierJuge = null;
    ble.allumerLeds(0);
    _versRevelation();
  }

  /// Annule la dernière décision. Rouvre la question sur le même buzzeur.
  void corriger() {
    final id = dernierJuge;
    if (id == null) return;
    if (derniereEtaitBonne) {
      scores[id]--;
    } else {
      enLice[id] = presents[id];
      if (estPenalite) scores[id]++;
    }
    dernierJuge = null;
    buzzeur = id;
    etape = EtapeQuiz.buzze;
    _arreterChrono();
    ble.allumerLeds(1 << id);
    notifyListeners();
  }

  /// Depuis les scores ou la révélation : on enchaîne.
  void continuer() {
    if (limiteQuestions > 0 && numeroQuestion >= limiteQuestions) {
      terminer();
      return;
    }
    // Questionnaire épuisé : inutile d'armer pour une question qui n'existe
    // pas. L'animateur peut encore continuer à l'oral s'il le veut.
    questionSuivante();
  }

  void terminer() {
    _arreterChrono();
    ble.desarmer();
    ble.allumerLeds(0);

    var meilleur = 0;
    var trouve = false;
    for (var i = 0; i < 4; i++) {
      if (presents[i] && (!trouve || scores[i] > meilleur)) {
        meilleur = scores[i];
        trouve = true;
      }
    }
    final exaequo = [for (var i = 0; i < 4; i++) if (presents[i] && scores[i] == meilleur) i];
    egalite = trouve && exaequo.length > 1;
    gagnant = (trouve && exaequo.length == 1) ? exaequo.first : null;
    etape = EtapeQuiz.finie;
    notifyListeners();
  }

  void retourAuMenu() {
    _arreterChrono();
    ble.desarmer();
    ble.allumerLeds(0);
    etape = EtapeQuiz.repos;
    jeu = null;
    notifyListeners();
  }

  void _versScores() {
    _arreterChrono();
    ble.desarmer();
    // Courte célébration : la LED du gagnant reste allumée pendant les scores.
    final qui = dernierJuge;
    ble.allumerLeds(derniereEtaitBonne && qui != null ? 1 << qui : 0);
    etape = EtapeQuiz.scores;
    notifyListeners();
  }

  void _versRevelation() {
    _arreterChrono();
    ble.desarmer();
    ble.allumerLeds(0);
    // Sans question à l'écran (questionnaire libre), il n'y a pas de réponse
    // à révéler : on va droit aux scores.
    etape = actif.current?.answer.isNotEmpty == true
        ? EtapeQuiz.revelee
        : EtapeQuiz.scores;
    notifyListeners();
  }

  int _prochainPresent(int depuis) {
    for (var pas = 1; pas <= 4; pas++) {
      final i = (depuis + pas) % 4;
      if (presents[i]) return i;
    }
    return depuis;
  }

  // --- Chrono ------------------------------------------------------------

  /// Le « top » de l'animateur, qui vient de lire la question.
  void lancerChronoPremiere() {
    if (!utiliseChrono || chronoPremiere <= 0) return;
    _lancerChrono(chronoPremiere);
  }

  void _lancerChrono(int secondes) {
    _arreterChrono();
    if (secondes <= 0) return;
    _chronoTotal = secondes;
    chronoRestant = secondes;
    _chrono = Timer.periodic(const Duration(seconds: 1), (_) {
      final reste = (chronoRestant ?? 0) - 1;
      chronoRestant = reste;
      if (reste <= 0) {
        _arreterChrono();
        _tempsEcoule();
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void _arreterChrono() {
    _chrono?.cancel();
    _chrono = null;
    chronoRestant = null;
  }

  double get progressionChrono {
    final reste = chronoRestant;
    if (reste == null || _chronoTotal <= 0) return 0;
    return reste / _chronoTotal;
  }

  void _tempsEcoule() {
    // Vol, première réponse : le temps écoulé vaut un échec du joueur
    // désigné, la question s'ouvre aux autres au lieu de se fermer.
    if (estVol && !secondeChance) {
      dernierJuge = tourVol;
      derniereEtaitBonne = false;
      enLice[tourVol] = false;
      for (var i = 0; i < 4; i++) {
        if (i != tourVol) enLice[i] = presents[i];
      }
      secondeChance = true;
      etape = EtapeQuiz.attente;
      _armer();
      notifyListeners();
      return;
    }
    tempsEcoule = true;
    passer();
  }

  @override
  void dispose() {
    _chrono?.cancel();
    super.dispose();
  }
}
