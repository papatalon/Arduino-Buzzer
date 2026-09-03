import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio/sonorisation.dart';
import 'moteur_quiz.dart' show CommandesBuzzer, ModeArmement;

enum EtapeSimon {
  /// Avant le lancement.
  repos,

  /// La machine joue la séquence. Les buzzers sont désarmés : un appui
  /// pendant la démonstration n'a rien à dire.
  demonstration,

  /// À l'équipe de la rejouer.
  repetition,

  /// Niveau réussi. Une courte pause avant d'allonger la séquence, sinon la
  /// couleur suivante partirait avant que personne ait eu le temps de se
  /// réjouir.
  bravo,

  /// Partie terminée.
  finie,
}

/// Pourquoi la partie s'est arrêtée. Ce n'est pas cosmétique : « raté » nomme
/// un fautif, « trop lent » n'en nomme aucun, et confondre les deux ferait
/// porter le chapeau à quelqu'un qui n'a rien fait.
enum FinDeSimon {
  /// Une couleur ne correspondait pas. [MoteurSimon.fautif] dit laquelle.
  rate,

  /// Plus de dix secondes sans le moindre appui.
  tropLent,

  /// L'animateur a coupé court.
  abandon,

  /// La séquence maximale a été rejouée en entier. Ça n'arrive jamais.
  parfait,
}

// SIMON, tenu par l'application.
//
// La machine joue une suite de couleurs, l'équipe la rejoue. Chacun tient UNE
// couleur et appuie quand la sienne passe : c'est un jeu collaboratif, sans
// score individuel. La séquence s'allonge d'une couleur par niveau réussi, et
// la moindre erreur termine la partie.
//
// LA SÉQUENCE NE SORT QUE DES COULEURS EN JEU. À deux joueurs, elle
// demanderait sinon des couleurs que personne ne tient, et la partie serait
// perdue d'avance sans que rien ne l'explique.
//
// POURQUOI L'APPLICATION ET PAS LE FIRMWARE. En mode application, le Mega
// quitte sa machine à états et ne garde aucun état de jeu (voir AppControl) :
// Simon au firmware voudrait dire soit qu'on ne peut pas le lancer d'ici, soit
// un mode hybride où le Mega mène un jeu pendant que l'application mène les
// autres. Et le son de chaque couleur appartient déjà à l'application : mené
// par le Mega, la lumière serait sur son horloge et le son sur la nôtre, avec
// un saut Bluetooth entre les deux. Ils sont dans la même fonction ici, comme
// ils l'étaient dans Simon.cpp.
//
// LE RYTHME N'EST PAS UNE MESURE. Six cents millisecondes d'allumage, deux
// cent cinquante de silence : la gigue Bluetooth de trente à cent
// millisecondes ne s'y voit pas, contrairement au Réflexe où elle fausserait
// un temps de réaction. Rien ici ne demande la précision du Mega.
class MoteurSimon extends ChangeNotifier {
  MoteurSimon({required this.ble, this.sons, Random? hasard})
      : _hasard = hasard ?? Random();

  final CommandesBuzzer ble;

  /// Facultatif : les règles ne dépendent pas du son, et les tests n'ont pas à
  /// simuler une carte audio.
  final Sonorisation? sons;

  final Random _hasard;

  // --- Réglages, repris du firmware ----------------------------------------
  //
  // Ces durées ont été jouées et ajustées pendant des soirées. Chaque écart
  // serait une régression pour quelqu'un qui connaît le jeu.

  /// Un octet par étape côté Mega, et bien au-delà de ce qu'une salle atteint.
  static const longueurMax = 32;

  /// Pause avant la démonstration, le temps de lire l'écran et de se taire.
  static const avantLaDemoMs = 1500;

  /// Durée d'allumage d'une couleur pendant la démonstration.
  static const allumeMs = 600;

  /// Silence entre deux couleurs de la démonstration.
  static const silenceMs = 250;

  /// Durée d'allumage de la LED en écho d'un appui.
  static const echoMs = 400;

  /// Pause « bravo » entre deux niveaux.
  static const bravoMs = 2000;

  /// Délai maximal entre deux appuis. Au-delà, la partie s'arrête : sans ça,
  /// une équipe qui ne sait plus resterait bloquée sans que rien ne tranche.
  static const delaiSansAppuiMs = 10000;

  /// Vrai en mode « Simon inverse » : la séquence se rejoue à l'envers. Elle
  /// est toujours MONTRÉE du début à la fin.
  ///
  /// C'est un RÉGLAGE, pas un autre jeu : mêmes règles, même matériel, même
  /// déroulement. Il n'a donc pas sa carte dans la grille des jeux.
  bool alEnvers = false;

  /// Change le sens, au repos seulement : basculer en pleine partie
  /// changerait la règle sous les pieds d'une équipe qui a déjà mémorisé
  /// trois niveaux.
  void choisirLeSens(bool envers) {
    if (etape != EtapeSimon.repos || alEnvers == envers) return;
    alEnvers = envers;
    notifyListeners();
  }

  // --- État ----------------------------------------------------------------

  EtapeSimon etape = EtapeSimon.repos;

  /// Les buzzers branchés, tels que le matériel les rapporte.
  List<bool> presentsMateriel = [true, true, true, true];

  List<bool> get presents => List<bool>.of(presentsMateriel);

  /// Les couleurs de la partie, figées au lancement. Changer la présence en
  /// pleine partie ne touche pas à celle qui est en cours : la séquence a
  /// déjà été tirée là-dedans.
  List<int> _joueurs = [];

  int get _masqueEnJeu {
    var m = 0;
    for (final j in _joueurs) {
      m |= 1 << j;
    }
    return m;
  }

  /// Il faut être au moins deux : à un seul joueur, la séquence serait la même
  /// couleur répétée et il n'y aurait rien à mémoriser. C'est aussi la règle
  /// du buzzer, qui refuse de lancer en dessous de deux.
  bool get compteDeJoueursValide =>
      presentsMateriel.where((p) => p).length >= 2;

  /// La séquence en cours. Sa longueur est celle du niveau qui se joue.
  final List<int> sequence = [];

  /// Niveaux RÉUSSIS. Celui qui se joue est donc le suivant, comme sur
  /// l'écran du buzzer (« SIMON - Niveau N »).
  int niveau = 0;

  /// Combien de couleurs l'équipe a déjà rejouées dans le niveau en cours.
  int saisis = 0;

  /// La LED allumée en ce moment : la couleur montrée pendant la
  /// démonstration, l'écho d'un appui pendant la répétition.
  int? couleurAllumee;

  /// Qui s'est trompé, quand c'est la raison de la fin.
  int? fautif;

  /// LA COULEUR QU'IL FALLAIT, quand la partie s'arrête sur une erreur.
  ///
  /// Elle est ce qui rend l'erreur compréhensible plutôt qu'accusatrice :
  /// « Bleu a pesé, c'était à Rouge » raconte la séquence, là où « Bleu s'est
  /// trompé » ne fait que désigner quelqu'un devant la salle.
  int? get couleurAttendue {
    if (fautif == null || saisis >= sequence.length) return null;
    return alEnvers ? sequence[sequence.length - 1 - saisis] : sequence[saisis];
  }

  FinDeSimon? raisonDeLaFin;

  /// Le mot de la fin, qui commente le niveau atteint.
  String motFinal = '';

  /// Le rythme : pause d'ouverture, allumage, silence, pause « bravo », délai
  /// sans appui. Un seul à la fois, chacun remplaçant le précédent.
  Timer? _rythme;

  /// L'écho lumineux d'un appui, qui tourne EN PARALLÈLE du rythme : il
  /// s'éteint tout seul pendant que le délai sans appui court toujours.
  Timer? _echo;

  int _indexDemo = 0;

  // --- Lancement -----------------------------------------------------------

  void demarrer({bool? envers}) {
    if (envers != null) alEnvers = envers;
    if (!compteDeJoueursValide) return;

    _annulerLesMinuteurs();
    sequence.clear();
    niveau = 0;
    saisis = 0;
    fautif = null;
    raisonDeLaFin = null;
    motFinal = '';
    couleurAllumee = null;
    _joueurs = [for (var i = 0; i < 4; i++) if (presentsMateriel[i]) i];

    _allongerEtMontrer();
  }

  /// Ajoute une couleur et relance la démonstration.
  void _allongerEtMontrer() {
    if (sequence.length < longueurMax) {
      sequence.add(_prochaineCouleur());
    }
    _montrerLaSequence();
  }

  /// COMBIEN UNE COULEUR EN RETARD EST FAVORISÉE, une fois que tout le monde
  /// est passé au moins une fois. Le retard se compte par rapport à la
  /// couleur la plus sortie.
  static const penteDeRattrapage = 4;

  /// LE SUPPLÉMENT D'UNE COULEUR RESTÉE SILENCIEUSE sur toute la fenêtre.
  ///
  /// La pente seule ne pouvait rien au début de partie : elle se mesure par
  /// rapport à la couleur la plus sortie, donc au premier tirage tous les
  /// poids valent 1 et le hasard est pur. Or une partie de Simon FINIT COURT,
  /// souvent avant la dixième couleur : elle se terminait avant que le
  /// rattrapage ait eu le temps d'agir. Sur cinq couleurs à quatre joueurs,
  /// une partie sur trois laissait quelqu'un sans un seul appui.
  ///
  /// LE CHIFFRE SORT D'UN BALAYAGE, pas d'une intuition. À quatre joueurs :
  ///
  ///   supplément    quelqu'un à zéro       quatre premières
  ///                 à 5 / 6 / 8 couleurs   toutes distinctes
  ///        0        30 % / 14 % / 2 %             49 %
  ///       24       3,5 % / 0,7 % / 0 %            87 %
  ///
  /// Monter plus haut ne gagne presque rien sur les zéros et raidit la suite
  /// vers le tour de rôle, où la quatrième couleur se devine.
  static const bonusDeSilence = 24;

  /// SUR COMBIEN DE TIRAGES ON REGARDE EN ARRIÈRE.
  ///
  /// Le compte est LOCAL, pas global, et c'est ce qui fait tenir l'équilibre
  /// sur toute la longueur d'une partie. Compté depuis le début, le
  /// supplément ne servait qu'une fois : une couleur sortie au troisième tour
  /// n'était plus « à zéro » et pouvait ensuite disparaître dix tours sans
  /// que rien ne la rappelle. Sur dix-huit tours, une partie sur trois
  /// laissait une couleur muette huit tirages d'affilée.
  ///
  /// Un de plus que le nombre de joueurs : à quatre, votre tour devrait
  /// revenir tous les quatre tirages, donc cinq sans rien est déjà un oubli.
  /// Sur dix-huit tours, à quatre joueurs :
  ///
  ///                       silence de 8 d'affilée   deux collées
  ///   compte global               38 %                 89 %
  ///   fenêtre de 5               3,8 %                 89 %
  ///
  /// L'imprévisibilité ne bouge pas : le supplément ne s'applique qu'à une
  /// couleur vraiment oubliée, et rien n'est jamais forcé.
  int get _fenetre => _joueurs.length + 1;

  /// LA COULEUR AJOUTÉE PENCHE VERS CELLES QUI SONT LE MOINS PASSÉES, sans
  /// jamais écarter les autres.
  ///
  /// Deux pièges se font face, et il a fallu tomber dans les deux avant de
  /// viser entre.
  ///
  /// Tirer chaque couleur indépendamment, comme le firmware le faisait,
  /// laisse un joueur avec un seul appui sur dix pendant qu'un autre en a
  /// cinq. Ce n'est pas une malchance rare : à quatre joueurs l'écart atteint
  /// trois ou plus dans sept parties sur dix. Et un jeu collaboratif n'a même
  /// pas de score pour consoler celui qui n'a rien touché.
  ///
  /// Ne garder que les couleurs les moins passées corrige l'écart, mais
  /// fabrique une PERMUTATION : deux couleurs collées deviennent presque
  /// impossibles, et après trois couleurs distinctes la quatrième se déduit.
  /// Dans un jeu de mémoire, c'est un cadeau qu'on ne veut pas faire.
  ///
  /// D'où un poids plutôt qu'un filtre. Une couleur qui vient de sortir reste
  /// possible tout de suite après, juste moins probable, et aucune ne se
  /// devine jamais.
  int _prochaineCouleur() {
    // On ne regarde que les derniers tirages : voir [_fenetre].
    final debut = sequence.length - _fenetre;
    final recents = sequence.sublist(debut < 0 ? 0 : debut);

    final compte = {for (final j in _joueurs) j: 0};
    for (final c in recents) {
      compte[c] = (compte[c] ?? 0) + 1;
    }

    final maxi = compte.values.reduce((a, b) => a > b ? a : b);
    final poids = [
      for (final j in _joueurs)
        1 +
            (maxi - compte[j]!) * penteDeRattrapage +
            (compte[j] == 0 ? bonusDeSilence : 0)
    ];

    var tir = _hasard.nextInt(poids.reduce((a, b) => a + b));
    for (var k = 0; k < _joueurs.length; k++) {
      if (tir < poids[k]) return _joueurs[k];
      tir -= poids[k];
    }
    // Inatteignable : le tirage est borné par la somme des poids.
    return _joueurs.last;
  }

  // --- Démonstration -------------------------------------------------------

  void _montrerLaSequence() {
    etape = EtapeSimon.demonstration;
    _indexDemo = 0;
    saisis = 0;
    fautif = null;
    couleurAllumee = null;

    // DÉSARMÉ pendant la démonstration : un appui n'a rien à dire tant que la
    // séquence se joue, et l'accepter ferait rater le niveau à quelqu'un qui
    // s'est juste appuyé sur son bouton en écoutant.
    ble.desarmer();
    ble.allumerLeds(0);

    _rythme = Timer(
        const Duration(milliseconds: avantLaDemoMs), _montrerLaSuivante);
    notifyListeners();
  }

  void _montrerLaSuivante() {
    if (_indexDemo >= sequence.length) {
      _passerALaRepetition();
      return;
    }

    final couleur = sequence[_indexDemo];
    couleurAllumee = couleur;
    ble.allumerLeds(1 << couleur);
    sons?.buzz(couleur);
    notifyListeners();

    _rythme = Timer(const Duration(milliseconds: allumeMs), () {
      couleurAllumee = null;
      ble.allumerLeds(0);
      _indexDemo++;
      notifyListeners();
      _rythme =
          Timer(const Duration(milliseconds: silenceMs), _montrerLaSuivante);
    });
  }

  // --- Répétition ----------------------------------------------------------

  void _passerALaRepetition() {
    etape = EtapeSimon.repetition;
    saisis = 0;
    couleurAllumee = null;
    ble.allumerLeds(0);

    // MODE RÉPÉTÉ, et pas continu : la même couleur peut revenir deux fois de
    // suite dans une séquence (une fois sur quatre à quatre joueurs). En mode
    // continu, le buzzer qui pèse sort du masque et l'application devrait le
    // réarmer entre les deux appuis : l'aller-retour Bluetooth avalerait le
    // second, l'équipe raterait un niveau qu'elle avait réussi, et rien à
    // l'écran ne l'expliquerait.
    ble.armer(_masqueEnJeu, mode: ModeArmement.repete);
    _relancerLeDelai();
    notifyListeners();
  }

  void _relancerLeDelai() {
    _rythme?.cancel();
    _rythme = Timer(
        const Duration(milliseconds: delaiSansAppuiMs), _plusPersonneNeJoue);
  }

  void _plusPersonneNeJoue() => _terminer(FinDeSimon.tropLent);

  /// [ms] n'est pas utilisé : Simon ne mesure aucun temps de réaction. Il
  /// arrive quand même parce que le Mega le mesure pour tout le monde.
  void surBuzz(int qui, int ms) {
    if (etape != EtapeSimon.repetition) return;
    if (qui < 0 || qui > 3 || !_joueurs.contains(qui)) return;

    // L'écho lumineux part AVANT le jugement : on montre la couleur appuyée,
    // juste ou fausse. C'est ce qui rend une erreur lisible pour la salle.
    couleurAllumee = qui;
    ble.allumerLeds(1 << qui);
    _echo?.cancel();
    _echo = Timer(const Duration(milliseconds: echoMs), () {
      if (couleurAllumee != qui) return;
      couleurAllumee = null;
      ble.allumerLeds(0);
      notifyListeners();
    });

    // La démonstration est toujours montrée du début à la fin ; en mode
    // inverse, c'est la fin de la séquence qui doit être rejouée en premier.
    final attendu =
        alEnvers ? sequence[sequence.length - 1 - saisis] : sequence[saisis];
    if (attendu != qui) {
      fautif = qui;
      _terminer(FinDeSimon.rate);
      return;
    }

    _relancerLeDelai();
    saisis++;

    if (saisis < sequence.length) {
      sons?.buzz(qui);
      notifyListeners();
      return;
    }

    // Séquence complète : niveau réussi.
    niveau++;
    if (niveau >= longueurMax) {
      _terminer(FinDeSimon.parfait);
      return;
    }

    etape = EtapeSimon.bravo;
    ble.desarmer();
    sons?.bonneReponse();
    _rythme?.cancel();
    _rythme = Timer(const Duration(milliseconds: bravoMs), _allongerEtMontrer);
    notifyListeners();
  }

  // --- Fin de partie -------------------------------------------------------

  /// L'animateur coupe court. Le niveau atteint reste celui qui était réussi.
  void abandonner() {
    if (etape == EtapeSimon.repos || etape == EtapeSimon.finie) return;
    _terminer(FinDeSimon.abandon);
  }

  void _terminer(FinDeSimon raison) {
    _annulerLesMinuteurs();
    raisonDeLaFin = raison;
    etape = EtapeSimon.finie;
    motFinal = motDuNiveau(niveau);

    // UNE PARTIE FINIE LAISSE LES BUZZERS ÉTEINTS. La règle vaut pour tous
    // les jeux : une LED qui reste allumée n'appartient plus à rien, et elle
    // brille pour le reste de la soirée.
    //
    // Celle du fautif restait allumée à dessein, pour que la salle voie qui
    // avait rompu la chaîne. L'écran public le dit maintenant en toutes
    // lettres, avec le rang où ça s'est produit : la lumière ne renseignait
    // plus personne, elle accusait juste quelqu'un plus longtemps que les
    // autres.
    ble.desarmer();
    ble.allumerLeds(0);
    couleurAllumee = null;

    if (raison == FinDeSimon.parfait) {
      sons?.victoire();
    } else {
      sons?.mauvaiseReponse();
    }
    notifyListeners();
  }

  /// Relance une partie avec les mêmes réglages.
  void rejouer() => demarrer();

  /// Range le jeu : LED éteintes, buzzers désarmés, retour au repos.
  void quitter() {
    _annulerLesMinuteurs();
    ble.desarmer();
    ble.allumerLeds(0);
    etape = EtapeSimon.repos;
    couleurAllumee = null;
    fautif = null;
    raisonDeLaFin = null;
    notifyListeners();
  }

  void _annulerLesMinuteurs() {
    _rythme?.cancel();
    _rythme = null;
    _echo?.cancel();
    _echo = null;
  }

  @override
  void dispose() {
    _annulerLesMinuteurs();
    super.dispose();
  }
}

/// LE MOT DE LA FIN commente le niveau atteint, et pas une victoire.
///
/// Simon est collaboratif : personne ne gagne, personne ne perd, donc ni
/// [motsDeVictoire] ni [motsDEgalite] ne conviennent. Les paliers sont ceux du
/// buzzer, et le registre celui du reste de l'application : effronté, jamais
/// dirigé contre quelqu'un. Ici la pique porte sur l'équipe au complet, ce qui
/// ne désigne personne.
String motDuNiveau(int niveau) {
  if (niveau >= MoteurSimon.longueurMax) {
    return 'Mémoire d\'éléphant. La séquence au complet.';
  }
  if (niveau >= 12) return 'Impressionnant. Là, on regardait pour vrai.';
  if (niveau >= 8) return 'Belle mémoire. Ça commençait à être long.';
  if (niveau >= 4) return 'Pas mal du tout. La suite était traître.';
  if (niveau >= 1) return 'Un début. La mémoire, ça se réchauffe.';
  return 'Même pas un niveau. Ça arrive aux meilleurs.';
}
