import 'dart:math';

import 'catalogue.dart';
import 'questionnaire.dart';

// UN QUESTIONNAIRE CONSTRUIT SUR PLACE, pour une partie et une seule.
//
// Plutôt que de choisir un questionnaire tout fait, l'animateur choisit un
// périmètre (tout, ou une collection) et un nombre de questions. Le tirage
// compose alors une manche qui n'existera qu'une fois.
//
// POURQUOI ON NE CHARGE PAS TOUT. Les 3000 questions du catalogue vivent dans
// 125 fichiers séparés, dont seuls ceux qui ont été synchronisés sont sur
// disque ; les autres se lisent en ligne, un par un. Charger le catalogue
// entier pour en tirer vingt questions coûterait 125 requêtes et rendrait le
// tirage inutilisable dans une salle sans wifi.
//
// On tire donc des QUESTIONNAIRES au hasard dans le périmètre, puis des
// questions dedans, jusqu'à en avoir assez : quelques fichiers au lieu de cent
// vingt-cinq. Les questionnaires font tous à peu près la même longueur, donc
// le tirage reste équilibré.
//
// LES DOUBLONS SONT LE VRAI PIÈGE. Une même question se retrouve dans
// plusieurs questionnaires (les mélanges reprennent celles des collections
// thématiques). Deux fois la même question dans une soirée, c'est un blanc
// gênant et un point donné pour rien. On compare donc les énoncés normalisés,
// pas les objets.
class TirageQuestions {
  TirageQuestions({required this.catalogue, Random? hasard})
      : _hasard = hasard ?? Random();

  final CatalogueStore catalogue;
  final Random _hasard;

  /// Questionnaires déjà lus pendant cette séance : un tirage en enchaîne
  /// plusieurs, et relire le même fichier deux fois serait du gaspillage.
  final Map<String, Questionnaire> _lus = {};

  /// Ce qu'on a déjà posé ce soir, pour ne jamais reposer la même question.
  /// Conservé entre deux tirages : deux manches de suite dans le même
  /// périmètre ne doivent pas se recouper.
  final Set<String> _dejaPosees = {};

  /// Nombre de questionnaires lus lors du dernier tirage. Pour l'affichage,
  /// et pour ne pas laisser croire que rien ne s'est passé.
  int dernierNombreDeFichiers = 0;

  /// Message quand le tirage n'a pas pu aboutir. Null si tout va bien.
  String? derniereErreur;

  /// La clé d'unicité : l'énoncé, débarrassé de sa casse, de ses espaces et
  /// de sa ponctuation de fin. Deux questionnaires qui reprennent la même
  /// question l'écrivent parfois avec un point d'interrogation en plus.
  static String cle(QuizQuestion q) => q.question
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[?!.…\s]+$'), '')
      .trim();

  void oublierCeQuiAEtePose() => _dejaPosees.clear();

  /// Les périmètres proposables : toutes les collections du catalogue, avec
  /// de quoi les afficher.
  List<CatalogueCollection> get collections => catalogue.catalogue.collections;

  /// Compose une manche de [nombre] questions dans le périmètre.
  ///
  /// [collection] à null veut dire « toutes les questions ». Retourne null si
  /// rien n'a pu être lu ; retourne une manche plus courte que demandé si le
  /// périmètre est trop petit, plutôt que d'échouer : mieux vaut douze
  /// questions qu'aucune.
  /// [niveaux] et [tranches] vides veulent dire « sans filtre ». Une question
  /// qui ne porte pas de niveau, ou pas de tranche, passe toujours : un
  /// questionnaire écrit à la main ne se prononce pas, et l'écarter d'un
  /// filtre reviendrait à le punir de ne rien avoir déclaré.
  Future<Questionnaire?> composer({
    String? collection,
    Set<int> niveaux = const {},
    Set<Tranche> tranches = const {},
    required int nombre,
  }) async {
    derniereErreur = null;
    dernierNombreDeFichiers = 0;

    bool retenue(QuizQuestion q) {
      if (!q.isUsable) return false;
      if (niveaux.isNotEmpty && q.niveau != null && !niveaux.contains(q.niveau)) {
        return false;
      }
      if (tranches.isNotEmpty &&
          q.ages.isNotEmpty &&
          q.ages.intersection(tranches).isEmpty) {
        return false;
      }
      return true;
    }

    final pioche = _piocheMelangee(collection);
    if (pioche.isEmpty) {
      derniereErreur = collection == null
          ? 'Le catalogue est vide.'
          : "La collection « $collection » ne contient aucun questionnaire.";
      return null;
    }

    final retenues = <QuizQuestion>[];
    final vues = <String>{};

    for (final entree in pioche) {
      if (retenues.length >= nombre) break;
      final q = await _lire(entree);
      if (q == null) continue;
      dernierNombreDeFichiers++;

      // Les questions du fichier sont mélangées aussi : sans ça, une manche
      // courte prendrait toujours les premières du questionnaire.
      final candidates = q.questions.where(retenue).toList()..shuffle(_hasard);
      for (final c in candidates) {
        if (retenues.length >= nombre) break;
        final k = cle(c);
        if (k.isEmpty || vues.contains(k) || _dejaPosees.contains(k)) continue;
        vues.add(k);
        retenues.add(c.copy());
      }
    }

    final filtre = niveaux.isNotEmpty || tranches.isNotEmpty;
    if (retenues.isEmpty) {
      // Distinguer les deux échecs : un périmètre illisible et un filtre trop
      // serré n'appellent pas le même geste. Le premier se règle en se
      // connectant, le second en relâchant une case.
      derniereErreur = filtre
          ? 'Aucune question ne répond à ces critères. Élargissez le niveau ou '
              "la tranche d'âge."
          : catalogue.lastError ??
              "Aucune question n'a pu être lue dans ce périmètre.";
      return null;
    }

    _dejaPosees.addAll(vues);
    return Questionnaire(
      title: collection == null
          ? 'Questions au hasard'
          : 'Au hasard : $collection',
      note: retenues.length < nombre
          ? (filtre
              ? 'Seulement ${retenues.length} questions répondaient aux critères.'
              : 'Le périmètre ne contenait que ${retenues.length} questions.')
          : '',
      collection: collection ?? '',
      questions: retenues,
    );
  }

  /// Une seule question, pour départager. Jamais une de celles déjà posées.
  Future<QuizQuestion?> questionDeBris({String? collection}) async {
    final compose = await composer(collection: collection, nombre: 1);
    if (compose == null || compose.questions.isEmpty) return null;
    return compose.questions.first;
  }

  List<CatalogueEntry> _piocheMelangee(String? collection) {
    final entrees = collection == null
        ? List<CatalogueEntry>.of(catalogue.catalogue.entries)
        : catalogue.entriesOf(collection);
    final liste = List<CatalogueEntry>.of(entrees)..shuffle(_hasard);
    return liste;
  }

  Future<Questionnaire?> _lire(CatalogueEntry entree) async {
    final connu = _lus[entree.id];
    if (connu != null) return connu;
    // « garder » : ce qui sert à jouer est mis en cache, ce qu'on ouvre pour
    // regarder ne l'est pas. Une soirée jouée avec du réseau laisse donc de
    // quoi rejouer la même sans, avec les questions à jour plutôt que celles
    // du build.
    final charge = await catalogue.load(entree, garder: true);
    if (charge != null) _lus[entree.id] = charge;
    return charge;
  }
}
