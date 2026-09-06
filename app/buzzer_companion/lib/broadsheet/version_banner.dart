import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../version_check.dart';
import 'ouvrir_navigateur.dart';
import 'tokens.dart';

// Bandeau annonçant une version plus récente de l'application.
//
// Discret par construction : il n'apparaît QUE s'il y a vraiment une version
// plus récente, il se ferme d'un clic, et sa fermeture tient d'une séance à
// l'autre. Rien ne s'affiche quand la vérification échoue (voir
// VersionCheck) : personne n'a envie d'un avertissement rouge cinq minutes
// avant de lancer une soirée.
class VersionBanner extends StatelessWidget {
  const VersionBanner({super.key, required this.check});

  final VersionCheck check;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: check,
      builder: (context, _) {
        if (!check.shouldShow) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: BSSpace.s3),
          padding: const EdgeInsets.fromLTRB(BSSpace.s3, BSSpace.s2, BSSpace.s2, BSSpace.s2),
          decoration: const BoxDecoration(
            color: BSColors.accent100,
            border: Border(top: BorderSide(color: BSColors.accent, width: 3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: BSType.body(size: 15, color: BSColors.accent900),
                    children: [
                      TextSpan(
                        text: 'La version ${check.latestVersion} est disponible. ',
                        style: BSType.body(size: 15, color: BSColors.accent900)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: 'Vous utilisez la ${check.localVersion}.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: BSSpace.s3),
              TextButton(
                onPressed: () => _ouvrir(context, check.downloadUrl),
                style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
                child: const Text('Télécharger'),
              ),
              if (check.notesUrl != null)
                TextButton(
                  onPressed: () => _ouvrir(context, check.notesUrl),
                  style: TextButton.styleFrom(foregroundColor: BSColors.accent700),
                  child: const Text('Nouveautés'),
                ),
              const SizedBox(width: BSSpace.s1),
              IconButton(
                tooltip: 'Fermer. Reviendra à la prochaine version.',
                onPressed: check.dismiss,
                color: BSColors.accent700,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
      },
    );
  }

  // Si l'ouverture échoue, l'adresse part dans le presse-papiers plutôt que
  // de laisser un bouton qui ne fait rien : l'opérateur peut la coller
  // lui-même.
  Future<void> _ouvrir(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    if (await ouvrirDansLeNavigateur(url)) return;
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: BSColors.text,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        content: Text(
          "Le navigateur n'a pas pu être ouvert. L'adresse est dans le presse-papiers.",
          style: BSType.body(size: 15, color: BSColors.bg),
        ),
      ),
    );
  }
}
