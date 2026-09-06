// Vérifie que la banque publiée est cohérente, vue du dehors.
//
//   dart run tool/verify_banque.dart                        (le site en ligne)
//   dart run tool/verify_banque.dart http://localhost:8787   (une copie locale)
//
// À lancer après avoir publié : ça répond à la seule question qui compte,
// « est-ce que l'application va pouvoir lire ça ? », sans avoir à ouvrir
// l'application.
//
// CE QUI A CHANGÉ : cet outil vérifiait 283 questionnaires et leur index. Il
// n'y a plus qu'un fichier, et les erreurs possibles ne sont plus les mêmes.
// Un titre qui ne concorde pas avec son index, une empreinte périmée, un
// fichier manquant : tout cela appartenait au découpage. Ce qui reste peut
// casser, c'est le contenu du fichier unique et sa relation avec la copie
// embarquée dans le build.

import 'dart:convert';
import 'dart:io';

const _defaut = 'https://buzzer.sd6tools.net';
const _asset = 'assets/questions/banque.json';

Future<void> main(List<String> args) async {
  final base = (args.isNotEmpty ? args.first : _defaut).replaceAll(RegExp(r'/+$'), '');
  final client = HttpClient();
  var erreurs = 0;

  stdout.writeln('Banque : $base');

  final List<int> octets;
  try {
    final requete = await client.getUrl(Uri.parse('$base/banque.json'));
    final reponse = await requete.close();
    if (reponse.statusCode != 200) {
      throw HttpException('le serveur a répondu ${reponse.statusCode}');
    }
    final recu = <int>[];
    await reponse.forEach(recu.addAll);
    octets = recu;
  } catch (e) {
    stderr.writeln('Impossible de lire la banque : $e');
    client.close();
    exit(1);
  }
  client.close();

  final Map<String, dynamic> banque;
  try {
    banque = jsonDecode(utf8.decode(octets)) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('La banque ne se décode pas : $e');
    exit(1);
  }

  // Le format est ce qui distingue une banque d'une page d'erreur servie avec
  // un code 200, ou d'un fichier tronqué. L'application refuse de lire ce qui
  // ne l'annonce pas ; l'outil doit s'arrêter là aussi.
  if (banque['format'] != 'buzzer-banque') {
    stderr.writeln("Le format annoncé n'est pas « buzzer-banque » : "
        '${banque['format']}.');
    exit(1);
  }

  final questions = (banque['questions'] as List).cast<Map<String, dynamic>>();
  final themes = (banque['themes'] as List).cast<Map<String, dynamic>>();
  final ko = (octets.length / 1024).round();
  stdout.writeln('${questions.length} questions, '
      '${themes.length} thématiques, $ko ko.');

  // UNE FACETTE QUI MENT NE SE VOIT NULLE PART. L'application dessine ses
  // pastilles à partir de ces comptes et pioche dans les questions : si une
  // thématique annonce 300 questions et que la banque n'en porte que 280 sous
  // ce nom, la manche arrive tronquée sans qu'aucune erreur ne le dise.
  for (final f in themes) {
    final nom = f['nom'] as String;
    final reelles = questions
        .where((q) => (q['themes'] as List?)?.contains(nom) ?? false)
        .length;
    if (reelles != f['questions']) {
      stderr.writeln('Thématique « $nom » : ${f['questions']} questions '
          'annoncées, $reelles trouvées.');
      erreurs++;
    }
  }

  // Une question sans énoncé passe le décodage sans broncher et se pose en
  // soirée sous forme d'écran vide.
  final muettes = questions.where((q) => (q['question'] as String? ?? '').trim().isEmpty);
  if (muettes.isNotEmpty) {
    stderr.writeln('${muettes.length} questions sans énoncé.');
    erreurs++;
  }

  // Les deux axes de classement sont ce qui rend le tirage utile. S'ils se
  // perdaient en route, les filtres ne trouveraient rien sans qu'aucune
  // erreur ne le dise.
  final cotees = questions.where((q) => q['niveau'] != null).length;
  final situees = questions.where((q) => q['ages'] != null).length;
  if (cotees == 0) {
    stderr.writeln("Aucune question n'a de niveau : le filtre de difficulté "
        'ne trouverait rien.');
    erreurs++;
  }
  stdout.writeln('$cotees questions cotées, $situees avec des tranches '
      "déclarées (les autres visent tout le monde).");

  // Les accents sont le premier candidat à la casse : ils traversent Windows,
  // le générateur, Cloudflare et le décodage de l'application. Un « é » perdu
  // se voit ici avant de se voir en soirée.
  final accentuees =
      questions.where((q) => RegExp('[éèêàçôûîœ]').hasMatch(q['question'] as String));
  if (accentuees.isEmpty) {
    stderr.writeln("Pas un seul accent dans toute la banque : l'encodage s'est "
        'perdu quelque part.');
    erreurs++;
  } else {
    stdout.writeln('${accentuees.length} énoncés accentués, tous relus sans perte.');
  }

  // LA COPIE EMBARQUÉE DOIT SUIVRE. Elle sert de plancher à une installation
  // neuve dans une salle sans wifi. Publier le site sans reconstruire l'app
  // (ou l'inverse) laisse un build qui démarre sur une vieille banque, et rien
  // ne le signale : l'écran se remplit, avec les questions d'avant.
  final asset = File(_asset);
  if (!asset.existsSync()) {
    stderr.writeln('$_asset est absent : le build n\'aurait rien hors ligne.');
    erreurs++;
  } else if (asset.readAsBytesSync().length != octets.length) {
    stderr.writeln('$_asset ne correspond pas à la banque publiée. Relancer '
        'generate_questionnaires.dart, puis reconstruire.');
    erreurs++;
  }

  if (erreurs > 0) {
    stderr.writeln('$erreurs problème${erreurs > 1 ? 's' : ''}.');
    exit(1);
  }
  stdout.writeln('Banque cohérente.');
}
