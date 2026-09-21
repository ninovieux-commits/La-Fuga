/// Menu d'accueil — portage de `MenuScreen` (main.py), disposition comprise.
///
/// Tout ce que fait le menu de Kivy se fait ici, au même endroit : la cadence,
/// les quatre boutons de jeu, la recherche d'un joueur, les favoris, les
/// emplacements de correspondance, l'interrupteur Random, le bouton Compte —
/// et le matchmaking, qui se lance depuis le menu avec un simple volet
/// d'attente, sans écran intermédiaire.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../engine/random_fuga.dart';
import '../../game/challenges.dart';
import '../../game/clock.dart';
import '../../game/correspondence.dart';
import '../../game/online_game.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../net/profile.dart';
import '../../net/socket_client.dart';
import '../../state/settings.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/corr_slot.dart';
import '../widgets/first_launch.dart';
import '../widgets/fuga_button.dart';
import '../widgets/menu_tour.dart';
import '../widgets/player_card.dart';
import '../widgets/story_view.dart';
import 'account_screen.dart';
import 'conversations_screen.dart';
import 'corr_game_screen.dart';
import 'game_screen.dart';
import 'login_screen.dart';
import 'online_game_screen.dart';
import 'parties_menu_screen.dart';
import 'settings_screen.dart';
import 'tuto_screen.dart';

/// Encre des titres du menu : le `(0.15, 0.15, 0.15)` de Kivy, presque noir.
/// Une couleur de thème les rendrait bleus sur certains fonds.
const Color kMenuInk = Color.fromRGBO(38, 38, 38, 1);

/// Ce qu'on a choisi dans la liste des favoris : qui, et pour quoi faire.
typedef FavoriteChoice = ({String pseudo, bool challenge});

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.online});

  /// Injectable pour les tests.
  final OnlineService? online;

  @override
  State<MenuScreen> createState() => MenuScreenState();
}

/// L'état du menu est public : la visite guidée se lance de l'extérieur
/// (fin du tuto), et les tests la déclenchent de la même façon.
class MenuScreenState extends State<MenuScreen> {
  late final OnlineService _online = widget.online ?? OnlineService.instance;
  late final CorrespondenceService _corr = CorrespondenceService(
    _online.client,
  );

  final TextEditingController _searchField = TextEditingController();

  ThemeAxes get _axes => Settings.instance.themeAxes;

  /// Cadence choisie au menu. Elle vaut pour les parties locales et en ligne ;
  /// Deep Grey joue toujours sans chrono.
  Cadence _cadence = Cadence.parDefaut;

  /// Variante Random Fuga. Comme en Kivy, elle se remet à zéro à chaque
  /// lancement de l'application.
  bool _random = false;

  ChallengeService? _challenges;
  OnlineGame? _openGame;
  BuildContext? _waitingContext;

  /// Clés des éléments que la visite guidée entoure, aux noms de Kivy.
  final Map<String, GlobalKey> _tourKeys = {
    for (final name in [
      'cad',
      'local',
      'online',
      'ai',
      'search',
      'fav',
      'corr',
      'compte',
      'random',
      'plus',
    ])
      name: GlobalKey(),
  };
  final ScrollController _scroll = ScrollController();
  late final List<MenuTourStop> _tour = loadMenuTour();

  /// Étape de la visite guidée en cours, ou `null` hors visite.
  int? _tourIndex;

  List<CorrGame> _corrGames = const [];
  int _unreadMessages = 0;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    unawaited(_connectWhenReady());
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstLaunch());
  }

  /// Tout premier lancement : la langue, puis le tuto — comme au démarrage de
  /// Kivy. Chacun ne se montre qu'une fois.
  Future<void> _firstLaunch() async {
    final settings = Settings.instance;
    if (!settings.languageChosen) {
      await askFirstLanguage(context);
      if (!mounted) return;
      // La langue change tous les textes : on redessine le menu.
      setState(() {});
    }
    if (settings.tutorialSeen || !mounted) return;
    await settings.markTutorialSeen();
    if (mounted) await _openTuto();
  }

  /// La reconnexion automatique tourne pendant que le menu s'affiche : on
  /// attend son issue avant de demander les parties par correspondance, sinon
  /// elles n'arrivent qu'au premier « Actualiser ».
  Future<void> _connectWhenReady() async {
    if (!_online.isLoggedIn) await _online.autoLogin;
    if (!mounted) return;
    await _connect();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchField.dispose();
    _unbind();
    super.dispose();
  }

  /// Se brancher au serveur dès l'arrivée au menu, comme en Kivy : sans cela
  /// on ne pourrait pas RECEVOIR un défi sans avoir rien fait.
  Future<void> _connect() async {
    if (!_online.isLoggedIn) return;
    await _online.connectSocket();
    if (!mounted) return;
    _bind();
    await _refreshAll();
  }

  void _bind() {
    final socket = _online.socket;
    if (socket == null) return;

    final challenges = ChallengeService(socket);
    _challenges = challenges;
    challenges.bind(
      onReceived: _onChallengeReceived,
      onFailed: (reason) {
        _closeWaiting();
        _say(switch (reason) {
          ChallengeFailure.self => T(
            'Vous ne pouvez pas vous défier vous-même.',
          ),
          ChallengeFailure.blocked => T(
            'Défi impossible : un blocage est en place entre vous.',
          ),
          ChallengeFailure.unavailable => T(
            "Désolé, cet adversaire n'est pas disponible.",
          ),
        });
      },
      onRefused: (opponent) {
        _closeWaiting();
        _say(T('%s a refusé votre défi.').replaceAll('%s', opponent));
      },
    );

    socket
      ..on(FugaEvents.partieTrouvee, _onGameFound)
      ..on(FugaEvents.rechercheTimeout, (_) {
        // Le serveur ne retire pas de la file : il suggère une autre cadence.
        _say(T('Essayez une autre cadence'));
      })
      ..on(FugaEvents.messageRecu, (_) => _refreshUnread());
  }

  void _unbind() {
    _challenges?.unbind();
    _online.socket
      ?..off(FugaEvents.partieTrouvee)
      ..off(FugaEvents.rechercheTimeout)
      ..off(FugaEvents.messageRecu);
  }

  Future<void> _refreshAll() async {
    await Future.wait([_refreshCorr(), _refreshUnread()]);
  }

  Future<void> _refreshCorr() async {
    if (!_online.isLoggedIn) {
      setState(() => _corrGames = const []);
      return;
    }
    final games = await _corr.list();
    if (!mounted || games == null) return;
    // Les parties où c'est à moi de jouer passent devant.
    final sorted = [...games]
      ..sort((a, b) => (a.myTurn ? 0 : 1).compareTo(b.myTurn ? 0 : 1));
    setState(() => _corrGames = sorted);
  }

  Future<void> _refreshUnread() async {
    if (!_online.isLoggedIn) return;
    final r = await _online.client.listConversations();
    if (!mounted || !r.isOk) return;
    setState(
      () => _unreadMessages = switch (r.get<Object>('total_unread')) {
        final int n => n,
        final num n => n.toInt(),
        _ => 0,
      },
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Exige un compte, comme Kivy qui bascule alors sur l'écran de connexion.
  Future<bool> _requireLogin() async {
    if (_online.isLoggedIn) return true;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginScreen(online: _online)),
    );
    if (ok != true || !mounted) return false;
    await _connect();
    return true;
  }

  // ── Lancer une partie ─────────────────────────────────────────────────────

  /// Code Random Fuga du moment, tiré à chaque partie quand l'interrupteur
  /// est allumé.
  String? get _randomCode => _random ? randomFugaCode() : null;

  Board? _boardFor(String? code) =>
      code == null ? null : buildRandomFugaBoard(code);

  Future<void> _startLocal() async {
    final code = _randomCode;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: _cadence,
          aiCamp: null, // deux joueurs sur le même appareil
          themeName: _axes.general,
          initialBoard: _boardFor(code),
          randomCode: code,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Choix de la couleur, puis partie contre Deep Grey — toujours sans chrono.
  Future<void> _startVsAi() async {
    final camp = await showDialog<Camp>(
      context: context,
      builder: (context) {
        final palette = paletteOf(_axes.general);
        return AlertDialog(
          backgroundColor: paletteOf(_axes.menu).menu,
          title: Text(
            T('Choisissez votre couleur'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FugaButton(
                text: T('Jouer avec les Blancs'),
                color: palette.clair,
                onPressed: () => Navigator.of(context).pop(Camp.blanc),
              ),
              SizedBox(height: S(10)),
              FugaButton(
                text: T('Jouer avec les Noirs'),
                color: palette.fonce,
                onPressed: () => Navigator.of(context).pop(Camp.noir),
              ),
              SizedBox(height: S(10)),
              FugaButton(
                text: T('Aléatoire'),
                onPressed: () => Navigator.of(context).pop(
                  DateTime.now().microsecond.isEven ? Camp.blanc : Camp.noir,
                ),
              ),
            ],
          ),
        );
      },
    );
    if (camp == null || !mounted) return;

    final code = _randomCode;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          // Contre Deep Grey, on s'entraîne : pas de pendule.
          cadence: Cadence.zen,
          aiCamp: camp.opposite,
          themeName: _axes.general,
          initialBoard: _boardFor(code),
          randomCode: code,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ── Jouer en ligne ────────────────────────────────────────────────────────

  Future<void> _playOnline() async {
    if (!await _requireLogin()) return;
    final socket = _online.socket;
    if (socket == null) {
      _say(T('Hors ligne'));
      return;
    }

    if (!mounted) return;
    socket.chercherPartie(
      objectif: 'partie',
      cadence: _cadence.wire,
      random: _random,
    );
    setState(() => _searching = true);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _waitingContext = dialogContext;
        return AlertDialog(
          content: Text(
            "${T("Recherche d'un adversaire…")}\n\n"
            '${T('Cadence')} : ${_cadence.label}',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () {
                socket.annulerRecherche();
                _waitingContext = null;
                Navigator.of(dialogContext).pop();
              },
              child: Text(T('Annuler')),
            ),
          ],
        );
      },
    );
    _waitingContext = null;
    if (mounted) setState(() => _searching = false);
  }

  void _closeWaiting() {
    final dialog = _waitingContext;
    _waitingContext = null;
    if (dialog == null || !dialog.mounted) return;
    Navigator.of(dialog).pop();
  }

  Future<void> _onGameFound(Map<String, dynamic> data) async {
    final socket = _online.socket;
    if (socket == null || !mounted) return;
    _closeWaiting();

    final info = OnlineGameInfo.fromEvent(data);

    // Partie SUIVANTE d'un match : l'écran est déjà ouvert, il enchaîne.
    final open = _openGame;
    if (open != null) {
      open.startNextGame(info);
      return;
    }

    final game = OnlineGame(
      socket: socket,
      info: info,
      cadence: Cadence.fromWire(info.cadence),
    );
    _openGame = game;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OnlineGameScreen(game: game, myPseudo: _online.pseudo ?? T('Moi')),
      ),
    );
    _openGame = null;
    // L'écran de partie avait repris les événements : on récupère les nôtres.
    if (mounted) {
      _bind();
      await _refreshAll();
    }
  }

  // ── Défis ─────────────────────────────────────────────────────────────────

  Future<void> _searchPlayer() async {
    if (!await _requireLogin()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final pseudo = _searchField.text.trim();
    if (pseudo.isEmpty) return;

    final r = await _online.client.searchUser(pseudo);
    if (!mounted) return;
    if (!r.isOk) {
      _say(T('Joueur introuvable'));
      return;
    }

    final target = await showPlayerCard(
      context,
      online: _online,
      player: Profile.fromJson(r.data!),
      palette: paletteOf(_axes.general),
    );
    if (target != null) await _challenge(target);
  }

  Future<void> _challenge(String pseudo) async {
    final challenges = _challenges;
    if (challenges == null) {
      _say(T('Hors ligne'));
      return;
    }

    challenges.challenge(
      pseudo,
      objectif: 'partie',
      cadence: _cadence.wire,
      random: _random,
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _waitingContext = dialogContext;
        return AlertDialog(
          title: Text(T('Défier')),
          content: Text(
            '${T("Défi envoyé à %s…").replaceAll('%s', pseudo)}\n\n'
            '${T("En attente de sa réponse.")}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                challenges.cancel();
                _waitingContext = null;
                Navigator.of(dialogContext).pop();
              },
              child: Text(T('Annuler')),
            ),
          ],
        );
      },
    );
    _waitingContext = null;
  }

  Future<void> _onChallengeReceived(IncomingChallenge defi) async {
    final challenges = _challenges;
    if (challenges == null || !mounted) return;

    final cadence = Cadence.fromWire(defi.cadence).label;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(T('Défi')),
        content: Text(
          '${defi.from} (${T('Mélo : %d').replaceAll('%d', '${defi.melo}')})\n'
          '${T('vous défie !')}\n\n'
          '${T('Cadence')} : $cadence'
          '${defi.random ? '\nRandom Fuga' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Refuser')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Accepter')),
          ),
        ],
      ),
    );
    challenges.respond(defi, accept: accepted ?? false);
  }

  Future<void> _openFavorites() async {
    if (!await _requireLogin()) return;
    final r = await _online.client.listFavorites();
    if (!mounted) return;
    final favorites = [
      for (final f in r.get<List<dynamic>>('favorites') ?? const [])
        if (f is Map) Person.fromJson(Map<String, dynamic>.from(f)),
    ];

    final choice = await _pickFavorite(favorites, T('Mes favoris'));
    if (choice == null || !mounted) return;
    if (await _handleFavoriteProfile(choice)) return;
    await _challenge(choice.pseudo);
  }

  /// Volet de choix d'un favori : le nom mène à son profil, « Défier » le
  /// défie. Deux gestes distincts, comme on s'y attend d'une liste de gens.
  Future<FavoriteChoice?> _pickFavorite(
    List<Person> favorites,
    String title,
  ) => showDialog<FavoriteChoice>(
    context: context,
    builder: (context) {
      final palette = paletteOf(_axes.general);
      return AlertDialog(
        title: Text(title),
        contentPadding: EdgeInsets.fromLTRB(S(12), S(12), S(12), 0),
        content: favorites.isEmpty
            ? Text(T('Aucun favori.\nAjoutez des favoris via la recherche.'))
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in favorites)
                      Padding(
                        padding: EdgeInsets.only(bottom: S(6)),
                        child: Row(
                          children: [
                            Icon(
                              f.online ? Icons.circle : Icons.circle_outlined,
                              size: S(12),
                              color: f.online ? Colors.green : Colors.grey,
                            ),
                            SizedBox(width: S(8)),
                            // Le nom est un bouton : il mène au profil.
                            Expanded(
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: S(6),
                                  ),
                                ),
                                onPressed: () => Navigator.of(
                                  context,
                                ).pop((pseudo: f.pseudo, challenge: false)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      f.pseudo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: SF(15),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      T(
                                        'Mélo : %d',
                                      ).replaceAll('%d', '${f.melo}'),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: SF(12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: S(8)),
                            SizedBox(
                              width: S(110),
                              child: FugaButton(
                                text: T('Défier'),
                                color: palette.fonce,
                                fontSize: SF(15),
                                height: S(52),
                                onPressed: () => Navigator.of(
                                  context,
                                ).pop((pseudo: f.pseudo, challenge: true)),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(T('Fermer')),
          ),
        ],
      );
    },
  );

  /// Suite d'un choix de favori : le profil, ou rien.
  Future<bool> _handleFavoriteProfile(FavoriteChoice choice) async {
    if (choice.challenge) return false;
    await _push(AccountScreen(online: _online, pseudo: choice.pseudo));
    return true;
  }

  // ── Correspondance ────────────────────────────────────────────────────────

  /// Case touchée : vide on défie un favori, en cours on ouvre la partie.
  /// Un défi ou une partie finie se règlent par leurs boutons.
  Future<void> _onCorrSlot(CorrGame? game) async {
    if (!await _requireLogin()) return;
    if (game == null) {
      await _corrChallenge();
      return;
    }
    if (game.status != CorrStatus.enCours || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CorrGameScreen(
          game: game,
          service: _corr,
          myPseudo: _online.pseudo ?? T('Moi'),
        ),
      ),
    );
    await _refreshCorr();
  }

  /// Défier un favori par correspondance : ni cadence ni objectif, une partie
  /// unique sans pendule.
  Future<void> _corrChallenge() async {
    final r = await _online.client.listFavorites();
    if (!mounted) return;
    final favorites = [
      for (final f in r.get<List<dynamic>>('favorites') ?? const [])
        if (f is Map) Person.fromJson(Map<String, dynamic>.from(f)),
    ];

    final choice = await _pickFavorite(
      favorites,
      T('Défier un favori\n(par correspondance)'),
    );
    if (choice == null || !mounted) return;
    if (await _handleFavoriteProfile(choice)) return;

    final error = await _corr.challenge(
      choice.pseudo,
      'partie',
      random: _random,
    );
    if (!mounted) return;
    if (error != null) _say(error);
    await _refreshCorr();
  }

  Future<void> _corrAnswer(CorrGame game, bool accept) async {
    await _corr.answerChallenge(game.id, accept);
    await _refreshCorr();
  }

  Future<void> _corrClose(CorrGame game) async {
    await _corr.close(game.id);
    await _refreshCorr();
  }

  Future<void> _corrRematch(CorrGame game) async {
    final error = await _corr.challenge(
      game.opponent,
      'partie',
      random: game.randomCode.isNotEmpty,
    );
    if (!mounted) return;
    if (error != null) _say(error);
    await _refreshCorr();
  }

  // ── Autres écrans ─────────────────────────────────────────────────────────

  Future<void> _push(Widget screen) async {
    // Le champ de recherche garde le focus : sans cela le clavier se
    // rouvrirait tout seul au retour sur le menu.
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {});
  }

  Future<void> _openMessages() async {
    if (!await _requireLogin()) return;
    await _push(ConversationsScreen(online: _online));
    await _refreshUnread();
  }

  Future<void> _openAccount() async {
    if (!await _requireLogin()) return;
    await _push(AccountScreen(online: _online));
  }

  /// Le bouton « Plus » de Kivy : cinq entrées, pas une de plus. Le lecteur
  /// `.nmc` est dans le menu de l'historique, et le composeur de thèmes dans
  /// les réglages — comme en Kivy.
  Future<void> _openPlus() async {
    final palette = paletteOf(_axes.general);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paletteOf(_axes.menu).menu,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, color, action)
                in <(String, Color, VoidCallback)>[
                  (T('Tuto'), palette.clair, _openTuto),
                  (
                    T('Historique'),
                    kFugaGrey,
                    () => _push(PartiesMenuScreen(online: _online)),
                  ),
                  (T('Analyse'), kFugaGrey, _openAnalysis),
                  (
                    T('Réglages'),
                    kFugaGrey,
                    () => _push(const SettingsScreen()),
                  ),
                  (T('Soutenir les devs'), palette.clair, _openSupport),
                ])
              Padding(
                padding: EdgeInsets.symmetric(vertical: S(5)),
                child: FugaButton(
                  text: label,
                  color: color,
                  fontSize: SF(17),
                  onPressed: () {
                    Navigator.of(context).pop();
                    action();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Le tuto. Sa dernière touche, « Le menu > », enchaîne sur la visite
  /// guidée du menu — comme en Kivy.
  Future<void> _openTuto() async {
    final tour = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const TutoScreen()));
    if (!mounted) return;
    setState(() {});
    if (tour == true) await startMenuTour();
  }

  /// Visite guidée : on remonte le menu, puis on déroule les étapes.
  Future<void> startMenuTour() async {
    setState(() => _tourIndex = 0);
    await _scrollToStop(0);
  }

  /// Amène à l'écran le premier élément décrit par l'étape.
  Future<void> _scrollToStop(int index) async {
    final targets = _tour[index].targets;
    if (targets.isEmpty || !_scroll.hasClients) return;
    final context = _tourKeys[targets.first]?.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      alignment: 0.35,
      duration: const Duration(milliseconds: 250),
    );
    if (mounted) setState(() {});
  }

  Future<void> _tourStep(int delta) async {
    final index = (_tourIndex ?? 0) + delta;
    // Reculer avant la première étape ramène au tuto ; avancer après la
    // dernière referme la visite.
    if (index < 0) {
      setState(() => _tourIndex = null);
      await _openTuto();
      return;
    }
    if (index >= _tour.length) {
      setState(() => _tourIndex = null);
      return;
    }
    setState(() => _tourIndex = index);
    await _scrollToStop(index);
  }

  /// Où se trouvent, à l'écran, les éléments entourés par l'étape.
  List<Rect> _tourRings(int index) {
    final rings = <Rect>[];
    for (final name in _tour[index].targets) {
      final context = _tourKeys[name]?.currentContext;
      final box = context?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      rings.add(box.localToGlobal(Offset.zero) & box.size);
    }
    return rings;
  }

  /// Analyse : on joue librement les deux camps, sans chrono, sans rien
  /// enregistrer.
  Future<void> _openAnalysis() => _push(
    GameScreen(
      cadence: Cadence.zen,
      aiCamp: null,
      themeName: _axes.general,
      analysis: true,
    ),
  );

  /// Les dons : Kivy ouvre une popup qui remercie et liste les plateformes.
  Future<void> _openSupport() async {
    final palette = paletteOf(_axes.general);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paletteOf(_axes.menu).menu,
        title: Text(T('Soutenir les devs')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              T('Merci de soutenir le développement de La Fuga !\n') +
                  T('Votre aide compte beaucoup.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: SF(14), color: Colors.white),
            ),
            SizedBox(height: S(10)),
            FugaButton(
              text: 'PayPal',
              color: palette.fonce,
              fontSize: SF(16),
              onPressed: () {
                Navigator.of(context).pop();
                _openSupportLink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSupportLink() async {
    if (kSupportLink.isEmpty) {
      _say(T('Ce lien sera bientôt disponible.'));
      return;
    }
    final launched = await launchUrl(
      Uri.parse(kSupportLink),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) _say(T('Ce lien sera bientôt disponible.'));
  }

  /// L'histoire du jeu, au toucher du logo.
  /// L'histoire de La Fuga, en plein écran — on l'ouvre en touchant le titre
  /// comme le logo.
  void _showStory() => unawaited(showStory(context));

  // ── Affichage ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(_axes.general);
    final menuPalette = paletteOf(_axes.menu);
    final background = imagesFor(_axes.menu)?.background;

    return Scaffold(
      backgroundColor: menuPalette.menu,
      body: Container(
        decoration: background == null
            ? null
            : BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(background),
                  fit: BoxFit.cover,
                ),
              ),
        child: Stack(
          children: [
            // Voile clair sur les fonds chargés, pour que les écritures du
            // menu restent lisibles — comme en Kivy sur fleur et dragon.
            if (background != null &&
                (_axes.menu == 'fleur' || _axes.menu == 'dragon'))
              Container(color: Colors.white.withValues(alpha: 0.45)),
            SafeArea(child: _content(palette)),
            _topBar(palette),
            if (_tourIndex != null)
              // Les anneaux se recalculent à chaque défilement : sans cela ils
              // restaient plantés là où la touche se trouvait au départ.
              AnimatedBuilder(
                animation: _scroll,
                builder: (context, _) => MenuTourOverlay(
                  stop: _tour[_tourIndex!],
                  index: _tourIndex!,
                  count: _tour.length,
                  rings: _tourRings(_tourIndex!),
                  onPrevious: () => _tourStep(-1),
                  onNext: () => _tourStep(1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(ThemePalette palette) {
    // Tout le menu se mesure en fractions de la HAUTEUR de l'écran chez Kivy
    // (`Window.height * f`), et les écarts entre les enfants en `S(6)`.
    const gap = 6.0; // le `spacing=S(6)` de la colonne

    return SingleChildScrollView(
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Espace sous la zone du bouton Compte.
          SizedBox(height: SH(0.06)),
          GestureDetector(
            onTap: _showStory,
            child: Image.asset(
              'assets/images/titre.webp',
              height: SH(0.16),
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(height: S(gap)),
          GestureDetector(
            onTap: _showStory,
            child: Image.asset(
              'assets/logos/logo_${_axes.logo}.webp',
              height: SH(0.13),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/logos/logo_original.webp',
                height: SH(0.13),
              ),
            ),
          ),
          SizedBox(height: SH(0.02) + S(gap)),

          SizedBox(
            height: SH(0.04),
            child: Center(
              child: Text(
                T('Cadence (min / joueur)'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: SF(17),
                  color: kMenuInk,
                ),
              ),
            ),
          ),
          SizedBox(height: S(gap)),
          SizedBox(
            height: SH(0.05),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: S(14)),
              child: Row(
                key: _tourKeys['cad'],
                children: [
                  for (final c in Cadence.toutes)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: S(3)),
                        child: FugaButton(
                          text: c.label,
                          fontSize: SF(15),
                          height: double.infinity,
                          color: _cadence == c ? palette.fonce : kFugaGrey,
                          onPressed: () => setState(() => _cadence = c),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: SH(0.02) + S(gap)),

          _wide(
            FugaButton(
              key: _tourKeys['local'],
              text: T('Jouer en local'),
              color: palette.clair,
              height: SH(0.06),
              fontSize: SF(16),
              onPressed: _startLocal,
            ),
          ),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(
            FugaButton(
              key: _tourKeys['online'],
              text: T('Jouer en ligne'),
              color: palette.fonce,
              height: SH(0.06),
              fontSize: SF(16),
              onPressed: _searching ? null : _playOnline,
            ),
          ),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(_searchRow()),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(
            FugaButton(
              text: _unreadMessages > 0
                  ? '${T('Messages')}  ($_unreadMessages)'
                  : T('Messages'),
              height: SH(0.06),
              fontSize: SF(16),
              onPressed: _openMessages,
            ),
          ),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(
            FugaButton(
              text: T('Jouer contre Deep Grey'),
              height: SH(0.06),
              fontSize: SF(16),
              onPressed: _startVsAi,
            ),
          ),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(
            FugaButton(
              key: _tourKeys['plus'],
              text: T('Plus'),
              height: SH(0.06),
              fontSize: SF(16),
              onPressed: _openPlus,
            ),
          ),
          SizedBox(height: SH(0.02) + S(gap)),

          _corrHeader(palette),
          SizedBox(height: S(gap)),
          _corrGrid(palette),
          SizedBox(height: SH(0.03)),
        ],
      ),
    );
  }

  /// Les boutons principaux font 70 % de la largeur, centrés, comme en Kivy.
  Widget _wide(Widget child) =>
      Center(child: FractionallySizedBox(widthFactor: 0.7, child: child));

  Widget _searchRow() => SizedBox(
    // Même hauteur que les touches du menu : une ligne plus fine faisait
    // désordre au milieu de la colonne.
    height: SH(0.06),
    child: Row(
      key: _tourKeys['search'],
      children: [
        Expanded(
          child: TextField(
            controller: _searchField,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: Colors.white, fontSize: SF(14)),
            decoration: InputDecoration(
              hintText: T('Rechercher un joueur…'),
              hintStyle: TextStyle(color: Colors.white70, fontSize: SF(13)),
              filled: true,
              fillColor: kFugaGrey,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: S(12),
                vertical: S(10),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(S(12)),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _searchPlayer(),
          ),
        ),
        SizedBox(width: S(6)),
        // L'étoile est carrée : sa largeur suit la hauteur de la ligne.
        AspectRatio(
          aspectRatio: 1,
          child: FugaButton(
            key: _tourKeys['fav'],
            text: '★',
            fontSize: SF(18),
            height: double.infinity,
            radius: S(12),
            textColor: const Color(0xFFFFD94D),
            onPressed: _openFavorites,
          ),
        ),
      ],
    ),
  );

  Widget _corrHeader(ThemePalette palette) => SizedBox(
    height: SH(0.04),
    child: Row(
      key: _tourKeys['corr'],
      children: [
        Expanded(
          child: Text(
            T('Parties par correspondance'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: SF(15),
              color: kMenuInk,
            ),
          ),
        ),
        SizedBox(width: S(8)),
        SizedBox(
          width: S(100),
          child: FugaButton(
            text: T('Actualiser'),
            color: palette.fonce,
            fontSize: SF(14),
            height: double.infinity,
            radius: S(12),
            onPressed: _refreshCorr,
          ),
        ),
      ],
    ),
  );

  /// Deux colonnes de plateaux : assez pour les parties en cours, plus deux
  /// cases vides pour en lancer, et dix au maximum.
  Widget _corrGrid(ThemePalette palette) {
    final rows = (_corrGames.length + 2 + 1) ~/ 2;
    final count = (rows.clamp(1, 5)) * 2;

    // Kivy donne à la grille 92 % de la LARGEUR de l'écran, deux colonnes,
    // et à chaque case la forme du plateau (7 colonnes pour 8 rangées).
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width * 0.04,
      ),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: S(10),
        crossAxisSpacing: S(10),
        childAspectRatio: 7 / 8,
      ),
      itemCount: count,
      itemBuilder: (context, i) {
        final game = i < _corrGames.length ? _corrGames[i] : null;
        return CorrSlot(
          game: game,
          palette: palette,
          boardTheme: _axes.board,
          onTap: () => _onCorrSlot(game),
          onAccept: (g) => _corrAnswer(g, true),
          onRefuse: (g) => _corrAnswer(g, false),
          onCancel: (g) => _corrAnswer(g, false),
          onRematch: _corrRematch,
          onClose: _corrClose,
        );
      },
    );
  }

  /// Ce qui ne défile pas : Random et le pseudo à gauche, Compte à droite.
  ///
  /// Aligné en haut et de hauteur fixe : sinon la barre couvrirait tout
  /// l'écran et avalerait les touchers destinés aux boutons du menu.
  Widget _topBar(ThemePalette palette) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        // Kivy cale ces trois éléments à 3 % du bord et leur donne 20 % de la
        // largeur sur 5 % de la hauteur.
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width * 0.03,
          vertical: SH(0.008),
        ),
        child: SizedBox(
          height: SH(0.05),
          child: Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.2,
                child: FugaButton(
                  key: _tourKeys['random'],
                  text: 'Random',
                  fontSize: SF(14),
                  height: double.infinity,
                  color: _random ? palette.clair : kFugaGrey,
                  textColor: _random ? Colors.black87 : Colors.white,
                  onPressed: () => setState(() => _random = !_random),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.2,
                child: FugaButton(
                  key: _tourKeys['compte'],
                  // Le mélo est DANS le bouton, comme en Kivy :
                  // `account_btn.text = "%s (%d)"`.
                  text: _online.isLoggedIn ? _accountLabel() : T('Compte'),
                  fontSize: SF(14),
                  height: double.infinity,
                  onPressed: _openAccount,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// Ce qu'écrit le bouton Compte une fois connecté : le pseudo et le mélo.
  ///
  /// Le mélo suit le mode — Random Fuga a son propre classement.
  String _accountLabel() {
    final session = _online.session;
    final pseudo = _online.pseudo ?? '?';
    if (session == null) return pseudo;
    return '$pseudo (${_random ? session.meloRandom : session.melo})';
  }
}
