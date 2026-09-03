import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio/sonorisation.dart';
import 'moteur_quiz.dart' show CommandesBuzzer, ModeArmement;
import 'mots_de_la_fin.dart';

enum EtapeChronoAveugle {
  /// Avant le lancement.
  repos,

  /// La cible est annoncée, on attend le « top » de l'animateur. Rien ne
  /// bouge : c'est lui qui lit la durée à voix haute.
  annonce,

  /// Le chrono court, invisible. Chacun buzze quand il croit y être.
  course,

  /// Manche tranchée : les temps de chacun et le gagnant.
  resultat,

  /// Partie terminée.
  finie,
}

// LE CHRONO AVEUGLE, tenu par l'application.
//
// Une durée est tirée au sort et annoncée, l'animateur donne le départ, puis
// plus rien ne bouge. Chacun pèse quand il pense que la durée est écoulée ;
// le plus proche remporte la manche.
//
// Aucune connaissance n'est demandée : petits et grands sont à égalité, ce qui
// en fait le meilleur jeu de la soirée pour une salle mélangée.
//
// LES LED SONT LE SEUL RETOUR. Toutes s'allument au départ, et celle d'un
// joueur s'éteint quand il s'est engagé. Ça ne divulgue aucune durée, juste le
// fait qu'un adversaire a déjà tranché, ce qui fait partie du jeu : voir
// quelqu'un peser trop tôt sème le doute, et c'est voulu.
//
// LE TEMPS EST MESURÉ SUR LE MEGA. Le départ passe par la commande GO, qui
// allume les LED et repart le chrono dans la même instruction : sans ça, la
// latence Bluetooth de l'allumage s'ajouterait à tous les écarts.
class MoteurChronoAveugle extends ChangeNotifier {
  MoteurChronoAveugle({required this.ble, this.sons, Random? hasard})
      : _hasard = hasard ?? Random();

  final CommandesBuzzer ble;

  /// Facultatif : les règles ne dépendent pas du son.
  final Sonorisation? sons;

  final Random _hasard;

  // --- Réglages ------------------------------------------------------------

  /// Cible tirée au sort, en secondes entières. Reprises du firmware : assez
  /// longue pour qu'on ne puisse pas compter dans sa tête sans se perdre,
  /// assez courte pour ne pas endormir la salle.
  static const cibleMinS = 5;
  static const cibleMaxS = 15;

  /// Rab après la cible avant de couper la manche. Dix secondes : au-delà,
  /// celui qui n'a pas pesé ne pèsera pas.
  static const grandDelaiMs = 10000;

  int manchesPrevues = 5;

  // --- État ----------------------------------------------------------------

  EtapeChronoAveugle etape = EtapeChronoAveugle.repos;

  List<bool> presentsMateriel = [true, true, true, true];

  final List<int> scores = [0, 0, 0, 0];

  int manche = 0;

  /// La durée à viser, en millisecondes.
  int cibleMs = 0;

  /// Le temps de chacun depuis le départ, ou null s'il n'a pas encore pesé.
  final List<int?> temps = [null, null, null, null];

  /// Gagnant de la manche, et son écart à la cible.
  int? gagnant;
  int? ecartGagnant;

  /// Le plus petit écart de la partie, et celui que le buzzer garde en EEPROM.
  int? meilleurEcart;
  int? record;
  bool recordBattu = false;

  /// Appelé quand le record tombe, pour que le Mega l'enregistre.
  void Function(int ecartMs)? surNouveauRecord;

  /// La phrase de fin, tirée au sort. Partagée avec les autres jeux.
  String motFinal = '';

  bool brisEgalite = false;

  Timer? _minuteur;

  List<bool> get presents => List<bool>.of(presentsMateriel);

  int get _masqueEnJeu {
    var m = 0;
    for (var i = 0; i < 4; i++) {
      if (presents[i]) m |= 1 << i;
    }
    return m;
  }

  /// Ceux qui n'ont pas encore pesé : leur LED reste allumée.
  int get _masqueEnAttente {
    var m = 0;
    for (var i = 0; i < 4; i++) {
      if (presents[i] && temps[i] == null) m |= 1 << i;
    }
    return m;
  }

  bool get aUnRecord => record != null && record != 0 && record != 65535;

  bool get compteDeJoueursValide => presents.any((p) => p);

  int get cibleSecondes => cibleMs ~/ 1000;

  /// L'écart d'un joueur à la cible, ou null s'il n'a pas pesé.
  int? ecartDe(int i) {
    final t = temps[i];
    if (t == null) return null;
    return (t - cibleMs).abs();
  }

  // --- Déroulement ---------------------------------------------------------

  void demarrer({int? manches}) {
    if (manches != null) manchesPrevues = manches;
    for (var i = 0; i < 4; i++) {
      scores[i] = 0;
    }
    manche = 0;
    meilleurEcart = null;
    motFinal = '';
    brisEgalite = false;
    mancheSuivante();
  }

  void mancheSuivante() {
    if (manchesPrevues > 0 && manche >= manchesPrevues) {
      terminer();
      return;
    }
    manche++;
    _annoncer();
  }

  void _annoncer() {
    _arreterMinuteur();
    gagnant = null;
    ecartGagnant = null;
    for (var i = 0; i < 4; i++) {
      temps[i] = null;
    }
    cibleMs =
        (cibleMinS + _hasard.nextInt(cibleMaxS - cibleMinS + 1)) * 1000;
    etape = EtapeChronoAveugle.annonce;
    // Rien n'est armé pendant l'annonce : un appui avant le départ n'aurait
    // aucun sens à mesurer, et le compter contre son auteur serait dur pour
    // un jeu qui se veut accessible.
    ble.desarmer();
    ble.allumerLeds(0);
    notifyListeners();
  }

  /// Le « top » de l'animateur, qui vient d'annoncer la durée.
  void donnerLeDepart() {
    if (etape != EtapeChronoAveugle.annonce) return;
    etape = EtapeChronoAveugle.course;
    ble.armer(_masqueEnJeu, mode: ModeArmement.continu);
    // GO : allume TOUT et repart le chrono dans la même instruction.
    ble.allumerSignal(_masqueEnJeu);
    _minuteur = Timer(
        Duration(milliseconds: cibleMs + grandDelaiMs), tempsEcoule);
    notifyListeners();
  }

  /// Le matériel rapporte un appui. [ms] est mesuré sur le Mega, depuis le
  /// départ.
  void surBuzz(int qui, int ms) {
    if (etape != EtapeChronoAveugle.course) return;
    if (qui < 0 || qui > 3 || !presents[qui]) return;
    if (temps[qui] != null) return; // il a déjà tranché

    temps[qui] = ms;
    // Sa LED s'éteint : les autres voient qu'il s'est engagé, sans savoir
    // quand il croyait y être.
    ble.allumerLeds(_masqueEnAttente);

    if (_masqueEnAttente == 0) {
      _trancher();
      return;
    }
    notifyListeners();
  }

  /// Le rab est écoulé : ceux qui n'ont pas pesé ne pèseront pas.
  @visibleForTesting
  void tempsEcoule() {
    if (etape != EtapeChronoAveugle.course) return;
    _trancher();
  }

  void _trancher() {
    _arreterMinuteur();
    ble.desarmer();

    int? meilleur;
    int? sonEcart;
    for (var i = 0; i < 4; i++) {
      final e = ecartDe(i);
      if (e == null) continue;
      if (sonEcart == null || e < sonEcart) {
        sonEcart = e;
        meilleur = i;
      }
    }

    gagnant = meilleur;
    ecartGagnant = sonEcart;
    if (meilleur != null && sonEcart != null) {
      scores[meilleur]++;
      if (meilleurEcart == null || sonEcart < meilleurEcart!) {
        meilleurEcart = sonEcart;
      }
      ble.allumerLeds(1 << meilleur);
      sons?.buzz(meilleur);
    } else {
      // Personne n'a pesé : la manche est nulle.
      ble.allumerLeds(0);
      sons?.mauvaiseReponse();
    }

    etape = EtapeChronoAveugle.resultat;
    notifyListeners();
  }

  void continuer() {
    if (etape != EtapeChronoAveugle.resultat) return;
    if (brisEgalite) {
      terminer();
      return;
    }
    mancheSuivante();
  }

  void terminer() {
    _arreterMinuteur();
    ble.desarmer();
    ble.allumerLeds(0);

    recordBattu = false;
    if (meilleurEcart != null && (!aUnRecord || meilleurEcart! < record!)) {
      recordBattu = true;
      record = meilleurEcart;
      surNouveauRecord?.call(meilleurEcart!);
    }

    etape = EtapeChronoAveugle.finie;
    motFinal = motDeLaFin(egalite: egalite);
    if (egalite) {
      sons?.egalite();
    } else if (vainqueur != null) {
      sons?.victoire();
    }
    notifyListeners();
  }

  void retourAuMenu() {
    _arreterMinuteur();
    ble.desarmer();
    ble.allumerLeds(0);
    etape = EtapeChronoAveugle.repos;
    manche = 0;
    notifyListeners();
  }

  /// Le bris d'égalité : une manche de plus entre les seuls ex æquo, décidé
  /// par l'animateur. Jamais automatique.
  void lancerBrisDegalite() {
    if (etape != EtapeChronoAveugle.finie || !egalite) return;
    final meilleur = scores
        .asMap()
        .entries
        .where((e) => presentsMateriel[e.key])
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    brisEgalite = true;
    motFinal = '';
    for (var i = 0; i < 4; i++) {
      presentsMateriel[i] =
          presentsMateriel[i] && scores[i] == meilleur;
    }
    manche++;
    _annoncer();
  }

  int? get vainqueur {
    var meilleur = 0;
    var trouve = false;
    for (var i = 0; i < 4; i++) {
      if (presents[i] && (!trouve || scores[i] > meilleur)) {
        meilleur = scores[i];
        trouve = true;
      }
    }
    final exaequo = [
      for (var i = 0; i < 4; i++)
        if (presents[i] && scores[i] == meilleur) i
    ];
    return exaequo.length == 1 ? exaequo.first : null;
  }

  bool get egalite {
    if (!presents.any((p) => p)) return false;
    return vainqueur == null;
  }

  void _arreterMinuteur() {
    _minuteur?.cancel();
    _minuteur = null;
  }

  @override
  void dispose() {
    _arreterMinuteur();
    super.dispose();
  }
}
