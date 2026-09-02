import '../ble_link_service.dart';
import 'sound_engine.dart';

// LA SEULE FAÇON DE JOUER UN SON DE PARTIE.
//
// Il y a deux sorties possibles, et l'opérateur choisit laquelle sur l'écran
// Buzzers : les haut-parleurs du PC, qui puisent dans la bibliothèque
// embarquée, ou le haut-parleur du buzzer, qui puise dans la carte SD du
// DFPlayer. Le repli sur le buzzer existe pour le cas très concret d'un poste
// sans haut-parleur.
//
// Aucun appelant n'a à connaître ce réglage. Les jeux demandent « joue le son
// d'une bonne réponse » et cette classe route, sinon chaque bouton et chaque
// règle de jeu porterait le même `if` et ils finiraient par diverger. C'est
// déjà arrivé deux fois dans cette application le même jour, avec l'instantané
// de l'écran public et avec le choix du jeu.
//
// Vers le buzzer, les messages réutilisent le canal SND déjà en place pour la
// configuration des sons, avec des actions qui ne visent aucun buzzer :
// W attente, G bonne réponse, B mauvaise réponse, R tirage au sort. Le son
// propre à un buzzer garde l'action E, qui existait déjà pour le faire
// écouter depuis l'écran de configuration.
class Sonorisation {
  Sonorisation({required this.locale, required this.ble});

  /// La bibliothèque embarquée, qui sort par les haut-parleurs du PC.
  final SoundEngine locale;

  /// Le lien vers le buzzer, qui porte aussi le réglage de sortie.
  final BleLinkService ble;

  bool get versLApplication => ble.appHandlesSound;

  /// Musique d'ouverture, au lancement d'une partie.
  void intro() => _jouer(locale.playIntro, 'I');

  /// Vrai tant que l'application SAIT qu'un son joue encore.
  ///
  /// Faux des que le son sort du buzzer : la broche BUSY du DFPlayer n'est
  /// pas rapportee vers l'application, donc elle ne peut pas le savoir. Les
  /// appelants qui suivent la fin d'un son doivent prevoir une duree de
  /// repli, comme le firmware le fait deja avec INTRO_MAX_MS.
  bool get sonEnCours => versLApplication && locale.busy;

  /// Vrai quand la fin des sons est observable.
  bool get finDesSonsConnue => versLApplication;

  /// Son d'ambiance pendant que la réponse se fait attendre.
  void attente() => _jouer(locale.playWaiting, 'W');

  void bonneReponse() => _jouer(locale.playGood, 'G');

  void mauvaiseReponse() => _jouer(locale.playBad, 'B');

  /// Coupe net ce qui joue.
  ///
  /// Sert quand l'animateur ecourte l'ouverture : le chenillard s'arrete, la
  /// musique doit s'arreter avec lui, sinon elle continue par-dessus la
  /// premiere question.
  void arreter() {
    if (versLApplication) {
      locale.arreter();
    } else {
      ble.sendSoundCommand('X', -1);
    }
  }

  /// Le mot de la fin, quand quelqu'un l'emporte.
  ///
  /// Reprend le dossier des bonnes reponses, faute d'un dossier « victoire »
  /// dans la bibliotheque. En ajouter un demanderait aussi un dossier sur la
  /// carte SD du DFPlayer et une constante de plus dans le firmware, pour un
  /// son que la salle entend une fois par soiree.
  void victoire() => _jouer(locale.playGood, 'G');

  /// Egalite : le dossier des mauvaises reponses, qui sonne comme le
  /// « wah wah » de circonstance. Personne n'a perdu, mais personne n'a
  /// gagne non plus.
  void egalite() => _jouer(locale.playBad, 'B');

  /// Tirage au sort animé, au départ d'une manche de Vol.
  void tirage() => _jouer(locale.playSpin, 'R');

  /// Le son propre à un buzzer, celui qu'on entend quand il est frappé.
  void buzz(int buzzer) {
    if (buzzer < 0 || buzzer > 3) return;
    if (versLApplication) {
      locale.playBuzzer(buzzer);
    } else {
      ble.sendSoundCommand('E', buzzer);
    }
  }

  void _jouer(void Function() enLocal, String action) {
    if (versLApplication) {
      enLocal();
    } else {
      // Les actions de catégorie ne visent aucun buzzer ; le firmware les
      // reconnaît sans index (voir BleLink::pollKey).
      ble.sendSoundCommand(action, -1);
    }
  }
}
