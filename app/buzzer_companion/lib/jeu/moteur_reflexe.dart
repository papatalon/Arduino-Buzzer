import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio/sonorisation.dart';
import 'moteur_quiz.dart' show CommandesBuzzer, ModeArmement;
import 'mots_de_la_fin.dart';

// CE QU'ON FAIT D'UN FAUX DÉPART.
//
// Le buzzer en connaît une seule : le fautif est écarté de la manche en cours.
// Elle reste la règle par défaut, mais elle ne convient pas à toutes les
// salles, d'où trois autres. Aucune n'est meilleure : elles font des soirées
// différentes.
enum FauxDepart {
  /// La règle du buzzer. Le fautif ne joue plus cette manche, les autres
  /// continuent. Si tout le monde se brûle, la manche est nulle.
  ecarte,

  /// Un point en moins, mais il reste en lice. Personne ne regarde les autres
  /// jouer, et l'anticipation coûte quand même.
  penalite,

  /// Nouveau délai, personne n'est puni. Convivial, mais quelqu'un d'agité
  /// peut faire traîner une manche indéfiniment.
  relance,

  /// Les appuis avant le signal sont ignorés. Pour une salle qui n'a pas envie
  /// qu'on lui compte ses fautes.
  tolere,

  /// DUEL : la manche est offerte a l'adversaire, qui n'a rien besoin de
  /// faire. N'a de sens qu'a deux : c'est la regle du Duel sur le buzzer.
  offreLaManche,

  /// ÉLIMINÉ DE LA PARTIE, pas seulement de la manche. Le plus dur : une
  /// seule anticipation et la soirée est finie pour vous. S'il ne reste qu'un
  /// joueur, il l'emporte sur-le-champ, sans jouer les manches restantes.
  elimine,
}

// DEUX JEUX, UN SEUL MOTEUR.
//
// Le Duel est un Reflexe a trois differences pres : exactement deux joueurs,
// un signal SONORE au lieu des LED, et un faux depart qui offre la manche a
// l'adversaire. Tout le reste - manches, delai imprevisible, mesure du temps,
// scores, bris d'egalite, fin de partie - est identique au mot pres.
//
// Les separer aurait recopie trois cents lignes pour trois reglages. C'est la
// duplication qui a coute quatre bogues dans ce projet : deux ecrans de fin,
// deux instantanes de l'ecran public, deux choix du jeu, deux jeux de lignes
// de source. Ils sont nommes plutot que caches derriere des booleens.
enum JeuDeVitesse {
  /// Signal visuel, de deux a quatre joueurs.
  reflexe,

  /// Signal SONORE, exactement deux joueurs. Ils peuvent jouer dos a dos,
  /// les yeux fermes.
  duel,
}

enum EtapeReflexe {
  /// Avant le lancement.
  repos,

  /// Le délai aléatoire s'écoule, LED éteintes. Les buzzers sont DÉJÀ armés :
  /// c'est ainsi qu'un appui prématuré nous parvient.
  attente,

  /// Le signal est donné, LED allumées. Le premier appui remporte la manche.
  signal,

  /// Manche tranchée. On montre le temps, puis l'animateur enchaîne.
  resultat,

  /// Partie terminée.
  finie,
}

// LE JEU DE RÉFLEXE, tenu par l'application.
//
// Les LED s'éteignent, un délai imprévisible s'écoule, puis tout s'allume d'un
// coup : le premier à peser remporte la manche, et son temps de réaction
// s'affiche en millisecondes.
//
// LE TEMPS EST MESURÉ SUR LE MEGA, jamais ici. Un aller-retour Bluetooth ajoute
// de 30 à 100 ms de gigue, sans que personne sache combien ; un temps de
// réaction se joue entre 150 et 400 ms. C'est aussi pourquoi le signal passe
// par la commande GO, qui allume les LED et repart le chrono dans la même
// instruction : si l'application allumait puis comptait de son côté, la latence
// de cette commande s'ajouterait à tous les temps.
//
// LES BUZZERS SONT ARMÉS AVANT LE SIGNAL, en mode continu. Un appui prématuré
// arrive donc comme un appui ordinaire, et c'est l'application qui décide que
// c'était trop tôt. Aucune primitive spéciale pour les faux départs : le buzzer
// rapporte, l'application juge.
class MoteurReflexe extends ChangeNotifier {
  MoteurReflexe({required this.ble, this.sons, Random? hasard})
      : _hasard = hasard ?? Random();

  final CommandesBuzzer ble;

  /// Facultatif : les règles ne dépendent pas du son, et les tests n'ont pas à
  /// simuler une carte audio.
  final Sonorisation? sons;

  final Random _hasard;

  // --- Réglages ------------------------------------------------------------

  /// Délai avant le signal, reprises du firmware : imprévisible, mais jamais
  /// assez court pour qu'on ne puisse pas se préparer.
  static const delaiMinMs = 2000;
  static const delaiMaxMs = 8000;

  /// Passé ce délai sans appui, la manche est nulle. Trois secondes suffisent
  /// largement : au-delà, personne ne regardait.
  static const delaiReponseMs = 3000;

  FauxDepart regleFauxDepart = FauxDepart.ecarte;

  /// Lequel des deux jeux ce moteur mene.
  JeuDeVitesse jeu = JeuDeVitesse.reflexe;

  /// Le Duel se lance au son : les duellistes n'ont pas a regarder les
  /// boutons, ce qui est tout l'interet du jeu.
  bool get signalSonore => jeu == JeuDeVitesse.duel;

  /// Zéro = sans limite, l'animateur arrête quand il veut.
  int manchesPrevues = 5;

  // --- État ----------------------------------------------------------------

  EtapeReflexe etape = EtapeReflexe.repos;

  // LES BUZZERS BRANCHES, tels que le materiel les rapporte. Distinct de qui
  // JOUE cette partie : au Duel, l'animateur choisit deux duellistes parmi
  // les buzzers presents, et ce choix ne vaut que pour la partie en cours.
  List<bool> presentsMateriel = [true, true, true, true];

  /// Les duellistes retenus pour CETTE partie, ou null pour « tous ceux qui
  /// sont branches ». Remis a null en fin de partie : c'est un choix de
  /// soiree, pas un reglage.
  List<bool>? selection;

  void retenirSelection(List<bool> choix) {
    selection = List<bool>.of(choix);
    notifyListeners();
  }

  /// Qui joue vraiment : branche ET retenu. Un buzzer debranche en cours de
  /// partie cesse de jouer, meme s'il avait ete choisi.
  List<bool> get presents => [
        for (var i = 0; i < 4; i++)
          presentsMateriel[i] && (selection == null || selection![i])
      ];

  final List<int> scores = [0, 0, 0, 0];

  /// Qui peut encore gagner CETTE manche. Un faux départ en écarte, selon la
  /// règle choisie.
  final List<bool> enLice = [true, true, true, true];

  /// Qui a fait un faux départ dans la manche en cours, pour l'afficher.
  final List<bool> fautifs = [false, false, false, false];

  /// Qui joue encore la PARTIE. Seul le mode [FauxDepart.elimine] en retire.
  /// Distinct de [enLice], qui ne vaut que pour la manche en cours.
  final List<bool> dansLaPartie = [true, true, true, true];

  /// Gagnant impose par elimination, quand il ne reste qu'un joueur. Il
  /// l'emporte meme avec moins de points : les autres ne sont plus la.
  int? gagnantParElimination;

  /// La phrase projetee a la fin, tiree au sort. Partagee avec le quiz : les
  /// jeux se terminent tous de la meme facon devant la salle.
  String motFinal = '';

  /// BRIS D'EGALITE en cours : une manche de plus entre les seuls ex aequo.
  /// Celui qui la remporte gagne la partie.
  bool brisEgalite = false;

  int manche = 0;

  /// Gagnant de la manche, et son temps. Null tant que rien n'est tranché.
  int? gagnant;
  int? tempsGagnant;

  /// Meilleur temps de la partie, toutes manches confondues.
  int? meilleurTemps;

  /// LE RECORD DE TOUS LES TEMPS, celui du buzzer.
  ///
  /// Il vit en EEPROM sur le Mega et vaut pour les deux modes : une partie
  /// menee par l'application compte pour le meme record qu'une partie au
  /// clavier. C'est l'objet qui garde la memoire des soirees, pas
  /// l'ordinateur qui passait par la. 65535 veut dire « aucun ».
  int? record;

  /// Vrai quand la partie qui vient de finir a battu le record.
  bool recordBattu = false;

  /// Appele quand le record tombe, pour que le Mega l'enregistre. Facultatif :
  /// les regles ne dependent pas de la persistance.
  void Function(int ms)? surNouveauRecord;

  bool get aUnRecord => record != null && record != 0 && record != 65535;

  /// Vrai quand la manche s'est terminée sans que personne ne pèse.
  bool personne = false;

  Timer? _minuteur;

  int get _masqueEnLice {
    var m = 0;
    for (var i = 0; i < 4; i++) {
      if (presents[i] && enLice[i] && dansLaPartie[i]) m |= 1 << i;
    }
    return m;
  }

  /// Vrai quand la partie ne peut plus continuer faute de joueurs.
  bool get aucunJoueur => !presents.any((p) => p);

  int get nombreDeJoueurs => presents.where((p) => p).length;

  /// Le Duel exige EXACTEMENT deux duellistes, comme sur le buzzer. A trois,
  /// « offrir la manche a l'adversaire » ne veut rien dire.
  bool get compteDeJoueursValide =>
      jeu == JeuDeVitesse.duel ? nombreDeJoueurs == 2 : nombreDeJoueurs >= 1;

  // --- Déroulement ---------------------------------------------------------

  void demarrer({int? manches, FauxDepart? regle, JeuDeVitesse? lequel}) {
    if (manches != null) manchesPrevues = manches;
    if (regle != null) regleFauxDepart = regle;
    if (lequel != null) jeu = lequel;
    for (var i = 0; i < 4; i++) {
      scores[i] = 0;
    }
    manche = 0;
    meilleurTemps = null;
    motFinal = '';
    gagnantParElimination = null;
    brisEgalite = false;
    for (var i = 0; i < 4; i++) {
      dansLaPartie[i] = true;
    }
    mancheSuivante();
  }

  void mancheSuivante() {
    if (manchesPrevues > 0 && manche >= manchesPrevues) {
      terminer();
      return;
    }
    manche++;
    _ouvrirLaManche();
  }

  /// Prépare une manche : tout le monde revient, les LED s'éteignent, et le
  /// délai commence. Sert aussi à relancer après un faux départ toléré.
  void _ouvrirLaManche() {
    _arreterMinuteur();
    gagnant = null;
    tempsGagnant = null;
    personne = false;
    for (var i = 0; i < 4; i++) {
      enLice[i] = presents[i] && dansLaPartie[i];
      fautifs[i] = false;
    }
    _attendreLeSignal();
  }

  void _attendreLeSignal() {
    _arreterMinuteur();
    etape = EtapeReflexe.attente;
    ble.allumerLeds(0);
    // Armés AVANT le signal, sinon un appui prématuré ne nous parviendrait
    // pas et il n'y aurait aucun faux départ à juger.
    ble.armer(_masqueEnLice, mode: ModeArmement.continu);
    final delai = delaiMinMs + _hasard.nextInt(delaiMaxMs - delaiMinMs);
    _minuteur = Timer(Duration(milliseconds: delai), donnerLeSignal);
    notifyListeners();
  }

  /// Le signal tombe, normalement declenche par le minuteur du delai.
  ///
  /// Ouvert aux tests : les regles se verifient sans attendre de vraies
  /// secondes, et ce qui est teste est bien la transition, pas la duree d'un
  /// minuteur.
  @visibleForTesting
  void donnerLeSignal() {
    if (etape != EtapeReflexe.attente) return;
    // Le minuteur du delai vient de se declencher en production, mais pas
    // quand on appelle cette methode directement : sans cette annulation, sa
    // reference serait ecrasee et il resterait arme.
    _arreterMinuteur();
    etape = EtapeReflexe.signal;
    // GO et non LED : le Mega allume et repart son chrono dans la même
    // instruction, donc les temps rapportés partent bien de l'allumage.
    //
    // Au Duel, le signal est le SON : on repart le chrono sans rien allumer,
    // sinon les duellistes verraient le depart au lieu de l'entendre.
    //
    // QUI JOUE LE SON CHANGE LA PRECISION. S'il sort du buzzer, on demande au
    // Mega de le jouer LUI-MEME dans la commande de depart : lecture et
    // chrono deviennent consecutifs, et il ne reste que le delai de
    // demarrage du lecteur. Le faire partir d'ici ajouterait la latence
    // Bluetooth entre les deux, inconnue et de plusieurs dizaines de ms.
    final sonSurLeBuzzer = signalSonore && sons != null && !sons!.versLApplication;
    ble.allumerSignal(signalSonore ? 0 : _masqueEnLice,
        avecSonDuel: sonSurLeBuzzer);
    if (signalSonore && !sonSurLeBuzzer) sons?.signalDuel();
    _minuteur = Timer(
        const Duration(milliseconds: delaiReponseMs), personneNaPese);
    notifyListeners();
  }

  /// Le matériel rapporte un appui. [ms] est mesuré sur le Mega, depuis le
  /// dernier armement ou le signal.
  void surBuzz(int qui, int ms) {
    if (qui < 0 || qui > 3 || !presents[qui]) return;

    if (etape == EtapeReflexe.attente) {
      _fauxDepart(qui);
      return;
    }
    if (etape != EtapeReflexe.signal) return;
    if (!enLice[qui]) return;

    _arreterMinuteur();
    gagnant = qui;
    tempsGagnant = ms;
    scores[qui]++;
    if (meilleurTemps == null || ms < meilleurTemps!) meilleurTemps = ms;
    etape = EtapeReflexe.resultat;
    ble.desarmer();
    ble.allumerLeds(1 << qui);
    sons?.bonneReponse();
    notifyListeners();
  }

  void _fauxDepart(int qui) {
    if (regleFauxDepart == FauxDepart.tolere) return;
    if (fautifs[qui]) return;   // deja fautif cette manche

    fautifs[qui] = true;
    sons?.mauvaiseReponse();

    switch (regleFauxDepart) {
      case FauxDepart.relance:
        // Personne n'est puni, mais la manche repart : le fautif a vu les LED
        // rester eteintes, il n'a rien appris du delai a venir.
        _ouvrirLaManche();
        return;
      case FauxDepart.penalite:
        scores[qui]--;
        // Il reste en lice : c'est tout l'interet de ce mode.
        break;
      case FauxDepart.ecarte:
        enLice[qui] = false;
        break;
      case FauxDepart.offreLaManche:
        // Le Duel se joue a deux : l'adversaire remporte la manche sans avoir
        // a appuyer. Inutile de le faire courir seul contre personne.
        final adversaire = [
          for (var i = 0; i < 4; i++)
            if (presents[i] && dansLaPartie[i] && i != qui) i
        ];
        _arreterMinuteur();
        enLice[qui] = false;
        if (adversaire.length == 1) {
          gagnant = adversaire.first;
          scores[gagnant!]++;
          ble.allumerLeds(1 << gagnant!);
        } else {
          personne = true;
          ble.allumerLeds(0);
        }
        etape = EtapeReflexe.resultat;
        ble.desarmer();
        notifyListeners();
        return;
      case FauxDepart.elimine:
        // Hors de la PARTIE, pas seulement de la manche.
        enLice[qui] = false;
        dansLaPartie[qui] = false;
        final restants = [
          for (var i = 0; i < 4; i++)
            if (presents[i] && dansLaPartie[i]) i
        ];
        // Un seul survivant : inutile de lui faire jouer les manches
        // restantes contre personne.
        if (restants.length == 1) {
          gagnantParElimination = restants.first;
          terminer();
          return;
        }
        if (restants.isEmpty) {
          terminer();
          return;
        }
        break;
      case FauxDepart.tolere:
        return;
    }

    if (_masqueEnLice == 0) {
      // Tout le monde s'est brule : manche nulle.
      _arreterMinuteur();
      personne = true;
      etape = EtapeReflexe.resultat;
      ble.desarmer();
      ble.allumerLeds(0);
      notifyListeners();
      return;
    }
    // On rearme sans toucher au delai en cours : le signal tombera quand il
    // devait tomber, sinon un faux depart renseignerait sur le moment du top.
    ble.armer(_masqueEnLice, mode: ModeArmement.continu);
    notifyListeners();
  }

  /// Le delai de reponse est ecoule sans que personne ne pese. Ouvert aux
  /// tests pour la meme raison que [donnerLeSignal].
  @visibleForTesting
  void personneNaPese() {
    if (etape != EtapeReflexe.signal) return;
    personne = true;
    etape = EtapeReflexe.resultat;
    ble.desarmer();
    ble.allumerLeds(0);
    notifyListeners();
  }

  /// Depuis le résultat : on enchaîne.
  void continuer() {
    if (etape != EtapeReflexe.resultat) return;
    // Un bris se joue en UNE manche : celui qui l'a remportee gagne la
    // partie, on ne relance pas.
    if (brisEgalite) {
      terminer();
      return;
    }
    mancheSuivante();
  }

  /// LE BRIS D'EGALITE, decide par l'animateur.
  ///
  /// Jamais automatique : une soiree peut se terminer sur une egalite, et
  /// forcer une manche de plus a des gens qui rangent leurs manteaux serait
  /// penible. Seuls les ex aequo y participent.
  void lancerBrisDegalite() {
    if (etape != EtapeReflexe.finie || !egalite) return;
    final meilleur = scores
        .asMap()
        .entries
        .where((e) => presents[e.key])
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    brisEgalite = true;
    motFinal = '';
    for (var i = 0; i < 4; i++) {
      dansLaPartie[i] = presents[i] && scores[i] == meilleur;
    }
    manche++;
    _ouvrirLaManche();
  }

  void terminer() {
    // LE RECORD NE VAUT QUE POUR LE REFLEXE : le Duel se joue au son, ses
    // temps incluent un delai de demarrage qui n'a rien a voir. Les melanger
    // fausserait une valeur que le buzzer garde depuis des mois.
    recordBattu = false;
    if (jeu == JeuDeVitesse.reflexe && meilleurTemps != null) {
      if (!aUnRecord || meilleurTemps! < record!) {
        recordBattu = true;
        record = meilleurTemps;
        surNouveauRecord?.call(meilleurTemps!);
      }
    }
    _arreterMinuteur();
    ble.desarmer();
    ble.allumerLeds(gagnantParElimination == null
        ? 0
        : 1 << gagnantParElimination!);
    etape = EtapeReflexe.finie;
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
    etape = EtapeReflexe.repos;
    manche = 0;
    // Le choix des duellistes ne vaut que pour la partie qui vient de finir.
    selection = null;
    notifyListeners();
  }

  /// Qui remporte la partie : le survivant s'il y a eu elimination, sinon
  /// celui qui mene aux points.
  int? get vainqueur => gagnantParElimination ?? meneur;

  /// Le meneur, ou null en cas d'égalité en tête.
  int? get meneur {
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
    if (gagnantParElimination != null) return false;
    if (!presents.any((p) => p)) return false;
    return meneur == null;
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
