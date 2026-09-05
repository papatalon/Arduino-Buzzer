import 'dart:convert';

// Un questionnaire thématique, écrit dans l'app et enregistré en JSON pour
// être rechargé au besoin (soirée de Noël, party de bureau, anniversaire...).
//
// Le format est volontairement en clair et en français : ces fichiers sont
// faits pour être retouchés à la main dans un éditeur de texte, partagés par
// courriel, ou générés par un tiers. Des clés « question »/« reponse » se
// comprennent sans documentation ; des clés « q »/« a » demanderaient de
// deviner.
//
// [kFormat] et [kVersion] sont là pour qu'un fichier d'une autre application
// soit refusé proprement plutôt que d'être chargé de travers, et pour qu'un
// changement de format plus tard puisse migrer les anciens au lieu de les
// perdre.
const kFormat = 'buzzer-questionnaire';
const kVersion = 1;

// Les trois niveaux d'une question, et le mot qu'on affiche pour chacun.
// 1 : un enfant de huit ans répond. 2 : culture générale ordinaire.
// 3 : connaisseur.
const kNomsNiveaux = {1: 'facile', 2: 'moyen', 3: 'difficile'};

// LES TRANCHES D'ÂGE, le second axe. Indépendant du niveau : le niveau se lit
// À L'INTÉRIEUR d'une tranche (« facile pour un enfant »), la tranche dit à qui
// la question s'adresse. Une question peut viser plusieurs tranches ; aucune
// règle implicite ne les déduit du niveau, chaque question porte les siennes.
enum Tranche { enfants, ados, adultes, aines }

const kNomsTranches = {
  Tranche.enfants: 'enfants',
  Tranche.ados: 'ados',
  Tranche.adultes: 'adultes',
  Tranche.aines: 'aînés',
};

// Ce que le fichier écrit : « aines » sans accent, pour rester lisible partout.
const _clesTranches = {
  'enfants': Tranche.enfants,
  'ados': Tranche.ados,
  'adultes': Tranche.adultes,
  'aines': Tranche.aines,
};

String cleTranche(Tranche t) =>
    _clesTranches.entries.firstWhere((e) => e.value == t).key;

// Une question sans tranche vaut pour tout le monde : un questionnaire écrit
// à la main n'a pas à se prononcer, et le filtre ne doit pas l'écarter.
Set<Tranche> tranchesDepuisJson(Object? brut) {
  if (brut is! List) return const {};
  return {
    for (final e in brut) ?_clesTranches['$e'.trim().toLowerCase()],
  };
}

// Combien de questions de chaque niveau, en ignorant celles qui n'en ont pas.
Map<int, int> compterNiveaux(Iterable<int?> niveaux) {
  final comptes = <int, int>{};
  for (final n in niveaux) {
    if (n != null) comptes[n] = (comptes[n] ?? 0) + 1;
  }
  return comptes;
}

// LE MOT QUI RÉSUME UN QUESTIONNAIRE. La moyenne des niveaux, ramenée aux
// trois mêmes mots que les questions : une manche toute au niveau 1 est
// « facile », une manche qui mélange les trois est « moyen », et une manche
// de connaisseurs est « difficile ». Null quand rien n'est coté : mieux vaut
// ne rien dire qu'inventer.
String? etiquetteDesNiveaux(Map<int, int> comptes) {
  var n = 0;
  var somme = 0;
  comptes.forEach((niveau, c) {
    n += c;
    somme += niveau * c;
  });
  if (n == 0) return null;
  final moyenne = somme / n;
  if (moyenne < 1.5) return kNomsNiveaux[1];
  if (moyenne < 2.4) return kNomsNiveaux[2];
  return kNomsNiveaux[3];
}

class QuizQuestion {
  QuizQuestion({
    this.category = '',
    this.question = '',
    this.answer = '',
    this.niveau,
    this.ages = const {},
    this.themes = const {},
  });

  String category;
  String question;
  String answer;
  // Voir [kNomsNiveaux]. Null quand personne ne l'a coté : un questionnaire
  // écrit à la main n'a pas à se prononcer, et l'app n'affiche alors rien.
  int? niveau;
  // Voir [Tranche]. Vide quand la question ne se prononce pas : elle vaut
  // alors pour tout le monde et aucun filtre ne l'écarte.
  Set<Tranche> ages;
  // Les découpes qui traversent les catégories : « Spécial Noël », « Le corps
  // humain ». Calculées par le générateur, portées par la question plutôt que
  // par un fichier depuis que les questionnaires prédécoupés ont disparu.
  Set<String> themes;

  // Une question sans énoncé n'est pas jouable ; la réponse peut rester vide
  // (l'animateur la connaît, ou la juge lui-même).
  bool get isUsable => question.trim().isNotEmpty;

  QuizQuestion copy() => QuizQuestion(
      category: category,
      question: question,
      answer: answer,
      niveau: niveau,
      ages: {...ages},
      themes: {...themes});

  Map<String, dynamic> toJson() => {
        'categorie': category,
        'question': question,
        'reponse': answer,
        if (niveau != null) 'niveau': niveau,
        if (ages.isNotEmpty) 'ages': [for (final t in Tranche.values) if (ages.contains(t)) cleTranche(t)],
        if (themes.isNotEmpty) 'themes': themes.toList(),
      };

  // Tolérant à dessein : un fichier écrit à la main peut omettre la
  // catégorie ou la réponse. Seul l'énoncé compte vraiment.
  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        category: (json['categorie'] as String?)?.trim() ?? '',
        question: (json['question'] as String?)?.trim() ?? '',
        answer: (json['reponse'] as String?)?.trim() ?? '',
        niveau: niveauDepuisJson(json['niveau']),
        ages: tranchesDepuisJson(json['ages']),
        themes: {
          if (json['themes'] case final List brut)
            for (final e in brut) '$e'.trim(),
        },
      );
}

// Un niveau écrit à la main peut arriver en nombre ou en texte ; tout ce qui
// n'est pas 1, 2 ou 3 vaut « pas coté » plutôt qu'une erreur.
int? niveauDepuisJson(Object? brut) {
  final n = brut is num ? brut.toInt() : int.tryParse('$brut');
  return n != null && kNomsNiveaux.containsKey(n) ? n : null;
}

class Questionnaire {
  Questionnaire({
    this.title = '',
    this.note = '',
    this.collection = '',
    this.emoji = '',
    List<QuizQuestion>? questions,
  }) : questions = questions ?? [];

  String title;
  // Consigne libre que l'animateur se laisse à lui-même (« garder les trois
  // dernières pour la finale », « prononcer les noms à l'anglaise »...).
  String note;
  // Regroupement dans la bibliothèque. Les 131 questionnaires générés
  // arrivent tous rangés (« Mélanges », « Histoire », « Spécial Noël »...) ;
  // sans ce niveau, la bibliothèque serait un mur de 131 cartes où plus rien
  // ne se trouve.
  //
  // Facultatif : un questionnaire écrit à la main, ou reçu de quelqu'un
  // d'autre, n'en a pas et se range dans « Mes questionnaires ».
  String collection;
  // Le pictogramme de la tuile. Porté par chaque fichier plutôt que par une
  // table dans l'app : une collection inventée par l'opérateur a droit au
  // sien, et l'app n'a pas à connaître par cœur les noms des collections
  // générées.
  String emoji;
  final List<QuizQuestion> questions;

  int get usableCount => questions.where((q) => q.isUsable).length;

  Map<int, int> get niveaux => compterNiveaux(questions.map((q) => q.niveau));
  String? get etiquetteNiveau => etiquetteDesNiveaux(niveaux);

  Questionnaire copy() => Questionnaire(
        title: title,
        note: note,
        collection: collection,
        emoji: emoji,
        questions: questions.map((q) => q.copy()).toList(),
      );

  String encode() => const JsonEncoder.withIndent('  ').convert({
        'format': kFormat,
        'version': kVersion,
        'titre': title,
        'note': note,
        'collection': collection,
        'emoji': emoji,
        'questions': questions.map((q) => q.toJson()).toList(),
      });

  // Lève [FormatException] avec un message lisible : il finit tel quel sous
  // les yeux de l'opérateur, qui a peut-être ouvert le mauvais fichier.
  factory Questionnaire.decode(String raw) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      throw const FormatException("Ce fichier n'est pas du JSON valide.");
    }
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException("Ce fichier ne contient pas un questionnaire.");
    }
    return Questionnaire.fromMap(parsed);
  }

  // La banque embarquée porte 283 questionnaires DÉJÀ décodés dans un seul
  // fichier : les ré-encoder un par un pour les redécoder serait absurde.
  factory Questionnaire.fromMap(Map<String, dynamic> parsed) {
    if (parsed['format'] != kFormat) {
      throw const FormatException(
        "Ce fichier n'est pas un questionnaire de Buzzer.",
      );
    }
    final version = parsed['version'];
    if (version is int && version > kVersion) {
      throw FormatException(
        "Ce questionnaire vient d'une version plus récente de l'application "
        '(version $version). Mettez l\'application à jour pour l\'ouvrir.',
      );
    }
    final rawQuestions = parsed['questions'];
    return Questionnaire(
      title: (parsed['titre'] as String?)?.trim() ?? '',
      note: (parsed['note'] as String?)?.trim() ?? '',
      collection: (parsed['collection'] as String?)?.trim() ?? '',
      emoji: (parsed['emoji'] as String?)?.trim() ?? '',
      questions: [
        if (rawQuestions is List)
          for (final q in rawQuestions)
            if (q is Map<String, dynamic>) QuizQuestion.fromJson(q),
      ],
    );
  }
}
