import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../popout/popout_snapshot.dart';
import 'cache_pochettes.dart';
import 'jetons_spotify.dart';
import 'spotify_api.dart';
import 'spotify_auth.dart';

// LA MUSIQUE D'AMBIANCE, ET RIEN D'AUTRE.
//
// Ce service ne joue aucun son : il commande le client Spotify du poste (ou
// n'importe quel appareil du compte) par l'API Web, et il rapporte ce qui
// joue. Le son de partie continue de passer par Sonorisation, qui ne sait
// rien d'ici. Les deux ne se croisent qu'à un seul endroit : l'ouverture
// d'une partie coupe l'ambiance.
//
// TOUT ÉCHOUE EN SILENCE, OU PRESQUE. Une soirée se joue très bien sans
// musique, et un message rouge cinq minutes avant le départ ne sert
// personne. Les seules erreurs affichées sont celles sur lesquelles
// l'animateur peut agir : Client ID fautif, aucun appareil actif, connexion
// révoquée. Le reste remplit [derniereErreur], sous les commandes, et
// s'efface au premier appel qui repasse.
//
// LE CLIENT ID EST SAISI PAR L'ANIMATEUR, jamais compilé. Depuis février
// 2026, une application Spotify en mode développement est limitée à cinq
// utilisateurs autorisés et à une seule par développeur : un identifiant
// compilé dans le binaire condamnerait tout le monde sauf cinq personnes.
// Chacun crée la sienne, et PKCE fait qu'il n'y a aucun secret à protéger.

enum EtatAmbiance {
  deconnecte,
  connexionEnCours,
  sansAppareil,
  enPause,
  enLecture,
  erreur,
}

class AmbianceSpotify extends ChangeNotifier {
  AmbianceSpotify({
    http.Client? client,
    AuthentificationSpotify? auth,
    CachePochettes? cache,
  })  : _client = client ?? http.Client(),
        _cache = cache ?? CachePochettes(client: client) {
    _auth = auth ?? AuthentificationSpotify(client: _client);
    _api = ApiSpotify(client: _client, jeton: _jetonValide);
  }

  static const _cleClientId = 'spotify_client_id';
  static const _cleRefresh = 'spotify_refresh_token';
  static const _clePlaylist = 'spotify_playlist_id';
  static const _cleAleatoire = 'spotify_aleatoire';

  // Trois secondes : assez pour que la salle voie le titre changer à peu
  // près quand la chanson change, assez peu pour rester loin des limites de
  // débit de Spotify. Le pop-out n'est prévenu que si quelque chose de
  // visible a bougé (voir _sonder), sinon l'instantané repartirait trois
  // fois par seconde pour rien.
  static const _rythme = Duration(seconds: 3);

  final http.Client _client;
  final CachePochettes _cache;
  late final AuthentificationSpotify _auth;
  late final ApiSpotify _api;

  Timer? _sondage;
  JetonsSpotify? _jetons;
  Future<JetonsSpotify>? _rafraichissementEnVol;
  String? _refresh;
  DateTime? _pauseJusqua;
  int _echecsReseau = 0;
  int _tics = 0;

  EtatAmbiance _etat = EtatAmbiance.deconnecte;
  EtatAmbiance get etat => _etat;

  String _clientId = '';
  String get clientId => _clientId;

  List<PlaylistSpotify> _playlists = const [];
  List<PlaylistSpotify> get playlists => _playlists;
  bool _chargementPlaylists = false;
  bool get chargementPlaylists => _chargementPlaylists;

  String? _playlistChoisieId;
  String? get playlistChoisieId => _playlistChoisieId;

  bool _aleatoire = false;
  bool get aleatoire => _aleatoire;

  AppareilSpotify? _appareil;
  AppareilSpotify? get appareil => _appareil;

  PisteEnCours _piste = PisteEnCours.aucune;

  /// Ce qui part vers l'écran public. Voir [PisteEnCours].
  PisteEnCours get piste => _piste;

  String? _derniereErreur;
  String? get derniereErreur => _derniereErreur;

  /// L'adresse d'autorisation, quand le navigateur n'a pas voulu s'ouvrir.
  String? get urlDeSecours => _auth.urlDeSecours;

  bool _enPausePourLaPartie = false;

  /// Vrai quand c'est le départ d'une partie qui a coupé la musique, et non
  /// l'animateur. L'écran le dit, sinon on cherche pourquoi ça s'est arrêté.
  bool get enPausePourLaPartie => _enPausePourLaPartie;

  bool get connecte =>
      _etat != EtatAmbiance.deconnecte &&
      _etat != EtatAmbiance.connexionEnCours &&
      _etat != EtatAmbiance.erreur;

  /// Vrai quand les commandes de lecture ont un sens.
  bool get peutCommander => connecte;

  // ---------------------------------------------------------------- prefs

  /// Relit ce qui a été retenu et reprend la connexion sans navigateur.
  ///
  /// LE JETON DE RAFRAÎCHISSEMENT DORT EN CLAIR dans les préférences (le
  /// registre de l'utilisateur, sous Windows). C'est assumé : il ne donne
  /// que les cinq droits demandés, il se révoque en un clic depuis
  /// spotify.com/account/apps, et l'alternative serait de refaire tout le
  /// détour par le navigateur au début de chaque soirée, devant la salle.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getString(_cleClientId) ?? '';
    _refresh = prefs.getString(_cleRefresh);
    _playlistChoisieId = prefs.getString(_clePlaylist);
    _aleatoire = prefs.getBool(_cleAleatoire) ?? false;
    notifyListeners();

    unawaited(_cache.menage());
    if (_refresh != null && _clientId.isNotEmpty) await _reprendre();
  }

  Future<void> reglerClientId(String valeur) async {
    final propre = valeur.trim();
    if (propre == _clientId) return;
    _clientId = propre;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleClientId, propre);
  }

  Future<void> choisirPlaylist(String id) async {
    // Choisir ne lance rien : l'animateur prépare souvent sa soirée
    // longtemps avant, et une musique qui partirait toute seule dans une
    // salle vide serait une surprise désagréable.
    _playlistChoisieId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clePlaylist, id);
  }

  Future<void> basculerAleatoire() async {
    _aleatoire = !_aleatoire;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cleAleatoire, _aleatoire);
    if (connecte) {
      await _commande(() => _api.melanger(_aleatoire, appareilId: _appareil?.id));
    }
  }

  // ----------------------------------------------------------- connexion

  Future<void> connecter() async {
    if (_clientId.isEmpty) return;
    _etat = EtatAmbiance.connexionEnCours;
    _derniereErreur = null;
    notifyListeners();
    try {
      final jetons = await _auth.connecter(clientId: _clientId);
      await _garderJetons(jetons);
      _etat = EtatAmbiance.enPause;
      notifyListeners();
      await rafraichirPlaylists();
      await _sonder();
      _demarrerSondage();
    } on ErreurAuthentification catch (e) {
      _etat = EtatAmbiance.erreur;
      _derniereErreur = e.message;
      notifyListeners();
    }
  }

  Future<void> annulerConnexion() async {
    await _auth.annuler();
    _etat = _refresh == null ? EtatAmbiance.deconnecte : EtatAmbiance.enPause;
    notifyListeners();
  }

  /// Oublie la connexion, garde le Client ID et la liste choisie.
  ///
  /// Se déconnecter n'est pas changer de compte : réenregistrer son Client ID
  /// et rechoisir sa liste à chaque fois serait une punition.
  Future<void> deconnecter() async {
    _sondage?.cancel();
    _sondage = null;
    _jetons = null;
    _refresh = null;
    _playlists = const [];
    _appareil = null;
    _piste = PisteEnCours.aucune;
    _enPausePourLaPartie = false;
    _derniereErreur = null;
    _etat = EtatAmbiance.deconnecte;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cleRefresh);
  }

  Future<void> _reprendre() async {
    try {
      final jetons =
          await _auth.rafraichir(clientId: _clientId, refresh: _refresh!);
      await _garderJetons(jetons);
      _etat = EtatAmbiance.enPause;
      notifyListeners();
      await rafraichirPlaylists();
      await _sonder();
      _demarrerSondage();
    } on ErreurAuthentification catch (e) {
      if (e.revoque) {
        // Le jeton ne vaut plus rien : le garder ferait échouer chaque
        // ouverture de l'application sans jamais s'expliquer.
        await deconnecter();
        _etat = EtatAmbiance.erreur;
        _derniereErreur = e.message;
      } else {
        // Hors ligne au lancement, par exemple. On garde le jeton : le
        // Wi-Fi de la salle arrive souvent après nous.
        _etat = EtatAmbiance.deconnecte;
        _derniereErreur = e.message;
      }
      notifyListeners();
    }
  }

  Future<void> _garderJetons(JetonsSpotify jetons) async {
    _jetons = jetons;
    _refresh = jetons.rafraichissement;
    _derniereErreur = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleRefresh, jetons.rafraichissement);
  }

  /// Un jeton d'accès valide, rafraîchi d'avance si l'heure approche.
  ///
  /// Une seule demande de rafraîchissement en vol à la fois : le sondage et
  /// un clic de l'animateur peuvent tomber en même temps, et deux échanges
  /// concurrents feraient tourner le jeton de rafraîchissement deux fois,
  /// dont une pour rien.
  Future<String> _jetonValide() async {
    final courant = _jetons;
    if (courant != null && !courant.doitRafraichir(DateTime.now())) {
      return courant.acces;
    }
    final refresh = _refresh;
    if (refresh == null) {
      throw ErreurAuthentification('Pas connecté à Spotify.');
    }
    final envol = _rafraichissementEnVol ??=
        _auth.rafraichir(clientId: _clientId, refresh: refresh);
    try {
      final jetons = await envol;
      await _garderJetons(jetons);
      return jetons.acces;
    } finally {
      _rafraichissementEnVol = null;
    }
  }

  // ------------------------------------------------------------ commandes

  Future<void> rafraichirPlaylists() async {
    _chargementPlaylists = true;
    notifyListeners();
    final trouvees = await _tenter(_api.listerPlaylists);
    if (trouvees != null) _playlists = trouvees;
    _chargementPlaylists = false;
    notifyListeners();
  }

  Future<void> lire() async {
    // L'APPAREIL D'ABORD. Spotify répond 404 quand aucun appareil n'est
    // actif, et « Spotify est ouvert mais je n'ai encore rien joué » est
    // exactement ce cas-là : viser explicitement le premier appareil connu
    // le règle, alors qu'un appel à l'aveugle échouerait.
    final cible = await _cibler();
    final id = _playlistChoisieId;

    if (_aleatoire) {
      // Avant de lancer, sinon la première pièce de la liste sort toujours
      // en premier et l'aléatoire ne commence qu'à la deuxième.
      await _commande(() => _api.melanger(true, appareilId: cible));
    }
    final fait = await _commande(() => _api.lire(
          contextUri: id == null ? null : 'spotify:playlist:$id',
          appareilId: cible,
        ));
    if (!fait) return;

    _enPausePourLaPartie = false;
    _etat = EtatAmbiance.enLecture;
    _piste = _piste.copierAvec(enLecture: true);
    notifyListeners();
    _demarrerSondage();
    await _sonder();
  }

  Future<void> pause() async {
    final fait = await _commande(() => _api.pause(appareilId: _appareil?.id));
    if (!fait) return;
    _enPausePourLaPartie = false;
    _etat = EtatAmbiance.enPause;
    _piste = _piste.copierAvec(enLecture: false);
    notifyListeners();
  }

  Future<void> suivant() async {
    await _commande(() => _api.suivant(appareilId: _appareil?.id));
    await _sonder();
  }

  /// Coupe l'ambiance parce qu'une partie s'ouvre.
  ///
  /// Appelé par Sonorisation au moment de l'ouverture. Silencieux par
  /// construction : personne ne veut d'un message d'erreur Spotify pendant
  /// que la salle se tait pour la première question.
  ///
  /// L'écran public perd son bandeau TOUT DE SUITE, sans attendre la réponse
  /// de Spotify : le son s'arrête en une fraction de seconde, et un bandeau
  /// qui survivrait deux secondes de plus se remarquerait.
  void pauserPourLaPartie() {
    if (_etat != EtatAmbiance.enLecture) return;
    _enPausePourLaPartie = true;
    _etat = EtatAmbiance.enPause;
    _piste = _piste.copierAvec(enLecture: false);
    notifyListeners();
    unawaited(_commande(() => _api.pause(appareilId: _appareil?.id),
        silencieux: true));
  }

  /// Place le service dans un état de lecture, sans passer par Spotify.
  ///
  /// Le seul moyen de vérifier que l'ouverture d'une partie coupe bien la
  /// musique : le vrai chemin demanderait un compte, un appareil actif et
  /// une chanson qui joue.
  @visibleForTesting
  void reprendrePourTest({
    required EtatAmbiance etat,
    String titre = '',
    String artiste = '',
  }) {
    _etat = etat;
    _piste = PisteEnCours(
      titre: titre,
      artiste: artiste,
      enLecture: etat == EtatAmbiance.enLecture,
    );
    notifyListeners();
  }

  Future<String?> _cibler() async {
    if (_appareil?.id != null) return _appareil!.id;
    final liste = await _tenter(_api.appareils);
    if (liste == null || liste.isEmpty) return null;
    _appareil = liste.firstWhere((a) => a.actif, orElse: () => liste.first);
    return _appareil?.id;
  }

  // -------------------------------------------------------------- sondage

  void _demarrerSondage() {
    _sondage?.cancel();
    _sondage = Timer.periodic(_rythme, (_) => unawaited(_sonder()));
  }

  Future<void> _sonder() async {
    if (_refresh == null) return;
    final pause = _pauseJusqua;
    if (pause != null && DateTime.now().isBefore(pause)) return;
    _pauseJusqua = null;

    // La liste des appareils bouge lentement : toutes les cinq passes
    // suffisent, et ça divise par deux le trafic vers Spotify.
    if (_tics++ % 5 == 0) {
      final liste = await _tenter(_api.appareils, silencieux: true);
      if (liste != null) {
        _appareil = liste.isEmpty
            ? null
            : liste.firstWhere((a) => a.actif, orElse: () => liste.first);
      }
    }

    final avantId = _piste.titre;
    final avantLecture = _piste.enLecture;
    final avantEtat = _etat;
    final avantErreur = _derniereErreur;

    final lecture = await _tenter(_api.lectureEnCours, silencieux: true);

    if (lecture == null) {
      // Rien ne joue : Spotify répond 204. Ce n'est pas une erreur, mais on
      // ne garde pas la dernière piste à l'écran pour autant.
      _piste = PisteEnCours.aucune;
      if (_etat != EtatAmbiance.erreur) {
        _etat = _appareil == null
            ? EtatAmbiance.sansAppareil
            : EtatAmbiance.enPause;
      }
    } else {
      _etat = lecture.enLecture ? EtatAmbiance.enLecture : EtatAmbiance.enPause;
      final memePiste = lecture.idPiste == _idPiste;
      _idPiste = lecture.idPiste;
      _piste = PisteEnCours(
        titre: lecture.titre,
        artiste: lecture.artiste,
        // Le titre part tout de suite ; la pochette suivra quand elle sera
        // descendue. Attendre l'image retarderait le texte pour rien.
        pochette: memePiste ? _piste.pochette : null,
        enLecture: lecture.enLecture,
      );
      if (!memePiste && lecture.pochetteUrl != null) {
        unawaited(_descendrePochette(lecture.idPiste, lecture.pochetteUrl!));
      }
    }

    // NE PRÉVENIR QUE SI QUELQUE CHOSE A BOUGÉ. Sans ce garde-fou,
    // l'instantané de l'écran public repartirait toutes les trois secondes,
    // toute la soirée, pour redire la même chose.
    if (_piste.titre != avantId ||
        _piste.enLecture != avantLecture ||
        _etat != avantEtat ||
        _derniereErreur != avantErreur) {
      notifyListeners();
    }
  }

  String? _idPiste;

  Future<void> _descendrePochette(String idPiste, String url) async {
    final chemin = await _cache.chemin(idPiste: idPiste, url: url);
    // La piste a pu changer pendant le téléchargement : coller cette
    // pochette-là sur la suivante montrerait la mauvaise image à la salle.
    if (chemin == null || _idPiste != idPiste) return;
    _piste = _piste.copierAvec(pochette: chemin);
    notifyListeners();
  }

  /// Une commande du lecteur, qui ne rend rien mais dont on veut savoir si
  /// elle est passée : c'est ce qui décide d'afficher « en lecture » ou de
  /// laisser l'écran tel quel.
  Future<bool> _commande(Future<void> Function() action,
          {bool silencieux = false}) async =>
      await _tenter<bool>(() async {
        await action();
        return true;
      }, silencieux: silencieux) ??
      false;

  /// Exécute un appel et traduit ses ennuis. Rend null quand ça a échoué.
  ///
  /// [silencieux] pour ce qui tourne tout seul : une coupure de Wi-Fi au
  /// milieu d'un sondage ne doit pas allumer un message pendant la partie.
  Future<T?> _tenter<T>(Future<T> Function() action,
      {bool silencieux = false}) async {
    for (var essai = 0; essai < 2; essai++) {
      try {
        final r = await action();
        _echecsReseau = 0;
        if (_derniereErreur != null) {
          _derniereErreur = null;
          notifyListeners();
        }
        return r;
      } on ErreurSpotify catch (e) {
        if (e.statut == 401 && essai == 0) {
          // Le jeton a expiré entre deux appels : on en redemande un et on
          // rejoue une fois. Deux fois serait une boucle.
          _jetons = null;
          continue;
        }
        if (e.statut == 429) {
          // Spotify demande une pause : la lui refuser ferait empirer les
          // choses, et le sondage n'est pas pressé.
          _pauseJusqua = DateTime.now()
              .add(e.reessayerDans ?? const Duration(seconds: 5));
        }
        _signaler(e.message, silencieux);
        return null;
      } on ErreurAuthentification catch (e) {
        if (e.revoque) {
          await deconnecter();
          _etat = EtatAmbiance.erreur;
        }
        _signaler(e.message, silencieux);
        return null;
      } catch (e) {
        _echecsReseau++;
        // Après une quinzaine de secondes de silence, la salle ne doit plus
        // lire un titre qui a peut-être changé trois fois depuis.
        if (_echecsReseau >= 5 && _piste.quelqueChose) {
          _piste = PisteEnCours.aucune;
          notifyListeners();
        }
        _signaler(messageErreurReseau(e), silencieux);
        return null;
      }
    }
    return null;
  }

  void _signaler(String message, bool silencieux) {
    if (silencieux && _derniereErreur == null) return;
    if (_derniereErreur == message) return;
    _derniereErreur = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _sondage?.cancel();
    unawaited(_auth.annuler());
    _client.close();
    super.dispose();
  }
}
