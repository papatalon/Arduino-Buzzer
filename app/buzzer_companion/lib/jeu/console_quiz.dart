import 'package:flutter/material.dart';

import '../audio/sonorisation.dart';
import '../broadsheet/boutons.dart';
import '../ble_link_service.dart';
import '../broadsheet/screens/game_choice_screen.dart';
import '../broadsheet/source_hasard.dart';
import '../broadsheet/source_questions.dart';
import '../broadsheet/tokens.dart';
import '../protocol.dart';
import '../questionnaires/active_questionnaire.dart';
import '../questionnaires/tirage_questions.dart';
import '../team_names.dart';
import 'moteur_quiz.dart';

// LA CONSOLE DE L'ANIMATEUR, en mode application.
//
// Elle ne lit plus la phase du buzzer : elle lit le moteur de jeu. C'est la
// différence de fond avec [QuestionFlowView], qui reste pour le mode
// autonome, quand c'est le firmware qui mène la partie et que l'app le suit.
//
// Le buzzer, ici, n'a aucun état de partie à montrer : il arme des boutons et
// rapporte les appuis. Tout ce qui s'affiche vient du moteur.

// Les cinq jeux de questions, dans l'ordre de GameMode.h : c'est cet index
// que le moteur attend, et il en tire les règles (pénalité, chrono, vol).
const _jeuxQuiz = [
  (
    index: 0,
    nom: 'Classique',
    quoi: 'Une bonne réponse, un point. Une erreur ne coûte rien.',
  ),
  (
    index: 1,
    nom: 'Pénalité',
    quoi: 'Une erreur retire un point. Le score peut descendre sous zéro.',
  ),
  (
    index: 2,
    nom: 'Chrono classique',
    quoi: 'Chaque réponse est minutée. Une erreur ne coûte rien.',
  ),
  (
    index: 3,
    nom: 'Chrono pénalité',
    quoi: 'Chaque réponse est minutée, et une erreur retire un point.',
  ),
  (
    index: 4,
    nom: 'Vol',
    quoi: "La question revient à un joueur. S'il se trompe, les autres peuvent la voler.",
  ),
];

class ConsoleQuizApp extends StatelessWidget {
  const ConsoleQuizApp({
    super.key,
    required this.moteur,
    required this.actif,
    required this.teams,
    required this.onAllerAuxQuestions,
    required this.sons,
    required this.game,
    required this.ble,
    required this.tirage,
  });

  final MoteurQuiz moteur;
  final ActiveQuestionnaire actif;
  final TeamNames teams;
  final VoidCallback onAllerAuxQuestions;
  final Sonorisation sons;
  final GameState game;
  final BleLinkService ble;
  final TirageQuestions tirage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([moteur, actif]),
      builder: (context, _) {
        return SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: switch (moteur.etape) {
              EtapeQuiz.repos => _Lancement(
                  moteur: moteur,
                  actif: actif,
                  game: game,
                  ble: ble,
                  onAllerAuxQuestions: onAllerAuxQuestions,
                  tirage: tirage,
                ),
              EtapeQuiz.intro => _Ouverture(moteur: moteur),
              EtapeQuiz.finie => _FinDePartie(
                  moteur: moteur,
                  teams: teams,
                  actif: actif,
                  tirage: tirage),
              _ => _EnPartie(moteur: moteur, actif: actif, teams: teams, sons: sons),
            },
          ),
        );
      },
    );
  }
}

// --- Avant la partie -----------------------------------------------------

class _Lancement extends StatefulWidget {
  const _Lancement({
    required this.moteur,
    required this.actif,
    required this.game,
    required this.ble,
    required this.onAllerAuxQuestions,
    required this.tirage,
  });

  final MoteurQuiz moteur;
  final ActiveQuestionnaire actif;
  final GameState game;
  final BleLinkService ble;
  final VoidCallback onAllerAuxQuestions;
  final TirageQuestions tirage;

  @override
  State<_Lancement> createState() => _LancementState();
}

class _LancementState extends State<_Lancement> {
  int _premiere = 20;
  int _suivantes = 10;

  // LE JEU N'EST PAS CHOISI ICI. Il l'est sur l'ecran « Jeu actif », et cet
  // ecran-ci ne fait que le lire. Redemander un choix deja fait, c'etait
  // remettre deux endroits sur la meme decision.
  int? get _jeu => widget.moteur.jeuChoisi;

  bool get _chrono => _jeu == 2 || _jeu == 3 || _jeu == 4;

  // Les cinq jeux de questions. Les six autres tournent encore sur le buzzer.
  bool get _estQuiz => _jeu != null && _jeu! >= 0 && _jeu! <= 4;

  @override
  Widget build(BuildContext context) {
    final actif = widget.actif;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Lancer une partie', style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s2),
        Text(
          "Les questions, les points et la fin de partie sont tenus ici. "
          "Le buzzer ne fait qu'allumer les boutons et rapporter les appuis.",
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s6),
        Container(height: 2, color: BSColors.text),
        const SizedBox(height: BSSpace.s4),
        // LE JEU D'ABORD. Les questions ne se posent qu'une fois qu'on sait
        // s'il y en aura : six des onze jeux n'en ont aucune, et les
        // reclamer avant le choix etait le flux a l'envers.
        Text('LE JEU', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        if (_jeu == null)
          GrilleDesJeux(
            game: widget.game,
            ble: widget.ble,
            moteur: widget.moteur,
            onChoisi: () => setState(() {}),
          )
        else ...[
          // Une fois le jeu retenu, les dix autres explications n'ont plus
          // rien a apprendre a personne : elles noyaient le seul
          // renseignement qui compte a ce moment-la.
          _JeuChoisi(
            nom: gameModeName(_jeu),
            regle: _estQuiz
                ? _jeuxQuiz.firstWhere((j) => j.index == _jeu).quoi
                : null,
            onChanger: () => setState(widget.moteur.oublierJeu),
          ),
          const SizedBox(height: BSSpace.s6),

          // D'ou viennent les questions. Seuls les cinq jeux de quiz en ont
          // besoin ; sans ca, « Lancer » demarrerait une partie sans matiere
          // et l'animateur ne le decouvrirait qu'apres.
          if (_estQuiz) ...[
            Text('LES QUESTIONS', style: BSType.sectionKicker()),
            const SizedBox(height: BSSpace.s2),
            SourceQuestionnaire(
                actif: actif, onChoisir: widget.onAllerAuxQuestions),
            const SizedBox(height: BSSpace.s2),
            SourceLibre(actif: actif),
            const SizedBox(height: BSSpace.s2),
            SourceAuHasard(actif: actif, tirage: widget.tirage),
            if (actif.libre) ...[
              const SizedBox(height: BSSpace.s4),
              NombreLibre(actif: actif, parDefaut: kNombreLibreParDefaut),
            ],
          ],
        ],

        if (_chrono) ...[
          const SizedBox(height: BSSpace.s4),
          Text('LE CHRONO', style: BSType.sectionKicker()),
          const SizedBox(height: BSSpace.s2),
          Text(
            'Zéro seconde retire le chrono de cette étape.',
            style: BSType.body(size: 15, color: BSColors.neutral600),
          ),
          const SizedBox(height: BSSpace.s3),
          _Compteur(
            label: 'Première réponse',
            valeur: _premiere,
            onChange: (v) => setState(() => _premiere = v),
          ),
          const SizedBox(height: BSSpace.s2),
          _Compteur(
            label: 'Réponses suivantes',
            valeur: _suivantes,
            onChange: (v) => setState(() => _suivantes = v),
          ),
        ],

        const SizedBox(height: BSSpace.s6),
        Row(
          children: [
            BSPrimaryButton(
              label: 'Lancer la partie',
              onPressed: (!_estQuiz || !actif.pretAJouer)
                  ? null
                  : () {
                      final m = widget.moteur;
                      m.chronoPremiere = _chrono ? _premiere : 0;
                      m.chronoSuivantes = _chrono ? _suivantes : 0;
                      m.demarrer(jeuChoisi: _jeu!, limite: _limite());
                    },
            ),
            const SizedBox(width: BSSpace.s3),
            if (!_estQuiz || !actif.pretAJouer)
              Expanded(
                child: Text(
                  !_estQuiz
                      ? 'Choisir un jeu de questions pour continuer'
                      : 'Choisir un questionnaire ou une manche libre',
                  style: BSType.body(size: 15, color: BSColors.neutral600),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Combien de questions avant la fin. Un questionnaire décide par sa
  // longueur ; une manche libre par ce que l'animateur a réglé, zéro voulant
  // dire qu'il arrête quand il veut.
  int _limite() {
    final actif = widget.actif;
    if (actif.libre) return actif.nombreLibre ?? 0;
    return actif.total;
  }
}

// LE JEU RETENU, et lui seul.
//
// Il prend la place de la liste : nom en grand, filet magenta, et sa regle
// rappelee dessous. L'animateur doit voir d'un coup d'oeil ce qu'il s'apprete
// a lancer, sans le chercher parmi quatre explications qui ne le concernent
// plus.
class _JeuChoisi extends StatelessWidget {
  const _JeuChoisi({required this.nom, required this.regle, required this.onChanger});

  final String nom;
  /// Null pour les six jeux que le buzzer mene encore lui-meme.
  final String? regle;
  final VoidCallback onChanger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 620,
      padding: const EdgeInsets.fromLTRB(BSSpace.s3, BSSpace.s3, BSSpace.s3, BSSpace.s4),
      decoration: const BoxDecoration(
        color: BSColors.accent100,
        border: Border(left: BorderSide(color: BSColors.accent, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(nom, style: BSType.buzzerNameConsole(size: 32)),
              ),
              BSGhostButton(label: 'Changer de jeu', onPressed: onChanger),
            ],
          ),
          const SizedBox(height: BSSpace.s2),
          const SizedBox(width: 72, height: 3, child: ColoredBox(color: BSColors.accent2)),
          const SizedBox(height: BSSpace.s3),
          Text(
            regle ?? "Ce jeu est mene par le buzzer, pas encore par l'application.",
            style: BSType.body(size: 17, color: BSColors.text),
          ),
        ],
      ),
    );
  }
}

class _Compteur extends StatelessWidget {
  const _Compteur({
    required this.label,
    required this.valeur,
    required this.onChange,
  });

  final String label;
  final int valeur;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: Text(label, style: BSType.body(size: 17, color: BSColors.text)),
        ),
        BSSecondaryButton(
          label: '-',
          onPressed:
              valeur <= 0 ? null : () => onChange(valeur - 5 < 0 ? 0 : valeur - 5),
        ),
        SizedBox(
          width: 90,
          child: Center(
            child: Text('$valeur s', style: BSType.buzzerNameConsole(size: 22)),
          ),
        ),
        BSSecondaryButton(
          label: '+',
          onPressed: valeur >= 120 ? null : () => onChange(valeur + 5),
        ),
      ],
    );
  }
}

// --- Pendant la partie ---------------------------------------------------

class _EnPartie extends StatelessWidget {
  const _EnPartie({
    required this.moteur,
    required this.actif,
    required this.teams,
    required this.sons,
  });

  final MoteurQuiz moteur;
  final ActiveQuestionnaire actif;
  final TeamNames teams;
  final Sonorisation sons;

  @override
  Widget build(BuildContext context) {
    final revelee = moteur.etape == EtapeQuiz.revelee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Entete(moteur: moteur),
        const SizedBox(height: BSSpace.s2),
        _Question(actif: actif, revelee: revelee),
        const SizedBox(height: BSSpace.s6),
        switch (moteur.etape) {
          EtapeQuiz.attente => _Attente(moteur: moteur, teams: teams, sons: sons),
          EtapeQuiz.buzze => _Juger(moteur: moteur, teams: teams),
          EtapeQuiz.scores => _Scores(moteur: moteur, teams: teams),
          EtapeQuiz.revelee => _Revelation(moteur: moteur),
          _ => const SizedBox.shrink(),
        },
        const SizedBox(height: BSSpace.s6),
        Container(height: 1, color: BSColors.divider),
        const SizedBox(height: BSSpace.s3),
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s4),
        Row(
          children: [
            // Corriger reste offert tant qu'une décision est annulable : c'est
            // la seule sortie quand l'animateur a cliqué trop vite.
            if (moteur.dernierJuge != null)
              BSGhostButton(
                  label: 'Corriger la dernière décision',
                  onPressed: moteur.corriger),
            const Spacer(),
            BSGhostButton(
                label: 'Terminer la partie', onPressed: moteur.terminer),
          ],
        ),
      ],
    );
  }
}

class _Entete extends StatelessWidget {
  const _Entete({required this.moteur});
  final MoteurQuiz moteur;

  @override
  Widget build(BuildContext context) {
    final jeu = _jeuxQuiz.firstWhere(
      (j) => j.index == moteur.jeu,
      orElse: () => _jeuxQuiz.first,
    );
    final total = moteur.limiteQuestions;
    // Un bris se joue en plus des questions prevues : le compter donnerait
    // « question 26 sur 25 ».
    final progression = moteur.brisEgalite
        ? "Bris d'égalité"
        : total > 0
            ? 'Question ${moteur.numeroQuestion} sur $total'
            : 'Question ${moteur.numeroQuestion}';
    return Row(
      children: [
        Text(jeu.nom.toUpperCase(), style: BSType.sectionKicker()),
        const Spacer(),
        Text(progression,
            style: BSType.body(size: 13, color: BSColors.neutral600)),
      ],
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.actif, required this.revelee});
  final ActiveQuestionnaire actif;
  final bool revelee;

  @override
  Widget build(BuildContext context) {
    final q = actif.current;
    // Manche libre, ou questionnaire épuisé pendant une partie sans limite :
    // l'animateur pose la question de vive voix. On le dit, au lieu de
    // laisser un blanc qui ressemble à une panne.
    if (q == null) {
      return Text(
        'Question posée à voix haute',
        style: BSType.questionConsole().copyWith(color: BSColors.neutral500),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (q.category.isNotEmpty) ...[
          Text(q.category.toUpperCase(), style: BSType.sectionKicker()),
          const SizedBox(height: BSSpace.s2),
        ],
        Text(q.question, style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s3),
        // La réponse reste visible sur la console en tout temps : c'est le
        // pop-out, projeté à la salle, qui attend la révélation.
        if (revelee)
          Container(
            padding: const EdgeInsets.all(BSSpace.s3),
            decoration: const BoxDecoration(
              color: BSColors.accent2_100,
              border:
                  Border(left: BorderSide(color: BSColors.accent2, width: 5)),
            ),
            child: Text(q.answer,
                style: BSType.answerConsole(color: BSColors.accent2_800)),
          )
        else
          Text(q.answer, style: BSType.answerConsole()),
      ],
    );
  }
}

class _Attente extends StatelessWidget {
  const _Attente({required this.moteur, required this.teams, required this.sons});
  final MoteurQuiz moteur;
  final TeamNames teams;
  final Sonorisation sons;

  @override
  Widget build(BuildContext context) {
    final enLice = [
      for (var i = 0; i < 4; i++)
        if (moteur.presents[i] && moteur.enLice[i]) i
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          moteur.estVol && enLice.length == 1
              ? 'À ${teams.nameFor(enLice.first)} de répondre'
              : 'Buzzers armés',
          style: BSType.buzzerNameConsole(size: 24),
        ),
        const SizedBox(height: BSSpace.s3),
        Row(
          children: [
            for (final i in enLice) ...[
              Container(width: 14, height: 14, color: kBuzzerColors[i].fill),
              const SizedBox(width: 6),
              Text(teams.nameFor(i),
                  style: BSType.body(size: 15, color: BSColors.text)),
              const SizedBox(width: BSSpace.s3),
            ],
            if (enLice.isEmpty)
              Text('Aucun buzzer disponible',
                  style: BSType.body(size: 15, color: BSColors.neutral600)),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        if (moteur.utiliseChrono) _Chrono(moteur: moteur),
        const SizedBox(height: BSSpace.s3),
        // Wrap et non Row : des boutons de cette taille debordent d'une
        // colonne etroite, et un bouton coupe est un bouton qu'on rate.
        Wrap(
          spacing: BSSpace.s4,
          runSpacing: BSSpace.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BSSecondaryButton(
              label: 'Personne ne trouve',
              onPressed: moteur.passer,
              grand: true,
            ),
            // Son d'ambiance pendant que la reponse se fait attendre. Il sort
            // la ou l'operateur a choisi, PC ou buzzer : le bouton ne decide
            // pas de la sortie (voir Sonorisation).
            BSGhostButton(label: "Son d'attente", onPressed: sons.attente),
          ],
        ),
      ],
    );
  }
}

class _Chrono extends StatelessWidget {
  const _Chrono({required this.moteur});
  final MoteurQuiz moteur;

  @override
  Widget build(BuildContext context) {
    if (moteur.chronoActif) {
      return Text('${moteur.chronoRestant} s',
          style:
              BSType.buzzerNameConsole(size: 40, color: BSColors.accent2_700));
    }
    if (moteur.tempsEcoule) {
      return Text('Temps écoulé',
          style: BSType.body(size: 17, color: BSColors.accent2_700));
    }
    if (moteur.chronoPremiere <= 0) return const SizedBox.shrink();
    // Le « top » de l'animateur : il vient de lire la question, le chrono ne
    // peut pas partir avant lui.
    return BSPrimaryButton(
        label: 'Lancer le chrono',
        onPressed: moteur.lancerChronoPremiere,
        grand: true);
  }
}

class _Juger extends StatelessWidget {
  const _Juger({required this.moteur, required this.teams});
  final MoteurQuiz moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final qui = moteur.buzzeur;
    if (qui == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 52, height: 52, color: kBuzzerColors[qui].fill),
            const SizedBox(width: BSSpace.s3),
            Text(teams.nameFor(qui), style: BSType.buzzerNameConsole(size: 38)),
          ],
        ),
        const SizedBox(height: BSSpace.s4),
        // Wrap et non Row : ces boutons debordent d'une colonne etroite, et un
        // bouton coupe est un bouton qu'on rate.
        Wrap(
          spacing: BSSpace.s6,
          runSpacing: BSSpace.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BSPrimaryButton(
              label: 'Bonne réponse',
              onPressed: moteur.bonneReponse,
              grand: true,
            ),
            // Un vrai ecart entre les deux jugements, et une couleur qui les
            // separe : se tromper ici retire ou donne un point devant tout le
            // monde, et il faut ensuite corriger a la vue de la salle.
            BSSecondaryButton(
              label: moteur.estPenalite ? 'Mauvaise (-1)' : 'Mauvaise réponse',
              onPressed: moteur.mauvaiseReponse,
              grand: true,
              teinte: BSColors.accent2,
            ),
            BSGhostButton(
                label: 'Personne ne trouve', onPressed: moteur.passer),
          ],
        ),
      ],
    );
  }
}

class _Scores extends StatelessWidget {
  const _Scores({required this.moteur, required this.teams});
  final MoteurQuiz moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    final qui = moteur.dernierJuge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (qui != null && moteur.derniereEtaitBonne)
          Text('Point pour ${teams.nameFor(qui)}',
              style: BSType.buzzerNameConsole(size: 28))
        else
          Text('Question terminée', style: BSType.buzzerNameConsole(size: 28)),
        const SizedBox(height: BSSpace.s4),
        _BoutonSuivante(moteur: moteur),
      ],
    );
  }
}

class _Revelation extends StatelessWidget {
  const _Revelation({required this.moteur});
  final MoteurQuiz moteur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          moteur.tempsEcoule ? 'Temps écoulé' : "Personne n'a trouvé",
          style: BSType.buzzerNameConsole(size: 28),
        ),
        const SizedBox(height: BSSpace.s4),
        _BoutonSuivante(moteur: moteur),
      ],
    );
  }
}

class _BoutonSuivante extends StatelessWidget {
  const _BoutonSuivante({required this.moteur});
  final MoteurQuiz moteur;

  @override
  Widget build(BuildContext context) {
    final derniere = moteur.limiteQuestions > 0 &&
        moteur.numeroQuestion >= moteur.limiteQuestions;
    return BSPrimaryButton(
      label: derniere ? 'Voir le résultat' : 'Question suivante',
      onPressed: moteur.continuer,
      grand: true,
    );
  }
}

class _TableauScores extends StatelessWidget {
  const _TableauScores({required this.moteur, required this.teams});
  final MoteurQuiz moteur;
  final TeamNames teams;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          if (moteur.presents[i])
            Padding(
              padding: const EdgeInsets.only(right: BSSpace.s6),
              child: Row(
                children: [
                  Container(width: 14, height: 14, color: kBuzzerColors[i].fill),
                  const SizedBox(width: 6),
                  Text(teams.nameFor(i),
                      style:
                          BSType.body(size: 15, color: BSColors.neutral700)),
                  const SizedBox(width: 8),
                  Text('${moteur.scores[i]}',
                      style: BSType.buzzerNameConsole(size: 22)),
                ],
              ),
            ),
      ],
    );
  }
}

// --- Après la partie -----------------------------------------------------

class _FinDePartie extends StatelessWidget {
  const _FinDePartie({
    required this.moteur,
    required this.teams,
    required this.actif,
    required this.tirage,
  });
  final MoteurQuiz moteur;
  final TeamNames teams;
  final ActiveQuestionnaire actif;
  final TirageQuestions tirage;

  // LA QUESTION DU BRIS EST PIOCHEE DANS LE PERIMETRE, pas prise dans le
  // questionnaire : celui-ci est termine, et rejouer une de ses questions
  // serait absurde puisque toute la salle l'a deja entendue.
  //
  // Le perimetre suit la manche : la collection du questionnaire choisi, ou
  // tout le catalogue pour un questionnaire personnalise, qui n'appartient a
  // aucune collection (voir ActiveQuestionnaire.collectionDuBris).
  Future<void> _departager() async {
    final question =
        await tirage.questionDeBris(collection: actif.collectionDuBris);
    if (question != null) actif.poserQuestionDeBris(question);
    // Faute de tirage possible (hors ligne, rien de synchronise), le moteur
    // prend la question suivante du questionnaire : mieux vaut departager
    // avec une question deja vue que pas du tout.
    moteur.lancerBrisDegalite();
  }

  @override
  Widget build(BuildContext context) {
    final qui = moteur.gagnant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(moteur.egalite ? 'Égalité' : 'Fin de partie',
            style: BSType.questionConsole()),
        const SizedBox(height: BSSpace.s4),
        if (qui != null)
          Row(
            children: [
              Container(width: 52, height: 52, color: kBuzzerColors[qui].fill),
              const SizedBox(width: BSSpace.s3),
              Text('${teams.nameFor(qui)} gagne',
                  style: BSType.buzzerNameConsole(size: 38)),
            ],
          )
        else if (moteur.egalite)
          Text('Plusieurs buzzers sont à égalité.',
              style: BSType.body(size: 17, color: BSColors.neutral700)),
        if (moteur.motFinal.isNotEmpty) ...[
          const SizedBox(height: BSSpace.s3),
          // La meme phrase que la salle voit, pour que l'animateur sache ce
          // qui est projete derriere lui.
          SizedBox(
            width: 620,
            child: Text(moteur.motFinal,
                style: BSType.body(size: 17, color: BSColors.neutral600)),
          ),
        ],
        const SizedBox(height: BSSpace.s6),
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s6),
        // SUR UNE EGALITE, C'EST L'ANIMATEUR QUI DECIDE. Une soiree peut tres
        // bien se terminer a egalite ; forcer une manche de plus a des gens
        // qui rangent deja leurs manteaux serait penible.
        Wrap(
          spacing: BSSpace.s4,
          runSpacing: BSSpace.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (moteur.egalite)
              BSPrimaryButton(
                label: 'Départager',
                onPressed: _departager,
                grand: true,
              ),
            BSSecondaryButton(
              label: moteur.egalite ? "Accepter l'égalité" : 'Nouvelle partie',
              onPressed: moteur.retourAuMenu,
              grand: true,
            ),
          ],
        ),
      ],
    );
  }
}

// --- Ouverture -----------------------------------------------------------

// Pendant la musique et le chenillard. Rien à décider, mais de quoi écourter :
// l'animateur peut vouloir enchaîner sans attendre la fin du morceau, et si le
// son sort du buzzer l'application ne sait pas quand il finit.
class _Ouverture extends StatelessWidget {
  const _Ouverture({required this.moteur});
  final MoteurQuiz moteur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(gameModeName(moteur.jeu).toUpperCase(), style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        Text(
          moteur.ouvertureTerminee ? 'Prêt à commencer' : 'Ouverture',
          style: BSType.questionConsole(),
        ),
        const SizedBox(height: BSSpace.s3),
        Text(
          moteur.ouvertureTerminee
              ? "La première question part quand vous le dites. Prenez le "
                  "temps d'accueillir la salle : l'écran public tient tout seul."
              : 'La musique joue et les boutons défilent.',
          style: BSType.body(size: 17, color: BSColors.neutral700),
        ),
        const SizedBox(height: BSSpace.s6),
        if (moteur.ouvertureTerminee)
          BSPrimaryButton(
            label: 'Lancer la première question',
            onPressed: moteur.commencerLesQuestions,
            grand: true,
          )
        else
          BSSecondaryButton(
            label: "Écourter l'ouverture",
            onPressed: moteur.commencerLesQuestions,
            grand: true,
          ),
      ],
    );
  }
}
