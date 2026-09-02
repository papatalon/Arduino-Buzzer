import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio/sonorisation.dart';
import 'moteur_quiz.dart';

// LE TIRAGE AU SORT ANIMÉ : un chenillard qui ralentit, calé sur son bruitage.
//
// Repris de `Buzzer::ledChaseEnabled` côté firmware, avec ses constantes.
// L'intervalle part très court et s'allonge exponentiellement, comme une roue
// de loterie qui perd sa vitesse. Le son du dossier 06 fait exactement ça :
// des clics rapides qui s'espacent. Les deux doivent ralentir ensemble, sinon
// l'effet tombe à plat.
//
// Deux moments s'en servent, et c'est pour ça que ce n'est pas enfoui dans un
// écran : mélanger les sons des buzzers, et désigner le joueur qui ouvre une
// manche de Vol. En mode autonome le Mega les anime tous les deux ; en mode
// application c'est à elle de le faire, puisque le buzzer n'a plus d'état de
// jeu.
class AnimationTirage extends ChangeNotifier {
  AnimationTirage({required this.ble, required this.sons});

  final CommandesBuzzer ble;
  final Sonorisation sons;

  /// Vitesse de départ, calée sur le premier clic du bruitage.
  static const _pasInitialMs = 40;

  /// Vitesse la plus lente, atteinte en fin d'animation.
  static const _pasMaxMs = 300;

  /// Constante de ralentissement.
  static const _tauMs = 3600.0;

  /// Durée de repli, quand la fin du son n'est pas observable.
  ///
  /// Le firmware s'arrête sur la fin réelle du bruitage, et l'application en
  /// fait autant quand c'est elle qui joue. Mais si le son sort du buzzer, sa
  /// broche BUSY n'est pas rapportée vers l'application : elle ne peut alors
  /// que borner. Généreux à dessein : mieux vaut quelques lumières de trop
  /// que des lumières qui s'arrêtent pendant que ça joue encore.
  static const _dureeMs = 7000;

  /// Garde-fou absolu, pour le cas ou un son ne se terminerait jamais. Il ne
  /// doit PAS servir de duree normale : il l'a fait, et les lumieres
  /// s'arretaient au milieu du bruitage.
  static const _securiteMs = 30000;

  /// Le son met un instant à démarrer : sans ce délai, on le croirait fini
  /// avant d'avoir commencé. Même précaution que INTRO_START_MS côté
  /// firmware.
  static const _avantDeTesterMs = 400;

  Timer? _minuteur;
  bool get enCours => _minuteur != null;

  /// Le buzzer allume a cet instant, ou null si rien ne tourne.
  ///
  /// Expose pour que l'ecran puisse refleter le chenillard PHYSIQUE : les
  /// deux montrent la meme chose au meme moment, sinon l'ecran raconte une
  /// autre histoire que la table.
  int? allume;

  /// Lance l'animation sur les buzzers [presents]. [surFin] est appelé une
  /// seule fois, à la fin, LED éteintes.
  void lancer({required List<bool> presents, required VoidCallback surFin}) {
    arreter();
    final pool = [for (var i = 0; i < 4; i++) if (presents[i]) i];
    if (pool.isEmpty) {
      surFin();
      return;
    }

    sons.tirage();
    final debut = DateTime.now();
    var index = 0;
    var prochainPas = _pasInitialMs;

    void pas() {
      final ecoule = DateTime.now().difference(debut).inMilliseconds;
      // On suit le VRAI son quand on peut, plutôt qu'une durée devinée : le
      // chenillard et le bruitage doivent s'arrêter ensemble.
      // Quand la fin du son est observable, elle FAIT FOI : la duree de repli
      // ne doit pas ecourter une animation qu'on sait suivre. C'est ce qu'elle
      // faisait, et le chenillard s'arretait pendant que le bruitage jouait
      // encore.
      final fini = ecoule >= _avantDeTesterMs &&
          (sons.finDesSonsConnue ? !sons.sonEnCours : ecoule >= _dureeMs);
      if (fini || ecoule >= _securiteMs) {
        arreter();
        ble.allumerLeds(0);
        surFin();
        return;
      }
      allume = pool[index % pool.length];
      ble.allumerLeds(1 << allume!);
      index++;
      notifyListeners();
      // Croissance exponentielle de l'intervalle, plafonnée : la roue ralentit
      // vite au début, puis de moins en moins.
      final facteur = exp(ecoule / _tauMs);
      prochainPas = min(_pasMaxMs, (_pasInitialMs * facteur).round());
      _minuteur = Timer(Duration(milliseconds: prochainPas), pas);
    }

    _minuteur = Timer(Duration(milliseconds: prochainPas), pas);
    // Notifie APRES avoir arme le minuteur : enCours doit deja etre vrai
    // quand l'ecran se reconstruit, sinon il se croit au repos.
    notifyListeners();
  }

  void arreter() {
    final tournait = _minuteur != null;
    _minuteur?.cancel();
    _minuteur = null;
    allume = null;
    if (tournait) notifyListeners();
  }
}


