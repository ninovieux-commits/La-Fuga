/// Toutes les routes HTTP du serveur La Fuga — portage de `OnlineClient`
/// (main.py). Mêmes chemins, mêmes clés de charge utile : `server.py` ne
/// change pas.
library;

import 'api_client.dart';

/// Session du joueur connecté.
final class OnlineSession {
  const OnlineSession({
    required this.token,
    required this.pseudo,
    this.melo = 1500,
    this.meloRandom = 1500,
    this.theme = 'original',
    this.photo = '',
  });

  final String token;
  final String pseudo;

  /// Classement en mode standard.
  final int melo;

  /// Classement en mode Random Fuga (colonne `melo_random` côté serveur).
  final int meloRandom;

  /// Thème composite `general|pieces|logo|menu|board`.
  final String theme;

  /// Photo de profil, au format `theme|Pièce`.
  final String photo;

  OnlineSession copyWith({
    String? theme,
    String? photo,
    int? melo,
    int? meloRandom,
  }) => OnlineSession(
    token: token,
    pseudo: pseudo,
    melo: melo ?? this.melo,
    meloRandom: meloRandom ?? this.meloRandom,
    theme: theme ?? this.theme,
    photo: photo ?? this.photo,
  );
}

/// Client de haut niveau : une méthode par route.
class OnlineClient {
  OnlineClient({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;
  OnlineSession? _session;

  OnlineSession? get session => _session;
  bool get isLoggedIn => _session != null;
  String? get token => _session?.token;
  String? get pseudo => _session?.pseudo;

  String get serverUrl => _api.serverUrl;
  set serverUrl(String value) => _api.serverUrl = value;

  void logout() => _session = null;

  /// Payload avec le token, pour les routes authentifiées.
  Map<String, dynamic> _auth([Map<String, dynamic> extra = const {}]) => {
    'token': _session?.token ?? '',
    ...extra,
  };

  OnlineSession _sessionFrom(Map<String, dynamic> d, {String? fallbackToken}) =>
      OnlineSession(
        token: (d['token'] as String?) ?? fallbackToken ?? '',
        pseudo: (d['pseudo'] as String?) ?? '',
        melo: (d['melo'] as num?)?.toInt() ?? 1500,
        meloRandom: (d['melo_random'] as num?)?.toInt() ?? 1500,
        theme: (d['theme'] as String?) ?? 'original',
        photo: (d['photo'] as String?) ?? '',
      );

  // ── Compte ────────────────────────────────────────────────────────────────

  /// Inscription. Pseudo : 3 à 20 caractères, `[A-Za-z0-9_-]`.
  Future<ApiResult> register(
    String pseudo,
    String password, {
    String email = '',
  }) async {
    final r = await _api.post('/register', {
      'pseudo': pseudo,
      'password': password,
      'email': email,
    });
    if (r.isOk) _session = _sessionFrom(r.data!);
    return r;
  }

  Future<ApiResult> login(String pseudo, String password) async {
    final r = await _api.post('/login', {
      'pseudo': pseudo,
      'password': password,
    });
    if (r.isOk) _session = _sessionFrom(r.data!);
    return r;
  }

  /// Reconnexion avec un token sauvegardé.
  ///
  /// En cas d'erreur **réseau**, on ne touche pas à la session : le token
  /// reste probablement valide, et une simple coupure ne doit pas déconnecter
  /// le joueur. Seul un refus explicite du serveur invalide la session.
  Future<ApiResult> pingWithToken(String token) async {
    final r = await _api.post('/ping', {'token': token});
    if (r.isOk) {
      _session = _sessionFrom(r.data!, fallbackToken: token);
    } else if (!r.isNetworkError) {
      _session = null;
    }
    return r;
  }

  Future<ApiResult> accountInfo() => _api.post('/account_info', _auth());

  Future<ApiResult> setEmail(String email) =>
      _api.post('/set_email', _auth({'email': email}));

  /// Préférences de notification : `mail`, `turn`, `msg`, `defi_corr`,
  /// `defi_direct`.
  Future<ApiResult> setNotifPrefs(Map<String, bool> prefs) =>
      _api.post('/set_notif_prefs', _auth(prefs));

  Future<ApiResult> setFcmToken(String fcmToken) =>
      _api.post('/set_fcm_token', _auth({'fcm_token': fcmToken}));

  /// Enregistre le thème côté serveur.
  ///
  /// ⚠️ Le serveur **tronque** la valeur stockée (historiquement à 40
  /// caractères), ce qui casse les thèmes composites longs. Au retour, passer
  /// par `reconcileTheme` pour conserver le thème local complet quand le
  /// serveur n'en a qu'une version coupée.
  Future<ApiResult> setTheme(String theme) async {
    final r = await _api.post('/set_theme', _auth({'theme': theme}));
    if (r.isOk) _session = _session?.copyWith(theme: theme);
    return r;
  }

  // ── Profil et relations ───────────────────────────────────────────────────

  /// Profil d'un joueur ; `pseudo` vide ou nul = le mien.
  Future<ApiResult> getProfile([String? pseudo]) =>
      _api.post('/get_profile', _auth({'pseudo': pseudo ?? ''}));

  Future<ApiResult> searchUser(String pseudo) =>
      _api.post('/search_user', _auth({'pseudo': pseudo}));

  /// Retient la photo de profil sans rien envoyer : le serveur la connaît
  /// déjà, c'est nous qui l'ignorions (le login ne la renvoie pas).
  void rememberPhoto(String photo) =>
      _session = _session?.copyWith(photo: photo);

  Future<ApiResult> setPhoto(String photo) async {
    final r = await _api.post('/set_photo', _auth({'photo': photo}));
    if (r.isOk) _session = _session?.copyWith(photo: photo);
    return r;
  }

  Future<ApiResult> setDescription(String description) =>
      _api.post('/set_description', _auth({'description': description}));

  Future<ApiResult> addFavorite(String pseudo) =>
      _api.post('/add_favorite', _auth({'pseudo': pseudo}));

  Future<ApiResult> removeFavorite(String pseudo) =>
      _api.post('/remove_favorite', _auth({'pseudo': pseudo}));

  Future<ApiResult> listFavorites() => _api.post('/list_favorites', _auth());

  Future<ApiResult> listFollowers() => _api.post('/list_followers', _auth());

  /// Bloquer un joueur : plus de matchmaking ni de défi entre vous.
  Future<ApiResult> blockUser(String pseudo) =>
      _api.post('/block_user', _auth({'pseudo': pseudo}));

  Future<ApiResult> unblockUser(String pseudo) =>
      _api.post('/unblock_user', _auth({'pseudo': pseudo}));

  Future<ApiResult> listBlocked() => _api.post('/list_blocked', _auth());

  // ── Parties enregistrées ──────────────────────────────────────────────────

  /// Lie une partie au compte. `gameData` porte `game_uid`, `nmc_text`,
  /// `joueur1`, `joueur2`, `resultat`, `methode`, `cadence`, `objectif`.
  Future<ApiResult> saveGame(Map<String, dynamic> gameData) =>
      _api.post('/save_game', _auth(gameData));

  /// Parties d'un joueur ; `pseudo` vide ou nul = les miennes.
  Future<ApiResult> listGames([String? pseudo]) =>
      _api.post('/list_games', _auth({'pseudo': pseudo ?? ''}));

  Future<ApiResult> getGame(String gameUid) =>
      _api.post('/get_game', _auth({'game_uid': gameUid}));

  // ── Messagerie ────────────────────────────────────────────────────────────

  Future<ApiResult> sendMessage(String pseudo, String text) =>
      _api.post('/send_message', _auth({'pseudo': pseudo, 'text': text}));

  Future<ApiResult> listConversation(String pseudo) =>
      _api.post('/list_conversation', _auth({'pseudo': pseudo}));

  Future<ApiResult> listConversations() =>
      _api.post('/list_conversations', _auth());

  Future<ApiResult> markRead(String pseudo) =>
      _api.post('/mark_read', _auth({'pseudo': pseudo}));

  // ── Correspondance ────────────────────────────────────────────────────────

  Future<ApiResult> corrList() => _api.post('/corr_list', _auth());

  Future<ApiResult> corrDefier(
    String pseudo,
    String objectif, {
    bool random = false,
  }) => _api.post(
    '/corr_defier',
    _auth({'pseudo': pseudo, 'objectif': objectif, 'random': random}),
  );

  Future<ApiResult> corrRepondre(String gameId, bool accepte) => _api.post(
    '/corr_repondre',
    _auth({'game_id': gameId, 'accepte': accepte}),
  );

  /// Joue un coup en correspondance.
  ///
  /// Quand le coup **clôt** la partie, passer [methode] : le serveur
  /// enregistre le coup et clôt la partie dans la même requête. C'est
  /// volontairement atomique, pour éviter tout double envoi et toute course
  /// entre deux appels.
  Future<ApiResult> corrJouer(
    String gameId,
    String notation, {
    String? methode,
  }) => _api.post(
    '/corr_jouer',
    _auth({
      'game_id': gameId,
      'notation': notation,
      if (methode != null) 'methode': methode,
    }),
  );

  Future<ApiResult> corrAbandon(String gameId) =>
      _api.post('/corr_abandon', _auth({'game_id': gameId}));

  /// Masque une partie de correspondance terminée.
  Future<ApiResult> corrClose(String gameId) =>
      _api.post('/corr_close', _auth({'game_id': gameId}));

  Future<ApiResult> corrProposerNulle(String gameId) =>
      _api.post('/corr_proposer_nulle', _auth({'game_id': gameId}));

  Future<ApiResult> corrRepondreNulle(String gameId, bool accepte) => _api.post(
    '/corr_repondre_nulle',
    _auth({'game_id': gameId, 'accepte': accepte}),
  );

  /// Chat de correspondance.
  ///
  /// Ces deux routes existent côté serveur mais ne sont pas utilisées par le
  /// client Kivy : la fonctionnalité est donc gratuite à brancher ici.
  Future<ApiResult> corrChatSend(String gameId, String text) =>
      _api.post('/corr_chat_send', _auth({'game_id': gameId, 'text': text}));

  Future<ApiResult> corrChatList(String gameId) =>
      _api.post('/corr_chat_list', _auth({'game_id': gameId}));

  void close() => _api.close();
}

/// Concilie le thème renvoyé par le serveur avec le thème local.
///
/// Le serveur tronque la valeur stockée, ce qui casse les composites longs.
/// Si le thème local est un composite dont une troncature correspond
/// exactement au thème serveur, c'est que le serveur n'en a que la version
/// coupée : on garde alors le **local**, plus complet. Sinon on prend celui du
/// serveur (thème choisi depuis un autre appareil).
String reconcileTheme(String? serverTheme, String localTheme) {
  final server = (serverTheme ?? '').trim();
  final local = localTheme.trim();
  if (local.contains('|')) {
    for (final cut in [40, 100, local.length]) {
      if (cut <= local.length && server == local.substring(0, cut)) {
        return local;
      }
    }
  }
  return server.isEmpty ? 'original' : server;
}
