// Génère des questionnaires JSON à partir de la banque compilée dans le
// firmware (Questions.cpp, 10 catégories de 200 questions).
//
//   dart run tool/generate_questionnaires.dart
//
// Gardé dans le dépôt plutôt que lancé une fois et oublié : le jour où des
// questions sont ajoutées au firmware, on régénère au lieu de tout refaire
// à la main.
//
// LES QUESTIONS VIVENT DANS tool/questions/, un fichier par catégorie. La
// première moitié de chaque fichier reflète Questions.cpp ligne pour ligne ;
// après le séparateur « === hors firmware === », c'est libre. Voir
// [_questionsDir] pour le détail du format et pourquoi les deux cohabitent.
//
// LES ACCENTS. Le firmware écrit sans accents, parce que l'écran LCD du
// buzzer ne sait pas les afficher. Les fichiers générés, eux, sont lus par
// des humains sur un écran d'ordinateur : « Genereux depute quebecois »
// n'est pas du français. Le miroir porte donc le texte accentué.
//
// Un garde-fou vérifie que retirer les accents d'une ligne du miroir redonne
// EXACTEMENT la ligne d'origine. Si l'invariant tient, la réécriture n'a fait
// qu'ajouter des accents : elle n'a pas reformulé, ni sauté une question, ni
// interverti une réponse. Toute dérive échoue bruyamment au lieu de passer
// inaperçue.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

const _sourcePath = '../../Questions.cpp';

// UN SEUL FICHIER PAR CATÉGORIE.
//
// Il y en a eu deux dossiers : l'un alignait le firmware ligne pour ligne,
// l'autre portait les questions qui n'existent que dans l'application. Leurs
// formats ont fini par converger, et la séparation ne servait plus qu'à une
// chose — la vérification d'alignement — tout en obligeant, pour chaque
// question ajoutée, à choisir entre vingt-huit fichiers. J'y ai écrit mes
// propres doublons.
//
// Un fichier porte donc les deux :
//
//   # Catégorie : Culture générale
//   # Emoji : 💡
//   # Firmware : 0            (absent si la catégorie n'est pas au firmware)
//   ... le miroir, vérifié contre Questions.cpp ...
//   === hors firmware ===
//   ... les questions libres ...
//
// L'invariant survit : il ne s'applique qu'aux lignes d'avant le séparateur.
const _questionsDir = 'tool/questions';
const _separateur = '=== hors firmware ===';

class _Fichier {
  _Fichier(this.nom, this.categorie, this.emoji, this.firmware, this.miroir, this.libres);
  final String nom;
  final String categorie;
  final String emoji;
  final int? firmware;      // index CATn_DATA, ou null
  final List<String> miroir;
  final List<String> libres;
}

List<_Fichier>? _cacheFichiers;

// Lu une seule fois : le miroir et les libres sortent du même fichier, et
// deux lectures séparées les feraient diverger au moindre changement.
List<_Fichier> _fichiersQuestions() {
  if (_cacheFichiers != null) return _cacheFichiers!;
  final dir = Directory(_questionsDir);
  if (!dir.existsSync()) {
    stderr.writeln('Introuvable : ${dir.absolute.path}');
    exit(1);
  }
  final fichiers = <_Fichier>[];
  final trouves = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.txt')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in trouves) {
    final nom = f.uri.pathSegments.last;
    String? categorie;
    String? emoji;
    int? firmware;
    final miroir = <String>[];
    final libres = <String>[];
    var apresSeparateur = false;
    for (final brute in f.readAsLinesSync()) {
      final l = brute.trim();
      if (l.isEmpty) continue;
      if (l == _separateur) {
        apresSeparateur = true;
        continue;
      }
      if (l.startsWith('#')) {
        final m = RegExp(r'^#\s*(Catégorie|Emoji|Firmware)\s*:\s*(.+)$').firstMatch(l);
        if (m == null) continue;
        switch (m.group(1)) {
          case 'Catégorie':
            categorie = m.group(2)!.trim();
          case 'Emoji':
            emoji = m.group(2)!.trim();
          case 'Firmware':
            firmware = int.tryParse(m.group(2)!.trim());
        }
        continue;
      }
      (apresSeparateur ? libres : miroir).add(l);
    }
    if (categorie == null || emoji == null) {
      stderr.writeln('$nom : « # Catégorie : ... » et « # Emoji : ... » sont obligatoires.');
      exit(1);
    }
    // SANS « # Firmware », TOUT EST LIBRE. Une catégorie que le firmware ne
    // connaît pas n'a pas de séparateur, donc ses questions se retrouveraient
    // toutes du côté miroir — et un miroir sans firmware à refléter n'est
    // jamais lu. C'est exactement ce qui a fait disparaître Culture pop au
    // premier essai.
    if (firmware == null && miroir.isNotEmpty) {
      libres.insertAll(0, miroir);
      miroir.clear();
    }
    fichiers.add(_Fichier(nom, categorie, emoji, firmware, miroir, libres));
  }
  return _cacheFichiers = fichiers;
}

// Plafond ferme : une soiree n'est pas un marathon. Passe une vingtaine de
// questions, les invites decrochent et ne redemandent pas la soiree suivante.
// Tout ce qui depasse est donc decoupe en manches de cette taille plutot que
// livre en un seul bloc : les 200 questions d'une categorie restent toutes
// accessibles, mais en huit manches qu'on enchaine (ou pas) selon l'ambiance
// de la salle.
const kMaxQuestions = 25;

// Le generateur ecrit un SITE, pas un dossier de travail. Ce site est publie
// par Cloudflare Pages sur buzzer.sd6tools.net, et l'application va y
// chercher son catalogue :
//
//   site/
//     index.html          page d'accueil, pour l'humain qui tombe sur l'URL
//     catalogue.json      l'index : un enregistrement par questionnaire
//     q/<id>.json         les questionnaires eux-memes
//
// Les questionnaires ne sont plus lus depuis le depot par l'application. Elle
// les telecharge et les garde dans son dossier de donnees ; le dossier
// configure dans l'application ne contient plus que les questionnaires
// PERSONNELS de l'operateur.
//
// Le chemin est relatif a app/buzzer_companion, d'ou le script se lance.
var _outputDir = '../../site';

// La page d'accueil renvoie vers la version publiee sur GitHub. Le binaire
// n'entre PAS dans le depot : 18 Mo par version, dans un depot qui en fait 11
// au complet, et qu'aucune compression delta ne reduit d'une livraison a
// l'autre. Chaque version resterait stockee en entier, pour toujours.
const kDepotGitHub = 'https://github.com/papatalon/Arduino-Buzzer';
const kDepotGitHubCourt = 'papatalon/Arduino-Buzzer';

// Purement indicatif, a rafraichir quand l'archive change nettement de taille.
// Faux, il ne fait qu'induire en erreur sur la duree du telechargement ; il ne
// casse rien.
const kTailleTelechargement = '18 Mo';

// D'où sort une question. Ne voyage pas dans les questionnaires (une question
// n'a pas à dire d'où elle vient à l'animateur), seulement dans la page de
// revue, où c'est justement ce qu'on veut savoir en relisant.
enum Origine { banque, retouchee, inedite }

// À QUI UNE QUESTION APPARTIENT.
//
// Deuxième axe, indépendant du niveau, et il a fallu se tromper pour le voir.
// Le niveau dit si c'est difficile ; la tranche dit DANS QUEL MONDE la question
// se trouve. « Quel Pokémon jaune lance des éclairs » est évident à quinze ans
// et opaque à soixante-quinze ; « Qui a chanté My Way » fait l'inverse. Sur un
// seul axe, une soirée « 7 à 77 ans » laissait les ados regarder passer
// vingt-cinq questions sans en posséder une seule.
//
// LES DEUX AXES NE SE REMPLACENT PAS. Le niveau se lit À L'INTÉRIEUR de la
// tranche : une question d'enfants peut être difficile (le nom du phacochère
// qui accompagne Timon), une question d'aînés peut être facile (Piaf).
//
// UNE QUESTION COUVRE PLUSIEURS TRANCHES, presque toujours. Minecraft
// appartient aux enfants ET aux ados ; Aznavour aux adultes ET aux aînés. Une
// seule tranche par question serait faux partout, d'où l'ensemble.
enum Tranche { enfants, ados, adultes, aines }

// Le cas de loin le plus fréquent : personne ne possède cette question plus
// qu'un autre. Le cri du chat, le nombre de côtés d'un carré, la couleur des
// Schtroumpfs. On ne marque donc QUE les exceptions.
const kToutesTranches = <Tranche>{
  Tranche.enfants,
  Tranche.ados,
  Tranche.adultes,
  Tranche.aines,
};

// AUCUNE TRANCHE N'EST DÉDUITE. Chaque question porte les siennes, écrites
// dans son fichier, et il n'existe pas de valeur par défaut.
//
// J'avais d'abord dérivé les tranches du niveau : « moyen » sortait les
// enfants, « difficile » sortait aussi les ados. La règle était juste dans la
// plupart des cas, et c'est exactement ce qui la rendait dangereuse — elle
// avait l'air de marcher, donc personne n'allait vérifier les cas où elle se
// trompait. Le gant de Thanos est coté moyen et appartient aux enfants ;
// « Combien de cases sur un échiquier » est coté moyen et un enfant qui joue
// répond. Une règle implicite décide pour ces questions-là sans le dire.
//
// Le coût : quatre mots de plus par ligne. Le gain : le fichier dit tout ce
// qu'il fait, et une question mal classée se voit en la lisant.

Set<Tranche> _tranchesDepuis(String mots, String ou) {
  final trouvees = <Tranche>{};
  for (final mot in mots.split(RegExp(r'[\s,]+'))) {
    if (mot.isEmpty) continue;
    final t = Tranche.values.where((v) => v.name == mot.toLowerCase());
    if (t.isEmpty) {
      stderr.writeln("$ou : tranche inconnue « $mot ». Attendu "
          '${Tranche.values.map((v) => v.name).join(', ')}.');
      exit(1);
    }
    trouvees.add(t.first);
  }
  if (trouvees.isEmpty) {
    stderr.writeln('$ou : aucune tranche nommée.');
    exit(1);
  }
  return trouvees;
}

class Entry {
  Entry(this.category, this.question, this.answer,
      {this.niveau, this.origine = Origine.banque, required this.tranches});
  final String category;
  final String question;
  final String answer;
  final Origine origine;
  final Set<Tranche> tranches;

  bool get pourTous => tranches.length == kToutesTranches.length;
  // 1 facile (un enfant de huit ans repond), 2 moyen (culture generale
  // ordinaire), 3 difficile (connaisseur). Null tant que la question n'a pas
  // ete cotee : le fichier generé ne porte alors pas la cle, et l'app n'affiche
  // rien plutot qu'un niveau invente.
  final int? niveau;

  // « ages » n'est écrit que pour les questions qui appartiennent à certaines
  // tranches : l'absence de la clé veut dire « tout le monde », ce qui est le
  // cas de la grande majorité et garde les fichiers lisibles.
  Map<String, dynamic> toJson() => {
        'categorie': category,
        'question': question,
        'reponse': answer,
        if (niveau != null) 'niveau': niveau,
        if (!pourTous) 'ages': [for (final t in Tranche.values) if (tranches.contains(t)) t.name],
      };
}

void main(List<String> args) {
  // « --perissables » liste les questions à revoir une fois l'an plutôt que
  // de générer le site : c'est la commande de la revue annuelle.
  if (args.contains('--perissables')) {
    _listerPerissables();
    return;
  }
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

  // LES INÉDITES : des questions qui n'existent que dans le catalogue, jamais
  // dans le firmware. Elles rejoignent leur catégorie (la tuile grossit
  // d'autant), les Mélanges, les thématiques et les collections par niveau,
  // exactement comme celles de la banque : une question n'a pas à savoir
  // d'où elle vient.
  final inedites = _readInedites(parCategorie.keys.toSet());
  for (final e in inedites) {
    parCategorie.putIfAbsent(e.category, () => []).add(e);
    all.add(e);
  }
  stdout.writeln('${inedites.length} questions inédites, hors firmware.');

  // Pas deux fois la même question, d'où qu'elle vienne. Une inédite qui
  // reprend une question de la banque ne sert à rien ; deux questions de la
  // banque qui se répètent méritent une retouche.
  final vues = <String, Entry>{};
  for (final e in all) {
    final k = _cle(e);
    final deja = vues[k];
    if (deja != null) {
      stderr.writeln('Question en double : « ${e.question} » (${e.category}) '
          'et « ${deja.question} » (${deja.category}).');
      exit(1);
    }
    vues[k] = e;
  }

  final sansNiveau = all.where((e) => e.niveau == null).length;
  final retouchees = categories.fold<int>(
      0, (n, c) => n + (c.accented?.where((l) => l.retouche != null).length ?? 0));
  final retirees = categories.fold<int>(
      0, (n, c) => n + (c.accented?.where((l) => l.retiree != null).length ?? 0));
  final perissables = _perissablesLibres +
      categories.fold<int>(
          0, (n, c) => n + (c.accented?.where((l) => l.perissable != null).length ?? 0));
  stdout.writeln('${all.length - sansNiveau} questions cotées, '
      '$sansNiveau sans niveau, $retouchees retouchées, $retirees retirées, '
      '$perissables à revoir une fois l\'an.');

  final out = Directory(_outputDir);
  // Le dossier q/ est vidé avant d'écrire : sans ça, un questionnaire
  // renommé (ou une thématique retirée) laisserait son ancien fichier en
  // place, publié et invisible dans le catalogue.
  final qDir = Directory('$_outputDir/q');
  if (qDir.existsSync()) qDir.deleteSync(recursive: true);
  qDir.createSync(recursive: true);

  // Un fichier par catégorie, découpé en manches de 25.
  //
  // ÉTALÉ AVANT D'ÊTRE DÉCOUPÉ. La banque est écrite par grappes (les
  // « Combien de… », puis les inventeurs, puis les peintres), et découper le
  // fichier dans son ordre donnait des manches qui posaient trois questions
  // sur Jules Verne d'affilée. Graine dérivée du nom : régénérer redonne les
  // mêmes fichiers.
  for (final entry in parCategorie.entries) {
    _writeParts(entry.key, _etaler(entry.value, Random(_graine(entry.key))),
        note: 'Catégorie ${entry.key}.', emoji: _emojiDe(entry.key));
  }

  // PAR NIVEAU. Les catégories et les Mélanges brassent les trois niveaux,
  // ce qui donne des soirées où un enfant de huit ans attend son tour entre
  // deux questions sur Hammurabi. Ces deux collections trient : « 7 à 77
  // ans » ne garde que le niveau 1, celui où tout le monde dans la salle
  // peut répondre ; « Connaisseurs » ne garde que le niveau 3, pour que ces
  // questions restent jouables au lieu de disparaître du paysage.
  //
  // Le niveau 2 n'a pas de collection à lui : c'est le tout-venant, il est
  // partout ailleurs.
  // 7 À 77 ANS : QUARANTE MANCHES, PAS TOUT LE LOT FACILE.
  //
  // Le lot facile ferait cinquante-huit manches, mais les dernières seraient
  // forcément les moins bonnes : à la fin, il ne reste que ce que les
  // premières n'ont pas voulu. Quarante soirées suffisent largement, et
  // s'arrêter là garde le meilleur.
  //
  // LE MÉLANGE DES GÉNÉRATIONS NE SE FAIT PLUS ICI. J'avais écrit des quotas
  // par tranche d'âge pour composer ces manches ; ils sont partis. La tranche
  // qu'il faut servir dépend de qui est dans la salle CE SOIR-LÀ, et le
  // générateur ne peut pas le savoir. Chaque question porte donc ses tranches
  // dans le JSON (clé « ages »), et c'est l'application qui compose au
  // lancement de la partie, quand l'opérateur a la salle devant lui.
  //
  // Ce qui reste ici est un préréglage tout fait, pour qui ne veut rien
  // régler : le niveau facile, équilibré par catégorie, en quarante manches.
  const kPourTous = '7 à 77 ans';
  const kRondes7a77 = 40;
  final manches7a77 = _manchesProportionnelles(
    all.where((e) => e.niveau == 1).toList(),
    kMaxQuestions,
    Random(_graine(kPourTous)),
  ).take(kRondes7a77).toList();
  for (var i = 0; i < manches7a77.length; i++) {
    _write(
      '$kPourTous ${_numero(i + 1, manches7a77.length)} sur ${manches7a77.length}',
      manches7a77[i],
      note: 'Des questions auxquelles tout le monde peut répondre, de 7 à 77 ans, '
          'toutes catégories confondues. Manche ${i + 1} sur ${manches7a77.length}.',
      collection: kPourTous,
      emoji: '🎈',
    );
  }
  _writeManches(
    'Connaisseurs',
    all.where((e) => e.niveau == 3).toList(),
    note: 'Les questions les plus dures de la banque, toutes catégories confondues.',
    emoji: '🎓',
  );

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
    final trouvees = _etaler(all.where(theme.matches).toList(), Random(_graine(theme.name)));
    if (trouvees.length < 12) {
      stdout.writeln('  (ignoré : ${theme.name}, seulement ${trouvees.length} questions)');
      continue;
    }
    _writeParts(theme.name, trouvees,
        note: theme.note, emoji: theme.emoji, collection: theme.collection);
  }

  // Volontairement pas de fichier « Banque complète » : 2000 questions dans un
  // seul questionnaire, c'est exactement ce que le plafond interdit. Les 2000
  // sont là quand même, réparties dans les manches par catégorie.

  _controleQualite(all);

  _writeCatalogue();
  _writeVersion();
  _writeRevue(all);
  _writeAccueil();
  _writeIntrouvable();
  _writeEntetes();

  stdout.writeln('Écrit dans ${out.absolute.path}');
}

// --- Le catalogue et la page d'accueil -----------------------------------

// L'index que l'application télécharge en premier. Il porte tout ce qu'il
// faut pour DESSINER la bibliothèque (titres, collections, emoji, nombre de
// questions) sans télécharger un seul questionnaire. C'est ce qui permet
// d'afficher les 125 fiches, dont celles qu'on n'a pas encore rapatriées.
void _writeCatalogue() {
  final collections = <String, Map<String, dynamic>>{};
  for (final entree in _catalogue) {
    final nom = entree['collection'] as String;
    // Le pictogramme de la TUILE, qui n'est plus forcément celui de ses
    // fichiers : une thématique rangée sous une catégorie garde le sien. La
    // table tranche donc en premier, sinon la tuile hériterait du picto du
    // premier fichier écrit, et changerait de tête au moindre changement
    // d'ordre d'écriture.
    final vue = collections.putIfAbsent(
        nom,
        () => {
              'nom': nom,
              'emoji': kEmojiCategories[nom] ?? _emojiInedites[nom] ?? entree['emoji'],
              'questionnaires': 0,
              'questions': 0,
            });
    vue['questionnaires'] = (vue['questionnaires'] as int) + 1;
    vue['questions'] = (vue['questions'] as int) + (entree['questions'] as int);
  }

  final json = const JsonEncoder.withIndent('  ').convert({
    'format': 'buzzer-catalogue',
    'version': 1,
    'questionnaires': _catalogue,
    // Les collections sont déductibles des questionnaires, mais les
    // pré-calculer évite à l'application de refaire le regroupement au
    // démarrage, et fixe leur ordre une fois pour toutes.
    'collections': collections.values.toList()
      ..sort((a, b) => (a['nom'] as String).compareTo(b['nom'] as String)),
  });
  File('$_outputDir/catalogue.json').writeAsStringSync('$json\n');

  final questions = _catalogue.fold<int>(0, (s, e) => s + (e['questions'] as int));
  stdout.writeln('catalogue.json : ${_catalogue.length} questionnaires, '
      '${collections.length} collections, $questions questions.');
}

// Cloudflare Pages sert ses fichiers avec « max-age=0, must-revalidate »,
// donc rien n'est garde au bord du reseau : chaque requete traverse jusqu'a
// l'origine Pages, qui a sa propre limite de debit. Rapatrier une collection
// de seize questionnaires se faisait ainsi refuser en 429, et la
// verification du catalogue (126 requetes d'affilee) signalait une vingtaine
// de faux problemes.
//
// Ce n'etait pas un reglage de securite de la zone : l'en-tete cf-mitigated
// etait vide et cf-cache-status disait DYNAMIC a chaque appel.
//
// CES EN-TETES NE SUFFISENT PAS A EUX SEULS. Le cache de Cloudflare ne
// s'applique d'office qu'a une liste d'extensions statiques, dont .json ne
// fait pas partie : s-maxage etait ecrit et ignore. Il a fallu une regle de
// cache sur la zone sd6tools.net (Caching > Cache Rules), « Eligible for
// cache » sur le hostname buzzer.sd6tools.net, en mode « use cache-control
// header » pour que ce fichier reste la seule source des durees.
//
// LES DEUX DUREES DOIVENT RESTER EGALES, et c'est contre-intuitif.
//
// Un deploiement Pages NE PURGE PAS ce cache : mesure le 1er septembre 2026,
// un objet mis en cache avant un push etait toujours servi apres, avec un
// age qui montait. Les anciennes valeurs (une heure pour les questionnaires,
// cinq minutes pour l'index) creaient donc une fenetre ou l'index annoncait
// une nouvelle empreinte pendant que le bord servait encore l'ancien
// fichier. Le controle d'empreinte de l'app refusait alors le
// telechargement, a juste titre, pendant pres d'une heure.
//
// Garder l'index plus frais que ce qu'il decrit est un piege : il decrit des
// fichiers par leur empreinte, donc il ne peut pas etre en avance sur eux.
// Cinq minutes des deux cotes laissent une fenetre de cinq minutes apres une
// publication, et suffisent amplement a absorber la rafale que le cache
// existe pour absorber : rapatrier une collection de seize questionnaires
// prend quelques secondes.
//
// s-maxage vise le cache de Cloudflare, max-age le poste client.
void _writeEntetes() {
  // version.json n'est PAS mis en cache, et c'est voulu. Il n'est demande
  // qu'une fois par lancement de l'application, donc il ne pese rien sur la
  // limite de debit, et l'avis de mise a jour doit dire la verite tout de
  // suite : une version publiee ce matin n'a pas a rester invisible cinq
  // minutes de plus. Il tombait deja sur le defaut de Pages, mais par oubli
  // plutot que par decision ; c'est ecrit maintenant.
  File('$_outputDir/_headers').writeAsStringSync('''
/q/*
  Cache-Control: public, max-age=300, s-maxage=300

/catalogue.json
  Cache-Control: public, max-age=300, s-maxage=300

/version.json
  Cache-Control: public, max-age=0, must-revalidate
''');
}

// Sans ce fichier, Cloudflare Pages sert la page d'accueil AVEC un code 200
// pour n'importe quelle adresse inconnue. Un client qui demande
// /q/inexistant.json recevrait donc du HTML en croyant recevoir du JSON, et
// un coup d'œil au code de retour laisserait croire que tout va bien. Pire :
// on a bien cru un instant que tout le dépôt était publié, parce que
// /Questions.cpp et /.git/config repondaient 200.
void _writeIntrouvable() {
  File('$_outputDir/404.html').writeAsStringSync('''
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Introuvable</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: Georgia, "Times New Roman", serif; max-width: 40rem;
         margin: 6rem auto; padding: 0 1.5rem; line-height: 1.6; }
  code { background: rgba(127,127,127,.15); padding: 0.1rem 0.3rem; }
</style>
</head>
<body>
  <h1>Introuvable</h1>
  <p>Ce site ne publie que le catalogue de questionnaires du Buzzer :
     <code>/catalogue.json</code> et les questionnaires dans <code>/q/</code>.</p>
  <p><a href="/">Retour au catalogue</a></p>
</body>
</html>
''');
}
// Ce que l'application interroge pour savoir si elle est périmée.
//
// La comparaison porte sur le NUMÉRO DE BUILD, un entier qui ne fait que
// monter, et non sur la version affichée. Comparer « 1.10.0 » et « 1.9.0 »
// comme des chaînes donne la mauvaise réponse, et les comparer correctement
// demande du code sémantique qu'il faut réussir. Un « > » entre deux entiers
// n'a rien à rater.
//
// La version lisible voyage quand même : c'est elle qu'on montre à
// l'opérateur, « 1.2.0 » voulant dire quelque chose là où « build 7 » ne dit
// rien.
void _writeVersion() {
  final version = _versionApp();
  final build = _buildApp();
  final json = const JsonEncoder.withIndent('  ').convert({
    'format': 'buzzer-version',
    'version': version,
    'build': build,
    'notes': '$kDepotGitHub/releases/tag/v$version',
    'telechargement': '$kDepotGitHub/releases/download/v$version/'
        'buzzer-console-$version-windows.zip',
  });
  File('$_outputDir/version.json').writeAsStringSync('$json\n');
  stdout.writeln('version.json : $version (build $build)');
}

// La page d'accueil est une page de TÉLÉCHARGEMENT. Le site distribue une
// application ; le catalogue de questionnaires est la machinerie qu'elle va
// chercher toute seule, pas le sujet. Quelqu'un qui arrive sur l'adresse veut
// installer la console, pas lire un inventaire.
//
// Le compte de questionnaires reste, mais comme argument : c'est ce que
// l'application apporte, pas ce que le site expose.
//
// Volontairement sans dépendance, sans image et sans script : un seul fichier
// que Cloudflare sert tel quel.
//
// Le binaire n'est PAS publié ici. Un zip de 18 Mo par version, dans un dépôt
// qui en fait 11 au complet, et qu'aucune compression delta ne réduit d'une
// version à l'autre : chaque livraison resterait stockée en entier, pour
// toujours. Il vit dans les versions publiées de GitHub, et cette page y
// renvoie.
// --- La page de revue -----------------------------------------------------

// TOUTES les questions sur une seule page, par catégorie, avec leur niveau.
//
// Pourquoi une page et pas l'application : l'app montre les questionnaires,
// c'est-à-dire des manches de 25 découpées et brassées. Pour RELIRE une
// catégorie (repérer une question mal cotée, une ambiguïté, un trou), il faut
// la voir en entier, d'un coup, et pouvoir chercher un mot dedans.
//
// Générée avec le reste du site : elle ne peut pas décrire une banque
// différente de celle qui est publiée, ce qu'un fichier exporté à la main
// finirait toujours par faire.
//
// Les lignes sont écrites en dur dans le HTML plutôt que rendues par du
// script : la page se lit même si le script ne tourne pas, et le navigateur
// n'a rien à construire au chargement. Le script ne fait que filtrer.
// Les guillemets droits sont échappés aussi : ces chaînes servent autant de
// texte que de valeur d'attribut (data-k, data-cat), et un seul guillemet non
// échappé dans une question casserait la balise.
String _echappe(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const _motsNiveaux = {1: 'facile', 2: 'moyen', 3: 'difficile'};

const _motsTranches = {
  Tranche.enfants: 'enfants',
  Tranche.ados: 'ados',
  Tranche.adultes: 'adultes',
  Tranche.aines: 'aînés',
};

void _writeRevue(List<Entry> all) {
  final parCategorie = <String, List<Entry>>{};
  for (final e in all) {
    parCategorie.putIfAbsent(e.category, () => []).add(e);
  }

  int compte(Iterable<Entry> es, int niveau) =>
      es.where((e) => e.niveau == niveau).length;

  final sections = StringBuffer();
  final sommaire = StringBuffer();
  for (final nom in parCategorie.keys) {
    final es = parCategorie[nom]!;
    final id = _identifiant(nom);
    final emoji = _emojiDe(nom);
    sommaire.write('<a href="#$id" data-cat="${_echappe(nom)}">'
        '$emoji ${_echappe(nom)} <b>${es.length}</b></a>');

    final lignes = StringBuffer();
    for (var i = 0; i < es.length; i++) {
      final e = es[i];
      final n = e.niveau ?? 0;
      final marque = switch (e.origine) {
        Origine.inedite => '<i class="marque inedite">inédite</i>',
        Origine.retouchee => '<i class="marque retouchee">retouchée</i>',
        Origine.banque => '',
      };
      // « tous » plutôt que les quatre mots : c'est le cas le plus fréquent,
      // et l'écrire en entier sur mille lignes cacherait les restrictions,
      // qui sont justement ce qu'on vient relire.
      final ages = e.tranches.map((t) => t.name).join(' ');
      final agesVus = e.pourTous
          ? 'tous'
          : [for (final t in Tranche.values) if (e.tranches.contains(t)) _motsTranches[t]!].join(', ');
      lignes.write('<div class="ligne" data-n="$n" data-o="${e.origine.name}" '
          'data-a="$ages" '
          'data-k="${_echappe(_strip('${e.question} ${e.answer}').toLowerCase())}">'
          '<span class="num">${i + 1}</span>'
          '<span class="q">${_echappe(e.question)}</span>'
          '<span class="r">${_echappe(e.answer)}</span>'
          '<span class="niv niv$n">${_motsNiveaux[n] ?? '?'}</span>'
          '<span class="ages">$agesVus</span>'
          '<span class="marques">$marque</span>'
          '</div>');
    }

    sections.write('''
  <section id="$id" data-cat="${_echappe(nom)}">
    <h2>$emoji ${_echappe(nom)}</h2>
    <p class="compte">${es.length} questions · ${compte(es, 1)} faciles,
       ${compte(es, 2)} moyennes, ${compte(es, 3)} difficiles ·
       ${es.where((e) => e.origine == Origine.inedite).length} inédites</p>
    <div class="lignes">$lignes</div>
    <p class="vide">Aucune question ne correspond au filtre.</p>
  </section>
''');
  }

  final total = all.length;
  File('$_outputDir/revue.html').writeAsStringSync('''
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Revue des questions</title>
<meta name="robots" content="noindex">
<style>
  :root {
    color-scheme: light dark;
    --texte: #201e1d;
    --gris: #605d5d;
    --filet: rgba(32,30,29,.16);
    --accent: #006786;
    --magenta: #a8005c;
    --fond: #f3f2f2;
    --bande: #f3f2f2;
  }
  @media (prefers-color-scheme: dark) {
    :root { --texte: #ece9e9; --gris: #a8a4a4; --filet: rgba(236,233,233,.18);
            --accent: #62c5ee; --magenta: #ef8fc4; --fond: #1a1918;
            --bande: #1a1918; }
  }
  * { box-sizing: border-box; }
  body { font-family: Georgia, "Times New Roman", serif; max-width: 62rem;
         margin: 0 auto; padding: 2.5rem 1.5rem 6rem; line-height: 1.5;
         color: var(--texte); background: var(--fond); }
  h1 { font-size: 2.4rem; line-height: 1.1; margin: 0 0 .4rem; }
  .chapeau { color: var(--gris); margin: 0 0 1.5rem; }
  h2 { font-size: 1.5rem; margin: 0 0 .2rem; }
  .compte { color: var(--gris); font-size: .92rem; margin: 0 0 .8rem; }
  section { margin: 3rem 0 0; border-top: 2px solid var(--texte);
            padding-top: 1rem; }

  /* La barre de filtres suit le défilement : relire 246 questions veut dire
     défiler longtemps, et devoir remonter pour changer de filtre ferait
     perdre sa place à chaque fois. */
  .barre { position: sticky; top: 0; z-index: 2; background: var(--bande);
           border-bottom: 1px solid var(--filet); padding: .8rem 0;
           display: flex; flex-wrap: wrap; gap: .6rem; align-items: center; }
  .barre input[type=search] { font: inherit; font-size: 1rem; padding: .45rem .7rem;
           border: 1px solid var(--filet); background: transparent;
           color: var(--texte); min-width: 15rem; flex: 1; }
  .barre label { font-size: .95rem; color: var(--gris); display: inline-flex;
                 align-items: center; gap: .3rem; cursor: pointer; }
  .barre select { font: inherit; font-size: .95rem; padding: .4rem;
                  border: 1px solid var(--filet); background: transparent;
                  color: var(--texte); }
  #resultat { color: var(--gris); font-size: .92rem; }
  .sep { border-left: 1px solid var(--filet); align-self: stretch; }

  nav { display: flex; flex-wrap: wrap; gap: .1rem 1.1rem; margin: 0 0 .5rem; }
  nav a { color: var(--accent); text-decoration: none; font-size: .95rem; }
  nav a:hover { text-decoration: underline; }
  nav b { font-weight: normal; color: var(--gris); }

  .ligne { display: grid;
           grid-template-columns: 2.6rem minmax(0,1fr) 11rem 4.6rem 9rem 5rem;
           gap: .6rem; align-items: baseline; padding: .45rem 0;
           border-bottom: 1px solid var(--filet); }
  .ages { font-size: .8rem; color: var(--gris); }
  .num { color: var(--gris); font-size: .85rem; text-align: right; }
  .r { color: var(--magenta); font-style: italic; }
  .niv { font-size: .82rem; color: var(--gris); }
  .niv1 { color: #2e7d32; }
  .niv3 { color: #b35300; }
  @media (prefers-color-scheme: dark) {
    .niv1 { color: #7bc47f; } .niv3 { color: #e0a05a; }
  }
  .marque { font-size: .78rem; font-style: normal; color: var(--gris);
            border: 1px solid var(--filet); padding: .05rem .35rem; }
  .vide { display: none; color: var(--gris); font-style: italic; }
  section.rien .vide { display: block; }
  section.rien { opacity: .55; }
  .ligne.cache, section.cache { display: none; }

  @media (max-width: 46rem) {
    .ligne { grid-template-columns: 2.2rem minmax(0,1fr); }
    .r { grid-column: 2; } .niv, .ages, .marques { grid-column: 2; }
  }
  a.retour { color: var(--accent); }
</style>
</head>
<body>
  <h1>Revue des questions</h1>
  <p class="chapeau">Les $total questions de la banque, par catégorie, avec leur
     niveau. Cette page suit exactement ce qui est publié : elle est écrite en
     même temps que le catalogue. <a class="retour" href="/">Retour au site</a></p>

  <div class="barre">
    <input type="search" id="q" placeholder="Chercher dans les questions et les réponses"
           autocomplete="off">
    <label><input type="checkbox" class="niv-f" value="1" checked> facile</label>
    <label><input type="checkbox" class="niv-f" value="2" checked> moyen</label>
    <label><input type="checkbox" class="niv-f" value="3" checked> difficile</label>
    <span class="sep"></span>
    <label><input type="checkbox" class="age-f" value="enfants" checked> enfants</label>
    <label><input type="checkbox" class="age-f" value="ados" checked> ados</label>
    <label><input type="checkbox" class="age-f" value="adultes" checked> adultes</label>
    <label><input type="checkbox" class="age-f" value="aines" checked> aînés</label>
    <select id="origine">
      <option value="">Toutes provenances</option>
      <option value="banque">Banque du buzzer</option>
      <option value="inedite">Inédites</option>
      <option value="retouchee">Retouchées</option>
    </select>
    <span id="resultat"></span>
  </div>

  <nav>$sommaire</nav>

$sections
<script>
(function () {
  var champ = document.getElementById('q');
  var origine = document.getElementById('origine');
  var cases = [].slice.call(document.querySelectorAll('.niv-f'));
  var casesAge = [].slice.call(document.querySelectorAll('.age-f'));
  var resultat = document.getElementById('resultat');
  var lignes = [].slice.call(document.querySelectorAll('.ligne'));
  var sections = [].slice.call(document.querySelectorAll('section'));

  function sansAccents(s) {
    return s.normalize('NFD').replace(/[\\u0300-\\u036f]/g, '').toLowerCase();
  }

  function filtrer() {
    var mot = sansAccents(champ.value.trim());
    var niveaux = {};
    cases.forEach(function (c) { if (c.checked) niveaux[c.value] = true; });
    // Une question passe si UNE de ses tranches est cochée. Celles qui
    // appartiennent à tout le monde portent les quatre, donc elles passent
    // toujours : décocher « aînés » ne cache que ce qui est propre aux aînés.
    var ages = {};
    casesAge.forEach(function (c) { if (c.checked) ages[c.value] = true; });
    var prov = origine.value;
    var visibles = 0;

    sections.forEach(function (section) {
      var compte = 0;
      var enfants = section.querySelectorAll('.ligne');
      for (var i = 0; i < enfants.length; i++) {
        var l = enfants[i];
        var sesAges = l.dataset.a.split(' ');
        var ageOk = false;
        for (var j = 0; j < sesAges.length; j++) {
          if (ages[sesAges[j]] === true) { ageOk = true; break; }
        }
        var ok = niveaux[l.dataset.n] === true && ageOk &&
                 (prov === '' || l.dataset.o === prov) &&
                 (mot === '' || l.dataset.k.indexOf(mot) !== -1);
        l.classList.toggle('cache', !ok);
        if (ok) compte++;
      }
      section.classList.toggle('rien', compte === 0);
      visibles += compte;
    });

    resultat.textContent = visibles === $total
      ? '$total questions'
      : visibles + ' question' + (visibles > 1 ? 's' : '') + ' sur $total';
  }

  champ.addEventListener('input', filtrer);
  origine.addEventListener('change', filtrer);
  cases.forEach(function (c) { c.addEventListener('change', filtrer); });
  casesAge.forEach(function (c) { c.addEventListener('change', filtrer); });
  filtrer();
})();
</script>
</body>
</html>
''');
  stdout.writeln('revue.html : $total questions relisibles sur une page.');
}

void _writeAccueil() {
  final collections = <String, int>{};
  for (final entree in _catalogue) {
    final nom = entree['collection'] as String;
    collections[nom] = (collections[nom] ?? 0) + 1;
  }
  final questions = _catalogue.fold<int>(0, (s, e) => s + (e['questions'] as int));
  final version = _versionApp();
  final lien = '$kDepotGitHub/releases/download/v$version/'
      'buzzer-console-$version-windows.zip';

  File('$_outputDir/index.html').writeAsStringSync('''
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Console de l'animateur</title>
<meta name="description" content="La console de l'animateur du Buzzer, pour Windows.">
<style>
  :root {
    color-scheme: light dark;
    --texte: #201e1d;
    --gris: #605d5d;
    --filet: rgba(32,30,29,.16);
    --accent: #006786;
    --fond: #f3f2f2;
  }
  @media (prefers-color-scheme: dark) {
    :root { --texte: #ece9e9; --gris: #a8a4a4; --filet: rgba(236,233,233,.18);
            --accent: #62c5ee; --fond: #1a1918; }
  }
  * { box-sizing: border-box; }
  body { font-family: Georgia, "Times New Roman", serif; max-width: 44rem;
         margin: 0 auto; padding: 4rem 1.5rem; line-height: 1.6;
         color: var(--texte); background: var(--fond); }
  h1 { font-size: 2.6rem; line-height: 1.1; margin: 0 0 .4rem; }
  .chapeau { color: var(--gris); font-size: 1.2rem; margin: 0 0 2.5rem; }
  .telecharger { display: inline-block; background: var(--accent);
                 color: var(--fond); text-decoration: none; font-size: 1.15rem;
                 padding: .9rem 1.6rem; border: 0; }
  .telecharger:hover { filter: brightness(1.12); }
  .sous-bouton { color: var(--gris); font-size: .95rem; margin-top: .7rem; }
  h2 { font-size: 1rem; letter-spacing: .09em; text-transform: uppercase;
       color: var(--gris); font-weight: normal; margin: 3rem 0 .8rem;
       border-top: 1px solid var(--filet); padding-top: 1.2rem; }
  ul { padding-left: 1.1rem; }
  li { margin-bottom: .5rem; }
  code { background: rgba(127,127,127,.15); padding: .1rem .35rem; }
  footer { margin-top: 3.5rem; border-top: 1px solid var(--filet);
           padding-top: 1.2rem; color: var(--gris); font-size: .92rem; }
  a { color: var(--accent); }
</style>
</head>
<body>
  <h1>Console de l'animateur</h1>
  <p class="chapeau">Menez une soirée de quiz depuis votre ordinateur, avec un
     écran projeté pour la salle. L'application pilote le buzzer par Bluetooth.</p>

  <a class="telecharger" href="$lien">Télécharger pour Windows</a>
  <p class="sous-bouton">Version $version · environ $kTailleTelechargement ·
     Windows 10 ou 11, 64 bits</p>

  <h2>Ce qu'elle fait</h2>
  <ul>
    <li>Conduit la partie : question posée, buzz, bonne ou mauvaise réponse,
        scores, chrono. Le clavier du buzzer se verrouille pendant ce temps.</li>
    <li>Affiche un <strong>écran public</strong> dans une fenêtre séparée, à
        glisser sur le projecteur et à passer en plein écran. Ce que la salle
        voit dépend du jeu, et la réponse n'y apparaît jamais avant la fin de
        la question.</li>
    <li>Joue les sons par les haut-parleurs de l'ordinateur plutôt que par le
        petit haut-parleur du buzzer, et retombe sur ce dernier si le lien
        Bluetooth tombe.</li>
    <li>Apporte <strong>$questions questions</strong> en
        ${_catalogue.length} questionnaires, aucun ne dépassant 25 questions.
        Vous pouvez aussi écrire les vôtres.</li>
  </ul>

  <h2>Installation</h2>
  <ul>
    <li>Décompressez l'archive où vous voulez, puis lancez
        <code>buzzer_companion.exe</code>. Il n'y a rien à installer.</li>
    <li>Gardez les fichiers ensemble : l'exécutable a besoin des bibliothèques
        et du dossier <code>data</code> qui l'accompagnent.</li>
    <li>Windows peut afficher un avertissement au premier lancement, faute de
        signature de code. « Informations complémentaires », puis « Exécuter
        quand même ».</li>
  </ul>

  <h2>Il vous faut aussi</h2>
  <ul>
    <li>Le buzzer à quatre boutons, avec son module Bluetooth.</li>
    <li>Un ordinateur Windows avec Bluetooth basse énergie.</li>
    <li>Un second écran ou un projecteur, si vous voulez l'écran public.</li>
  </ul>

  <footer>
    Les questionnaires sont téléchargés par l'application depuis ce même site.
    Toutes les questions se relisent sur une page :
    <a href="/revue.html">la revue des questions</a>.
    Le code est ouvert : <a href="$kDepotGitHub">$kDepotGitHubCourt</a>.
  </footer>
</body>
</html>
''');
}

// Lue dans pubspec.yaml plutôt que recopiée ici : une version en double finit
// toujours par diverger, et c'est la page publique qui mentirait.
String _versionApp() {
  final pubspec = File('pubspec.yaml');
  if (pubspec.existsSync()) {
    for (final ligne in pubspec.readAsLinesSync()) {
      if (ligne.startsWith('version:')) {
        // « 1.0.0+1 » : le numéro de build ne regarde pas l'utilisateur.
        return ligne.substring(8).trim().split('+').first;
      }
    }
  }
  stderr.writeln('Version introuvable dans pubspec.yaml.');
  exit(1);
}

// Le nombre après le « + » de « 1.0.0+1 ». C'est lui qui décide si une
// version est plus récente qu'une autre, alors on refuse de deviner : sans
// numéro de build, mieux vaut arrêter le générateur que publier un
// version.json qui empêcherait toute mise à jour d'être annoncée.
int _buildApp() {
  final pubspec = File('pubspec.yaml');
  if (pubspec.existsSync()) {
    for (final ligne in pubspec.readAsLinesSync()) {
      if (ligne.startsWith('version:')) {
        final morceaux = ligne.substring(8).trim().split('+');
        final build = morceaux.length > 1 ? int.tryParse(morceaux[1]) : null;
        if (build != null) return build;
      }
    }
  }
  stderr.writeln('Numéro de build absent de pubspec.yaml (attendu « 1.0.0+1 »).');
  exit(1);
}

// --- Lecture de Questions.cpp -------------------------------------------

class _Category {
  _Category(this.name, this.lines, this.accented);
  final String name;
  final List<String> lines;        // "Question|Reponse", sans accents
  final List<_Ligne>? accented;    // même ordre, accentué et coté, ou null
}

// Une ligne du fichier accentué. Le fichier porte plus que les accents,
// maintenant : le niveau de la question, et au besoin une RETOUCHE.
//
// La retouche est la seule façon de corriger une question sans toucher au
// firmware. L'invariant (dépouillée de ses accents, la ligne redonne la
// source) interdit de reformuler dans la ligne elle-même, et c'est voulu :
// c'est lui qui prouve que rien n'a dérivé. Une question ambiguë (« Qui a
// cofondé Microsoft ? », Gates ou Allen) reçoit donc une ligne « > » juste
// dessous, avec l'énoncé et la réponse qui la remplacent dans les fichiers
// générés. La source reste intacte, l'invariant tient, et le buzzer autonome
// continue de poser l'ancienne question jusqu'à ce qu'on décide de le
// reflasher.
class _Ligne {
  _Ligne(this.texte, this.niveau);
  final String texte;      // "Question|Réponse", aligné sur la source
  final int? niveau;       // 1, 2, 3, ou null tant que non coté
  String? retouche;        // "Question|Réponse" servi à la place, ou null
  // Raison du retrait, ou null. Une question retirée reste DANS le fichier,
  // à sa place, avec le motif écrit à côté : le fichier doit garder une ligne
  // par question de la source, et le motif se relit quand on se demande, dans
  // deux ans, pourquoi elle n'est plus jouée.
  String? retiree;
  // Ce qu'il faut revérifier, ou null. Marqué par une ligne « ~ raison ».
  // Réservé aux questions dont la réponse peut devenir FAUSSE alors que
  // l'énoncé reste valable : un record qu'on bat, un joueur qui change
  // d'équipe, un compte qui bouge. « Qui a fondé Québec ? » sera vrai dans
  // vingt ans et ne se marque pas. Une marque qui disparaîtrait rendrait sa
  // question caduque, pas fausse : elle ne se marque pas non plus.
  String? perissable;
  Set<Tranche>? tranches;
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

// --- Inédites ------------------------------------------------------------

// Les questions d'après le séparateur : celles qui n'existent que dans
// l'application. Aucun alignement à respecter, mais exactement la même
// syntaxe — c'est tout l'intérêt d'avoir fusionné les deux dossiers.
//
// Pas d'en-tête qui vaudrait pour tout le fichier : ce serait une règle
// implicite de plus, et l'exception y passerait inaperçue. Chaque question
// écrit son niveau et ses tranches.
// La revue annuelle : lit les fichiers de questions et sort ce qu'il faut
// aller revérifier, avec la raison écrite à côté du marqueur. Ne génère rien.
void _listerPerissables() {
  var n = 0;
  for (final fichier in _fichiersQuestions()) {
    final marquees = <String>[];
    for (final bloc in [fichier.miroir, fichier.libres]) {
      for (final ligne in _lireBloc(bloc, fichier.nom)) {
        if (ligne.perissable == null) continue;
        final servie = ligne.retouche ?? ligne.texte;
        marquees.add('   ${servie.split('|').first.trim()}\n'
            '      → ${servie.split('|').last.trim()}   (${ligne.perissable})');
      }
    }
    if (marquees.isEmpty) continue;
    stdout.writeln('${fichier.categorie} (${marquees.length})');
    marquees.forEach(stdout.writeln);
    n += marquees.length;
  }
  stdout.writeln('\n$n questions à revérifier. '
      'Chacune reste jouable, mais sa réponse a une date de péremption.');
}

final _emojiInedites = <String, String>{};

// Les questions à revoir une fois l'an qui vivent du côté libre du fichier :
// leurs _Ligne ne survivent pas à la lecture, alors on les compte au passage.
int _perissablesLibres = 0;

String _emojiDe(String categorie) =>
    kEmojiCategories[categorie] ?? _emojiInedites[categorie] ?? '';

List<Entry> _readInedites(Set<String> categoriesConnues) {
  final entries = <Entry>[];
  for (final fichier in _fichiersQuestions()) {
    // Le pictogramme du fichier fait foi pour une catégorie que le firmware
    // ne connaît pas : sans lui, sa tuile n'aurait pas d'image.
    _emojiInedites[fichier.categorie] = fichier.emoji;
    for (final ligne in _lireBloc(fichier.libres, fichier.nom)) {
      if (ligne.retiree != null) continue;
      if (ligne.perissable != null) _perissablesLibres++;
      final servie = ligne.retouche ?? ligne.texte;
      final sep = servie.indexOf('|');
      entries.add(Entry(
        fichier.categorie,
        servie.substring(0, sep).trim(),
        servie.substring(sep + 1).trim(),
        niveau: ligne.niveau,
        origine: Origine.inedite,
        tranches: ligne.tranches ?? kToutesTranches,
      ));
    }
  }
  return entries;
}

// --- Accents -------------------------------------------------------------

// Format d'une ligne : « Question|Réponse|niveau|tranches ». Les quatre champs
// sont obligatoires : le niveau (1 à 3) et les tranches d'âge, séparées par
// des espaces. Une ligne qui commence par « > » retouche la question
// juste au-dessus, « - » la retire. Les lignes vides et les « # » sont des
// commentaires.
// Le même bloc de lignes se lit des deux côtés du séparateur : c'est ce qui
// permet aux deux moitiés d'un fichier de catégorie d'avoir exactement la
// même syntaxe, retouches et retraits compris.
List<_Ligne> _lireBloc(List<String> lignes, String nom) {
  final lues = <_Ligne>[];
  for (final l in lignes) {
    final ou = '$nom, question ${lues.length + 1}';

    // Retrait : la question reste dans le fichier et dans le firmware, mais
    // ne sort plus dans les questionnaires. Sert quand une question n'a pas
    // sa place dans une soirée, plutôt qu'elle soit fausse ou mal posée.
    if (l.startsWith('-')) {
      if (lues.isEmpty) {
        stderr.writeln('$ou : retrait sans question à retirer.');
        exit(1);
      }
      lues.last.retiree = l.substring(1).trim();
      continue;
    }

    // Péremption : la question reste jouable, mais sa réponse a une date de
    // péremption. Le générateur les liste à chaque passage pour qu'on les
    // revoie une fois l'an, plutôt que de découvrir en pleine soirée que
    // le joueur a changé d'équipe.
    if (l.startsWith('~')) {
      if (lues.isEmpty) {
        stderr.writeln('$ou : péremption sans question à marquer.');
        exit(1);
      }
      lues.last.perissable = l.substring(1).trim();
      continue;
    }

    if (l.startsWith('>')) {
      if (lues.isEmpty || lues.last.retouche != null) {
        stderr.writeln('$ou : retouche sans question à retoucher, ou deuxième '
            'retouche pour la même question.');
        exit(1);
      }
      final r = l.substring(1).trim();
      if (r.split('|').length != 2) {
        stderr.writeln('$ou : une retouche s\'écrit « > Question|Réponse ».');
        exit(1);
      }
      lues.last.retouche = r;
      continue;
    }

    final champs = l.split('|');
    if (champs.length != 4) {
      stderr.writeln('$ou : attendu « Question|Réponse|niveau|tranches », lu « $l ».');
      exit(1);
    }
    final niveau = int.tryParse(champs[2].trim());
    if (niveau == null || niveau < 1 || niveau > 3) {
      stderr.writeln('$ou : le niveau doit être 1, 2 ou 3, lu « ${champs[2]} ».');
      exit(1);
    }
    lues.add(_Ligne('${champs[0]}|${champs[1]}', niveau)
      ..tranches = _tranchesDepuis(champs[3], ou));
  }
  return lues;
}

// Le miroir de la catégorie [index] du firmware, s'il existe.
List<_Ligne>? _readAccents(int index, int expected) {
  final fichier = _fichiersQuestions().where((f) => f.firmware == index).firstOrNull;
  if (fichier == null) return null;
  final lignes = _lireBloc(fichier.miroir, fichier.nom);
  if (lignes.length != expected) {
    stderr.writeln('${fichier.nom} : ${lignes.length} lignes avant le séparateur '
        'pour $expected questions dans Questions.cpp. Le miroir a dérivé.');
    exit(1);
  }
  return lignes;
}

List<Entry> _applyAccents(_Category cat) {
  final accented = cat.accented;
  final entries = <Entry>[];
  final categoryName = accented == null ? cat.name : _accentedName(cat.name);

  for (var i = 0; i < cat.lines.length; i++) {
    final cotee = accented?[i];
    final ligne = cotee?.texte ?? cat.lines[i];

    // L'invariant : sans ses accents, la ligne accentuée DOIT redonner la
    // source au caractère près. C'est ce qui garantit qu'on n'a fait
    // qu'accentuer. La retouche, elle, n'y est pas soumise : c'est justement
    // la ligne qui a le droit de dire autre chose que la source.
    if (accented != null && _strip(ligne) != cat.lines[i]) {
      stderr.writeln('${cat.name}, ligne ${i + 1} : la version accentuée ne '
          "correspond pas à la source.");
      stderr.writeln('  source   : ${cat.lines[i]}');
      stderr.writeln('  accentué : $ligne');
      stderr.writeln('  dépouillé: ${_strip(ligne)}');
      exit(1);
    }

    // Retirée : l'invariant a été vérifié juste au-dessus (le fichier reste
    // aligné sur la source), mais la question ne descend pas dans le catalogue.
    if (cotee?.retiree != null) continue;

    final servie = cotee?.retouche ?? ligne;
    final sep = servie.indexOf('|');
    entries.add(Entry(
      categoryName,
      servie.substring(0, sep).trim(),
      servie.substring(sep + 1).trim(),
      niveau: cotee?.niveau,
      origine: cotee?.retouche != null ? Origine.retouchee : Origine.banque,
      tranches: cotee?.tranches ?? kToutesTranches,
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
      {this.exclude = const [],
      this.excludeCategories = const [],
      this.collection});

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

  // Sous quelle tuile ranger la thematique, quand ce n'est pas la sienne.
  // Exclure une categorie regle le fond (aucune question en double) mais pas
  // la forme : la bibliotheque se lit en survolant des tuiles, et deux tuiles
  // voisines qui portent le meme sujet donnent l'impression d'un doublon,
  // meme quand il n'y en a pas. La thematique se range donc DANS la tuile de
  // la categorie dont elle est le complement, ou son titre suffit a la
  // distinguer des manches ordinaires.
  //
  // Null pour une thematique qui traverse les categories sans en doubler
  // aucune : elle merite sa propre tuile.
  final String? collection;

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
  // Rangée sous la tuile « Québec » et non à côté : deux tuiles québécoises
  // voisines dans la bibliothèque se lisaient comme un doublon, alors que la
  // distinction ne se voit qu'en ouvrant les fichiers. Le titre des manches
  // la porte très bien à l'intérieur de la tuile.
  //
  // Son sapin lui reste : dans une tuile à fleur de lys, il signale d'un coup
  // d'œil les cinq manches qui ne sont pas la catégorie.
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
  ], excludeCategories: ['Québec'], collection: 'Québec'),
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
    rondes.add(_etaler(ronde, rnd));
    decalage = (decalage + reste) % noms.length;
  }
  return rondes;
}

// Découpe un lot en manches où CHAQUE MANCHE A LA MÊME COMPOSITION.
//
// Le problème que ça règle : « 7 à 77 ans » puise dans un lot où le cinéma
// pèse 203 questions et l'histoire 67. Brassé puis découpé, ça donnait une
// ronde à cinq questions de cinéma et une seule d'histoire, et la suivante
// sans aucune histoire ni musique. Sur une manche de 25, un tirage au sort
// n'a aucune raison de tomber juste : c'est la loi des petits nombres, pas
// un défaut de la graine.
//
// La règle est celle des plus forts quotients : à chaque place, la catégorie
// qui maximise « ce qui lui reste, divisé par ce qu'elle a déjà pris dans
// cette manche ». Une catégorie deux fois plus fournie prend deux fois plus
// de places, mais elle ne peut pas rafler toute la manche, et une petite
// catégorie garde toujours la sienne.
//
// PROPORTIONNEL, ET NON À PARTS ÉGALES comme les Mélanges. Des parts égales
// videraient l'histoire (67 questions faciles) après 26 manches et
// laisseraient 779 questions inutilisées. Le jour où les catégories faibles
// seront étoffées, passer à parts égales ne coûtera plus rien.
List<List<Entry>> _manchesProportionnelles(List<Entry> lot, int taille, Random rnd) {
  final restant = <String, List<Entry>>{};
  for (final e in lot) {
    restant.putIfAbsent(e.category, () => []).add(e);
  }
  for (final l in restant.values) {
    l.shuffle(rnd);
  }

  final manches = <List<Entry>>[];
  var total = lot.length;
  while (total > 0) {
    final combien = min(taille, total);
    final pris = <String, int>{};
    final manche = <Entry>[];
    for (var i = 0; i < combien; i++) {
      String? choix;
      var meilleur = 0.0;
      for (final nom in restant.keys) {
        if (restant[nom]!.isEmpty) continue;
        final quotient = restant[nom]!.length / ((pris[nom] ?? 0) + 1);
        if (choix == null || quotient > meilleur) {
          choix = nom;
          meilleur = quotient;
        }
      }
      pris[choix!] = (pris[choix] ?? 0) + 1;
      manche.add(restant[choix]!.removeLast());
    }
    total -= combien;
    // Étalée à l'intérieur : la répartition dit COMBIEN de chaque catégorie,
    // pas dans quel ordre, et deux questions voisines du même sujet se
    // remarquent autant ici qu'ailleurs.
    manches.add(_etaler(manche, rnd));
  }
  return manches;
}

// Graine reproductible tirée d'un nom. Pas la longueur du nom : « Québec »
// et « Sports » en ont la même, et brassaient donc pareil.
int _graine(String nom) => nom.codeUnits.fold(17, (h, c) => (h * 31 + c) & 0x7fffffff);

// Brasse une liste en ÉCARTANT les questions qui se ressemblent. Un simple
// mélange laisse passer deux questions sur Jules Verne côte à côte une fois
// sur dix ; ici, une question qui partage un mot marquant avec l'une des
// quatre précédentes attend son tour.
//
// « Marquant » se décide par la fréquence dans le lot lui-même, pas par une
// liste de mots à ignorer : « film » revient dans la moitié des questions de
// Cinéma et n'y distingue rien, mais dans une ronde toutes catégories il
// signale bien deux questions de cinéma. Le seuil est relatif à la taille du
// lot pour que la règle tienne aussi bien pour 25 questions que pour 200.
//
// Glouton : on prend la première candidate acceptable dans le reste brassé.
// Faute de candidate, on accepte la voisine plutôt que de tourner en rond :
// vers la fin d'un lot, il ne reste parfois que des questions qui se
// ressemblent.
const kFenetreVoisinage = 4;

List<Entry> _etaler(List<Entry> entries, Random rnd) {
  final frequence = <String, int>{};
  final mots = <Entry, Set<String>>{};
  for (final e in entries) {
    final m = _motsMarquants(e);
    mots[e] = m;
    for (final mot in m) {
      frequence[mot] = (frequence[mot] ?? 0) + 1;
    }
  }
  final seuil = max(3, entries.length * 15 ~/ 100);
  for (final e in entries) {
    mots[e]!.removeWhere((mot) => frequence[mot]! >= seuil);
  }

  final reste = List<Entry>.of(entries)..shuffle(rnd);
  final resultat = <Entry>[];
  while (reste.isNotEmpty) {
    final debut = max(0, resultat.length - kFenetreVoisinage);
    final voisinage = <String>{
      for (var i = debut; i < resultat.length; i++) ...mots[resultat[i]]!,
    };
    var choisi = reste.indexWhere((e) => mots[e]!.intersection(voisinage).isEmpty);
    if (choisi < 0) choisi = 0;
    resultat.add(reste.removeAt(choisi));
  }
  return resultat;
}

// Les mots d'au moins quatre lettres, sans accents ni majuscules, de l'énoncé
// et de la réponse. Les mots-outils courts (« qui », « que », « de ») tombent
// d'eux-mêmes ; les plus longs (« quel », « comment », « combien ») sont
// éliminés par la fréquence dans _etaler.
//
// La catégorie compte comme un mot marquant : dans une ronde toutes
// catégories, deux questions de cinéma d'affilée se remarquent autant que
// deux questions sur Jules Verne. Dans une manche de catégorie, où toutes
// les questions la partagent, la fréquence l'élimine d'elle-même.
Set<String> _motsMarquants(Entry e) => {
      'categorie:${e.category}',
      ..._strip('${e.question} ${e.answer}')
          .toLowerCase()
          .split(RegExp('[^a-z0-9]+'))
          .where((m) => m.length >= 4),
    };

// Deux défauts que la relecture ne voit pas mais qu'une machine attrape, sur
// les versions SERVIES : la réponse déjà donnée dans l'énoncé, et deux
// questions différentes qui attendent la même réponse. Ni l'un ni l'autre
// n'arrête la génération : les cas légitimes existent (« la vitamine C »
// quand la question dit vitamine, « Quatre » qui répond à vingt questions
// sans rapport). Mais le compte s'affiche à chaque passage, et une hausse
// veut dire qu'un lot est entré sans être contrôlé.
void _controleQualite(List<Entry> all) {
  // Les mots outils ne comptent pas : « appelle-t-on » se retrouve partout.
  const vides = {
    'le', 'la', 'les', 'un', 'une', 'des', 'du', 'de', 'au', 'aux', 'dans',
    'sur', 'sous', 'pour', 'par', 'avec', 'sans', 'que', 'qui', 'quoi', 'dont',
    'est', 'sont', 'fait', 'font', 'quel', 'quelle', 'quels', 'quelles',
    'comment', 'combien', 'quand', 'pourquoi', 'appelle', 'nomme', 'deux',
    'trois', 'plus', 'tout', 'toute', 'tous', 'toutes', 'son', 'sa', 'ses',
  };
  String plat(String s) => _strip(s)
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9 ]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  var echos = 0;
  for (final e in all) {
    final q = plat(e.question);
    final mots = plat(e.answer)
        .split(' ')
        .where((m) => m.length > 3 && !vides.contains(m))
        .toList();
    if (mots.isEmpty) continue;
    // La racine plutôt que le mot entier : « voiles » doit attraper « voile ».
    final donnes = mots.where((m) {
      final racine = m.substring(0, max(5, m.length - 2).clamp(0, m.length));
      return q.contains(racine);
    }).length;
    if (donnes == mots.length) echos++;
  }

  final parReponse = <String, List<Entry>>{};
  for (final e in all) {
    final k = plat(e.answer)
        .replaceFirst(RegExp(r'^(le|la|les|un|une|des|du|de la) '), '');
    (parReponse[k] ??= []).add(e);
  }
  final collisions = parReponse.values.where((v) => v.length > 1).length;

  // Le quasi-doublon : deux questions de la même catégorie qui attendent la
  // même réponse et partagent au moins trois mots porteurs. Le contrôle des
  // doublons ne les voit pas, leur texte diffère ; au jeu, c'est deux fois la
  // même question. Celui-là s'affiche en détail, parce qu'il n'a pas de cas
  // légitime : quand il en sort un, une des deux lignes est de trop.
  var jumelles = 0;
  Set<String> porteurs(String s) => plat(s)
      .split(' ')
      .where((m) => m.length > 2 && !vides.contains(m))
      .toSet();
  for (final v in parReponse.values) {
    for (var i = 0; i < v.length; i++) {
      for (var j = i + 1; j < v.length; j++) {
        if (v[i].category != v[j].category) continue;
        final communs = porteurs(v[i].question).intersection(porteurs(v[j].question));
        if (communs.length < 3) continue;
        jumelles++;
        stderr.writeln('Quasi-doublon (${v[i].category}) « ${v[i].answer} » :');
        stderr.writeln('   ${v[i].question}');
        stderr.writeln('   ${v[j].question}');
      }
    }
  }

  // La variante de nom : deux réponses différentes désignent la même chose,
  // et le joueur qui donne l'autre nom se fait refuser alors qu'il a raison.
  // « La tire » et « la tire d'érable », « L'Ère de glace » et « L'Âge de
  // glace », « le casque » et « le casque de vélo ». Le signal : deux
  // réponses proches à l'écrit ET deux énoncés qui parlent du même sujet.
  // On regroupe par mot de la réponse pour ne pas comparer tout avec tout.
  final parMot = <String, List<Entry>>{};
  for (final e in all) {
    for (final m in plat(e.answer).split(' ')) {
      if (m.length > 2 && !vides.contains(m)) (parMot[m] ??= []).add(e);
    }
  }
  var variantes = 0;
  final vues = <String>{};
  for (final v in parMot.values) {
    if (v.length > 60) continue;   // un mot trop courant ne dit rien
    for (var i = 0; i < v.length; i++) {
      for (var j = i + 1; j < v.length; j++) {
        final a = plat(v[i].answer), b = plat(v[j].answer);
        if (a == b) continue;
        if (!a.contains(b) && !b.contains(a)) continue;
        if (porteurs(v[i].question).intersection(porteurs(v[j].question)).length < 2) continue;
        final signature = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
        if (!vues.add(signature)) continue;
        variantes++;
        stderr.writeln('Deux noms pour la même chose « ${v[i].answer} » / '
            '« ${v[j].answer} » :');
        stderr.writeln('   ${v[i].question}');
        stderr.writeln('   ${v[j].question}');
      }
    }
  }

  stdout.writeln('Contrôle : $echos réponses déjà dans leur question, '
      '$collisions réponses partagées par plusieurs questions, '
      '$jumelles quasi-doublons, $variantes variantes de nom.');
}

// La clé d'unicité d'une question : l'énoncé sans accents, sans casse, sans
// ponctuation finale. La même règle que l'app applique pour ne pas reposer
// deux fois la même question dans une soirée.
String _cle(Entry e) => _strip(e.question)
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[?!.\s]+$'), '')
    .trim();

// Écrit une collection dont chaque manche a la même composition par
// catégorie. Contrairement à _writeParts, qui découpe une liste déjà ordonnée,
// celle-ci compose chaque manche à partir du lot entier.
void _writeManches(String titre, List<Entry> lot,
    {required String note, required String emoji}) {
  final manches = _manchesProportionnelles(lot, kMaxQuestions, Random(_graine(titre)));
  for (var i = 0; i < manches.length; i++) {
    _write(
      '$titre ${_numero(i + 1, manches.length)} sur ${manches.length}',
      manches[i],
      note: '$note Manche ${i + 1} sur ${manches.length}.',
      collection: titre,
      emoji: emoji,
    );
  }
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

// Ce que le catalogue publiera, rempli au fil des écritures.
final _catalogue = <Map<String, dynamic>>[];
final _idsVus = <String, String>{};

void _write(String titre, List<Entry> entries,
    {required String note, required String collection, required String emoji}) {
  final contenu = '${const JsonEncoder.withIndent('  ').convert({
        'format': 'buzzer-questionnaire',
        'version': 1,
        'titre': titre,
        'note': note,
        // Range le fichier sous sa tuile dans la bibliothèque de l'app. Sans
        // elle, les 125 fichiers arrivent en un seul tas.
        'collection': collection,
        'emoji': emoji,
        'questions': entries.map((e) => e.toJson()).toList(),
      })}\n';

  final id = _identifiant(titre);
  final deja = _idsVus[id];
  if (deja != null) {
    stderr.writeln('Collision d\'identifiant « $id » : « $deja » et « $titre » '
        'produisent le même nom de fichier.');
    exit(1);
  }
  _idsVus[id] = titre;

  final octets = utf8.encode(contenu);
  File('$_outputDir/q/$id.json').writeAsStringSync(contenu);

  // Combien de questions de chaque niveau. C'est ce qui permet à l'app
  // d'annoncer la difficulté d'un questionnaire sur sa fiche, avant même de
  // l'avoir téléchargé. Absent tant qu'aucune question n'est cotée.
  final niveaux = <String, int>{};
  for (final e in entries) {
    if (e.niveau != null) {
      niveaux['${e.niveau}'] = (niveaux['${e.niveau}'] ?? 0) + 1;
    }
  }

  _catalogue.add({
    'id': id,
    'titre': titre,
    'note': note,
    'collection': collection,
    'emoji': emoji,
    'questions': entries.length,
    if (niveaux.isNotEmpty) 'niveaux': niveaux,
    'octets': octets.length,
    // Empreinte du contenu : c'est ce qui permet à l'application de savoir
    // qu'une copie locale est périmée après une régénération, au lieu de
    // garder indéfiniment une vieille version sans le dire.
    'empreinte': sha1.convert(octets).toString(),
  });

  stdout.writeln('  q/$id.json  (${entries.length})');
}

// Identifiant stable, sûr dans une URL. Les titres portent des accents, des
// apostrophes et des espaces : « L'espace et le ciel 1 sur 3 » deviendrait
// « L%27espace%20et%20le%20ciel... » dans une adresse, illisible et sensible
// aux différences d'encodage entre Windows, Cloudflare et Dart. Le titre
// lisible vit dans le JSON, pas dans le nom du fichier.
String _identifiant(String titre) => _strip(titre)
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
