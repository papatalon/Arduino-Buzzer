import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';

const _teamNamesKey = 'team_names';

// Noms d'équipe donnés aux quatre buzzers. Purement local à l'app : le
// firmware continue de raisonner en couleurs (c'est le câblage physique),
// seule la présentation change.
//
// Un nom vide retombe sur la couleur, ce qui évite un état « sans nom » :
// avant d'avoir baptisé les équipes, la console reste lisible.
class TeamNames extends ChangeNotifier {
  final List<String> _names = ['', '', '', ''];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_teamNamesKey);
    if (saved != null && saved.length == 4) {
      for (var i = 0; i < 4; i++) {
        _names[i] = saved[i];
      }
      notifyListeners();
    }
  }

  // Nom à afficher : celui de l'équipe si donné, sinon la couleur.
  String nameFor(int index) {
    if (index < 0 || index >= 4) return '';
    return _names[index].isNotEmpty ? _names[index] : kBuzzerColors[index].name;
  }

  // Nom brut, vide s'il n'a jamais été saisi — pour ne pas préremplir un
  // champ de saisie avec « Rouge », que l'opérateur devrait effacer.
  String rawName(int index) => (index < 0 || index >= 4) ? '' : _names[index];

  bool get anyCustom => _names.any((n) => n.isNotEmpty);

  Future<void> setName(int index, String name) async {
    if (index < 0 || index >= 4) return;
    _names[index] = name.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_teamNamesKey, _names);
  }

  Future<void> clearAll() async {
    for (var i = 0; i < 4; i++) {
      _names[i] = '';
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_teamNamesKey, _names);
  }

  // Pour l'instantané envoyé à la fenêtre de l'écran public, qui ne
  // partage pas la mémoire de la fenêtre principale.
  List<String> get all => List<String>.unmodifiable(_names);
}
