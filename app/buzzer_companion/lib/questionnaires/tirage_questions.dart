import 'dart:math';

import 'banque.dart';
import 'questionnaire.dart';

// UNE MANCHE COMPOSÉE SUR PLACE, pour une partie et une seule.
//
// C'est devenu la façon normale de jouer. L'animateur dit ce qu'il a devant
// lui — des enfants, un mélange, des connaisseurs — et la manche se compose.
// Elle n'existera qu'une fois.
//
// CE QUI A DISPARU ET POURQUOI. Le tirage piochait dans 283 questionnaires
// prédécoupés, en évitant de tous les charger : quelques fichiers plutôt que
// cent vingt-cinq requêtes. La banque tient maintenant dans un seul fichier
// de 570 ko, lu une fois au démarrage, et cette gymnastique n'a plus lieu
// d'être. Le tirage voit toutes les questions à la fois, ce qui lui permet de
// filtrer sur n'importe quelle combinaison de critères — chose impossible
// quand il fallait deviner quel fichier contenait des questions faciles pour
// enfants en histoire.
//
// LES DOUBLONS RESTENT LE VRAI PIÈGE, même si la banque ne contient plus
// qu'un exemplaire de chaque question : deux manches de suite dans le même
// périmètre ne doivent pas se recouper. Deux fois la même question dans une
// soirée, c'est un blanc gêné et un point donné pour rien.
class TirageQuestions {
  TirageQuestions({required this.banque, Random? hasard})
      : _hasard = hasard ?? Random();

  final BanqueStore banque;
  final Random _hasard;

  /// Ce qu'on a déjà posé ce soir. Conservé entre deux tirages.
  final Set<String> _dejaPosees = {};

  /// Message quand le tirage n'a pas pu aboutir. Null si tout va bien.
  String? derniereErreur;

  /// La clé d'unicité : l'énoncé, débarrassé de sa casse, de ses espaces et
  /// de sa ponctuation de fin.
  static String cle(QuizQuestion q) => q.question
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[?!.…\s]+$'), '')
      .trim();

  void oublierCeQuiAEtePose() => _dejaPosees.clear();

  List<Facette> get themes => banque.banque.themes;

  /// Combien de questions répondent à ces critères, avant même de tirer.
  /// Affiché à côté des cases : un filtre qui ne laisse que huit questions
  /// doit se voir AVANT de composer, pas après.
  int compter({
    Set<String> themes = const {},
    Set<int> niveaux = const {},
    Set<Tranche> tranches = const {},
  }) =>
      banque.banque.questions
          .where((q) => _retenue(q, themes, niveaux, tranches))
          .length;

  /// Un filtre vide veut dire « sans filtre ». Une question qui ne porte pas
  /// de niveau, ou pas de tranche, passe toujours : un questionnaire écrit à
  /// la main ne se prononce pas, et l'écarter reviendrait à le punir de son
  /// silence.
  bool _retenue(
    QuizQuestion q,
    Set<String> themes,
    Set<int> niveaux,
    Set<Tranche> tranches,
  ) {
    if (!q.isUsable) return false;
    // Les thématiques cochées se cumulent en OU : cocher « Québec » et
    // « Spécial Noël » demande les questions de l'une OU de l'autre, pas leur
    // intersection, qui serait presque toujours vide.
    //
    // Il y avait ici une seconde condition sur l'ancien axe des étiquettes.
    // Elle ne pouvait plus être vraie sans que la thématique du fichier le
    // soit déjà : chaque question porte celle de son fichier, et un test de
    // banque_embarquee_test.dart garde qu'aucune n'en est dépourvue.
    if (themes.isNotEmpty && !q.themes.any(themes.contains)) return false;
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

  /// Compose une manche de [nombre] questions.
  ///
  /// Retourne une manche plus courte que demandé si les critères ne laissent
  /// pas assez de questions, plutôt que d'échouer : mieux vaut douze
  /// questions qu'aucune, et la note le dit.
  Questionnaire? composer({
    Set<String> themes = const {},
    Set<int> niveaux = const {},
    Set<Tranche> tranches = const {},
    required int nombre,
  }) {
    derniereErreur = null;

    if (banque.banque.isEmpty) {
      derniereErreur = banque.lastError ?? "La banque de questions est vide.";
      return null;
    }

    final candidates = banque.banque.questions
        .where((q) => _retenue(q, themes, niveaux, tranches))
        .where((q) => !_dejaPosees.contains(cle(q)))
        .toList()
      ..shuffle(_hasard);

    if (candidates.isEmpty) {
      final filtre = themes.isNotEmpty ||
          niveaux.isNotEmpty ||
          tranches.isNotEmpty;
      // Distinguer les deux échecs : « tout a déjà été posé » et « ces
      // critères ne donnent rien » n'appellent pas le même geste.
      derniereErreur = _dejaPosees.isNotEmpty && !filtre
          ? "Toutes les questions ont déjà été posées ce soir."
          : filtre
              ? 'Aucune question ne répond à ces critères. Élargissez la '
                  "sélection, ou le niveau et la tranche d'âge."
              : "Aucune question à poser.";
      return null;
    }

    final oubliees = <Tranche>[];
    final retenues = _repartir(candidates, nombre, tranches, oubliees)
        .map((q) => q.copy())
        .toList();
    _dejaPosees.addAll(retenues.map(cle));

    return Questionnaire(
      title: _titre(themes),
      note: _note(retenues.length, nombre, oubliees),
      questions: retenues,
    );
  }

  // Ce que la note doit dire, et rien de plus. Une manche tronquée et une
  // tranche laissée de côté se découvrent autrement en pleine soirée : la
  // première quand la manche s'arrête trop tôt, la seconde jamais.
  String _note(int obtenu, int demande, List<Tranche> oubliees) {
    final bouts = <String>[
      if (obtenu < demande)
        'Seulement $obtenu questions répondaient aux critères.',
      if (oubliees.isNotEmpty)
        'Rien pour ${_enumerer(oubliees.map((t) => kNomsTranches[t]!))} '
            'dans cette sélection.',
    ];
    return bouts.join(' ');
  }

  static String _enumerer(Iterable<String> mots) {
    final l = mots.toList();
    if (l.length <= 1) return l.join();
    return '${l.sublist(0, l.length - 1).join(', ')} et ${l.last}';
  }

  // --------------------------------------------------------- La répartition

  // BRASSER PUIS COUPER NE DONNE PAS UNE MANCHE ÉQUILIBRÉE, et c'est le
  // hasard qui décide de quoi elle a l'air.
  //
  // Mesuré sur 4000 manches de 25 tirées ainsi : 1,3 question par manche
  // écrite pour le monde des enfants, et UNE MANCHE SUR QUATRE sans aucune.
  // Rien ne le signalait : la manche était pleine, les questions étaient
  // bonnes, et l'enfant à la table regardait passer vingt-cinq questions qui
  // ne venaient pas de chez lui. C'est le déséquilibre du bassin qui
  // ressortait tel quel (192 questions enfants contre 1553 adultes), parce
  // qu'un tirage uniforme reproduit fidèlement les proportions de ce dans
  // quoi il pioche.
  //
  // DEUX RÈGLES, ET ELLES NE SE RESSEMBLENT PAS.
  //
  // Les CATÉGORIES se répartissent au prorata de leur stock : Culture pop en
  // porte 428 et Cinéma 271, la manche doit s'en ressentir. Le tirage
  // uniforme le faisait déjà, mais en espérance seulement, ce qui laissait
  // passer des manches sans une seule question de Cinéma.
  //
  // Les TRANCHES reçoivent un PLANCHER : le prorata les servirait mal, parce
  // que le stock d'une tranche ne dit pas combien de gens de cet âge sont
  // dans la pièce. Le plancher n'occupe jamais plus de la moitié de la
  // manche, et il CÈDE quand le stock n'y est pas : Géographie n'a aucune
  // question écrite pour les enfants, et ce n'est pas une raison pour
  // refuser de composer une manche de géographie.
  List<QuizQuestion> _repartir(
    List<QuizQuestion> bassin,
    int nombre,
    Set<Tranche> demandees,
    List<Tranche> oubliees,
  ) {
    // Brassé une fois : tout ce qui suit départage à égalité en prenant le
    // premier venu dans cet ordre, ce qui revient à tirer au sort parmi les
    // ex aequo.
    final restant = List<QuizQuestion>.from(bassin)..shuffle(_hasard);
    final choisies = <QuizQuestion>[];
    final quotas = _quotasEtiquettes(bassin, nombre);
    final pris = <String, int>{};

    // Combien il manque à cette étiquette pour atteindre sa cible. Négatif
    // quand elle déborde déjà, ce qui la fait passer en dernier.
    int manque(String etiquette) =>
        (quotas[etiquette] ?? 0) - (pris[etiquette] ?? 0);

    // La question la plus utile parmi celles proposées : celle dont la
    // étiquette est la plus en retard. À égalité, la première dans l'ordre
    // brassé.
    QuizQuestion? meilleure(Iterable<QuizQuestion> parmi) {
      QuizQuestion? gagnante;
      var meilleurEcart = -1 << 30;
      for (final q in parmi) {
        final ecart = manque(q.etiquette);
        if (ecart > meilleurEcart) {
          meilleurEcart = ecart;
          gagnante = q;
        }
      }
      return gagnante;
    }

    void prendre(QuizQuestion q) {
      choisies.add(q);
      restant.remove(q);
      pris[q.etiquette] = (pris[q.etiquette] ?? 0) + 1;
    }

    // Aucune tranche cochée veut dire « tout le monde », pas « peu importe » :
    // c'est l'état par défaut de l'écran, et c'est justement là que le
    // déséquilibre passait inaperçu.
    final enJeu = demandees.isEmpty ? Tranche.values.toSet() : demandees;

    // UNE SEULE TRANCHE, PAS DE PLANCHER. Cocher « aînés » tout seul écarte
    // déjà ce qui ne leur est pas destiné ; leur imposer en plus un quota de
    // questions écrites pour eux reviendrait à décider à leur place qu'ils ne
    // veulent rien de général. Le plancher répond à une demande de MÉLANGE.
    if (enJeu.length >= 2) {
      // Jamais plus de la moitié de la manche en planchers : le reste doit
      // rester libre pour le prorata des étiquettes. Pour une manche courte,
      // la division tombe à zéro d'elle-même, et une question de bris ne se
      // retrouve pas à devoir servir une tranche en particulier.
      final plancher = nombre ~/ (2 * enJeu.length);
      // LA PLUS RARE D'ABORD. Les 192 questions enfants doivent être servies
      // avant que les 1553 questions adultes ne vident le bassin qu'elles
      // partagent : beaucoup de questions portent deux ou trois tranches, et
      // celle qui sert en premier prend dans le tas commun.
      final ordre = enJeu.toList()
        ..sort((a, b) => _stock(bassin, a).compareTo(_stock(bassin, b)));
      for (final t in ordre) {
        // Ce qu'une tranche a déjà reçu par ricochet compte : une question
        // ados + adultes remplit les deux planchers à la fois.
        var acquis = choisies.where((q) => q.ages.contains(t)).length;
        while (acquis < plancher && choisies.length < nombre) {
          final q = meilleure(restant.where((e) => e.ages.contains(t)));
          if (q == null) break; // Le stock n'y est pas : le plancher cède.
          prendre(q);
          acquis++;
        }
        if (acquis == 0 && plancher > 0) oubliees.add(t);
      }
      // AUCUNE TRANCHE SERVIE VEUT DIRE QUE LE BASSIN N'EN PARLE PAS. Un
      // questionnaire écrit à la main ne cote rien, et annoncer « rien pour
      // les enfants, les ados, les adultes et les aînés » serait un
      // avertissement sur quatre lignes pour dire que l'axe ne s'applique
      // pas. On ne signale un trou que là où les autres tranches, elles, ont
      // été servies.
      if (oubliees.length == enJeu.length) oubliees.clear();
    }

    // Le reste au prorata des étiquettes, en rattrapant celles que les
    // planchers ont laissées derrière.
    while (choisies.length < nombre && restant.isNotEmpty) {
      prendre(meilleure(restant)!);
    }
    return choisies;
  }

  int _stock(List<QuizQuestion> bassin, Tranche t) =>
      bassin.where((q) => q.ages.contains(t)).length;

  // Combien de questions chaque étiquette doit fournir, au prorata de son
  // stock dans le bassin filtré.
  //
  // Onze étiquettes valant chacune 2,3 questions donnent 22 places sur 25
  // demandées : il reste toujours des miettes à distribuer, et c'est là que
  // tout se joue.
  //
  // LES DONNER AUX PLUS FORTS RESTES SERAIT UN BIAIS PERMANENT. Québec vaut
  // 2,50 questions et Histoire 2,45, pour 2 % d'écart de stock. La règle du
  // plus fort reste donne la place à Québec, et elle la lui donne À CHAQUE
  // MANCHE, parce que le calcul repart des mêmes chiffres : Québec finit la
  // soirée à trois questions par manche et Histoire à deux, soit 40 %
  // d'écart né d'un écart de stock de 2 %. L'arrondi ne se compense jamais,
  // il s'accumule.
  //
  // LES PLACES SE TIRENT DONC AU SORT, avec une chance égale au reste :
  // Québec obtient sa troisième question une manche sur deux, Histoire un
  // peu moins souvent, et sur une soirée chacune retombe sur son vrai
  // prorata. Balayage à départ aléatoire plutôt que tirages indépendants,
  // pour que le compte tombe pile sur le nombre demandé.
  Map<String, int> _quotasEtiquettes(List<QuizQuestion> bassin, int nombre) {
    final stock = <String, int>{};
    for (final q in bassin) {
      stock[q.etiquette] = (stock[q.etiquette] ?? 0) + 1;
    }
    final quotas = <String, int>{};
    final restes = <String, double>{};
    var attribuees = 0;
    for (final e in stock.entries) {
      final exact = nombre * e.value / bassin.length;
      quotas[e.key] = exact.floor();
      restes[e.key] = exact - exact.floor();
      attribuees += exact.floor();
    }

    final places = nombre - attribuees;
    if (places <= 0) return quotas;

    // Ordre brassé : sans lui, deux étiquettes aux restes voisins seraient
    // toujours départagées dans le même sens par le balayage.
    final ordre = restes.keys.toList()..shuffle(_hasard);
    var curseur = _hasard.nextDouble();
    var cumul = 0.0;
    var donnees = 0;
    for (final nom in ordre) {
      cumul += restes[nom]!;
      if (donnees < places && curseur < cumul) {
        quotas[nom] = quotas[nom]! + 1;
        curseur += 1.0;
        donnees++;
      }
    }
    // Filet contre l'arithmétique flottante : la somme des restes vaut le
    // nombre de places à un cheveu près, et ce cheveu peut laisser la
    // dernière place non attribuée. Une manche courte d'une question sans
    // raison serait invisible et fausse.
    if (donnees < places) {
      final parReste = restes.keys.toList()
        ..sort((a, b) => restes[b]!.compareTo(restes[a]!));
      for (final nom in parReste) {
        if (donnees >= places) break;
        quotas[nom] = quotas[nom]! + 1;
        donnees++;
      }
    }
    return quotas;
  }

  /// Une seule question, pour départager. Jamais une de celles déjà posées.
  QuizQuestion? questionDeBris({
    Set<String> themes = const {},
  }) {
    final compose = composer(themes: themes, nombre: 1);
    if (compose == null || compose.questions.isEmpty) return null;
    return compose.questions.first;
  }

  // Le titre dit le périmètre, parce qu'il s'affiche sur l'écran public et
  // que la salle doit comprendre ce qu'on lui pose.
  String _titre(Set<String> themes) {
    final noms = themes.toList();
    if (noms.isEmpty) return 'Questions au hasard';
    if (noms.length == 1) return 'Au hasard : ${noms.first}';
    return 'Au hasard : ${noms.length} sélections';
  }
}
