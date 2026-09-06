import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../broadsheet/tokens.dart';
import '../protocol.dart';
import 'phrases_attente.dart';
import 'popout_snapshot.dart';

// Écran d'attente du pop-out : ce que la salle regarde entre deux parties,
// pendant que l'animateur configure un jeu, ou avant même que la soirée
// commence. C'est le plan le plus longtemps affiché de la soirée, et c'était
// jusqu'ici un rectangle gris.
//
// Parti pris : une une de journal en attente de son édition. Un chapeau qui
// dit ce qui s'en vient, un gros titre qui change tout seul pour faire
// sourire, et en pied de page les équipes du soir. Aucun chiffre nulle part :
// annoncer un pointage avant le début de la partie serait faux, et c'est
// justement ce qu'on vient de corriger.
class PopoutIdle extends StatefulWidget {
  const PopoutIdle({super.key, required this.snapshot});

  final PopoutSnapshot snapshot;

  @override
  State<PopoutIdle> createState() => _PopoutIdleState();
}

class _PopoutIdleState extends State<PopoutIdle> {
  static const _rotation = Duration(seconds: 9);

  final _random = Random();
  late int _index = _random.nextInt(phrasesAttente.length);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_rotation, (_) => setState(() => _index = _nextIndex()));
  }

  // Tirage sans répétition immédiate : voir la même phrase deux fois de
  // suite donnerait l'impression que l'écran est figé, exactement ce qu'on
  // cherche à éviter.
  int _nextIndex() {
    if (phrasesAttente.length < 2) return 0;
    final next = _random.nextInt(phrasesAttente.length - 1);
    return next >= _index ? next + 1 : next;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Un jeu déjà choisi mais pas encore lancé : la salle a le droit de
    // savoir ce qui l'attend, c'est la moitié du plaisir.
    final aVenir = gameModeName(widget.snapshot.displayGameMode);
    final tirage = widget.snapshot.motTirage;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 120),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    aVenir.isEmpty ? 'LE JEU S\'EN VIENT' : 'À L\'AFFICHE',
                    style: BSType.popoutHeaderMeta(color: BSColors.neutral500),
                  ),
                  if (aVenir.isNotEmpty) ...[
                    const SizedBox(height: BSSpace.s3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        aVenir,
                        maxLines: 1,
                        style: BSType.heroDigitPopout(size: 92, color: BSColors.accent),
                      ),
                    ),
                  ],
                  const SizedBox(height: BSSpace.s8),
                  // Le trait magenta sert de point final au titre, comme
                  // ailleurs dans le design system : une règle, jamais un
                  // encadré ni une ombre.
                  const SizedBox(width: 96, height: 4, child: ColoredBox(color: BSColors.accent2)),
                  const SizedBox(height: BSSpace.s8),
                  // Le fondu croisé rend le changement vivant sans jamais
                  // attirer l'oeil pendant que l'animateur parle : neuf
                  // secondes entre deux phrases, une seconde de transition.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 900),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    // Hauteur figée à deux lignes : sans ça, passer d'une
                    // phrase courte à une longue faisait sauter tout le bloc
                    // (et le trait magenta avec lui) à chaque rotation.
                    // Pendant le tirage au sort, la rotation s'efface : la salle
                    // doit lire ce qui est en train de se decider, pas une
                    // phrase d'attente qui changerait au milieu.
                    child: SizedBox(
                      key: ValueKey(tirage.isNotEmpty ? 'tirage' : ''),
                      width: 1080,
                      height: 150,
                      child: Center(
                        child: Text(
                          tirage.isNotEmpty ? tirage : phrasesAttente[_index],
                          textAlign: TextAlign.center,
                          style: BSType.questionPopout(
                                  color: tirage.isNotEmpty
                                      ? BSColors.accent2_800
                                      : BSColors.text)
                              .copyWith(fontSize: 62, height: 1.15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // La musique d'ambiance s'annonce SOUS le bloc central, jamais à sa
        // place : les phrases qui tournent sont ce qui fait sourire la salle
        // pendant que l'animateur parle, et elles gardent leur boîte de
        // 1080 x 150 et leur rotation de neuf secondes. Le bandeau se sert
        // dans le mou du bloc centré, qui en a largement.
        if (widget.snapshot.pisteEnCours.quelqueChose)
          _BandeauMusique(piste: widget.snapshot.pisteEnCours),
        _TonightBand(snapshot: widget.snapshot),
      ],
    );
  }
}

// « C'est quoi, cette toune-là ? »
//
// La question revient à chaque soirée, et personne ne veut interrompre pour
// la poser. Trois éléments y répondent : la pochette, le titre, l'artiste.
//
// LA POCHETTE EST MONTRÉE TELLE QUELLE, sans recadrage, sans filtre et sans
// le traitement demi-teinte du design system : les règles de Spotify
// l'exigent, et c'est aussi la seule photographie de tout l'écran public.
// Elle vient d'un fichier local (voir CachePochettes) : cette fenêtre n'a
// jamais fait de réseau et ne va pas commencer dans une salle sans Wi-Fi.
class _BandeauMusique extends StatelessWidget {
  const _BandeauMusique({required this.piste});

  final PisteEnCours piste;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Le même filet que le pied de page des équipes, pour que les deux
        // bandes se lisent comme un seul bas de page.
        const SizedBox(height: 4, child: ColoredBox(color: BSColors.text)),
        SizedBox(
          height: 128,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 52),
            child: Row(
              children: [
                if (piste.pochette != null) ...[
                  // Une image disparue ne casse pas l'écran en pleine
                  // soirée : on n'affiche simplement rien, comme le logo.
                  Image.file(
                    File(piste.pochette!),
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 28),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EN LECTURE SUR SPOTIFY',
                          style: BSType.popoutHeaderMeta(
                              color: BSColors.neutral500)),
                      const SizedBox(height: BSSpace.s2),
                      // Plancher de lisibilité du pop-out : 26 px, aucune
                      // exception pour du contenu réel. Le titre monte plus
                      // haut, l'artiste reste juste au-dessus.
                      Text(
                        piste.titre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BSType.buzzerNamePopout(color: BSColors.text)
                            .copyWith(fontSize: 34),
                      ),
                      if (piste.artiste.isNotEmpty)
                        Text(
                          piste.artiste,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BSType.body(
                              size: 26, color: BSColors.neutral700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Pied de page : les équipes du soir, sans le moindre chiffre. Reprend la
// géométrie du tableau des scores (mêmes marges, mêmes pastilles de couleur)
// pour que le passage de l'attente à la partie ne fasse pas sauter l'écran,
// et donne aux joueurs le seul renseignement qui compte avant le départ :
// leur nom est bien entré.
class _TonightBand extends StatelessWidget {
  const _TonightBand({required this.snapshot});

  final PopoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    // Seulement les équipes en jeu : un buzzer déclaré absent n'existe pas
    // pour la salle, et le montrer estompé ne fait que poser la question
    // « pourquoi celui-là est gris ? ». Celles qui restent se partagent
    // toute la largeur.
    final enJeu = [
      for (var i = 0; i < 4; i++)
        if (i < snapshot.present.length && snapshot.present[i]) i,
    ];
    if (enJeu.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 4, child: ColoredBox(color: BSColors.text)),
        SizedBox(
          height: 140,
          child: Row(
            children: [
              for (var rang = 0; rang < enJeu.length; rang++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: rang == 0 ? 52 : 28, top: 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 44, height: 10, color: kBuzzerColors[enJeu[rang]].fill),
                        const SizedBox(height: BSSpace.s3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            snapshot.teamName(enJeu[rang]).toUpperCase(),
                            maxLines: 1,
                            style: BSType.buzzerNamePopout(color: BSColors.text),
                          ),
                        ),
                        Text('PRÊT', style: BSType.body(size: 18, color: BSColors.neutral600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
