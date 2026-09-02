import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../broadsheet/tokens.dart';
import '../protocol.dart';
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

// Assez de lignes pour qu'une soirée entière n'en montre jamais deux fois la
// même de suite. Ton québécois, jamais moqueur envers un joueur en
// particulier : c'est affiché devant tout le monde.
//
// PAS DE POUCES. Les buzzers sont de gros boutons qu'on abat avec la main,
// pas des manettes. Quatre messages y faisaient référence et sonnaient faux
// devant l'objet posé sur la table.
const _messages = <String>[
  'Le bouton est gros. Personne ne pourra dire qu\'il l\'a manqué.',
  "Personne n'a encore perdu. Profitez-en.",
  'Le pointage est à zéro. Tout le monde est premier.',
  'Ça commence dans pas long.',
  "Le premier à peser l'emporte. Toujours.",
  'Buzzer avant de savoir la réponse : un plan risqué.',
  "Aucune question n'a encore fait de victime.",
  'Que la main la plus rapide gagne.',
  'Prenez une gorgée. Après, ça va vite.',
  'Il y a des bonnes réponses, et il y a des réponses à zéro point.',
  'Vos coéquipiers comptent sur vous. Aucune pression.',
  'On teste vos réflexes dans un instant.',
  'Le silence avant la tempête de buzz.',
  'La main au-dessus du bouton. Respirez.',
  "Ce soir, quelqu'un va buzzer trop vite.",
  'Les remontées spectaculaires commencent toutes à zéro.',
  "Le buzzer ne pardonne pas l'hésitation.",
  'Chacun son tour de briller.',
  'La chance sourit à ceux qui appuient.',
  'Préparez vos meilleures excuses.',
  'Frapper plus fort ne rend pas la réponse meilleure.',
  'Le bouton ne connaît pas la réponse. Vous non plus, peut-être.',
  'On entend qui a buzzé. On voit qui le regrette.',
  'Un gros bouton, une petite hésitation, une longue soirée.',
  'Le bouton encaisse. Votre orgueil, un peu moins.',
  'Quatre boutons, une seule bonne réponse, beaucoup de courage.',
];

class _PopoutIdleState extends State<PopoutIdle> {
  static const _rotation = Duration(seconds: 9);

  final _random = Random();
  late int _index = _random.nextInt(_messages.length);
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
    if (_messages.length < 2) return 0;
    final next = _random.nextInt(_messages.length - 1);
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
                    child: SizedBox(
                      key: ValueKey(_index),
                      width: 1080,
                      height: 150,
                      child: Center(
                        child: Text(
                          _messages[_index],
                          textAlign: TextAlign.center,
                          style: BSType.questionPopout(color: BSColors.text).copyWith(fontSize: 62, height: 1.15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _TonightBand(snapshot: widget.snapshot),
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
