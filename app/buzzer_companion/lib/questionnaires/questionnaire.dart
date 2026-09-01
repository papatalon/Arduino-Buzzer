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

class QuizQuestion {
  QuizQuestion({this.category = '', this.question = '', this.answer = ''});

  String category;
  String question;
  String answer;

  // Une question sans énoncé n'est pas jouable ; la réponse peut rester vide
  // (l'animateur la connaît, ou la juge lui-même).
  bool get isUsable => question.trim().isNotEmpty;

  QuizQuestion copy() => QuizQuestion(category: category, question: question, answer: answer);

  Map<String, dynamic> toJson() => {
        'categorie': category,
        'question': question,
        'reponse': answer,
      };

  // Tolérant à dessein : un fichier écrit à la main peut omettre la
  // catégorie ou la réponse. Seul l'énoncé compte vraiment.
  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        category: (json['categorie'] as String?)?.trim() ?? '',
        question: (json['question'] as String?)?.trim() ?? '',
        answer: (json['reponse'] as String?)?.trim() ?? '',
      );
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
