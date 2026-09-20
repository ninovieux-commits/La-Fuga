/// Service en ligne : session, reconnexion automatique et temps réel.
///
/// Réunit [OnlineClient] (HTTP) et [FugaSocket] (Socket.IO) derrière une seule
/// façade, et retient la session dans les réglages pour que l'app retrouve le
/// compte au lancement suivant.
library;

import 'dart:async';

import '../state/settings.dart';
import 'api_client.dart';
import 'online_client.dart';
import 'socket_client.dart';

/// Comment s'est terminée une tentative de reconnexion automatique.
enum AutoLoginOutcome {
  /// Session retrouvée : le joueur est connecté.
  connected,

  /// Aucun token enregistré.
  noSession,

  /// Le serveur a explicitement rejeté le token : il faut se reconnecter.
  rejected,

  /// Serveur injoignable. Le token reste valide, on ne déconnecte pas —
  /// une simple coupure ne doit pas effacer un compte.
  offline,
}

/// Façade du mode en ligne.
class OnlineService {
  OnlineService({
    OnlineClient? client,
    Settings? settings,
    RealtimeSocket Function(String serverUrl)? socketFactory,
  }) : _socketFactory = socketFactory ?? _defaultSocket,
       _client =
           client ??
           OnlineClient(
             api: ApiClient(
               serverUrl: (settings ?? Settings.instance).serverUrl,
             ),
           ),
       _settings = settings ?? Settings.instance;

  static OnlineService? _instance;

  /// Instance de l'application. Créée une fois au démarrage.
  static OnlineService get instance => _instance ??= OnlineService();

  /// Remplace l'instance — pour les tests.
  static set instance(OnlineService service) => _instance = service;

  final OnlineClient _client;
  final Settings _settings;

  /// Fabrique de la connexion temps réel. Injectable pour les tests.
  final RealtimeSocket Function(String serverUrl) _socketFactory;

  static RealtimeSocket _defaultSocket(String serverUrl) =>
      FugaSocket(serverUrl: serverUrl);

  RealtimeSocket? _socket;

  OnlineClient get client => _client;
  OnlineSession? get session => _client.session;
  bool get isLoggedIn => _client.isLoggedIn;
  String? get pseudo => _client.pseudo;

  /// Connexion temps réel, créée à la demande.
  ///
  /// `null` tant que personne n'est connecté : il n'y a rien à authentifier.
  RealtimeSocket? get socket => _socket;

  bool get isSocketConnected => _socket?.isConnected ?? false;

  // ── Authentification ──────────────────────────────────────────────────────

  /// Tente de retrouver la session enregistrée.
  Future<AutoLoginOutcome> tryAutoLogin() async {
    final token = _settings.onlineToken;
    if (token == null || token.isEmpty) return AutoLoginOutcome.noSession;

    final r = await _client.pingWithToken(token);
    if (r.isOk) {
      await _persistSession();
      await connectSocket();
      return AutoLoginOutcome.connected;
    }
    if (r.isNetworkError) return AutoLoginOutcome.offline;

    // Refus explicite : le token est périmé, on nettoie.
    await _settings.clearOnlineSession();
    return AutoLoginOutcome.rejected;
  }

  /// Connexion avec pseudo et mot de passe.
  ///
  /// Renvoie `null` si tout s'est bien passé, sinon le message à afficher.
  Future<String?> login(String pseudo, String password) async {
    final r = await _client.login(pseudo.trim(), password);
    if (!r.isOk) return _messageFor(r);
    await _persistSession();
    await connectSocket();
    return null;
  }

  /// Création de compte. Pseudo : 3 à 20 caractères, `[A-Za-z0-9_-]`.
  Future<String?> register(
    String pseudo,
    String password, {
    String email = '',
  }) async {
    final r = await _client.register(
      pseudo.trim(),
      password,
      email: email.trim(),
    );
    if (!r.isOk) return _messageFor(r);
    await _persistSession();
    await connectSocket();
    return null;
  }

  /// Déconnexion : coupe le temps réel et efface la session enregistrée.
  Future<void> logout() async {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _client.logout();
    await _settings.clearOnlineSession();
  }

  String _messageFor(ApiResult r) =>
      r.serverError ?? r.error ?? 'Erreur inconnue';

  Future<void> _persistSession() async {
    final s = _client.session;
    if (s == null) return;
    await _settings.saveOnlineSession(
      token: s.token,
      pseudo: s.pseudo,
      melo: s.melo,
      meloRandom: s.meloRandom,
    );
    // Le serveur tronque le thème stocké : on concilie avec le thème local
    // avant de l'appliquer, sinon un composite long reviendrait amputé.
    final theme = reconcileTheme(s.theme, _settings.theme);
    if (theme != _settings.theme) await _settings.setTheme(theme);
  }

  // ── Temps réel ────────────────────────────────────────────────────────────

  /// Ouvre la connexion Socket.IO et s'authentifie.
  Future<void> connectSocket() async {
    final token = _client.token;
    if (token == null) return;
    _socket ??= _socketFactory(_client.serverUrl);
    await _socket!.connect(token);
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
    _client.close();
  }
}

/// Validation d'un pseudo, aux règles du serveur.
///
/// Les vérifier ici évite un aller-retour réseau pour dire au joueur ce qu'on
/// sait déjà.
String? validatePseudo(String pseudo) {
  final p = pseudo.trim();
  if (p.length < 3) return 'Le pseudo fait au moins 3 caractères.';
  if (p.length > 20) return 'Le pseudo fait au plus 20 caractères.';
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(p)) {
    return 'Lettres, chiffres, tiret et tiret bas uniquement.';
  }
  return null;
}
