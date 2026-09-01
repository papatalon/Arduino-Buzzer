// Génère des questionnaires JSON à partir de la banque compilée dans le
// firmware (Questions.cpp, 10 catégories de 200 questions).
//
//   dart run tool/generate_questionnaires.dart
//
// Gardé dans le dépôt plutôt que lancé une fois et oublié : le jour où des
// questions sont ajoutées au firmware, on régénère au lieu de tout refaire
// à la main.
//
// LES ACCENTS. Le firmware écrit sans accents, parce que l'écran LCD du
// buzzer ne sait pas les afficher. Les fichiers générés, eux, sont lus par
// des humains sur un écran d'ordinateur : « Genereux depute quebecois »
// n'est pas du français. Le texte accentué vit donc dans tool/accents/,
// un fichier par catégorie, dans le MÊME ordre que la source.
//
// Un garde-fou vérifie que retirer les accents d'une ligne accentuée
// redonne EXACTEMENT la ligne d'origine. Si l'invariant tient, la
// réécriture n'a fait qu'ajouter des accents : elle n'a pas reformulé, ni
// sauté une question, ni interverti une réponse. Toute dérive échoue
// bruyamment au lieu de passer inaperçue.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _sourcePath = '../../Questions.cpp';
const _accentsDir = 'tool/accents';

// Plafond ferme : une soiree n'est pas un marathon. Passe une vingtaine de
// questions, les invites decrochent et ne redemandent pas la soiree suivante.
// Tout ce qui depasse est donc decoupe en manches de cette taille plutot que
// livre en un seul bloc : les 200 questions d'une categorie restent toutes
// accessibles, mais en huit manches qu'on enchaine (ou pas) selon l'ambiance
// de la salle.
const kMaxQuestions = 25;

// Destination par defaut : un dossier du depot, pratique pour verifier le
// resultat. Mais ce n'est PAS l'endroit ou l'operateur veut ses propres
// questionnaires : tout ce qu'il creerait la serait versionne. D'ou le
// premier argument, qui permet d'ecrire directement dans le dossier
// configure dans l'application :
//
//   dart run tool/generate_questionnaires.dart "C:\Users\...\Mes questionnaires"
var _outputDir = 'questionnaires';

class Entry {
  Entry(this.category, this.question, this.answer);
  final String category;
  final String question;
  final String answer;

  Map<String, dynamic> toJson() => {
        'categorie': category,
        'question': question,
        'reponse': answer,
      };
}

void main(List<String> args) {
  if (args.isNotEmpty && args.first.trim().isNotEmpty) {
    _outputDir = args.first.trim();
  }

  final source = File(_sourcePath);
  if (!source.existsSync()) {
    stderr.writeln('Introuvable : ${source.absolute.path}');
    stderr.writeln('Lancez ce script depuis app/buzzer_companion.');
    exit(1);
  }

  final raw = source.readAsStringSync();
  final categories = _parseCategories(raw);
  if (categories.isEmpty) {
    stderr.writeln("Aucune catégorie trouvée : le format de Questions.cpp a changé.");
    exit(1);
  }

  var accentues = 0;
  final all = <Entry>[];
  final parCategorie = <String, List<Entry>>{};

  for (final cat in categories) {
    final entries = _applyAccents(cat);
    if (cat.accented != null) accentues++;
    parCategorie[entries.first.category] = entries;
    all.addAll(entries);
  }

  stdout.writeln('${all.length} questions, ${categories.length} catégories '
      '($accentues accentuées, ${categories.length - accentues} en attente).');

  final out = Directory(_outputDir);
  if (!out.existsSync()) out.createSync(recursive: true);

  // Un fichier par catégorie, découpé en manches de 25.
  for (final entry in parCategorie.entries) {
    _writeParts(entry.key, entry.value,
        note: 'Banque du buzzer, catégorie ${entry.key}.',
        emoji: kEmojiCategories[entry.key] ?? '');
  }

  // Le mélange, c'est le format principal : seize rondes de 25, toutes
  // catégories confondues, TIRÉES SANS AUCUN RECOUPEMENT. Les seize
  // s'enchaînent d'une soirée à l'autre sans jamais reposer une question déjà
  // posée, et chaque ronde sert autant de chaque catégorie : personne n'est
  // avantagé parce qu'il connaît le sport.
  //
  // Graine fixe : régénérer redonne exactement les mêmes fichiers, donc ils
  // sont reproductibles et comparables d'une version à l'autre.
  //
  // La dernière taille de la liste est la manche éclair : elle est tirée dans
  // la même série, donc elle ne recoupe pas non plus les seize rondes.
  const kRondes = 16;
  final series = _equilibreSeries(
    parCategorie,
    [...List.filled(kRondes, kMaxQuestions), 10],
    Random(7),
  );
  const kMelanges = 'Mélanges';
  const kEmojiMelanges = '🎲';
  for (var i = 0; i < kRondes; i++) {
    _write(
      'Toutes catégories ${_numero(i + 1, kRondes)} sur $kRondes',
      series[i],
      note: 'Toutes catégories, autant de chacune. '
          'Ronde ${i + 1} sur $kRondes, aucune question en double.',
      collection: kMelanges,
      emoji: kEmojiMelanges,
    );
  }

  // Format court : de quoi réchauffer la salle avant le vrai jeu, ou remplir
  // un creux, sans engager la soirée. Rangée avec les mélanges, dont elle est
  // tirée.
  _write('Manche éclair', series.last,
      note: 'Dix questions, une de chaque catégorie.',
      collection: kMelanges,
      emoji: kEmojiMelanges);

  // Découpes thématiques : elles traversent les catégories. « Noël » pioche
  // le renne dans Culture générale, la bûche dans Bouffe, les chants dans
  // Musique et le Grincheux dans Cinéma. Aucune catégorie du firmware ne
  // sait faire ça, c'est tout l'intérêt.
  for (final theme in kThemes) {
    final trouvees = all.where(theme.matches).toList()..shuffle(Random(theme.name.length * 13));
    if (trouvees.length < 12) {
      stdout.writeln('  (ignoré : ${theme.name}, seulement ${trouvees.length} questions)');
      continue;
    }
    _writeParts(theme.name, trouvees, note: theme.note, emoji: theme.emoji);
  }

  // Volontairement pas de fichier « Banque complète » : 2000 questions dans un
  // seul questionnaire, c'est exactement ce que le plafond interdit. Les 2000
  // sont là quand même, réparties dans les manches par catégorie.

  stdout.writeln('Écrit dans ${out.absolute.path}');
}

// --- Lecture de Questions.cpp -------------------------------------------

class _Category {
  _Category(this.name, this.lines, this.accented);
  final String name;
  final List<String> lines;        // "Question|Reponse", sans accents
  final List<String>? accented;    // même ordre, accentué, ou null
}

List<_Category> _parseCategories(String raw) {
  final result = <_Category>[];
  for (var i = 0; ; i++) {
    final name = _literalAfter(raw, 'CAT${i}_NAME[] QDATA =');
    final data = _literalsAfter(raw, 'CAT${i}_DATA[] QDATA =');
    if (name == null || data == null) break;

    // Les entrées sont séparées par \n dans la source C++ : une chaîne
    // littérale par ligne, mais rien ne l'impose, d'où le découpage sur le
    // séparateur réel plutôt que sur les littéraux.
    final lines = data
        .split('\\n')
        .map((l) => l.trim())
        .where((l) => l.contains('|'))
        .toList();

    result.add(_Category(name, lines, _readAccents(i, lines.length)));
  }
  return result;
}

String? _literalAfter(String raw, String marker) {
  final at = raw.indexOf(marker);
  if (at < 0) return null;
  final open = raw.indexOf('"', at + marker.length);
  if (open < 0) return null;
  final close = raw.indexOf('"', open + 1);
  if (close < 0) return null;
  return raw.substring(open + 1, close);
}

// Concatène tous les littéraux entre le marqueur et le point-virgule, comme
// le fait le compilateur C.
String? _literalsAfter(String raw, String marker) {
  final at = raw.indexOf(marker);
  if (at < 0) return null;
  final end = raw.indexOf(';', at);
  if (end < 0) return null;
  final body = raw.substring(at + marker.length, end);
  final buffer = StringBuffer();
  var i = 0;
  while (i < body.length) {
    final open = body.indexOf('"', i);
    if (open < 0) break;
    final close = body.indexOf('"', open + 1);
    if (close < 0) break;
    buffer.write(body.substring(open + 1, close));
    i = close + 1;
  }
  return buffer.toString();
}

// --- Accents -------------------------------------------------------------

List<String>? _readAccents(int index, int expected) {
  final file = File('$_accentsDir/cat$index.txt');
  if (!file.existsSync()) return null;
  final lines = file
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  if (lines.length != expected) {
    stderr.writeln('cat$index.txt : ${lines.length} lignes pour $expected '
        'questions attendues. Fichier ignoré.');
    return null;
  }
  return lines;
}

List<Entry> _applyAccents(_Category cat) {
  final accented = cat.accented;
  final entries = <Entry>[];
  final categoryName = accented == null ? cat.name : _accentedName(cat.name);

  for (var i = 0; i < cat.lines.length; i++) {
    final ligne = accented == null ? cat.lines[i] : accented[i];

    // L'invariant : sans ses accents, la ligne accentuée DOIT redonner la
    // source au caractère près. C'est ce qui garantit qu'on n'a fait
    // qu'accentuer.
    if (accented != null && _strip(ligne) != cat.lines[i]) {
      stderr.writeln('${cat.name}, ligne ${i + 1} : la version accentuée ne '
          "correspond pas à la source.");
      stderr.writeln('  source   : ${cat.lines[i]}');
      stderr.writeln('  accentué : $ligne');
      stderr.writeln('  dépouillé: ${_strip(ligne)}');
      exit(1);
    }

    final sep = ligne.indexOf('|');
    entries.add(Entry(
      categoryName,
      ligne.substring(0, sep).trim(),
      ligne.substring(sep + 1).trim(),
    ));
  }
  return entries;
}

// Les noms de catégories sont écrits sans accents dans le firmware pour la
// même raison que les questions.
const _nomsAccentues = {
  'Culture generale': 'Culture générale',
  'Geographie': 'Géographie',
  'Cinema et tele': 'Cinéma et télé',
  'Quebec': 'Québec',
};

String _accentedName(String brut) => _nomsAccentues[brut] ?? brut;

// Un pictogramme par collection, pour reperer une tuile sans lire son nom.
// Ecrit dans chaque fichier plutot que code en dur dans l'app : l'app n'a
// pas a connaitre par coeur les noms des collections generees, et une
// collection inventee par l'operateur a droit au sien.
//
// Clefs = noms ACCENTUES, ceux qui finissent dans les fichiers.
const kEmojiCategories = {
  'Culture générale': '💡',
  'Histoire': '🏛️',
  'Géographie': '🌍',
  'Sciences et nature': '🔬',
  'Sports': '🏅',
  'Musique': '🎵',
  'Cinéma et télé': '🎬',
  'Québec': '⚜️',
  'Bouffe et cuisine': '🍲',
  'Mots et langue': '🔤',
};

// Au-delà du français : la banque est pleine de noms étrangers (Dalí,
// Tolstoï, Bogotá) que le firmware a écrits sans leurs signes. Sans eux dans
// cette table, l'invariant refuserait une graphie pourtant correcte.
const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', 'ø': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ç': 'c', 'ñ': 'n', 'ý': 'y', 'š': 's', 'ž': 'z',
  // Est de l'Europe : Comăneci, Đoković, Wałęsa...
  'ă': 'a', 'ą': 'a', 'ș': 's', 'ś': 's', 'ț': 't', 'ř': 'r', 'ł': 'l',
  'ő': 'o', 'ű': 'u', 'ů': 'u', 'đ': 'd', 'ď': 'd', 'ě': 'e', 'ę': 'e',
  'ć': 'c', 'č': 'c', 'ń': 'n', 'ň': 'n', 'ź': 'z', 'ż': 'z', 'ť': 't',
  'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A', 'Ã': 'A', 'Å': 'A',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
  'Î': 'I', 'Ï': 'I', 'Í': 'I', 'Ì': 'I',
  'Ô': 'O', 'Ö': 'O', 'Ó': 'O', 'Ò': 'O', 'Õ': 'O', 'Ø': 'O',
  'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ú': 'U',
  'Ç': 'C', 'Ñ': 'N', 'Ý': 'Y', 'Š': 'S', 'Ž': 'Z',
  'Ă': 'A', 'Ą': 'A', 'Ș': 'S', 'Ś': 'S', 'Ț': 'T', 'Ř': 'R', 'Ł': 'L',
  'Ő': 'O', 'Ű': 'U', 'Ů': 'U', 'Đ': 'D', 'Ď': 'D', 'Ě': 'E', 'Ę': 'E',
  'Ć': 'C', 'Č': 'C', 'Ń': 'N', 'Ň': 'N', 'Ź': 'Z', 'Ż': 'Z', 'Ť': 'T',
  // Ligatures : le firmware les écrit déjà en deux lettres.
  'œ': 'oe', 'Œ': 'OE', 'æ': 'ae', 'Æ': 'AE',
};

String _strip(String s) {
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final c = String.fromCharCode(rune);
    buffer.write(_accents[c] ?? c);
  }
  return buffer.toString();
}

// --- Themes --------------------------------------------------------------

// Un theme rassemble des questions dispersees dans les dix categories. La
// selection se fait par mots-cles cherches dans l'enonce ET la reponse : une
// question comme « Quel renne du pere Noel a le nez rouge ? » vit dans
// Culture generale, mais sa place est evidemment dans le questionnaire de
// Noel.
//
// Comparaison SANS accents et en minuscules : les mots-cles s'ecrivent donc
// simplement, et « Noel » attrape « Noël ». Bornes de mots obligatoires,
// sinon « os » attraperait « chose » et « ski » attraperait « whisky ».
class Theme {
  const Theme(this.name, this.emoji, this.note, this.keywords,
      {this.exclude = const [], this.excludeCategories = const []});

  final String name;
  final String emoji;
  final String note;
  final List<String> keywords;

  // Des mots-cles ne suffisent pas toujours : « cotes » attrape autant les
  // cotes d'un thorax que les cotes d'un hexagone, et rien dans le mot ne
  // permet de trancher. Cette liste retire les cas connus, verifies en
  // relisant ce que chaque theme avait ramasse.
  final List<String> exclude;

  // Categories entieres a laisser de cote. Sert quand une thematique porte le
  // meme sujet qu'une categorie de la banque : sans ca, « Tout sur le
  // Quebec » reprenait 161 des 200 questions de la categorie Quebec et
  // annoncait deux fois la meme chose sous deux tuiles voisines. En excluant
  // la categorie, la thematique ne garde que ce que la categorie n'a PAS :
  // le Quebec dispersé dans Musique, Bouffe, Cinema, Sports.
  final List<String> excludeCategories;

  bool matches(Entry e) {
    if (excludeCategories.contains(e.category)) return false;
    final texte = _strip('${e.question} ${e.answer}').toLowerCase();
    for (final mot in exclude) {
      if (_motPresent(texte, mot)) return false;
    }
    for (final mot in keywords) {
      if (_motPresent(texte, mot)) return true;
    }
    return false;
  }

  static bool _motPresent(String texte, String mot) {
    final motif = RegExp('(?<![a-z0-9])${RegExp.escape(mot)}(?![a-z0-9])');
    return motif.hasMatch(texte);
  }
}

const kThemes = <Theme>[
  Theme('Spécial Noël', '🎄', 'Le temps des fêtes, toutes catégories confondues.', [
    'noel', 'renne', 'rudolphe', 'sapin', 'buche', 'dinde',
    'reveillon', 'tourtiere', 'canneberge', 'canneberges', 'cannelle',
    'muscade', 'girofle', 'guimauve', "pain d'epice", 'patates pilees',
    'ragout de pattes', 'lait de poule', 'saint-nicolas',
    "jour de l'an", 'bye bye', 'cantique', 'frosty', 'gingembre',
    // Volontairement absents : « decembre » n'attrapait que Pearl Harbor,
    // et « grincheux » ramenait le Dr House. Les vraies questions de Noel
    // qu'ils visaient sont deja prises par « noel ».
  ], exclude: [
    'chaise',   // « se tirer une buche » : la buche est un siege, ici
  ]),
  // Complémentaire de la catégorie « Québec », pas concurrente : elle ramasse
  // le Québec qui vit AILLEURS, Maurice Richard dans Sports, La Petite Vie
  // dans Cinéma, la poutine râpée dans Bouffe, les rigodons dans Musique.
  // Jouer la catégorie puis celle-ci ne repose aucune question.
  //
  // Pas de feuille d'érable : c'est l'emblème du Canada. La fleur de lys va
  // à la catégorie Québec.
  Theme('Le Québec ailleurs', '🌲',
      'Le Québec caché dans les neuf autres catégories.', [
    'quebec', 'quebecois', 'quebecoise', 'quebecoises', 'montreal',
    'montrealais', 'montrealaise', 'saint-laurent', 'erable', 'poutine',
    'celine', 'canadiens', 'expos', 'gaspesie', 'gaspesienne', 'saguenay',
    'laurentides', 'charlevoix', 'outaouais', 'acadien', 'acadienne',
    'hydro-quebec', 'fleurdelise', 'tuque', 'maringouins', 'beluga',
    'belugas', 'orignal', 'st-hubert', 'schwartz', 'bagel', 'smoked meat',
    'feves au lard', 'pate chinois', 'pouding chomeur', 'steame', 'caribou',
    'bleuet', 'trois-rivieres', 'sherbrooke', 'gatineau', 'tadoussac',
    'nouvelle-france', 'patriotes', 'champlain', 'jacques cartier',
    'maurice richard', 'lafleur', 'beliveau', 'lemieux', 'les boys',
    'la petite vie', 'passe-partout', 'caillou', 'unite 9', 'infoman',
    'harmonium', 'offenbach', 'beau dommage', 'colocs', 'vigneault',
    'leclerc', 'charlebois', 'ginette reno', 'marjo', 'nelligan',
    'gabrielle roy', 'tremblay', 'villeneuve', 'arcand', 'cirque du soleil',
    'louis cyr', 'bombardier', 'levesque', 'duplessis', 'legault',
    'loi 101', 'oqlf', 'verglas', 'hurons-wendat', 'madelinots',
    'saguenéen', 'trifluvien', 'terre-neuvien',
  ], excludeCategories: ['Québec']),
  Theme('Le règne animal', '🐾', 'Bêtes à poil, à plume et à écailles.', [
    'animal', 'animaux', 'oiseau', 'oiseaux', 'poisson', 'poissons',
    'insecte', 'insectes', 'mammifere', 'mammiferes', 'reptile', 'reptiles',
    'chien', 'chienne', 'chat', 'cheval', 'chevaux', 'lion', 'lionceau',
    'elephant', 'girafe', 'baleine', 'abeille', 'abeilles', 'fourmi',
    'fourmis', 'papillon', 'araignee', 'araignees', 'serpent', 'grenouille',
    'tortue', 'ours', 'loup', 'renard', 'castor', 'kangourou', 'kangourous',
    'panda', 'koala', 'singe', 'chimpanze', 'tigre', 'felin', 'guepard',
    'zebre', 'crocodile', 'requin', 'pieuvre', 'hippocampe', 'colibri',
    'autruche', 'manchots', 'chauve-souris', 'scorpion', 'crabe', 'homard',
    'moustique', 'chenille', 'vache', 'brebis', 'mouton', 'cochon', 'coq',
    'poule', 'canard', 'cerf', 'sanglier', 'chevre', 'lapin', 'aigle',
    'corbeau', 'ane', 'dromadaire', 'chameau', 'capybara', 'orignal',
    'dinosaure', 'triceratops', 'stegosaure', 'ornithorynque', 'lama',
  ], exclude: [
    // Contextes où l'animal n'est qu'un mot : des pâtes papillon, une pâte
    // à frire pour le poisson, une question de grammaire sur le mot loup.
    'pates', 'pate', 'frire', 'muettes', 'palindrome',
  ]),
  Theme("L'espace et le ciel", '🪐', 'Planètes, étoiles et conquête spatiale.', [
    'planete', 'planetes', 'soleil', 'lune', 'lunes', 'etoile', 'etoiles',
    'galaxie', 'espace', 'astronaute', 'satellite', 'telescope', 'orbite',
    'comete', 'meteorite', 'eclipse', 'mars', 'jupiter', 'saturne', 'venus',
    'mercure', 'uranus', 'neptune', 'pluton', 'apollo', 'spoutnik',
    'hubble', 'gagarine', 'armstrong', 'aldrin', 'trou noir', 'voie lactee',
    'astre', 'astres', 'astronomie', 'astronome', 'spatiale', 'spatial',
    'aurore boreale', 'equateur', 'hemispheres', 'marees', 'atmosphere',
  ]),
  Theme('Le corps humain', '🧠', 'Os, organes et petites mécaniques internes.', [
    'os', 'sang', 'coeur', 'cerveau', 'poumon', 'poumons', 'muscle',
    'organe', 'organes', 'dent', 'dents', 'oeil', 'yeux', 'oreille',
    'peau', 'vitamine', 'cellule', 'cellules', 'chromosomes', 'estomac',
    'foie', 'reins', 'pancreas', 'squelette', 'vertebres', 'femur',
    'crane', 'cotes', 'etrier', 'iris', 'pupille', 'oesophage', 'bile',
    'hemoglobine', 'insuline', 'globules', 'sanguin', 'genou', 'articulation',
    'humain', 'adulte',
    // « corps » attrapait le corps de lion du Sphinx et la langue du
    // caméléon : trop large, et rien ne se perd à l'enlever (ces questions
    // gardent « organe » ou « os »).
  ], exclude: [
    // « côtes » du thorax et « côtés » d'un polygone s'écrivent pareil une
    // fois les accents retirés.
    'hexagone', 'triangle', 'octogone', 'pentagone', 'cube', 'statue',
  ]),
  Theme('Super-héros et BD', '🦸', 'Capes, masques et bulles.', [
    'super-heros', 'superheros', 'marvel', 'batman', 'superman',
    'spider-man', 'hulk', 'iron man', 'thor', 'wonder woman', 'aquaman',
    'wolverine', 'ant-man', 'thanos', 'captain america', 'joker', 'robin',
    'gotham', 'krypton', 'kryptonite', 'clark kent', 'lois lane', 'alfred',
    'tony stark', 'groot', 'gardiens', 'mutant', 'mutants', 'asterix',
    'obelix', 'idefix', 'panoramix', 'tintin', 'milou', 'herge',
    'schtroumpfs', 'gargamel', 'lucky luke', 'dalton', 'picsou', 'popeye',
    'garfield', 'bd',
  ]),
  Theme('Créatures et légendes', '🐉', 'Monstres, dieux et histoires qu\'on se raconte.', [
    'monstre', 'creature', 'creatures', 'dragon', 'fantome', 'sorcier',
    'sorciere', 'vampire', 'geant', 'legende', 'legendaire', 'mythologique',
    'mythique', 'dieu', 'deesse', 'zeus', 'poseidon', 'hades', 'aphrodite',
    'hermes', 'athena', 'atlas', 'hercule', 'meduse', 'pegase', 'phenix',
    'centaure', 'cyclope', 'cerbere', 'minotaure', 'licorne', 'farfadet',
    'chasse-galerie', 'bonhomme sept-heures', 'loch ness', 'sirene',
    'fee', 'ogre', 'troll', 'conte', 'contes', 'graal', 'excalibur',
    'merlin', 'arthur', 'romulus', 'remus', 'pandore', 'midas', 'troie',
    'halloween', 'superstition', 'malheur', 'chaudron',
  ]),
  Theme("Sports d'hiver", '⛷️', 'Tout ce qui se joue sur la glace ou la neige.', [
    'hockey', 'patinage', 'patineur', 'patineuse', 'patinoire', 'ski',
    'skieur', 'curling', 'luge', 'skeleton', 'biathlon', 'slalom',
    'ballon-balai', 'rondelle', 'glace', 'neige', 'planche a neige',
    'jo d\'hiver', 'coupe stanley', 'lnh', 'gretzky', 'crosby', 'mcdavid',
    'ovechkin', 'brodeur', 'maple leafs', 'oilers', 'canadiens',
    'vancouver', 'calgary', 'bilodeau', 'hamelin', 'virtue', 'tremblant',
    'traineaux', 'iditarod', 'combine nordique', 'alpinisme',
  ], exclude: [
    // « glace » attrapait le gelato italien, « neige » un chant de Noel.
    'gelato', 'chanson',
  ]),
];

// --- Tirages -------------------------------------------------------------

// Une série de rondes équilibrées, sans jamais repiocher la même question :
// chaque catégorie garde son propre curseur, qui avance de ronde en ronde.
// Les tailles peuvent varier, ce qui permet de tirer la manche éclair dans la
// même série que les grosses rondes, donc sans recoupement avec elles.
//
// 25 ne se divise pas par 10, donc cinq catégories reçoivent une question de
// plus. Ce surplus TOURNE d'une ronde à l'autre : sinon les cinq mêmes
// catégories seraient avantagées les seize rondes durant.
List<List<Entry>> _equilibreSeries(
    Map<String, List<Entry>> parCategorie, List<int> tailles, Random rnd) {
  final noms = parCategorie.keys.toList();
  final pools = <String, List<Entry>>{
    for (final nom in noms) nom: List<Entry>.from(parCategorie[nom]!)..shuffle(rnd),
  };
  final curseurs = <String, int>{for (final nom in noms) nom: 0};

  final rondes = <List<Entry>>[];
  var decalage = 0;
  for (final taille in tailles) {
    final base = taille ~/ noms.length;
    final reste = taille % noms.length;
    final ronde = <Entry>[];
    for (var i = 0; i < noms.length; i++) {
      // Le modulo de Dart suit le signe du diviseur : (i - decalage) % 10 est
      // toujours dans 0..9, même quand le décalage dépasse i.
      final rang = (i - decalage) % noms.length;
      final combien = base + (rang < reste ? 1 : 0);
      final nom = noms[i];
      final depart = curseurs[nom]!;
      if (depart + combien > pools[nom]!.length) {
        stderr.writeln('$nom : la série demande plus de questions que la '
            'catégorie n\'en contient (${pools[nom]!.length}).');
        exit(1);
      }
      ronde.addAll(pools[nom]!.sublist(depart, depart + combien));
      curseurs[nom] = depart + combien;
    }
    // Remélangée : sinon la ronde enchaînerait ses questions catégorie par
    // catégorie, dans le même ordre à chaque fois.
    ronde.shuffle(rnd);
    rondes.add(ronde);
    decalage = (decalage + reste) % noms.length;
  }
  return rondes;
}

// Découpe en parts aussi égales que possible. 265 questions en 11 manches
// donne onze manches de 24, pas dix de 25 suivies d'une de 15.
List<List<Entry>> _decoupe(List<Entry> entries, int nbParts) {
  final base = entries.length ~/ nbParts;
  final reste = entries.length % nbParts;
  final parts = <List<Entry>>[];
  var curseur = 0;
  for (var i = 0; i < nbParts; i++) {
    final combien = base + (i < reste ? 1 : 0);
    parts.add(entries.sublist(curseur, curseur + combien));
    curseur += combien;
  }
  return parts;
}

// --- Écriture ------------------------------------------------------------

// Écrit un questionnaire, ou plusieurs manches si le lot dépasse le plafond.
// Faute de collection explicite, le titre fait office : les huit manches
// d'« Histoire » se retrouvent ensemble sous « Histoire ».
void _writeParts(String titre, List<Entry> entries,
    {required String note, required String emoji, String? collection}) {
  final nbParts = (entries.length + kMaxQuestions - 1) ~/ kMaxQuestions;
  if (nbParts <= 1) {
    _write(titre, entries, note: note, collection: collection ?? titre, emoji: emoji);
    return;
  }
  final parts = _decoupe(entries, nbParts);
  for (var i = 0; i < parts.length; i++) {
    _write(
      '$titre ${_numero(i + 1, nbParts)} sur $nbParts',
      parts[i],
      note: '$note Manche ${i + 1} sur $nbParts.',
      collection: collection ?? titre,
      emoji: emoji,
    );
  }
}

// Au-dela de neuf manches, les numeros portent un zero devant : sans ca, la
// bibliotheque triee par nom placerait « 10 sur 16 » juste apres « 1 sur 16 »,
// avant « 2 sur 16 ».
String _numero(int n, int total) => total >= 10 ? '$n'.padLeft(2, '0') : '$n';

void _write(String titre, List<Entry> entries,
    {required String note, required String collection, required String emoji}) {
  final json = const JsonEncoder.withIndent('  ').convert({
    'format': 'buzzer-questionnaire',
    'version': 1,
    'titre': titre,
    'note': note,
    // Range le fichier sous sa tuile dans la bibliothèque de l'app. Sans
    // elle, les 131 fichiers arrivent en un seul tas.
    'collection': collection,
    'emoji': emoji,
    'questions': entries.map((e) => e.toJson()).toList(),
  });
  final nom = titre.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
  File('$_outputDir/$nom.json').writeAsStringSync('$json\n');
  stdout.writeln('  $nom.json  (${entries.length})');
}
