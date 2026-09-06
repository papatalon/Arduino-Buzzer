import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'questionnaire.dart';

// CE QU'ON A DEMANDÉ AU DERNIER TIRAGE, et qu'on redemandera sans doute.
//
// Une soirée, c'est la même tablée toute la veillée : mêmes enfants, même
// niveau, souvent les mêmes thématiques. Recocher quatre cases entre chaque
// manche, devant la salle qui attend, était une corvée que rien ne
// justifiait — d'autant que les réglages ne survivaient même pas à un
// aller-retour vers l'écran Questions, puisqu'ils vivaient dans l'état d'un
// widget.
//
// ILS SURVIVENT MAINTENANT À LA FERMETURE DE L'APPLICATION. C'est le cas qui
// compte : la soirée se prépare l'après-midi, et on rouvre la console le soir
// venu.
//
// CE QUI N'EST PAS RETENU : les questions déjà posées. Elles vivent dans
// TirageQuestions et meurent avec la session, ce qui est juste — deux
// soirées différentes ont le droit à la même bonne question.
class CriteresTirage extends ChangeNotifier {
  static const _cleThemes = 'tirage_themes';
  static const _cleTranches = 'tirage_tranches';
  static const _cleNiveaux = 'tirage_niveaux';
  static const _cleNombre = 'tirage_nombre';

  // Vingt questions font une manche d'une trentaine de minutes.
  static const nombreParDefaut = 20;

  // Vides = sans filtre. C'est l'état normal et le plus large.
  final Set<String> themes = {};
  final Set<Tranche> tranches = {};
  final Set<int> niveaux = {};
  int nombre = nombreParDefaut;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themes
      ..clear()
      ..addAll(prefs.getStringList(_cleThemes) ?? const []);
    tranches
      ..clear()
      ..addAll([
        for (final nom in prefs.getStringList(_cleTranches) ?? const [])
          for (final t in Tranche.values)
            if (t.name == nom) t,
      ]);
    niveaux
      ..clear()
      ..addAll([
        for (final n in prefs.getStringList(_cleNiveaux) ?? const [])
          if (int.tryParse(n) case final v? when kNomsNiveaux.containsKey(v)) v,
      ]);
    final n = prefs.getInt(_cleNombre);
    nombre = (n != null && n >= 1 && n <= 99) ? n : nombreParDefaut;
    notifyListeners();
  }

  void basculerTheme(String nom) {
    themes.contains(nom) ? themes.remove(nom) : themes.add(nom);
    _enregistrer();
  }

  void basculerTranche(Tranche t) {
    tranches.contains(t) ? tranches.remove(t) : tranches.add(t);
    _enregistrer();
  }

  void basculerNiveau(int n) {
    niveaux.contains(n) ? niveaux.remove(n) : niveaux.add(n);
    _enregistrer();
  }

  void reglerNombre(int n) {
    final borne = n.clamp(1, 99);
    if (borne == nombre) return;
    nombre = borne;
    _enregistrer();
  }

  /// UNE THÉMATIQUE PEUT DISPARAÎTRE DE LA BANQUE d'une version à l'autre :
  /// elles se renomment, se fusionnent, et un nom retenu l'hiver dernier peut
  /// ne plus rien désigner. Coché, il ne laisserait passer aucune question,
  /// et l'écran annoncerait « aucune question ne répond à ces critères » sans
  /// montrer nulle part d'où vient le filtre fautif : sa case n'existe plus.
  ///
  /// Appelé dès que la banque est lue, pas au chargement : c'est elle qui dit
  /// ce qui existe encore.
  void oublierThemesInconnus(Iterable<String> connus) {
    if (themes.isEmpty) return;
    final vivants = connus.toSet();
    final morts = themes.where((t) => !vivants.contains(t)).toList();
    if (morts.isEmpty) return;
    themes.removeAll(morts);
    _enregistrer();
  }

  Future<void> _enregistrer() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cleThemes, themes.toList());
    await prefs.setStringList(
        _cleTranches, [for (final t in tranches) t.name]);
    await prefs.setStringList(_cleNiveaux, [for (final n in niveaux) '$n']);
    await prefs.setInt(_cleNombre, nombre);
  }
}
