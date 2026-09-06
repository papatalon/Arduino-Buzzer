import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/sonorisation.dart';
import 'animation_tirage.dart';
import 'mots_de_la_fin.dart';
import '../questionnaires/active_questionnaire.dart';

/// COMMENT LES APPUIS SONT RAPPORTES pendant un armement.
///
/// Le quiz s'arrete au premier ; les autres jeux non, et pas de la meme
/// facon. Nommes plutot que caches derriere des booleens : « continu: true,
/// repete: false » ne dit pas ce qui se passe, et les deux combinaisons
/// impossibles existeraient quand meme.
enum ModeArmement {
  /// Le PREMIER appui seulement, puis desarmement complet. La regle du quiz,
  /// ou le premier qui pese prend la main.
  premier,

  /// Chaque buzzer arme rapporte son appui UNE fois et sort du masque, les
  /// autres restent en jeu. Chrono aveugle attend un appui de chacun, Ne
  /// buzze pas une reaction par son.
  continu,

  /// Chaque appui est rapporte et le masque ne bouge pas : le meme buzzer
  /// peut revenir tout de suite. C'est ce que Simon demande, ou une sequence
  /// « rouge, rouge » sort une fois sur quatre a quatre joueurs.
  repete,
}

// Les trois seules choses que le moteur demande au materiel. Un contrat aussi
// etroit se simule en trois lignes dans un test, la ou dependre du service
// Bluetooth complet rendrait les regles du jeu invérifiables.
abstract class CommandesBuzzer {
  /// Accepte le prochain appui parmi ces buzzers (bit 0 = rouge).
  ///
  /// Voir [ModeArmement] pour ce que le buzzer fait des appuis suivants.
  void armer(int masque, {ModeArmement mode = ModeArmement.premier});

  /// N'accepte plus aucun appui.
  void desarmer();

  /// Allume exactement ces LED.
  void allumerLeds(int masque);

  /// LE SIGNAL DE DEPART du Reflexe et du Duel : allume ces LED ET repart le
  /// chrono de reaction, dans la meme instruction cote Mega.
  ///
  /// [avecSonDuel] demande au Mega de jouer AUSSI le son de depart, juste
  /// avant de repartir le chrono. Sert quand le son sort du haut-parleur du
  /// buzzer : le faire partir depuis l'application ajouterait la latence
  /// Bluetooth entre le son et le chrono.
  ///
  /// Distinct de [allumerLeds] parce que la latence Bluetooth de la commande
  /// est inconnue, de 30 a 100 ms. Si l'application allumait puis comptait de
  /// son cote, cette latence s'ajouterait a tous les temps de reaction, qui
  /// se jouent entre 150 et 400 ms.
  void allumerSignal(int masque, {bool avecSonDuel = false});
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

  /// Ouverture : musique et chenillard sur les boutons, avant la premiere
  /// question. C'est le moment ou la salle comprend que ca commence.
  intro,

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
  MoteurQuiz({required this.ble, required this.actif, this.sons});

  final CommandesBuzzer ble;

  /// De quoi sonner. Facultatif : les regles du jeu ne dependent pas du son,
  /// et les tests les verifient sans avoir a simuler une carte audio.
  ///
  /// Le moteur ne sait pas d'ou sort le son. Il demande « joue une bonne
  /// reponse » et [Sonorisation] route vers les haut-parleurs du PC ou vers
  /// le haut-parleur du buzzer, selon le reglage de l'operateur.
  final Sonorisation? sons;

  /// Le tirage au sort anime, quand il y en a un. Facultatif comme [sons] :
  /// les regles du jeu ne dependent pas d'une animation.
  AnimationTirage? tirage;
  final ActiveQuestionnaire actif;

  EtapeQuiz etape = EtapeQuiz.repos;

  /// Index du jeu choisi (0-4 : Classique, Pénalité, Chrono ×2, Vol).
  int? jeu;

  /// Le jeu retenu par l'animateur, AVANT le lancement.
  ///
  /// Distinct de [jeu], qui est celui de la partie en cours. Il se choisit
  /// sur l'ecran « Jeu actif » et nulle part ailleurs : l'ecran de lancement
  /// le lit, il ne le redemande pas. Le buzzer n'en garde aucune trace quand
  /// l'application mene.
  int? jeuChoisi;

  /// Revenir sur son choix, pour rouvrir la grille des jeux.
  void oublierJeu() {
    if (jeuChoisi == null) return;
    jeuChoisi = null;
    notifyListeners();
  }

  void choisirJeu(int index) {
    if (jeuChoisi == index) return;
    jeuChoisi = index;
    notifyListeners();
  }

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

  /// BRIS D'EGALITE en cours. Seuls les ex aequo peuvent repondre ; une
  /// bonne reponse emporte la partie, une mauvaise elimine du bris, et le
  /// dernier en lice l'emporte. Regle reprise du firmware.
  bool brisEgalite = false;

  /// La phrase projetee sous le resultat, tiree au sort a la fin de la partie.
  String motFinal = '';

  /// La phrase projetee a la place de la question, en manche libre.
  String motAttention = '';

  /// La phrase projetee pendant le tirage au sort du mode Vol. Vide sinon.
  String motTirage = '';

  // --- Chrono ------------------------------------------------------------

  /// Secondes restantes, ou null si aucun chrono ne tourne.
  int? chronoRestant;
  Timer? _chrono;
  int _chronoTotal = 0;

  /// Duree reglee du chrono en cours, pour dessiner une barre qui se vide.
  int get chronoTotal => _chronoTotal;

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
    brisEgalite = false;
    actif.goTo(0);
    egalite = false;
    // Vol : le premier joueur est tiré au sort avant la première question.
    if (estVol) {
      final pool = [for (var i = 0; i < 4; i++) if (presents[i]) i];
      tourVol = pool.isEmpty ? 0 : pool[DateTime.now().microsecond % pool.length];
      // Le bruitage du tirage NE joue PAS ici : l'ouverture demarre juste
      // apres, et les deux sons se seraient couverts. Il accompagne
      // l'animation, au depart de la premiere question (voir
      // commencerLesQuestions).
    }
    // OUVERTURE : musique et chenillard, comme en mode autonome.
    //
    // Sans elle, la partie commençait sur une question, sans rien annoncer à
    // la salle. Le firmware fait ça depuis toujours (Buzzer::ledChase) ; en
    // mode application c'est au moteur de le faire, puisque c'est lui qui
    // mène.
    //
    // Sautée quand aucune sonorisation n'est branchée : une ouverture
    // silencieuse n'ouvre rien, et les tests des règles n'ont pas à traverser
    // une animation pour arriver à la première question.
    if (sons == null) {
      questionSuivante();
      return;
    }
    etape = EtapeQuiz.intro;
    ouvertureTerminee = false;
    ble.desarmer();
    sons!.intro();
    _lancerChenillard();
    notifyListeners();
  }

  // --- Ouverture ---------------------------------------------------------

  Timer? _chenillard;
  int _pasChenillard = 0;
  DateTime? _debutIntro;

  /// Vitesse du chenillard, en millisecondes par LED. Reprise de
  /// INTRO_STEP_MS côté firmware, pour que les deux modes aient le même
  /// rythme.
  static const _pasMs = 120;

  /// Le firmware attend un peu avant de tester la fin du son, le temps que le
  /// lecteur démarre (INTRO_START_MS). Même précaution ici, sinon l'ouverture
  /// se terminerait avant d'avoir commencé.
  static const _avantDeTesterMs = 500;

  /// Garde-fou, comme INTRO_MAX_MS. Il sert surtout quand le son sort du
  /// buzzer : l'application ne peut alors pas savoir quand il finit.
  static const _introMaxMs = 12000;

  void _lancerChenillard() {
    _arreterChenillard();
    _pasChenillard = 0;
    _debutIntro = DateTime.now();
    ble.allumerLeds(1);
    _chenillard = Timer.periodic(const Duration(milliseconds: _pasMs), (_) {
      _pasChenillard++;
      ble.allumerLeds(1 << (_pasChenillard % 4));

      final depuis = DateTime.now().difference(_debutIntro!).inMilliseconds;
      if (depuis < _avantDeTesterMs) return;
      final fini = sons!.finDesSonsConnue ? !sons!.sonEnCours : depuis >= _introMaxMs;
      if (fini || depuis >= _introMaxMs) _finDeLOuverture();
    });
  }

  void _arreterChenillard() {
    _chenillard?.cancel();
    _chenillard = null;
  }

  /// La musique est finie : on ATTEND l'animateur.
  ///
  /// Enchainer tout seul sur la premiere question le prenait de court : il
  /// vient de lancer la partie, la salle applaudit encore, et il doit lire la
  /// question a voix haute. L'ecran public garde ses messages d'attente
  /// pendant ce temps, ce qui donne un plan tenable aussi longtemps qu'il
  /// faut.
  void _finDeLOuverture() {
    _arreterChenillard();
    ble.allumerLeds(0);
    ouvertureTerminee = true;
    notifyListeners();
  }

  /// Vrai quand la musique est finie et qu'on attend le depart de la premiere
  /// question. Sans objet hors de l'ouverture.
  bool ouvertureTerminee = false;

  /// Le depart donne par l'animateur. Ecourte aussi la musique si elle joue
  /// encore.
  void commencerLesQuestions() {
    if (etape != EtapeQuiz.intro) return;
    _arreterChenillard();
    // La musique s'arrete avec le chenillard : la laisser courir par-dessus
    // la premiere question serait pire que pas d'ouverture du tout.
    sons?.arreter();
    ble.allumerLeds(0);

    // Vol : on designe le joueur qui ouvre, avec le meme tirage anime que le
    // buzzer fait en mode autonome. Le sort est deja tire (voir demarrer) :
    // l'animation ne decide de rien, elle annonce.
    if (estVol && tirage != null) {
      motTirage = motDeTirage();
      notifyListeners();
      tirage!.lancer(
        presents: presents,
        motif: MotifTirage.joueur,
        surFin: questionSuivante,
      );
      return;
    }
    questionSuivante();
  }

  void questionSuivante() {
    numeroQuestion++;
    // Manche libre : aucun texte a projeter, donc une phrase qui dit ou porter
    // attention. Tiree ici, une fois par question, pour qu'elle ne change pas
    // sous les yeux de la salle pendant que l'animateur parle.
    motAttention = actif.libre ? motDattention() : '';
    motTirage = '';
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
    sons?.buzz(qui);
    _arreterChrono();
    // Le firmware a déjà allumé la LED du buzzeur ; on la garde seule.
    ble.allumerLeds(1 << qui);
    notifyListeners();
  }

  void bonneReponse() {
    final qui = buzzeur;
    if (qui == null || etape != EtapeQuiz.buzze) return;
    sons?.bonneReponse();
    scores[qui]++;
    dernierJuge = qui;
    derniereEtaitBonne = true;
    if (estVol) tourVol = _prochainPresent(tourVol);
    // Un bris d'egalite se joue en une question : celui qui trouve emporte
    // la partie, on ne repasse pas par l'ecran des scores.
    if (brisEgalite) {
      terminer();
      return;
    }
    _versScores();
  }

  void mauvaiseReponse() {
    final qui = buzzeur;
    if (qui == null || etape != EtapeQuiz.buzze) return;
    sons?.mauvaiseReponse();
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

    // BRIS D'EGALITE : une mauvaise reponse elimine du bris. Le dernier en
    // lice l'emporte sans avoir a repondre, comme sur le buzzer.
    if (brisEgalite) {
      final restants = [
        for (var i = 0; i < 4; i++)
          if (presents[i] && enLice[i]) i
      ];
      if (restants.length <= 1) {
        if (restants.length == 1) scores[restants.first]++;
        terminer();
        return;
      }
      etape = EtapeQuiz.attente;
      buzzeur = null;
      _armer();
      notifyListeners();
      return;
    }

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
    _arreterChenillard();
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
    // UNE PARTIE FINIE LAISSE LES BUZZERS ETEINTS. La regle vaut pour tous
    // les jeux : une LED qui reste allumee n'appartient plus a rien, et elle
    // brille pour le reste de la soiree. Le quiz eteint deja a chaque
    // revelation, mais il n'y a qu'ici que ce soit garanti quel que soit le
    // chemin par lequel la partie s'est terminee.
    ble.desarmer();
    ble.allumerLeds(0);
    etape = EtapeQuiz.finie;
    // Tire ici, une seule fois : l'ecran public le recoit dans l'instantane
    // et ne le retire pas a chaque reconstruction.
    motFinal = motDeLaFin(egalite: egalite);
    if (egalite) {
      sons?.egalite();
    } else if (gagnant != null) {
      sons?.victoire();
    }
    notifyListeners();
  }

  /// LE BRIS D'EGALITE, decide par l'animateur.
  ///
  /// Jamais automatique : une soiree peut tres bien se terminer sur une
  /// egalite, et forcer une question de plus a des gens qui rangent leurs
  /// manteaux serait penible. C'est lui qui juge si la salle en a envie.
  ///
  /// Seuls les ex aequo y participent : les autres restent presents mais ne
  /// peuvent plus buzzer, comme sur le buzzer.
  void lancerBrisDegalite() {
    if (etape != EtapeQuiz.finie || !egalite) return;
    final meilleur = scores
        .asMap()
        .entries
        .where((e) => presents[e.key])
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    brisEgalite = true;
    gagnant = null;
    egalite = false;
    motFinal = '';
    numeroQuestion++;
    buzzeur = null;
    secondeChance = false;
    tempsEcoule = false;
    dernierJuge = null;
    // La question du bris peut avoir ete piochee dans le perimetre par la
    // console. Sinon on prend la suivante du questionnaire, faute de mieux :
    // elle n'a pas encore ete posee.
    if (!actif.questionDeBrisPosee) actif.goTo(numeroQuestion - 1);
    for (var i = 0; i < 4; i++) {
      enLice[i] = presents[i] && scores[i] == meilleur;
    }
    etape = EtapeQuiz.attente;
    _arreterChrono();
    _armer();
    notifyListeners();
  }

  void retourAuMenu() {
    _arreterChenillard();
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
    _arreterChenillard();
    _chrono?.cancel();
    super.dispose();
  }
}
