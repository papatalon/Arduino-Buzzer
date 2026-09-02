import 'package:flutter/material.dart';

import '../broadsheet/boutons.dart';
import '../broadsheet/tokens.dart';
import '../protocol.dart';
import '../questionnaires/active_questionnaire.dart';
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
  });

  final MoteurQuiz moteur;
  final ActiveQuestionnaire actif;
  final TeamNames teams;
  final VoidCallback onAllerAuxQuestions;

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
                  onAllerAuxQuestions: onAllerAuxQuestions,
                ),
              EtapeQuiz.finie => _FinDePartie(moteur: moteur, teams: teams),
              _ => _EnPartie(moteur: moteur, actif: actif, teams: teams),
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
    required this.onAllerAuxQuestions,
  });

  final MoteurQuiz moteur;
  final ActiveQuestionnaire actif;
  final VoidCallback onAllerAuxQuestions;

  @override
  State<_Lancement> createState() => _LancementState();
}

class _LancementState extends State<_Lancement> {
  int? _jeu;
  int _premiere = 20;
  int _suivantes = 10;

  bool get _chrono => _jeu == 2 || _jeu == 3 || _jeu == 4;

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

        // D'où viennent les questions. Sans ça, « Lancer » démarrerait une
        // partie sans matière et l'animateur ne le découvrirait qu'après.
        Text('LES QUESTIONS', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        _SourceQuestions(
            actif: actif, onAllerAuxQuestions: widget.onAllerAuxQuestions),
        const SizedBox(height: BSSpace.s6),

        Text('LE JEU', style: BSType.sectionKicker()),
        const SizedBox(height: BSSpace.s2),
        for (final j in _jeuxQuiz) ...[
          _CarteJeu(
            nom: j.nom,
            quoi: j.quoi,
            choisi: _jeu == j.index,
            onTap: () => setState(() => _jeu = j.index),
          ),
          const SizedBox(height: BSSpace.s2),
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
              onPressed: (_jeu == null || !actif.pretAJouer)
                  ? null
                  : () {
                      final m = widget.moteur;
                      m.chronoPremiere = _chrono ? _premiere : 0;
                      m.chronoSuivantes = _chrono ? _suivantes : 0;
                      m.demarrer(jeuChoisi: _jeu!, limite: _limite());
                    },
            ),
            const SizedBox(width: BSSpace.s3),
            if (_jeu == null || !actif.pretAJouer)
              Expanded(
                child: Text(
                  _jeu == null
                      ? 'Choisir un jeu pour continuer'
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

class _SourceQuestions extends StatelessWidget {
  const _SourceQuestions(
      {required this.actif, required this.onAllerAuxQuestions});

  final ActiveQuestionnaire actif;
  final VoidCallback onAllerAuxQuestions;

  @override
  Widget build(BuildContext context) {
    final String quoi;
    if (actif.libre) {
      final n = actif.nombreLibre;
      quoi = n == null
          ? "Manche libre, sans limite. Vous posez les questions, l'app compte les points."
          : "Manche libre de $n question${n > 1 ? 's' : ''}. Vous posez les questions, l'app compte les points.";
    } else if (actif.active) {
      quoi =
          '${actif.title} : ${actif.total} question${actif.total > 1 ? 's' : ''}';
    } else {
      quoi = 'Aucun questionnaire choisi.';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            quoi,
            style: BSType.body(
              size: 17,
              color: actif.pretAJouer ? BSColors.text : BSColors.neutral600,
            ),
          ),
        ),
        const SizedBox(width: BSSpace.s3),
        BSGhostButton(
          label: actif.pretAJouer ? 'Changer' : 'Choisir',
          onPressed: onAllerAuxQuestions,
        ),
      ],
    );
  }
}

class _CarteJeu extends StatelessWidget {
  const _CarteJeu({
    required this.nom,
    required this.quoi,
    required this.choisi,
    required this.onTap,
  });

  final String nom;
  final String quoi;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 620,
        padding: const EdgeInsets.symmetric(
            horizontal: BSSpace.s3, vertical: BSSpace.s3),
        decoration: BoxDecoration(
          color: choisi ? BSColors.accent100 : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: choisi ? BSColors.accent : BSColors.divider,
              width: choisi ? 5 : 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nom, style: BSType.buzzerNameConsole(size: 20)),
            const SizedBox(height: 2),
            Text(quoi, style: BSType.body(size: 15, color: BSColors.neutral700)),
          ],
        ),
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
  const _EnPartie(
      {required this.moteur, required this.actif, required this.teams});

  final MoteurQuiz moteur;
  final ActiveQuestionnaire actif;
  final TeamNames teams;

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
          EtapeQuiz.attente => _Attente(moteur: moteur, teams: teams),
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
    final progression = total > 0
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
  const _Attente({required this.moteur, required this.teams});
  final MoteurQuiz moteur;
  final TeamNames teams;

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
        Row(
          children: [
            BSSecondaryButton(
              label: 'Personne ne trouve',
              onPressed: moteur.passer,
            ),
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
    return BSSecondaryButton(
        label: 'Lancer le chrono', onPressed: moteur.lancerChronoPremiere);
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
        Row(
          children: [
            BSPrimaryButton(
                label: 'Bonne réponse', onPressed: moteur.bonneReponse),
            const SizedBox(width: BSSpace.s3),
            BSSecondaryButton(
              label: moteur.estPenalite ? 'Mauvaise (-1)' : 'Mauvaise réponse',
              onPressed: moteur.mauvaiseReponse,
            ),
            const SizedBox(width: BSSpace.s3),
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
  const _FinDePartie({required this.moteur, required this.teams});
  final MoteurQuiz moteur;
  final TeamNames teams;

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
        const SizedBox(height: BSSpace.s6),
        _TableauScores(moteur: moteur, teams: teams),
        const SizedBox(height: BSSpace.s6),
        BSPrimaryButton(
            label: 'Nouvelle partie', onPressed: moteur.retourAuMenu),
      ],
    );
  }
}
