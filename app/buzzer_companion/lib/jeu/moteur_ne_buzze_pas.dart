import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio/sonorisation.dart';
import 'moteur_quiz.dart' show CommandesBuzzer, ModeArmement;
import 'mots_de_la_fin.dart';

enum EtapeNeBuzzePas {
  /// Avant le lancement.
  repos,

  /// ÉCOUTE GUIDÉE : chacun découvre le son qui lui est attribué pour CETTE
  /// partie, en pesant lui-même sur son bouton.
  ecoute,

  /// Le flux de sons est lancé.
  flux,

  /// Partie terminée.
  finie,
}

// « NE BUZZE PAS » : un jeu d'oreille.
//
// Des sons s'enchaînent en flux continu, de plus en plus serré. Il faut peser
// quand c'est le sien, et surtout pas quand c'est celui d'un autre.
//
// LES SONS SONT TIRÉS AU SORT POUR CHAQUE PARTIE, et n'ont rien à voir avec
// les sons configurés des buzzers. Deux raisons : les habitués connaissent
// leur propre son par cœur et le jeu perd tout son sel dès la deuxième
// soirée ; et ça remet tout le monde à égalité, y compris celui qui a passé
// vingt minutes à choisir le sien.
//
// L'ÉCOUTE EST GUIDÉE, PAS SUBIE. Le firmware joue les quatre sons à la
// suite en nommant les couleurs ; ici, chaque joueur pèse lui-même sur son
// bouton pour entendre le sien. Le geste ancre l'association bien mieux que
// de regarder une LED s'allumer, et c'est aussi le moment de s'apercevoir que
// deux sons se ressemblent trop.
//
// LE BARÈME EST CELUI DU BUZZER, reprises telles quelles parce qu'elles ont
// été jouées : reconnaître son son vaut un point, ou deux dans la première
// moitié de l'écart courant, ce qui récompense la vitesse et pas seulement la
// justesse. Peser sur le son d'un autre coûte un point et vous écarte de ce
// son, mais son propriétaire peut encore le réclamer. Et laisser passer son
// propre son coûte un point aussi : sans ça, ne jamais peser serait une
// stratégie sans risque.
class MoteurNeBuzzePas extends ChangeNotifier {
  MoteurNeBuzzePas({required this.ble, this.sons, Random? hasard})
      : _hasard = hasard ?? Random();

  final CommandesBuzzer ble;
  final Sonorisation? sons;
  final Random _hasard;

  // --- Réglages ------------------------------------------------------------

  /// Écart entre deux sons, qui se resserre au fil de la partie. Reprises du
  /// firmware : c'est ce resserrement qui fait monter la tension et donne une
  /// fin naturelle.
  static const ecartDepartMs = 2500;
  static const ecartMinMs = 1200;
  static const ecartPasMs = 100;

  /// Proportion de leurres quand ils sont actifs : des sons qui n'appartiennent
  /// à personne, et sur lesquels personne ne doit peser. Les pièges les plus
  /// efficaces.
  static const partDeLeurres = 30;

  bool avecLeurres = true;

  // --- État ----------------------------------------------------------------

  EtapeNeBuzzePas etape = EtapeNeBuzzePas.repos;

  List<bool> presentsMateriel = [true, true, true, true];

  final List<int> scores = [0, 0, 0, 0];

  /// Le son attribué à chaque buzzer POUR CETTE PARTIE, par son index dans le
  /// dossier. Null quand rien n'est attribué.
  final List<int?> assignation = [null, null, null, null];

  /// Combien de sons différents la bibliothèque propose. Fourni au lancement.
  int nombreDeSons = 0;

  /// Pendant l'écoute : à qui c'est le tour. Null quand l'écoute est finie.
  int? aQuiLeTour;

  /// Qui a déjà entendu son son.
  final List<bool> aEcoute = [false, false, false, false];

  /// Combien de sons ont été joués dans le flux.
  int sonsJoues = 0;

  /// Le son en cours dans le flux : son index, et son propriétaire (null pour
  /// un leurre).
  int? sonCourant;
  int? proprietaireDuSon;

  /// Qui a déjà pesé sur le son en cours : on ne compte qu'une réaction par
  /// personne et par son.
  final List<bool> dejaReagi = [false, false, false, false];

  /// Vrai quand le propriétaire a réclamé son son : il ne sera pas pénalisé
  /// à la fin de l'écart.
  bool reclame = false;

  /// LE SON PRÉCÉDENT, celui qui est déjà joué et déjà jugé.
  ///
  /// C'est le seul que l'écran public peut montrer : révéler à qui appartient
  /// le son EN COURS répondrait à la question avant les joueurs. Null pour un
  /// leurre, et -1 tant qu'aucun son n'est passé.
  int? proprietairePrecedent;
  bool precedentEtaitLeurre = false;
  bool precedentReclame = false;
  bool aDejaJoue = false;

  String motFinal = '';

  /// Vrai pendant qu'un son d'ecoute joue : personne n'est arme.
  bool sonEnEcoute = false;

  Timer? _minuteur;
  Timer? _attenteDuSon;
  DateTime _debutDeLEcoute = DateTime.now();

  List<bool> get presents => List<bool>.of(presentsMateriel);

  bool get compteDeJoueursValide => presents.any((p) => p);

  int get _masqueEnJeu {
    var m = 0;
    for (var i = 0; i < 4; i++) {
      if (presents[i]) m |= 1 << i;
    }
    return m;
  }

  /// L'écart courant, qui se resserre à chaque son joué.
  int get ecartCourantMs {
    final e = ecartDepartMs - sonsJoues * ecartPasMs;
    return e < ecartMinMs ? ecartMinMs : e;
  }

  /// COMBIEN DE TEMPS DURE UNE PARTIE DE [sons] SONS.
  ///
  /// « 10 sons » ne dit rien a l'animateur qui doit decider si ca rentre
  /// avant la pause. Comme l'ecart se resserre, la duree n'est pas
  /// proportionnelle : les vingt derniers sons passent bien plus vite que les
  /// vingt premiers. On additionne donc les vrais ecarts plutot que de
  /// multiplier, sinon l'estimation deriverait des la trentaine.
  static Duration dureeEstimee(int sons) {
    var total = 0;
    // Le premier son joue deja a un pas du depart, comme ecartCourantMs le
    // calcule : compter a partir de 1 sinon l'estimation devance la partie.
    for (var i = 1; i <= sons; i++) {
      final e = ecartDepartMs - i * ecartPasMs;
      total += e < ecartMinMs ? ecartMinMs : e;
    }
    return Duration(milliseconds: total);
  }

  // --- Écoute --------------------------------------------------------------

  /// [nombreDeSonsDisponibles] vient de la bibliothèque de l'application ou de
  /// la carte SD du buzzer, selon la sortie choisie.
  void demarrer({
    required int nombreDeSonsDisponibles,
    int? chances,
    bool? leurres,
  }) {
    if (chances != null) chancesParBuzzer = chances;
    if (leurres != null) avecLeurres = leurres;
    nombreDeSons = nombreDeSonsDisponibles;

    for (var i = 0; i < 4; i++) {
      scores[i] = 0;
      aEcoute[i] = false;
      assignation[i] = null;
    }
    sonsJoues = 0;
    motFinal = '';
    aDejaJoue = false;
    proprietairePrecedent = null;
    _tirerAssignation();
    // Apres l'assignation : les leurres se piochent dans ce qui reste libre.
    _monterLeParcours();

    etape = EtapeNeBuzzePas.ecoute;
    aQuiLeTour = _prochainAEcouter();
    _armerPourLEcoute();
    notifyListeners();
  }

  /// Quatre sons DIFFÉRENTS, tirés au hasard. S'il y en a moins que de
  /// joueurs dans la bibliothèque, on prend ce qu'il y a : mieux vaut un jeu
  /// bancal qu'un refus de démarrer.
  void _tirerAssignation() {
    final pool = [for (var i = 0; i < nombreDeSons; i++) i]..shuffle(_hasard);
    var k = 0;
    for (var i = 0; i < 4; i++) {
      if (!presents[i]) continue;
      assignation[i] = pool.isEmpty ? null : pool[k % pool.length];
      k++;
    }
  }

  /// Les sons qui n'appartiennent à personne : les leurres se piochent là.
  List<int> get _sonsLibres {
    final pris = {for (final a in assignation) ?a};
    return [for (var i = 0; i < nombreDeSons; i++) if (!pris.contains(i)) i];
  }

  int? _prochainAEcouter() {
    for (var i = 0; i < 4; i++) {
      if (presents[i] && !aEcoute[i]) return i;
    }
    return null;
  }

  void _armerPourLEcoute() {
    final qui = aQuiLeTour;
    if (qui == null) {
      ble.desarmer();
      ble.allumerLeds(0);
      return;
    }
    // SEUL celui dont c'est le tour est armé : un voisin impatient ne peut pas
    // déclencher le son de quelqu'un d'autre, ni brûler son tour.
    ble.armer(1 << qui);
    ble.allumerLeds(1 << qui);
  }

  /// L'écoute est finie quand chacun a entendu le sien.
  bool get ecouteTerminee => _prochainAEcouter() == null;

  // --- Flux ----------------------------------------------------------------

  /// Le départ, donné par l'animateur une fois l'écoute faite.
  void lancerLeFlux() {
    if (etape != EtapeNeBuzzePas.ecoute || !ecouteTerminee) return;
    etape = EtapeNeBuzzePas.flux;
    sonsJoues = 0;
    ble.allumerLeds(0);
    _jouerLeProchainSon();
  }

  void _jouerLeProchainSon() {
    _arreterMinuteur();
    if (sonsPrevus > 0 && sonsJoues >= sonsPrevus) {
      terminer();
      return;
    }

    // Fin de l'écart précédent : celui qui a laissé passer son son le paie.
    _punirLOubli();
    if (aDejaJoue || sonCourant != null) {
      proprietairePrecedent = proprietaireDuSon;
      precedentEtaitLeurre = proprietaireDuSon == null;
      precedentReclame = reclame;
      aDejaJoue = true;
    }

    sonsJoues++;
    for (var i = 0; i < 4; i++) {
      dejaReagi[i] = false;
    }
    reclame = false;

    _choisirLeSon();
    // Tous armés en continu : n'importe qui peut réagir, à ses risques.
    ble.armer(_masqueEnJeu, mode: ModeArmement.continu);
    sons?.sonNumero(sonCourant ?? 0);

    _minuteur = Timer(
        Duration(milliseconds: ecartCourantMs), _jouerLeProchainSon);
    notifyListeners();
  }

  /// LE PARCOURS DE LA PARTIE, monté d'avance.
  ///
  /// Chaque case dit à qui appartient le son de ce tour, ou null pour un
  /// leurre. Tirer chaque tour au hasard indépendamment, comme on le faisait,
  /// ne garantit rien : sur seize tours il arrive couramment qu'un buzzer ne
  /// sorte jamais, et ce joueur ne peut alors pas marquer un seul point sans
  /// que rien à l'écran ne l'explique. Ici tout le monde a exactement le même
  /// nombre de tours, par construction.
  List<int?> parcours = [];

  /// Combien de tours chaque buzzer présent obtient. C'est le seul réglage de
  /// longueur : le total en découle.
  int chancesParBuzzer = 4;

  /// La part de leurres, tirée au sort dans cette fourchette pour que deux
  /// parties ne se ressemblent pas, mais bornée par le nombre de tours des
  /// joueurs : seize tours ne peuvent pas porter cent leurres.
  static const leurresMinPourCent = 15;
  static const leurresMaxPourCent = 35;

  /// Le nombre total de tours, leurres compris. Découle du parcours.
  int get sonsPrevus => parcours.length;

  void _monterLeParcours() {
    final joueurs = [for (var i = 0; i < 4; i++) if (presents[i]) i];
    final pieces = <int?>[];
    for (final j in joueurs) {
      for (var k = 0; k < chancesParBuzzer; k++) {
        pieces.add(j);
      }
    }
    if (avecLeurres && _sonsLibres.isNotEmpty && pieces.isNotEmpty) {
      final mini = (pieces.length * leurresMinPourCent / 100).round();
      final maxi = (pieces.length * leurresMaxPourCent / 100).round();
      final combien = mini + _hasard.nextInt((maxi - mini).abs() + 1);
      for (var k = 0; k < combien; k++) {
        pieces.add(null);
      }
    }
    parcours = _entrelacer(pieces);
  }

  /// ÉTALER LES TOURS D'UN MÊME BUZZER, au lieu de brasser bêtement.
  ///
  /// Deux tours de suite pour la même personne se jouent mal : elle vient de
  /// peser, son son revient une seconde et demie plus tard, et elle croit
  /// avoir mal entendu. On place donc toujours le propriétaire qui a le plus
  /// de tours restants parmi ceux qui ne viennent pas de jouer, ce qui donne
  /// toujours un ordre valide quand il en existe un. Les leurres, eux, ont
  /// le droit de se suivre : ce sont des sons différents à chaque fois.
  List<int?> _entrelacer(List<int?> pieces) {
    final restant = <int?, int>{};
    for (final p in pieces) {
      restant[p] = (restant[p] ?? 0) + 1;
    }
    final sortie = <int?>[];
    int? precedent;
    while (sortie.length < pieces.length) {
      final cles = restant.keys.toList()..shuffle(_hasard);
      // NULL EST UNE VRAIE VALEUR ICI (le leurre), donc il ne peut pas servir
      // aussi de « rien trouve » : sans ce drapeau, choisir un leurre passait
      // pour un echec et se faisait ecraser par une cle au hasard, y compris
      // celle qu'on venait de jouer.
      int? choix;
      var trouve = false;
      var plus = 0;
      for (final c in cles) {
        final reste = restant[c]!;
        if (reste <= 0) continue;
        if (c != null && c == precedent) continue;
        if (reste > plus) {
          plus = reste;
          choix = c;
          trouve = true;
        }
      }
      // Dernier recours : il ne reste que celui qu'on vient de jouer.
      if (!trouve) choix = cles.firstWhere((c) => restant[c]! > 0);
      restant[choix] = restant[choix]! - 1;
      sortie.add(choix);
      precedent = choix;
    }
    return sortie;
  }

  void _choisirLeSon() {
    final qui = (sonsJoues >= 1 && sonsJoues <= parcours.length)
        ? parcours[sonsJoues - 1]
        : null;
    if (qui == null) {
      final libres = _sonsLibres;
      sonCourant = libres.isEmpty ? 0 : libres[_hasard.nextInt(libres.length)];
      proprietaireDuSon = null;
      return;
    }
    proprietaireDuSon = qui;
    sonCourant = assignation[qui];
  }

  /// Laisser passer son propre son coûte un point. Sans cette pénalité, ne
  /// jamais peser serait une stratégie sans risque.
  void _punirLOubli() {
    final qui = proprietaireDuSon;
    if (qui == null || reclame) return;
    if (!presents[qui]) return;
    scores[qui]--;
  }

  /// Le matériel rapporte un appui. [ms] est mesuré sur le Mega depuis le
  /// début du son en cours.
  void surBuzz(int qui, int ms) {
    if (qui < 0 || qui > 3 || !presents[qui]) return;

    if (etape == EtapeNeBuzzePas.ecoute) {
      _surEcoute(qui);
      return;
    }
    if (etape != EtapeNeBuzzePas.flux) return;
    if (dejaReagi[qui]) return;
    dejaReagi[qui] = true;

    if (qui == proprietaireDuSon) {
      // Deux points dans la PREMIÈRE MOITIÉ de l'écart : sans ça, écouter le
      // son en entier avant de peser serait sans risque.
      final vite = ms <= ecartCourantMs ~/ 2;
      scores[qui] += vite ? 2 : 1;
      reclame = true;
    } else {
      // Le son d'un autre, ou un leurre.
      scores[qui]--;
    }
    // AUCUN SON DE REACTION ICI, ni bon ni mauvais.
    //
    // Ailleurs un « bonne reponse » recompense ; ici le son EST la question.
    // Un bruit par-dessus couvrirait le son suivant, qui part deja une
    // seconde et demie plus tard : ca ne decorerait pas la manche, ca la
    // casserait. Et ca dirait a toute la salle si celui qui vient de peser
    // avait raison, alors que c'est justement ce qu'elle doit deviner.
    // Le verdict sort a l'ecran quand le son suivant demarre.
    notifyListeners();
  }

  void _surEcoute(int qui) {
    if (qui != aQuiLeTour) return;
    if (sonEnEcoute) return;
    aEcoute[qui] = true;
    final son = assignation[qui];
    if (son == null || sons == null) {
      aQuiLeTour = _prochainAEcouter();
      _armerPourLEcoute();
    } else {
      // ON RESTE SUR CELUI-LA le temps que son son joue : nommer deja le
      // suivant lui dirait de peser, et il peserait par-dessus.  Le tour ne
      // change qu'une fois le silence revenu.
      sons!.sonNumero(son);
      _attendreLaFinDuSon();
    }
    notifyListeners();
  }

  /// ON N'ARME PERSONNE TANT QUE LE SON JOUE.
  ///
  /// Sans ça le suivant peut peser par-dessus, et il mémorise alors un mélange
  /// de deux sons : le sien et la queue de celui d'avant. C'est précisément
  /// l'association que toute la partie repose dessus, et l'erreur ne se verrait
  /// nulle part avant que quelqu'un se trompe dans le flux.
  void _attendreLaFinDuSon() {
    sonEnEcoute = true;
    _aVuLeSonJouer = false;
    ble.desarmer();
    ble.allumerLeds(0);
    _attenteDuSon?.cancel();
    _debutDeLEcoute = DateTime.now();
    _attenteDuSon = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => verifierLaFinDuSon(),
    );
  }

  /// Combien de temps on attend quand la fin du son n'est pas observable,
  /// c'est-à-dire quand c'est le buzzer qui joue : le firmware coupe déjà tout
  /// son de buzzer à deux secondes, donc au-delà il n'y a plus rien à couvrir.
  static const gardeDuSonMs = 2200;

  /// Le temps qu'il faut au moteur audio pour se déclarer occupé. Interroger
  /// avant ça répondrait « rien ne joue » alors que le son vient de partir.
  /// Réglable pour que les tests puissent piloter la fin des sons eux-mêmes.
  int delaiAvantDeSonderMs = 300;

  /// Vrai dès qu'on a VU le son jouer : à partir de là le drapeau du moteur
  /// audio est digne de foi tout de suite, plus besoin d'attendre à l'aveugle.
  bool _aVuLeSonJouer = false;

  @visibleForTesting
  void verifierLaFinDuSon() {
    if (!sonEnEcoute) return;
    final ecoule = DateTime.now().difference(_debutDeLEcoute).inMilliseconds;
    final bool fini;
    if (sons?.finDesSonsConnue ?? false) {
      final joue = sons?.sonEnCours ?? false;
      if (joue) _aVuLeSonJouer = true;
      // La vraie fin prime, avec la garde comme filet si le moteur audio
      // restait occupé pour une raison qu'on ne contrôle pas.
      final assezAttendu = _aVuLeSonJouer || ecoule >= delaiAvantDeSonderMs;
      fini = (assezAttendu && !joue) || ecoule >= gardeDuSonMs * 3;
    } else {
      fini = ecoule >= gardeDuSonMs;
    }
    if (!fini) return;
    _attenteDuSon?.cancel();
    _attenteDuSon = null;
    sonEnEcoute = false;
    aQuiLeTour = _prochainAEcouter();
    _armerPourLEcoute();
    notifyListeners();
  }

  /// Refaire entendre un son pendant l'écoute, si quelqu'un n'a pas saisi.
  void reecouter(int qui) {
    if (etape != EtapeNeBuzzePas.ecoute || sonEnEcoute) return;
    final son = assignation[qui];
    if (son == null || sons == null) return;
    sons!.sonNumero(son);
    // Même attente : une réécoute couvrirait le tour suivant tout autant.
    _attendreLaFinDuSon();
    notifyListeners();
  }

  // --- Fin -----------------------------------------------------------------

  void terminer() {
    _arreterMinuteur();
    // Le dernier son compte comme les autres : l'oubli se paie aussi.
    _punirLOubli();
    ble.desarmer();
    ble.allumerLeds(0);
    proprietaireDuSon = null;
    sonCourant = null;

    etape = EtapeNeBuzzePas.finie;
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
    etape = EtapeNeBuzzePas.repos;
    notifyListeners();
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

  /// Le prochain son du flux, forcé par l'animateur. Ouvert aux tests : les
  /// règles se vérifient sans attendre de vraies secondes.
  @visibleForTesting
  void sonSuivant() {
    if (etape != EtapeNeBuzzePas.flux) return;
    _jouerLeProchainSon();
  }

  void _arreterMinuteur() {
    _minuteur?.cancel();
    _minuteur = null;
  }

  @override
  void dispose() {
    _attenteDuSon?.cancel();
    _arreterMinuteur();
    super.dispose();
  }
}
