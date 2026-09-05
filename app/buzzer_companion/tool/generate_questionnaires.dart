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

// Le generateur ecrit un SITE, pas un dossier de travail. Ce site est publie
// par Cloudflare Pages sur buzzer.sd6tools.net, et l'application va y
// chercher sa banque :
//
//   site/
//     index.html          page de telechargement, pour l'humain
//     banque.json         toutes les questions, une seule fois chacune
//     revue.html          les memes questions a relire, par categorie
//     version.json        de quoi savoir si l'application est perimee
//
// IL N'Y A PLUS DE QUESTIONNAIRES SUR LE SITE. Il y en a eu 283, decoupes en
// manches de 25 : un plafond pose parce qu'une soiree n'est pas un marathon,
// et qu'au-dela d'une vingtaine de questions les invites decrochent. Le
// plafond avait raison, mais le decoupage figeait a la generation ce qui doit
// se decider devant la salle. C'est l'application qui compose sa manche
// maintenant, a partir de cette banque et des criteres choisis au lancement.
//
// Le dossier configure dans l'application ne contient donc plus que les
// questionnaires PERSONNELS de l'operateur.
//
// Le chemin est relatif a app/buzzer_companion, d'ou le script se lance.
var _outputDir = '../../site';

// LA BANQUE EMBARQUÉE. Le site est la source vivante, mais une installation
// neuve dans une salle sans wifi n'a rien : le cache disque ne se remplit
// qu'après une première lecture en ligne réussie. On embarque donc une copie
// dans le build, qui sert de plancher.
//
// UN SEUL FICHIER et non 283. La même matière en 283 fichiers d'assets ferait
// 283 lignes de diff à chaque question corrigée, en plus des 283 du site :
// le bruit doublerait et cacherait les vrais changements. Un fichier unique
// se lit d'un coup et se diffe en une ligne.
const _assetBanque = 'assets/questions/banque.json';

// Le format de la banque, verifie par l'application avant de la lire : un
// fichier tronque ou une vieille version ne doit pas passer pour une banque
// vide, ce qui donnerait un ecran sans questions sans dire pourquoi.
const kFormatBanque = 'buzzer-banque';


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
      {this.niveau,
      this.origine = Origine.banque,
      required this.tranches,
      this.themes = const {}});
  final String category;
  final String question;
  final String answer;
  final Origine origine;
  final Set<Tranche> tranches;
  // Les thematiques ecrites sur la question dans son fichier. Vide pour la
  // plupart : une thematique est une exception, pas un rangement de plus.
  final Set<String> themes;

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
  // « --themes » montre CE QUE CHAQUE MOT-CLÉ A RAMASSÉ.
  //
  // Une thématique n'est pas écrite sur la question : elle est déduite d'une
  // liste de mots-clés au moment de générer. C'est commode, et c'est
  // exactement pour ça que ça se vérifie mal : « neige » attrape Blanche-Neige
  // et « dents » attrape Les Dents de la mer, sans que rien ne le signale.
  // Cette commande met chaque mot-clé en face de ses prises pour qu'on puisse
  // couper ceux qui ratissent large.
  if (args.contains('--themes')) {
    _auditThemes();
    return;
  }
  // « --proposer <slug> » sort les candidates d'une thematique, PAS ENCORE
  // etiquetees, une par ligne avec son fichier et son rang. C'est la liste
  // qu'on relit pour decider, et le moyen de ne pas relire trois mille
  // questions a chaque thematique.
  final iEtiqueter = args.indexOf('--etiqueter');
  if (iEtiqueter >= 0) {
    _etiqueter(args.sublist(iEtiqueter + 1));
    return;
  }
  final iProposer = args.indexOf('--proposer');
  if (iProposer >= 0) {
    _proposer(iProposer + 1 < args.length ? args[iProposer + 1] : '');
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
  out.createSync(recursive: true);
  // LE DOSSIER q/ EST EFFACÉ, PAS SEULEMENT DÉLAISSÉ. Il tenait les 283
  // questionnaires prédécoupés ; ne plus les écrire ne les enlève pas du
  // site, et Cloudflare continuerait à servir la dernière version publiée à
  // toute application encore configurée pour aller la chercher. Même chose
  // pour catalogue.json, qui les indexait.
  final qDir = Directory('$_outputDir/q');
  if (qDir.existsSync()) qDir.deleteSync(recursive: true);
  final ancienCatalogue = File('$_outputDir/catalogue.json');
  if (ancienCatalogue.existsSync()) ancienCatalogue.deleteSync();

  // PLUS AUCUN QUESTIONNAIRE PRÉDÉCOUPÉ ICI.
  //
  // Il y en avait 283 : un par catégorie découpée en manches de 25, seize
  // rondes toutes catégories, « 7 à 77 ans », « Connaisseurs », les
  // thématiques. Chacun était un choix figé au moment de la génération —
  // combien de questions, quel niveau, quelle tranche d'âge — pris des mois
  // avant la soirée, par un script qui ne savait pas qui serait dans la
  // pièce.
  //
  // L'application compose maintenant la manche au lancement de la partie, à
  // partir de la banque et des critères que l'opérateur coche devant sa
  // salle. Les fichiers ne servaient plus qu'à répéter, en moins souple, ce
  // que le tirage fait mieux, et ils coûtaient 283 lignes de diff à chaque
  // question corrigée.
  //
  // Ce que le générateur publie tient maintenant en un fichier.
  _controleQualite(all);

  _writeBanqueQuestions(all);
  _writeVersion();
  _writeRevue(all);
  _writeAccueil(all);
  _writeIntrouvable();
  _writeEntetes();

  stdout.writeln('Écrit dans ${out.absolute.path}');
}

// --- Ce que le site publie ------------------------------------------------

// LA BANQUE : chaque question UNE FOIS, avec de quoi la retrouver.
//
// C'est le format qui remplace les questionnaires prédécoupés. Découper la
// banque en 283 fichiers servait à choisir un questionnaire tout fait ; on
// compose maintenant la manche au moment de jouer, selon la pièce qu'on a
// devant soi, et une liste plate suffit.
//
// LES THÉMATIQUES DEVIENNENT DES ÉTIQUETTES. « Spécial Noël » ou « Créatures
// et légendes » traversent les catégories, et c'est tout leur intérêt : aucune
// catégorie du firmware ne sait rassembler le renne, la bûche, les chants et
// le Grincheux. Elles étaient calculées par mots-clés pour fabriquer des
// fichiers ; le même calcul écrit maintenant une étiquette sur la question,
// et l'application filtre dessus. La curation survit, les fichiers non.
//
// Écrite à deux endroits, le même contenu : dans le site, que l'application
// va relire pour se mettre à jour, et dans les assets, pour qu'une
// installation neuve sans wifi ait de quoi jouer.
void _writeBanqueQuestions(List<Entry> all) {
  // Les thématiques d'abord : une question peut en porter plusieurs.
  //
  // LUES SUR LA QUESTION, plus devinées : c'est le marqueur « @ » de son
  // fichier qui fait foi. Une thématique vide ne s'annonce pas, mais elle ne
  // s'ignore pas en silence non plus.
  final etiquettes = <Entry, List<String>>{};
  final comptesThemes = <String, int>{};
  for (final theme in kThemes) {
    final trouvees = all.where((e) => e.themes.contains(theme.slug)).toList();
    // Le même plancher qu'avant : sous douze questions, une thématique ne
    // remplit même pas une demi-manche. Elle est signalée plutôt que passée
    // sous silence, sinon une thématique qu'on vient d'ouvrir et qu'on n'a
    // étiquetée qu'à moitié disparaîtrait sans un mot.
    if (trouvees.length < 12) {
      if (trouvees.isNotEmpty) {
        stdout.writeln('  (${theme.name} : ${trouvees.length} questions '
            'étiquetées, il en faut 12 pour la publier)');
      }
      continue;
    }
    comptesThemes[theme.name] = trouvees.length;
    for (final e in trouvees) {
      (etiquettes[e] ??= []).add(theme.name);
    }
  }

  final comptesCategories = <String, int>{};
  for (final e in all) {
    comptesCategories[e.category] = (comptesCategories[e.category] ?? 0) + 1;
  }

  final contenu = {
    'format': kFormatBanque,
    'version': 1,
    'categories': [
      for (final nom in comptesCategories.keys.toList()..sort())
        {
          'nom': nom,
          'emoji': kEmojiCategories[nom] ?? _emojiInedites[nom] ?? '',
          'questions': comptesCategories[nom],
        },
    ],
    'themes': [
      for (final theme in kThemes)
        if (comptesThemes.containsKey(theme.name))
          {
            'nom': theme.name,
            'emoji': theme.emoji,
            'note': theme.note,
            'questions': comptesThemes[theme.name],
          },
    ],
    'questions': [
      for (final e in all)
        {
          ...e.toJson(),
          if (etiquettes[e] != null) 'themes': etiquettes[e],
        },
    ],
  };

  // Sans indentation : personne ne relit ce fichier, et les espaces
  // partiraient dans chaque installation comme dans chaque téléchargement.
  final json = '${jsonEncode(contenu)}\n';
  File('$_outputDir/banque.json').writeAsStringSync(json);
  // La même matière dans les assets : une installation neuve dans une salle
  // sans wifi doit avoir de quoi jouer.
  final asset = File(_assetBanque);
  asset.parent.createSync(recursive: true);
  asset.writeAsStringSync(json);

  final ko = (utf8.encode(json).length / 1024).round();
  stdout.writeln('banque.json : ${all.length} questions, '
      '${comptesCategories.length} catégories, ${comptesThemes.length} '
      'thématiques, $ko ko. Copiée dans $_assetBanque.');
}


// Cloudflare Pages sert ses fichiers avec « max-age=0, must-revalidate »,
// donc rien n'est garde au bord du reseau : chaque requete traverse jusqu'a
// l'origine Pages, qui a sa propre limite de debit. C'est ce qui refusait en
// 429 le rapatriement d'une collection du temps des 283 questionnaires.
//
// Ce n'etait pas un reglage de securite de la zone : l'en-tete cf-mitigated
// etait vide et cf-cache-status disait DYNAMIC a chaque appel.
//
// LA RAFALE A DISPARU AVEC LES 283 FICHIERS : la banque est un seul fichier,
// demande une fois par lancement. L'en-tete reste quand meme, et pour une
// raison qui n'est plus la meme : ce fichier fait plus d'un demi-mega, et le
// faire traverser jusqu'a l'origine a chaque demarrage d'application n'a
// aucun interet quand il ne change qu'a une publication.
//
// CET EN-TETE NE SUFFIT PAS A LUI SEUL. Le cache de Cloudflare ne s'applique
// d'office qu'a une liste d'extensions statiques, dont .json ne fait pas
// partie : s-maxage etait ecrit et ignore. Il a fallu une regle de cache sur
// la zone sd6tools.net (Caching > Cache Rules), « Eligible for cache » sur le
// hostname buzzer.sd6tools.net, en mode « use cache-control header » pour que
// ce fichier reste la seule source des durees.
//
// Un deploiement Pages NE PURGE PAS ce cache : mesure le 1er septembre 2026,
// un objet mis en cache avant un push etait toujours servi apres, avec un age
// qui montait. Cinq minutes laissent donc une fenetre de cinq minutes apres
// une publication pendant laquelle une application peut encore recevoir
// l'ancienne banque. C'est sans consequence : elle la garde en cache disque,
// et le lancement suivant prendra la neuve.
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
/banque.json
  Cache-Control: public, max-age=300, s-maxage=300

/version.json
  Cache-Control: public, max-age=0, must-revalidate
''');
}

// Sans ce fichier, Cloudflare Pages sert la page d'accueil AVEC un code 200
// pour n'importe quelle adresse inconnue. Un client qui demande
// /banque.jsno recevrait donc du HTML en croyant recevoir du JSON, et
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
  <p>Ce site publie la console de l'animateur du Buzzer et sa banque de
     questions : <code>/banque.json</code>.</p>
  <p><a href="/">Retour à l'accueil</a></p>
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

void _writeAccueil(List<Entry> all) {
  final questions = all.length;
  final categories = all.map((e) => e.category).toSet().length;
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
    <li>Apporte <strong>$questions questions</strong> en $categories
        catégories, cotées par difficulté et par tranche d'âge. Vous choisissez
        vos critères avant chaque manche et l'application la compose sur le
        champ. Vous pouvez aussi écrire vos propres questionnaires.</li>
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
    La banque de questions est téléchargée par l'application depuis ce même site.
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
  // Les thématiques auxquelles la question appartient, écrites en toutes
  // lettres sous elle : « @ noel creatures ». Vide par défaut.
  //
  // ÉCRITES, ET NON DÉDUITES. Elles l'étaient, par mots-clés, et se
  // trompaient sans le dire : « neige » mettait Blanche-Neige dans Sports
  // d'hiver. Une thématique est un jugement sur le sujet de la question, du
  // même ordre que sa catégorie, et la catégorie n'a jamais été devinée.
  final Set<String> themes = {};
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
        themes: ligne.themes,
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

    // Thématiques : « @ noel creatures ». Une question peut en porter
    // plusieurs, une thématique traverse les catégories.
    if (l.startsWith('@')) {
      if (lues.isEmpty) {
        stderr.writeln('$ou : thématique sans question à étiqueter.');
        exit(1);
      }
      for (final slug in l.substring(1).trim().split(RegExp(r'\s+'))) {
        if (slug.isEmpty) continue;
        // UN SLUG INCONNU ARRÊTE LA GÉNÉRATION. Une faute de frappe
        // produirait sinon une étiquette qui n'existe nulle part : la
        // question disparaîtrait de sa thématique sans que rien ne le dise,
        // ce qui est exactement le défaut qu'on vient de corriger.
        if (!kThemes.any((t) => t.slug == slug)) {
          stderr.writeln('$ou : thématique inconnue « $slug ». '
              'Connues : ${kThemes.map((t) => t.slug).join(', ')}.');
          exit(1);
        }
        lues.last.themes.add(slug);
      }
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
      themes: cotee?.themes ?? const {},
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
  const Theme(this.slug, this.name, this.emoji, this.note, this.keywords,
      {this.exclude = const [],
      this.excludeCategories = const [],
      this.proposeAges = const [],
      this.collection});

  // Ce qu'on écrit dans les fichiers de questions, sous la ligne : « @ noel ».
  // Sans accents ni espaces, parce qu'un nom accentué dans un fichier soumis
  // à l'invariant des accents serait une invitation au dégât.
  final String slug;
  final String name;
  final String emoji;
  final String note;

  // LES MOTS-CLÉS NE CLASSENT PLUS RIEN. Ils ne servent qu'à PROPOSER des
  // candidates à la relecture (« --themes » et « --proposer »), et l'étiquette
  // n'existe que si quelqu'un l'a écrite dans le fichier.
  //
  // Ils ont classé, et mal. Un audit des prises l'a montré : « neige »
  // ramassait Olaf et Blanche-Neige dans Sports d'hiver, « dents » ramassait
  // Les Dents de la mer dans Le corps humain, et « cotes » y ramassait « Combien
  // de côtés a un carré ? » parce que l'invariant sans accents transforme
  // côtés en cotes. Environ soixante des cent trente-sept questions de Sports
  // d'hiver n'étaient pas des sports. Rien ne le signalait : une déduction ne
  // se trompe jamais bruyamment.
  //
  // Comme pour la catégorie et les tranches d'âge, une question ne porte
  // désormais que ce qu'on a écrit sur elle.
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

  // UN FILET QUI NE PASSE PAS PAR LES MOTS, pour « --proposer » seulement.
  //
  // Aucun mot-clé ne sait repérer un souvenir : rien dans « Quelle chaîne
  // d'épicerie québécoise a fermé ses portes en 1992 ? » ne dit qu'elle
  // appartient à un monde révolu, sinon le fait qu'on ait coté la question
  // pour les aînés. La banque porte donc déjà l'information, sur l'autre axe.
  //
  // Une question devient candidate quand toutes ses tranches déclarées
  // tiennent dans cette liste : « aînés » attrape ce qui ne vise qu'eux, et
  // laisse dehors ce qui vise aussi les ados. N'a AUCUN effet sur ce qui est
  // publié, comme le reste : seule l'étiquette écrite compte.
  final List<String> proposeAges;

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
  Theme('noel', 'Spécial Noël', '🎄', 'Le temps des fêtes, toutes catégories confondues.', [
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
  Theme('quebec-ailleurs', 'Le Québec ailleurs', '🌲',
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
  Theme('regne-animal', 'Le règne animal', '🐾', 'Bêtes à poil, à plume et à écailles.', [
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
  Theme('espace', "L'espace et le ciel", '🪐', 'Planètes, étoiles et conquête spatiale.', [
    'planete', 'planetes', 'soleil', 'lune', 'lunes', 'etoile', 'etoiles',
    'galaxie', 'espace', 'astronaute', 'satellite', 'telescope', 'orbite',
    'comete', 'meteorite', 'eclipse', 'mars', 'jupiter', 'saturne', 'venus',
    'mercure', 'uranus', 'neptune', 'pluton', 'apollo', 'spoutnik',
    'hubble', 'gagarine', 'armstrong', 'aldrin', 'trou noir', 'voie lactee',
    'astre', 'astres', 'astronomie', 'astronome', 'spatiale', 'spatial',
    'aurore boreale', 'equateur', 'hemispheres', 'marees', 'atmosphere',
  ]),
  Theme('corps-humain', 'Le corps humain', '🧠', 'Os, organes et petites mécaniques internes.', [
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
  Theme('super-heros', 'Super-héros et BD', '🦸', 'Capes, masques et bulles.', [
    'super-heros', 'superheros', 'marvel', 'batman', 'superman',
    'spider-man', 'hulk', 'iron man', 'thor', 'wonder woman', 'aquaman',
    'wolverine', 'ant-man', 'thanos', 'captain america', 'joker', 'robin',
    'gotham', 'krypton', 'kryptonite', 'clark kent', 'lois lane', 'alfred',
    'tony stark', 'groot', 'gardiens', 'mutant', 'mutants', 'asterix',
    'obelix', 'idefix', 'panoramix', 'tintin', 'milou', 'herge',
    'schtroumpfs', 'gargamel', 'lucky luke', 'dalton', 'picsou', 'popeye',
    'garfield', 'bd',
  ]),
  Theme('creatures', 'Créatures et légendes', '🐉', 'Monstres, dieux et histoires qu\'on se raconte.', [
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
  Theme('sports-hiver', "Sports d'hiver", '⛷️', 'Tout ce qui se joue sur la glace ou la neige.', [
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
  // Le pendant du règne animal, et le mieux réparti de tous : l'érable et la
  // tubulure côté Québec, la photosynthèse côté Sciences, l'épinard côté
  // Bouffe, le pin blanc du drapeau de Montréal au passage.
  Theme('regne-vegetal', 'Le règne végétal', '🌿',
      'Arbres, fleurs, et tout ce qui pousse.', [
    'arbre', 'arbres', 'fleur', 'fleurs', 'plante', 'plantes', 'feuille',
    'feuilles', 'racine', 'racines', 'graine', 'graines', 'foret', 'forets',
    'erable', 'erables', 'erabliere', 'chene', 'sapin', 'epinette', 'pin',
    'bouleau', 'saule', 'peuplier', 'sequoia', 'bambou', 'eucalyptus',
    'cactus', 'champignon', 'champignons', 'mousse', 'algue', 'algues',
    'herbe', 'gazon', 'jardin', 'potager', 'legume', 'legumes', 'tige',
    'petale', 'petales', 'pollen', 'photosynthese', 'seve', 'tronc',
    'branche', 'branches', 'ecorce', 'bourgeon', 'tulipe', 'marguerite',
    'tournesol', 'orchidee', 'nenuphar', 'lilas', 'pissenlit', 'fougere',
    'bonsai', 'semer', 'germer', 'botanique', 'bleuet', 'bleuets',
  ]),
  Theme('mer', 'La mer et les bateaux', '⚓',
      'Océans, navigation, et ce qui se passe au large.', [
    'mer', 'mers', 'ocean', 'oceans', 'bateau', 'bateaux', 'navire',
    'navires', 'marin', 'marins', 'voilier', 'traversier', 'ferry',
    'paquebot', 'chaloupe', 'canot', 'kayak', 'radeau', 'sous-marin',
    'port', 'quai', 'phare', 'ancre', 'voile', 'voiles', 'coque',
    'proue', 'equipage', 'capitaine', 'matelot', 'naufrage',
    'pirate', 'pirates', 'corsaire', 'ile', 'iles', 'archipel', 'plage',
    'vague', 'vagues', 'maree', 'marees', 'recif', 'lagon', 'baie',
    'golfe', 'detroit', 'fleuve', 'estuaire', 'coquillage', 'titanic',
    'croisiere', 'boussole', 'sextant', 'gouvernail', 'nautique',
  ]),
  Theme('transports', 'Les transports', '🚗',
      'Autos, trains, avions, ponts et tunnels.', [
    'auto', 'autos', 'automobile', 'voiture', 'voitures', 'camion',
    'camions', 'autobus', 'autocar', 'moto', 'motocyclette', 'scooter',
    'velo', 'bicyclette', 'trottinette', 'train', 'trains', 'locomotive',
    'wagon', 'rails', 'tramway', 'metro', 'avion', 'avions', 'helicoptere',
    'fusee', 'montgolfiere', 'route', 'routes', 'autoroute',
    'pont', 'ponts', 'tunnel', 'tunnels', 'viaduc', 'permis', 'conduire',
    'conducteur', 'chauffeur', 'pneu', 'pneus', 'volant', 'freins',
    'moteur', 'essence', 'klaxon', 'pare-brise', 'ceinture de securite',
    'stationnement', 'circulation', 'peage', 'roue', 'roues', 'diligence',
    'traineau', 'charrue', 'souffleuse', 'motoneige',
  ]),
  // DEMANDÉE MALGRÉ SA CONCENTRATION. Les trois quarts de ses prises viennent
  // de Cinéma et télé, ce qui en fait presque une sous-catégorie du même
  // ordre que Le corps humain ; le client la veut quand même, et une manche
  // Disney se demande vraiment un soir de party avec des enfants.
  //
  // PIXAR EN EST, DREAMWORKS N'EN EST PAS. Shrek, Kung Fu Panda, Dragons et
  // Madagascar sortent de DreamWorks, les Minions et le Grinch
  // d'Illumination. Ils se ressemblent tous à l'écran et la confusion est
  // facile, mais une manche Disney qui pose Shrek se fait reprendre par le
  // premier enfant venu.
  Theme('disney', 'Disney', '🏰', 'Le royaume de Mickey, Pixar compris.', [
    'disney', 'pixar', 'mickey', 'minnie', 'donald', 'dingo', 'pluto',
    'picsou', 'walt', 'simba', 'mufasa', 'nala', 'timon', 'pumbaa',
    'ariel', 'ursula', 'aladin', 'jasmine', 'abu', 'genie',
    'raiponce', 'elsa', 'anna', 'olaf', 'sven', 'kristoff',
    'moana', 'vaiana', 'maui', 'tiana', 'mulan', 'pocahontas', 'cendrillon',
    'blanche-neige', 'clochette', 'peter pan', 'crochet',
    'dumbo', 'bambi', 'baloo', 'mowgli', 'stitch', 'lilo', 'nemo', 'dory',
    'woody', 'buzz', 'sulley', 'wall-e', 'remy',
    'ratatouille', 'toy story', 'roi lion', 'reine des neiges',
    'petite sirene', 'livre de la jungle', 'incroyables', 'coco', 'luca',
    'vice-versa', 'monstres inc', 'flash mcqueen', 'nains',
  ], exclude: [
    // DreamWorks et Illumination, que le filet attrape par ressemblance.
    'shrek', 'fiona', 'krokmou', 'harold', 'minions', 'gru', 'grinch',
    'madagascar', 'chat potte',
  ]),
  // CE QUI A DISPARU DU QUOTIDIEN, et non « ce qui est vieux ». Le tramway de
  // Montréal, le catalogue qui arrivait par la poste, Steinberg, le TV Hebdo.
  //
  // AUCUN MOT-CLÉ NE SAIT REPÉRER UN SOUVENIR. Le filet ci-dessous ramasse les
  // marques et les objets nommément disparus, mais l'essentiel se trouve
  // autrement : par les tranches d'âge, puisque la banque cote déjà « aînés »
  // les questions qui appartiennent à un monde révolu. C'est à quoi sert
  // proposeAges.
  Theme('nostalgie', 'Dans l\'temps', '📻',
      'Ce qui a disparu du quotidien : marques, émissions, objets.', [
    'autrefois', 'jadis', 'antan', 'ancien', 'ancienne', 'anciens',
    'disparu', 'disparue', 'epoque',
    'tramway', 'catalogue', 'walkman', 'baladeur', 'cassette', 'cassettes',
    'vinyle', 'tourne-disque', 'disquette',
    'magnetoscope', 'vhs', 'polaroid', 'diapositive',
    'telegramme', 'annuaire', 'bottin', 'laitier', 'glaciere',
    'steinberg', 'eaton', 'woolworth', 'kresge',
    'tv hebdo', 'cre basile', 'symphorien', 'yeye', 'discotheque',
    'club video', 'transistor', 'sears', 'lessiveuse', 'tordeur',
  ], proposeAges: ['aines']),
];

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


// Ancre stable et sure dans une URL. Les noms de categorie portent des
// accents, des apostrophes et des espaces : « Mots et langue » deviendrait
// « Mots%20et%20langue » dans un href, illisible et sensible aux differences
// d'encodage entre Windows, Cloudflare et Dart. Le nom lisible reste dans le
// texte du lien.
String _identifiant(String titre) => _strip(titre)
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

// Ce que chaque mot-clé de chaque thématique a réellement ramassé.
//
// La sortie est faite pour être LUE, pas pour passer un test : c'est un
// jugement humain qui décide si « Les Dents de la mer » a sa place dans « Le
// corps humain ». Les mots-clés sont donc classés du plus gourmand au moins
// gourmand, avec deux prises en exemple pour chacun : un mot qui ramasse
// quarante questions et dont les deux exemples sont hors sujet se repère en
// une seconde.
void _auditThemes() {
  final categories = _parseCategories(File(_sourcePath).readAsStringSync());
  final all = <Entry>[];
  final parCategorie = <String, List<Entry>>{};
  for (final cat in categories) {
    final entries = _applyAccents(cat);
    parCategorie[entries.first.category] = entries;
    all.addAll(entries);
  }
  all.addAll(_readInedites(parCategorie.keys.toSet()));

  for (final theme in kThemes) {
    final prises = all.where(theme.matches).toList();
    stdout.writeln('\n=== ${theme.name} : ${prises.length} questions');
    // Une question peut répondre à plusieurs mots-clés ; on la compte pour le
    // PREMIER qui la retient, celui dont la suppression la libérerait.
    final parMot = <String, List<Entry>>{};
    for (final e in prises) {
      final texte = _strip('${e.question} ${e.answer}').toLowerCase();
      final mot = theme.keywords.firstWhere(
          (m) => Theme._motPresent(texte, m),
          orElse: () => '?');
      (parMot[mot] ??= []).add(e);
    }
    final mots = parMot.keys.toList()
      ..sort((a, b) => parMot[b]!.length.compareTo(parMot[a]!.length));
    for (final mot in mots) {
      final lot = parMot[mot]!;
      stdout.writeln('  ${lot.length.toString().padLeft(4)}  « $mot »');
      for (final e in lot.take(2)) {
        stdout.writeln('        ${e.question}  →  ${e.answer}');
      }
    }
    final jamais =
        theme.keywords.where((m) => !parMot.containsKey(m)).toList();
    if (jamais.isNotEmpty) {
      stdout.writeln('     0  jamais seuls : ${jamais.join(', ')}');
    }
  }
}

// Les candidates d'une thématique qui ne portent pas encore son étiquette.
//
// C'est l'outil de l'étiquetage, et il ne décide rien : il ramasse large avec
// les mots-clés et rend une liste à lire. Chaque ligne dit où écrire le
// marqueur, parce que retrouver à la main la bonne ligne dans onze fichiers
// de deux cents questions est le vrai coût de l'exercice.
void _proposer(String slug) {
  if (!kThemes.any((t) => t.slug == slug)) {
    stderr.writeln('Thématique inconnue « $slug ». '
        'Connues : ${kThemes.map((t) => t.slug).join(', ')}.');
    exit(1);
  }
  final theme = kThemes.firstWhere((t) => t.slug == slug);
  var deja = 0;
  var proposees = 0;

  for (final fichier in _fichiersQuestions()) {
    final lignes = <String>[];
    // Les deux blocs se relisent : une question du firmware et une inédite
    // s'étiquettent pareil, et rien ne dit qu'une thématique ne vit que d'un
    // côté.
    for (final bloc in [
      (nom: 'miroir', contenu: fichier.miroir),
      (nom: 'libres', contenu: fichier.libres),
    ]) {
      final lues = _lireBloc(bloc.contenu, fichier.nom);
      for (var i = 0; i < lues.length; i++) {
        final ligne = lues[i];
        if (ligne.retiree != null) continue;
        if (ligne.themes.contains(slug)) {
          deja++;
          continue;
        }
        final servie = ligne.retouche ?? ligne.texte;
        final sep = servie.indexOf('|');
        final e = Entry(
          fichier.categorie,
          servie.substring(0, sep).trim(),
          servie.substring(sep + 1).trim(),
          niveau: ligne.niveau,
          tranches: ligne.tranches ?? kToutesTranches,
        );
        // Les mots-clés OU les tranches : deux filets pour la même liste à
        // relire, et un thème comme « Dans l'temps » ne vit que du second.
        final parAges = theme.proposeAges.isNotEmpty &&
            !e.pourTous &&
            e.tranches.every((t) => theme.proposeAges.contains(t.name));
        if (!theme.matches(e) && !parAges) continue;
        proposees++;
        lignes.add('  ${bloc.nom} #${i + 1}  ${e.question}  →  ${e.answer}');
      }
    }
    if (lignes.isEmpty) continue;
    stdout.writeln('\n--- ${fichier.nom}  (${lignes.length})');
    lignes.forEach(stdout.writeln);
  }

  stdout.writeln('\n« ${theme.name} » : $deja déjà étiquetées, '
      '$proposees candidates à relire.');
  stdout.writeln('Les mots-clés ne servent qu\'à proposer : rien n\'est '
      'étiqueté tant qu\'un « @ $slug » n\'est pas écrit sous la question.');
}

// Écrit le marqueur « @ <slug> » sous les questions désignées.
//
//   dart run tool/generate_questionnaires.dart --etiqueter noel bouffe-et-cuisine.txt miroir 12,40,77
//
// À LA MAIN, C'EST LA MAUVAISE LIGNE. Les rangs comptent les questions, pas
// les lignes du fichier : entre la question 40 et la question 41 se glissent
// les retouches, les retraits et les autres thématiques, et le décalage
// s'accumule à chaque insertion. Cette commande compte comme le lecteur du
// fichier compte, et insère au bon endroit même quand elle en insère trente.
//
// Un rang déjà porteur de l'étiquette est ignoré sans bruit : relancer la
// même commande deux fois ne double rien.
void _etiqueter(List<String> args) {
  if (args.length < 4) {
    stderr.writeln('Usage : --etiqueter <slug> <fichier.txt> <miroir|libres> '
        '<rangs séparés par des virgules>');
    exit(1);
  }
  final slug = args[0];
  if (!kThemes.any((t) => t.slug == slug)) {
    stderr.writeln('Thématique inconnue « $slug ». '
        'Connues : ${kThemes.map((t) => t.slug).join(', ')}.');
    exit(1);
  }
  final nom = args[1];
  final bloc = args[2];
  if (bloc != 'miroir' && bloc != 'libres') {
    stderr.writeln('Le bloc est « miroir » ou « libres », lu « $bloc ».');
    exit(1);
  }
  final rangs = args[3]
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toSet();
  if (rangs.isEmpty) {
    stderr.writeln('Aucun rang lisible dans « ${args[3]} ».');
    exit(1);
  }

  final fichier = File('$_questionsDir/$nom');
  if (!fichier.existsSync()) {
    stderr.writeln('Introuvable : ${fichier.absolute.path}');
    exit(1);
  }
  final lignes = fichier.readAsLinesSync();
  // LA MÊME RÈGLE QUE LE LECTEUR, sinon les deux ne parlent pas des mêmes
  // questions. Sans « # Firmware », un fichier n'a rien à refléter et TOUT y
  // est libre, séparateur ou pas (voir _fichiersQuestions). Culture pop est
  // dans ce cas : « --proposer » y annonçait des rangs « libres » que
  // « --etiqueter » cherchait dans un bloc miroir vide.
  final toutLibre = !lignes.any((l) => l.trim().startsWith('# Firmware'));
  final sortie = <String>[];
  var apresSeparateur = toutLibre;
  var rang = 0;
  var attente = false; // Une question vient d'être vue ; ses marqueurs suivent.
  var poses = 0;
  var deja = 0;

  // Le marqueur se pose APRÈS les marqueurs existants de la même question,
  // pour que le fichier garde un ordre stable et se relise sans surprise.
  void vider() {
    if (!attente) return;
    attente = false;
    if (rangs.contains(rang)) {
      sortie.add('@ $slug');
      poses++;
    }
  }

  for (final brute in lignes) {
    final l = brute.trim();
    if (l.isEmpty || l.startsWith('#') || l == _separateur) {
      vider();
      if (l == _separateur) apresSeparateur = true;
      sortie.add(brute);
      continue;
    }
    final estMarqueur = l.startsWith('>') ||
        l.startsWith('-') ||
        l.startsWith('~') ||
        l.startsWith('@');
    if (estMarqueur) {
      // Déjà étiquetée : on note, et « vider » ne repassera pas dessus.
      if (l.startsWith('@') &&
          l.substring(1).trim().split(RegExp(r'\s+')).contains(slug) &&
          rangs.contains(rang)) {
        deja++;
        rangs.remove(rang);
      }
      sortie.add(brute);
      continue;
    }
    vider();
    final dansLeBloc = apresSeparateur ? bloc == 'libres' : bloc == 'miroir';
    if (dansLeBloc) {
      rang++;
      attente = true;
    }
    sortie.add(brute);
  }
  vider();

  final manquants = rangs.where((r) => r > rang).toList()..sort();
  if (manquants.isNotEmpty) {
    stderr.writeln('$nom / $bloc ne compte que $rang questions : '
        'rangs hors bornes ${manquants.join(', ')}.');
    exit(1);
  }

  fichier.writeAsStringSync('${sortie.join('\n')}\n');
  stdout.writeln('$nom / $bloc : $poses étiquettes « $slug » posées'
      '${deja > 0 ? ', $deja déjà là' : ''}.');
}
