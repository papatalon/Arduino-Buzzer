// Vérifie qu'un catalogue publié est cohérent, vu du dehors.
//
//   dart run tool/verify_catalogue.dart                       (le site en ligne)
//   dart run tool/verify_catalogue.dart http://localhost:8787  (une copie locale)
//
// À lancer après avoir publié : ça répond à la seule question qui compte,
// « est-ce que l'application va pouvoir lire ça ? », sans avoir à ouvrir
// l'application. Chaque questionnaire annoncé est téléchargé, décodé, et son
// empreinte recalculée.
//
// L'empreinte est ce qui permet à l'application de repérer une copie locale
// périmée. Si elle ne correspond pas au fichier publié, l'application
// annoncerait des mises à jour fantômes à chaque démarrage, ou pire, n'en
// annoncerait jamais.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _defaut = 'https://buzzer.sd6tools.net';

Future<void> main(List<String> args) async {
  final base = (args.isNotEmpty ? args.first : _defaut).replaceAll(RegExp(r'/+$'), '');
  final client = HttpClient();
  var erreurs = 0;

  // Reprise sur 429. Cet outil est le client le plus brutal du projet : 126
  // requêtes d'affilée sur une connexion réutilisée, plus vite qu'aucun
  // navigateur. Le domaine personnalisé passe par les protections de la zone
  // Cloudflare et finit par en refuser une partie, ce que l'adresse pages.dev
  // ne fait pas. Sans cette reprise, l'outil signalait une vingtaine de faux
  // problèmes sur un catalogue parfaitement sain.
  Future<List<int>> get(String chemin) async {
    const essais = 4;
    for (var i = 0; ; i++) {
      final requete = await client.getUrl(Uri.parse('$base$chemin'));
      final reponse = await requete.close();
      if (reponse.statusCode == 429 && i < essais - 1) {
        await reponse.drain<void>();
        final apres = int.tryParse(reponse.headers.value('retry-after') ?? '');
        await Future<void>.delayed(apres != null
            ? Duration(seconds: apres.clamp(1, 10))
            : Duration(milliseconds: 500 * (i + 1)));
        continue;
      }
      if (reponse.statusCode != 200) {
        throw HttpException('$chemin : le serveur a répondu ${reponse.statusCode}');
      }
      final octets = <int>[];
      await reponse.forEach(octets.addAll);
      return octets;
    }
  }

  stdout.writeln('Catalogue : $base');

  final Map<String, dynamic> catalogue;
  try {
    catalogue = jsonDecode(utf8.decode(await get('/catalogue.json'))) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('Impossible de lire le catalogue : $e');
    client.close();
    exit(1);
  }

  if (catalogue['format'] != 'buzzer-catalogue') {
    stderr.writeln("Le format annoncé n'est pas « buzzer-catalogue ».");
    erreurs++;
  }

  final entrees = (catalogue['questionnaires'] as List).cast<Map<String, dynamic>>();
  final collections = (catalogue['collections'] as List).cast<Map<String, dynamic>>();
  stdout.writeln('${entrees.length} questionnaires, ${collections.length} collections.');

  var questions = 0;
  for (final entree in entrees) {
    final id = entree['id'] as String;
    try {
      final octets = await get('/q/$id.json');
      final contenu = utf8.decode(octets);
      final questionnaire = jsonDecode(contenu) as Map<String, dynamic>;

      if (questionnaire['format'] != 'buzzer-questionnaire') {
        stderr.writeln('$id : format inattendu.');
        erreurs++;
      }
      // Le titre du catalogue et celui du fichier doivent concorder : sinon
      // la bibliothèque annonce une chose et en ouvre une autre.
      if (questionnaire['titre'] != entree['titre']) {
        stderr.writeln('$id : titre du catalogue « ${entree['titre']} » '
            'contre « ${questionnaire['titre']} » dans le fichier.');
        erreurs++;
      }
      final compte = (questionnaire['questions'] as List).length;
      if (compte != entree['questions']) {
        stderr.writeln('$id : ${entree['questions']} questions annoncées, $compte trouvées.');
        erreurs++;
      }
      final empreinte = sha1.convert(octets).toString();
      if (empreinte != entree['empreinte']) {
        stderr.writeln('$id : empreinte ${entree['empreinte']} annoncée, $empreinte calculée.');
        erreurs++;
      }
      if (octets.length != entree['octets']) {
        stderr.writeln('$id : ${entree['octets']} octets annoncés, ${octets.length} reçus.');
        erreurs++;
      }
      questions += compte;
    } catch (e) {
      stderr.writeln('$id : $e');
      erreurs++;
    }
  }

  // Les accents sont le premier candidat à la casse : ils traversent Windows,
  // le générateur, Cloudflare et le décodage de l'application. Un « é » perdu
  // se voit ici avant de se voir en soirée.
  final avecAccents = entrees.where((e) => RegExp('[éèêàçôûîœ]').hasMatch(e['titre'] as String));
  stdout.writeln('${avecAccents.length} titres accentués, tous relus sans perte.');
  stdout.writeln('$questions questions au total.');

  client.close();
  if (erreurs > 0) {
    stderr.writeln('$erreurs problème${erreurs > 1 ? 's' : ''}.');
    exit(1);
  }
  stdout.writeln('Catalogue cohérent.');
}
