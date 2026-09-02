import 'dart:async';

import 'package:flutter/foundation.dart';

import 'protocol.dart';

// Rejoue des parties sans buzzer branché.
//
// POURQUOI. Les écrans de jeu ne s'affichent que pendant les phases
// correspondantes. Sans matériel, aucune de ces phases n'arrive jamais :
// travailler l'interface d'un Réflexe ou d'un Duel se ferait à l'aveugle, et
// se relirait à l'aveugle. Le simulateur rend ces écrans regardables.
//
// IL PARLE LE VRAI PROTOCOLE. Chaque étape est une ligne telle que le
// firmware l'enverrait, injectée par le même chemin que le lien Bluetooth
// (GameState.injecter). Un simulateur qui écrirait directement dans les
// champs de l'état prouverait seulement que les écrans savent afficher des
// champs. Ici, il prouve qu'ils savent afficher ce que le Mega envoie, et
// le jour où un message du firmware change, la simulation se met à mentir
// exactement là où l'application se mettrait à mentir.
//
// Les scénarios sont écrits à partir des `ble.send` de chaque jeu côté
// firmware, pas de mémoire.

class Etape {
  const Etape(this.ligne, {this.apres = const Duration(milliseconds: 900)});
  final String ligne;
  final Duration apres;
}

class Scenario {
  const Scenario(this.nom, this.description, this.etapes);
  final String nom;
  final String description;
  final List<Etape> etapes;
}

int _phase(String nom) => kPhaseNames.indexOf(nom);

// --- Scénarios ------------------------------------------------------------

// Réflexe. Trois manches : une gagnée nettement, une avec deux faux départs,
// une où personne ne buzze. Puis la fin de partie avec un record battu.
//
// Les faux départs et la manche nulle ne sont pas là pour faire joli : ce
// sont les cas que la console doit savoir raconter et qu'une partie
// « normale » ne montrerait jamais.
const _reflexe = Scenario(
  'Réflexe',
  'Trois manches : une nette, une avec deux faux départs, une où personne ne buzze.',
  [
    Etape('GAME|7'),
    Etape('PRESENT|1|1|1|1'),
    Etape('STATE|6', apres: Duration(milliseconds: 600)),           // INTRO
    Etape('GSCORE|0|0|0|0'),
    Etape('GROUND|0|3'),
    Etape('RFLX|-1|0|0'),

    Etape('GROUND|1|3'),
    Etape('STATE|22', apres: Duration(milliseconds: 1600)),         // REFLEX_ARM
    Etape('STATE|23', apres: Duration(milliseconds: 1400)),         // REFLEX_GO
    Etape('BUZZ|1'),
    Etape('GSCORE|0|1|0|0'),
    Etape('RFLX|1|214|214'),
    Etape('STATE|24', apres: Duration(milliseconds: 2600)),         // REFLEX_RESULT

    Etape('GROUND|2|3'),
    Etape('STATE|22', apres: Duration(milliseconds: 1500)),
    Etape('RFLXF|0', apres: Duration(milliseconds: 700)),
    Etape('RFLXF|3', apres: Duration(milliseconds: 500)),
    Etape('STATE|23', apres: Duration(milliseconds: 900)),
    Etape('BUZZ|2'),
    Etape('GSCORE|0|1|1|0'),
    Etape('RFLX|2|287|214'),
    Etape('STATE|24', apres: Duration(milliseconds: 2600)),

    Etape('GROUND|3|3'),
    Etape('STATE|22', apres: Duration(milliseconds: 1500)),
    Etape('STATE|23', apres: Duration(milliseconds: 1200)),
    Etape('RFLX|-1|0|214'),
    Etape('STATE|24', apres: Duration(milliseconds: 2600)),

    Etape('RFLXR|214|198|0'),
    Etape('GOVER|1|0'),
    Etape('STATE|25', apres: Duration(milliseconds: 400)),          // REFLEX_OVER
  ],
);

const kScenarios = <Scenario>[_reflexe];

// --- Moteur ---------------------------------------------------------------

class Simulateur extends ChangeNotifier {
  Simulateur(this._game);

  final GameState _game;

  Scenario? _encours;
  int _etape = 0;
  Timer? _timer;

  Scenario? get encours => _encours;
  int get etape => _etape;
  int get total => _encours?.etapes.length ?? 0;
  bool get actif => _encours != null;

  void jouer(Scenario scenario) {
    arreter();
    _encours = scenario;
    _etape = 0;
    notifyListeners();
    _suivante();
  }

  void arreter() {
    _timer?.cancel();
    _timer = null;
    if (_encours != null) {
      _encours = null;
      _etape = 0;
      notifyListeners();
    }
  }

  void _suivante() {
    final scenario = _encours;
    if (scenario == null) return;
    if (_etape >= scenario.etapes.length) {
      // On laisse le dernier écran affiché : c'est souvent celui qu'on veut
      // regarder. Seul le déroulement s'arrête.
      _timer = null;
      notifyListeners();
      return;
    }
    final etape = scenario.etapes[_etape];
    _game.injecter(etape.ligne);
    _etape++;
    notifyListeners();
    _timer = Timer(etape.apres, _suivante);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// Remet l'état de partie au repos, comme au retour au menu du buzzer.
void remettreAuMenu(GameState game) {
  game.injecter('STATE|${_phase('CONFIGURATION')}');
}
