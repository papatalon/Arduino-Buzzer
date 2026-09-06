// Les deux jetons de Spotify, et la seule règle qui compte : quand
// rafraîchir.
//
// LE JETON D'ACCÈS DURE UNE HEURE. Une soirée en dure trois. Le rafraîchir
// « quand ça échoue » voudrait dire un 401 en plein milieu d'une chanson,
// donc on le rafraîchit AVANT, avec une marge : la règle est pure et testée
// ici plutôt que noyée dans la plomberie HTTP.
//
// LE JETON DE RAFRAÎCHISSEMENT, LUI, NE REVIENT PAS TOUJOURS. Spotify le
// renvoie parfois (rotation), parfois pas. Écraser l'ancien par un null
// déconnecterait l'animateur à la première heure écoulée : [decode] garde
// le précédent quand la réponse n'en porte pas.
class JetonsSpotify {
  const JetonsSpotify({
    required this.acces,
    required this.rafraichissement,
    required this.expiration,
  });

  /// Le jeton porté par chaque appel à l'API, en en-tête Authorization.
  final String acces;

  /// Ce qui survit à la fermeture de l'application, et la seule chose qu'on
  /// garde dans les préférences.
  final String rafraichissement;

  final DateTime expiration;

  /// [maintenant] est passé plutôt que lu : sans ça, la règle ne se teste
  /// qu'en attendant vraiment une heure.
  ///
  /// [refreshPrecedent] sert au rafraîchissement, où la réponse peut ne pas
  /// contenir de nouveau jeton de rafraîchissement.
  factory JetonsSpotify.decode(
    Map<String, dynamic> json, {
    required DateTime maintenant,
    String? refreshPrecedent,
  }) {
    final refresh = json['refresh_token'] as String? ?? refreshPrecedent;
    if (refresh == null || refresh.isEmpty) {
      throw const FormatException('Réponse sans jeton de rafraîchissement.');
    }
    final secondes = json['expires_in'] as int? ?? 3600;
    return JetonsSpotify(
      acces: json['access_token'] as String,
      rafraichissement: refresh,
      expiration: maintenant.add(Duration(seconds: secondes)),
    );
  }

  /// Vrai quand il reste moins de [marge] avant l'expiration.
  ///
  /// Une minute : assez pour qu'un appel parti juste avant la bascule
  /// arrive encore avec un jeton valide, assez peu pour ne pas rafraîchir
  /// à tout bout de champ.
  bool doitRafraichir(DateTime maintenant,
          {Duration marge = const Duration(seconds: 60)}) =>
      !maintenant.add(marge).isBefore(expiration);
}
