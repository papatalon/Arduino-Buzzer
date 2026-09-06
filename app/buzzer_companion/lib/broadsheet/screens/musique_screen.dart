import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../musique/ambiance_spotify.dart';
import '../../musique/spotify_auth.dart';
import '../boutons.dart';
import '../phosphor_duotone.dart';
import '../source_questions.dart';
import '../tokens.dart';

// Écran « Musique » : la musique d'ambiance entre deux parties.
//
// TOUT SE PILOTE D'ICI, ET RIEN NE SE PILOTE DE L'ÉCRAN PUBLIC, qui n'a
// jamais eu le moindre contrôle (design_handoff_buzzer_console/README.md,
// « Comportement du pop-out »). La salle voit ce qui joue, l'animateur
// décide.
//
// L'écran a deux visages selon qu'on est connecté ou non, et le premier des
// deux est un mode d'emploi : créer une application Spotify n'est pas
// évident, et se tromper d'adresse de retour est l'erreur qui fait perdre
// une demi-heure. Les trois adresses se copient d'un clic.
class MusiqueScreen extends StatefulWidget {
  const MusiqueScreen({super.key, required this.ambiance});

  final AmbianceSpotify ambiance;

  @override
  State<MusiqueScreen> createState() => _MusiqueScreenState();
}

class _MusiqueScreenState extends State<MusiqueScreen> {
  late final _clientId =
      TextEditingController(text: widget.ambiance.clientId);

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ambiance,
      builder: (context, _) {
        final a = widget.ambiance;
        return SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('Musique', style: BSType.buzzerNameConsole(size: 26)),
                    const Spacer(),
                    PhosphorDuotone(
                      PhosphorGlyphs.musicNotes,
                      size: 16,
                      color:
                          a.connecte ? BSColors.accent700 : BSColors.neutral500,
                    ),
                    const SizedBox(width: BSSpace.s1),
                    Text(_libelleEtat(a.etat),
                        style: BSType.body(size: 14, color: BSColors.neutral600)),
                  ],
                ),
                const SizedBox(height: BSSpace.s4),
                Container(height: 1, color: BSColors.divider),
                const SizedBox(height: BSSpace.s4),
                Text('COMPTE SPOTIFY', style: BSType.sectionKicker()),
                const SizedBox(height: BSSpace.s3),
                _Compte(ambiance: a, champ: _clientId),
                if (a.connecte) ...[
                  const SizedBox(height: BSSpace.s6),
                  Container(height: 1, color: BSColors.divider),
                  const SizedBox(height: BSSpace.s4),
                  Text('APPAREIL', style: BSType.sectionKicker()),
                  const SizedBox(height: BSSpace.s3),
                  _Appareil(ambiance: a),
                  const SizedBox(height: BSSpace.s6),
                  Container(height: 1, color: BSColors.divider),
                  const SizedBox(height: BSSpace.s4),
                  Row(
                    children: [
                      SizedBox(
                        width: 520,
                        child: Text('LISTE DE LECTURE',
                            style: BSType.sectionKicker()),
                      ),
                      BSGhostButton(
                        label: 'Actualiser',
                        onPressed:
                            a.chargementPlaylists ? null : a.rafraichirPlaylists,
                      ),
                    ],
                  ),
                  const SizedBox(height: BSSpace.s3),
                  _Playlists(ambiance: a),
                  const SizedBox(height: BSSpace.s6),
                  Container(height: 1, color: BSColors.divider),
                  const SizedBox(height: BSSpace.s4),
                  Text('LECTURE', style: BSType.sectionKicker()),
                  const SizedBox(height: BSSpace.s3),
                  _Commandes(ambiance: a),
                  if (a.piste.titre.isNotEmpty) ...[
                    const SizedBox(height: BSSpace.s6),
                    _EnLecture(ambiance: a),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _libelleEtat(EtatAmbiance etat) => switch (etat) {
        EtatAmbiance.deconnecte => 'Non connecté',
        EtatAmbiance.connexionEnCours => 'Connexion en cours',
        EtatAmbiance.sansAppareil => 'Connecté, aucun appareil',
        EtatAmbiance.enPause => 'En pause',
        EtatAmbiance.enLecture => 'En lecture',
        EtatAmbiance.erreur => 'Connexion à reprendre',
      };
}

class _Compte extends StatelessWidget {
  const _Compte({required this.ambiance, required this.champ});

  final AmbianceSpotify ambiance;
  final TextEditingController champ;

  @override
  Widget build(BuildContext context) {
    if (ambiance.etat == EtatAmbiance.connexionEnCours) {
      return SizedBox(
        width: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Une page Spotify vient de s\'ouvrir dans le navigateur. '
              'Autorisez la console, puis revenez ici.',
              style: BSType.body(size: 15, color: BSColors.neutral700),
            ),
            const SizedBox(height: BSSpace.s2),
            Row(
              children: [
                BSSecondaryButton(
                    label: 'Annuler', onPressed: ambiance.annulerConnexion),
                if (ambiance.urlDeSecours != null) ...[
                  const SizedBox(width: BSSpace.s2),
                  BSGhostButton(
                    label: 'Copier l\'adresse',
                    onPressed: () => _copier(context, ambiance.urlDeSecours!),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    if (ambiance.connecte) {
      return SizedBox(
        width: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: BSSpace.s3, vertical: BSSpace.s2),
              color: BSColors.accent100,
              child: Row(
                children: [
                  const PhosphorDuotone(PhosphorGlyphs.musicNotes,
                      size: 18, color: BSColors.accent700),
                  const SizedBox(width: BSSpace.s2),
                  Expanded(
                    child: Text('Connecté à Spotify',
                        style: BSType.body(size: 16, color: BSColors.text)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: ambiance.deconnecter,
                    style:
                        TextButton.styleFrom(foregroundColor: BSColors.accent700),
                    child: const Text('Se déconnecter'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BSSpace.s2),
            Text('Client ID : ${ambiance.clientId}',
                style: BSType.body(size: 13, color: BSColors.neutral600)),
          ],
        ),
      );
    }

    // Non connecté : le mode d'emploi.
    return SizedBox(
      width: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Etape(
            numero: 1,
            texte: 'Créez une application sur developer.spotify.com/dashboard. '
                'Un compte Premium est nécessaire pour commander la lecture.',
          ),
          _Etape(
            numero: 2,
            texte: 'Dans « Redirect URIs », ajoutez les trois adresses '
                'ci-dessous, une à la fois. Les deux dernières servent de '
                'secours si le premier port est occupé. Cochez « Web API ».',
          ),
          const SizedBox(height: BSSpace.s2),
          for (final uri in AuthentificationSpotify.urisAEnregistrer)
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 4),
              child: Row(
                children: [
                  SelectableText(uri,
                      style: BSType.body(size: 15, color: BSColors.text)
                          .copyWith(fontFeatures: const [
                        FontFeature.tabularFigures()
                      ])),
                  const SizedBox(width: BSSpace.s2),
                  BSGhostButton(
                      label: 'Copier',
                      onPressed: () => _copier(context, uri)),
                ],
              ),
            ),
          const SizedBox(height: BSSpace.s2),
          _Etape(
            numero: 3,
            texte: 'Copiez le Client ID de votre application ici, puis '
                'connectez-vous.',
          ),
          const SizedBox(height: BSSpace.s3),
          Row(
            children: [
              SizedBox(
                width: 400,
                child: TextField(
                  controller: champ,
                  onChanged: ambiance.reglerClientId,
                  style: BSType.body(size: 16, color: BSColors.text),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: BSSpace.s2, vertical: BSSpace.s2),
                    hintText: 'Client ID',
                    hintStyle:
                        BSType.body(size: 16, color: BSColors.neutral500),
                    border: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: BSColors.divider)),
                    enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: BSColors.divider)),
                    focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide:
                            BorderSide(color: BSColors.accent, width: 2)),
                  ),
                ),
              ),
              const SizedBox(width: BSSpace.s3),
              BSPrimaryButton(
                label: 'Se connecter',
                onPressed:
                    ambiance.clientId.isEmpty ? null : ambiance.connecter,
              ),
            ],
          ),
          if (ambiance.derniereErreur != null) ...[
            const SizedBox(height: BSSpace.s2),
            Text(ambiance.derniereErreur!,
                style: BSType.body(size: 15, color: BSColors.accent2_800)),
          ],
        ],
      ),
    );
  }

  Future<void> _copier(BuildContext context, String texte) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: texte));
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: BSColors.text,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        content: Text('Copié dans le presse-papiers.',
            style: BSType.body(size: 15, color: BSColors.bg)),
      ),
    );
  }
}

// Une étape numérotée, sur le modèle des règles de jeu : un chiffre en
// petit, le texte à côté. Pas de puces, pas de cadre.
class _Etape extends StatelessWidget {
  const _Etape({required this.numero, required this.texte});

  final int numero;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BSSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text('$numero',
                style: BSType.body(size: 15, color: BSColors.accent)
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(texte,
                style: BSType.body(size: 15, color: BSColors.neutral700)),
          ),
        ],
      ),
    );
  }
}

class _Appareil extends StatelessWidget {
  const _Appareil({required this.ambiance});

  final AmbianceSpotify ambiance;

  @override
  Widget build(BuildContext context) {
    final appareil = ambiance.appareil;
    return SizedBox(
      width: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorDuotone(
                PhosphorGlyphs.speakerHigh,
                size: 18,
                color:
                    appareil == null ? BSColors.neutral500 : BSColors.accent700,
              ),
              const SizedBox(width: BSSpace.s2),
              Text(
                appareil == null
                    ? 'Aucun appareil actif'
                    : '${appareil.nom} (${appareil.type})',
                style: BSType.body(size: 16, color: BSColors.text),
              ),
            ],
          ),
          if (appareil == null) ...[
            const SizedBox(height: BSSpace.s2),
            Text(
              'Ouvrez Spotify sur ce poste (ou sur un autre appareil du '
              'compte) et lancez n\'importe quoi une fois : il devient '
              'l\'appareil actif.',
              style: BSType.body(size: 15, color: BSColors.accent2_800),
            ),
          ],
        ],
      ),
    );
  }
}

class _Playlists extends StatelessWidget {
  const _Playlists({required this.ambiance});

  final AmbianceSpotify ambiance;

  @override
  Widget build(BuildContext context) {
    if (ambiance.chargementPlaylists && ambiance.playlists.isEmpty) {
      return Text('Lecture des listes...',
          style: BSType.body(size: 15, color: BSColors.neutral600));
    }
    if (ambiance.playlists.isEmpty) {
      return Text('Aucune liste de lecture sur ce compte.',
          style: BSType.body(size: 15, color: BSColors.neutral600));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in ambiance.playlists)
          Padding(
            padding: const EdgeInsets.only(bottom: BSSpace.s2),
            child: ChoixLigne(
              choisi: p.id == ambiance.playlistChoisieId,
              titre: p.nom,
              detail: p.proprietaire.isEmpty
                  ? '${p.nombrePistes} pistes'
                  : '${p.nombrePistes} pistes · ${p.proprietaire}',
              onTap: () => ambiance.choisirPlaylist(p.id),
            ),
          ),
      ],
    );
  }
}

class _Commandes extends StatelessWidget {
  const _Commandes({required this.ambiance});

  final AmbianceSpotify ambiance;

  @override
  Widget build(BuildContext context) {
    final joue = ambiance.etat == EtatAmbiance.enLecture;
    return SizedBox(
      width: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BSPrimaryButton(
                label: joue ? 'Pause' : 'Lire',
                onPressed: joue ? ambiance.pause : ambiance.lire,
              ),
              const SizedBox(width: BSSpace.s2),
              BSSecondaryButton(
                  label: 'Suivante', onPressed: ambiance.suivant),
              const SizedBox(width: BSSpace.s4),
              _Aleatoire(ambiance: ambiance),
            ],
          ),
          if (ambiance.enPausePourLaPartie) ...[
            const SizedBox(height: BSSpace.s2),
            Text(
              'Mise en pause au départ de la partie. Cliquez Lire pour '
              'reprendre.',
              style: BSType.body(size: 15, color: BSColors.accent700),
            ),
          ],
          if (ambiance.derniereErreur != null) ...[
            const SizedBox(height: BSSpace.s2),
            Text(ambiance.derniereErreur!,
                style: BSType.body(size: 15, color: BSColors.accent2_800)),
          ],
        ],
      ),
    );
  }
}

// Case carrée dessinée, pas un Switch de Material : le design system n'a ni
// ses couleurs ni son animation, comme pour ChoixLigne.
class _Aleatoire extends StatelessWidget {
  const _Aleatoire({required this.ambiance});

  final AmbianceSpotify ambiance;

  @override
  Widget build(BuildContext context) {
    final actif = ambiance.aleatoire;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ambiance.basculerAleatoire,
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: actif ? BSColors.accent : null,
                border: Border.all(
                  color: actif ? BSColors.accent : BSColors.neutral400,
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: BSSpace.s2),
            PhosphorDuotone(
              PhosphorGlyphs.shuffle,
              size: 16,
              color: actif ? BSColors.accent700 : BSColors.neutral600,
            ),
            const SizedBox(width: BSSpace.s1),
            Text('Aléatoire',
                style: BSType.body(
                        size: 15,
                        color: actif ? BSColors.text : BSColors.neutral700)
                    .copyWith(
                        fontWeight:
                            actif ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

// La piste en cours, dans la forme du bandeau de questionnaire actif : un
// filet accent en haut, un filet fin en bas, aucune boîte.
class _EnLecture extends StatelessWidget {
  const _EnLecture({required this.ambiance});

  final AmbianceSpotify ambiance;

  @override
  Widget build(BuildContext context) {
    final piste = ambiance.piste;
    return Container(
      width: 620,
      padding: const EdgeInsets.symmetric(vertical: BSSpace.s2),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: BSColors.accent, width: 3),
          bottom: BorderSide(color: BSColors.divider),
        ),
      ),
      child: Row(
        children: [
          if (piste.pochette != null) ...[
            // Un fichier disparu ne doit pas casser l'écran : on n'affiche
            // simplement rien, comme pour le logo de la soirée.
            Image.file(
              File(piste.pochette!),
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            const SizedBox(width: BSSpace.s3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EN LECTURE SUR SPOTIFY', style: BSType.sectionKicker()),
                const SizedBox(height: 2),
                Text(piste.titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BSType.buzzerNameConsole(size: 21)),
                if (piste.artiste.isNotEmpty)
                  Text(piste.artiste,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          BSType.body(size: 14, color: BSColors.neutral600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
