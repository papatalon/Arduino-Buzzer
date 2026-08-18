import 'dart:convert';

import '../protocol.dart';

// Instantané de l'état à synchroniser vers la fenêtre de l'écran public —
// c'est aussi un contrat de confidentialité : seuls les champs présents ici
// PEUVENT atteindre le pop-out (design_handoff_buzzer_console/README.md,
// tableau "Règles de confidentialité"). Ne pas y ajouter la réponse, la
// séquence Simon, les écarts du chrono aveugle ou le numéro du son sans
// passer par un état "révélée" explicite.
class PopoutSnapshot {
  const PopoutSnapshot({
    required this.scores,
    required this.present,
    this.gameMode,
    this.lastBuzz,
  });

  static const empty = PopoutSnapshot(scores: [0, 0, 0, 0], present: [true, true, true, true]);

  final List<int> scores;
  final List<bool> present;
  final int? gameMode;
  final int? lastBuzz;

  factory PopoutSnapshot.fromGameState(GameState game) => PopoutSnapshot(
        scores: game.scores,
        present: game.present,
        gameMode: game.gameMode,
        lastBuzz: game.lastBuzz,
      );

  factory PopoutSnapshot.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return PopoutSnapshot(
      scores: (json['scores'] as List).cast<int>(),
      present: (json['present'] as List).cast<bool>(),
      gameMode: json['gameMode'] as int?,
      lastBuzz: json['lastBuzz'] as int?,
    );
  }

  String encode() => jsonEncode({
        'scores': scores,
        'present': present,
        'gameMode': gameMode,
        'lastBuzz': lastBuzz,
      });
}
