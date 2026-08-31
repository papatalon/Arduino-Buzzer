import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _eventLogoKey = 'event_logo_path';

// Logo de la soirée affiché en haut de l'écran public. Le design le prévoyait
// depuis le début (design_handoff_buzzer_console/README.md : « emplacement à
// remplir par l'utilisateur, prévoir un import d'image dans les réglages »)
// mais rien ne le remplissait, d'où la case tiretée vide que le client a vue.
//
// C'est un chemin de fichier qu'on garde, pas l'image elle-même : les deux
// fenêtres (console et écran public) tournent sur la même machine, donc le
// chemin suffit à les mettre d'accord sans copier des octets dans
// l'instantané à chaque rafraîchissement.
class EventLogo extends ChangeNotifier {
  String? _path;

  // Null quand rien n'est choisi, ou quand le fichier a disparu depuis (image
  // déplacée, clé USB retirée) : dans les deux cas l'écran public ne doit pas
  // réserver de place vide, il n'affiche simplement rien.
  String? get path => _path;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_eventLogoKey);
    if (saved != null && saved.isNotEmpty && File(saved).existsSync()) {
      _path = saved;
      notifyListeners();
    }
  }

  // Ouvre le sélecteur de fichiers du système. Retourne faux si l'opérateur
  // a fermé la fenêtre sans rien choisir.
  Future<bool> pick() async {
    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return false;
    await _save(file.path);
    return true;
  }

  Future<void> clear() => _save(null);

  Future<void> _save(String? value) async {
    _path = (value != null && value.isNotEmpty) ? value : null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_path == null) {
      await prefs.remove(_eventLogoKey);
    } else {
      await prefs.setString(_eventLogoKey, _path!);
    }
  }
}
