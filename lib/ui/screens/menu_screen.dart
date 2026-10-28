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
import '../../engine/fug.dart';
import '../../engine/piece.dart';
import '../../engine/random_fuga.dart';
import '../../game/challenges.dart';
import '../../game/defi_relais.dart';
import '../../game/clock.dart';
import '../../game/correspondence.dart';
import '../../game/online_game.dart';
import '../../i18n/translations.dart';
import '../../net/corr_hub.dart';
import '../../net/filet_relecture.dart';
import '../../net/online_service.dart';
import '../../net/profile.dart';
import '../../net/socket_client.dart';
import '../../state/settings.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../suit_les_reglages.dart';
import '../widgets/corr_slot.dart';
import '../widgets/first_launch.dart';
import '../widgets/fuga_button.dart';
import '../widgets/picto_touche.dart';
import '../widgets/corr_mode_dialog.dart';
import '../widgets/profile_photo.dart';
import '../widgets/unread_dot.dart';
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
import 'challenge_screen.dart';
import 'position_composer_screen.dart';
import 'settings_screen.dart';
import 'tuto_screen.dart';

/// Encre des titres du menu : le `(0.15, 0.15, 0.15)` de Kivy, presque noir.
/// Une couleur de thème les rendrait bleus sur certains fonds.
const Color kMenuInk = Color.fromRGBO(38, 38, 38, 1);

/// Ce qu'on a choisi dans la liste des favoris : qui, et pour quoi faire.
/// Ce qu'on veut faire d'un favori qu'on vient de toucher.
enum FavoriteAction {
  /// Son profil — c'est la touche qui porte son nom.
  profil,

  /// Le défier.
  defier,

  /// Lui écrire.
  chat,
}

typedef FavoriteChoice = ({String pseudo, FavoriteAction action});

/// Côté des touches « Défier » et « Chat » dans la liste des favoris.
///
/// CARRÉES. Nino : « élargis les touches chat et défier pour qu'ils soient
/// carrés pas rectangles. » Leur largeur était un nombre à part, mesuré sur
/// un écran de 393 points ; elle suit maintenant leur hauteur, qui est celle
/// de toute touche de l'appli — elles restent carrées sur n'importe quel
/// écran, et y gagnent dix points de large au passage.
double get kCoteActionFavori => FugaButton.comfortableHeight;

/// La barre de recherche du menu, repérée pour `menu_search_bar_test.dart` :
/// c'est sa hauteur PEINTE qui compte, pas celle de la boîte du `TextField`.
const Key kBarreRechercheKey = Key('barre_recherche');

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.online});

  /// Injectable pour les tests.
  final OnlineService? online;

  @override
  State<MenuScreen> createState() => MenuScreenState();
}

/// L'état du menu est public : la visite guidée se lance de l'extérieur
/// (fin du tuto), et les tests la déclenchent de la même façon.
class MenuScreenState extends State<MenuScreen>
    with WidgetsBindingObserver, SuitLesReglages {
  late final OnlineService _online = widget.online ?? OnlineService.instance;
  late final CorrespondenceService _corr = CorrespondenceService(
    _online.client,
  );

  final TextEditingController _searchField = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

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
  bool _searching = false;

  /// Battement de l'actualisation des parties par correspondance.
  Timer? _corrPoll;

  /// Toutes les combien on redemande la liste, tant que le menu est à
  /// l'écran ET au premier plan.
  ///
  /// Quatre secondes : un coup de l'adversaire apparaît pendant qu'on regarde
  /// la grille, sans avoir rien à faire. Le battement s'arrête dès que
  /// l'application passe en arrière-plan, et une demande ne part jamais si la
  /// précédente n'est pas revenue — sur un réseau lent, elles
  /// s'empileraient.
  static const Duration _corrInterval = Duration(seconds: 4);

  /// Une demande de liste est en cours.
  bool _corrBusy = false;

  /// Le direct : les aperçus se mettent à jour à l'instant où une partie
  /// bouge, au lieu d'attendre le prochain battement.
  StreamSubscription<CorrChange>? _ecouteCorr;

  /// Et le battement devient un filet : espacé tant que le direct répond.
  final FiletRelecture _filet = FiletRelecture();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ecouteCorr = _online.corr.changes.listen(_surChangementCorr);
    // La touche « Jouer en ligne » affiche le mélo : sans cette écoute elle
    // garderait l'ancien à l'écran après une partie classée.
    _online.revisionMelo.addListener(_surMelo);
    unawaited(_connectWhenReady());
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstLaunch());
  }

  /// Le battement ne tourne qu'au premier plan.
  ///
  /// En le quittant, on l'arrête : interroger le serveur toutes les quatre
  /// secondes pour un écran que personne ne regarde coûte de la batterie et
  /// des données. En y revenant, on remet la liste à jour tout de suite — le
  /// téléphone a pu rester des heures dans une poche.
  /// Le clavier vient-il d'être baissé ? On le sait à la marge du bas.
  ///
  /// Nino : « quand on a fait une recherche le clavier revient sans cesse à
  /// chaque retour sur le menu. Descendre le clavier doit désélectionner la
  /// barre de recherche. »
  ///
  /// Baisser le clavier avec la flèche du système ne retire PAS le focus au
  /// champ : Flutter le garde sélectionné, et tout ce qui redonne la main au
  /// menu — fermer un popup, revenir d'un écran — le fait remonter. On coupe
  /// donc le focus nous-mêmes dès que le clavier a fini de descendre.
  /// Hauteur du clavier à la dernière mesure. Sert à voir qu'il DESCEND.
  double _hauteurClavier = 0;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Ce qu'on guette, c'est une DESCENTE : le clavier était là, il n'y est
    // plus. Guetter un zéro ne suffit pas, et c'est l'erreur que j'ai livrée
    // hier : au toucher du champ, le clavier COMMENCE à monter, la marge vaut
    // encore zéro à cette mesure-là, et le focus sautait aussitôt — le clavier
    // repartait sans qu'on ait pu écrire une lettre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final avant = _hauteurClavier;
      final maintenant = MediaQuery.viewInsetsOf(context).bottom;
      _hauteurClavier = maintenant;
      if (avant > 0 && maintenant == 0 && _searchFocus.hasFocus) {
        _searchFocus.unfocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // La connexion temps réel d'abord : après des heures en veille, le
      // réseau mobile l'a souvent coupée sans que personne ne le dise, et
      // rien ne la relançait. Tout ce qui en dépend — les messages, les
      // défis, la partie en ligne — restait muet jusqu'au redémarrage de
      // l'application.
      unawaited(_online.connectSocket());
      unawaited(_refreshAll());
      _startCorrPolling();
      return;
    }
    _corrPoll?.cancel();
    _corrPoll = null;
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
    _ecouteCorr?.cancel();
    _online.revisionMelo.removeListener(_surMelo);
    _corrPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
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

    // Tant que le menu écoute, la fiche d'un joueur peut défier depuis
    // n'importe quel écran : c'est ici que le défi se mène.
    DefiRelais.pose(_challenge);

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

    // Les messages ne passent plus par ici : la boîte aux lettres les suit
    // pour toute l'appli, et la pastille s'y abonne à l'affichage.
    socket
      ..on(FugaEvents.partieTrouvee, _onGameFound)
      ..on(FugaEvents.rechercheTimeout, _onSearchTimeout);
  }

  /// Le serveur ne retire pas de la file : il suggère une autre cadence.
  void _onSearchTimeout(Map<String, dynamic> _) =>
      _say(T('Essayez une autre cadence'));

  void _unbind() {
    DefiRelais.oublie();
    _challenges?.unbind();
    _online.socket
      ?..off(FugaEvents.partieTrouvee, _onGameFound)
      ..off(FugaEvents.rechercheTimeout, _onSearchTimeout);
  }

  Future<void> _refreshAll() async {
    await Future.wait([_refreshCorr(), _refreshUnread()]);
  }

  /// Redemande la liste toutes les [_corrInterval], tant qu'on est connecté
  /// et que le menu est là. Plus de touche « Actualiser » : comme sur les
  /// sites de jeu, la liste se tient à jour toute seule.
  ///
  /// Les non-lus battent au même rythme. Ils ne le faisaient pas : la pastille
  /// rouge du bouton Messages ne changeait que sur un événement temps réel.
  /// Quand il n'arrivait pas, elle restait éteinte alors qu'un message
  /// attendait — il fallait quitter le menu et y revenir pour la voir.
  void _startCorrPolling() {
    _corrPoll?.cancel();
    if (!_online.isLoggedIn) return;
    _corrPoll = Timer.periodic(_corrInterval, (_) {
      if (!mounted || !_online.isLoggedIn) return;
      // Le direct a-t-il déjà fait le travail ? Alors on ne redemande que de
      // loin en loin, pour rattraper ce qu'il aurait manqué.
      if (!_filet.fautRelire(
        directVivant: _online.socket?.isConnected ?? false,
      )) {
        return;
      }
      _filet.note();
      unawaited(_refreshCorr());
      unawaited(_refreshUnread());
    });
  }

  void _surMelo() {
    if (mounted) setState(() {});
  }

  /// Une partie en correspondance vient de bouger : on relit tout de suite.
  ///
  /// Le serveur dit laquelle, mais la liste se redemande entière de toute
  /// façon — c'est un seul appel, et il rafraîchit aussi l'ordre des aperçus,
  /// qui dépend de à qui est le tour.
  void _surChangementCorr(CorrChange _) {
    if (!mounted || !_online.isLoggedIn) return;
    _filet.note();
    unawaited(_refreshCorr());
  }

  Future<void> _refreshCorr() async {
    // La précédente n'est pas revenue : on ne double pas la mise.
    if (_corrBusy) return;
    if (!_online.isLoggedIn) {
      _corrPoll?.cancel();
      // Remis à zéro : une reconnexion doit relancer le battement.
      _corrPoll = null;
      if (_corrGames.isNotEmpty) setState(() => _corrGames = const []);
      return;
    }
    _corrBusy = true;
    final List<CorrGame>? games;
    try {
      games = await _corr.list();
    } finally {
      _corrBusy = false;
    }
    if (!mounted || games == null) return;
    // Les parties où c'est à moi de jouer passent devant.
    final sorted = [...games]
      ..sort((a, b) => (a.myTurn ? 0 : 1).compareTo(b.myTurn ? 0 : 1));
    if (!_sameGames(sorted, _corrGames)) {
      setState(() => _corrGames = sorted);
    }
    if (_corrPoll == null) _startCorrPolling();
  }

  /// Deux listes qui se ressemblent assez pour qu'on ne redessine pas.
  ///
  /// L'actualisation tourne toute seule : redessiner la grille toutes les
  /// quatre secondes pour rien ferait sauter le défilement sous le doigt.
  bool _sameGames(List<CorrGame> a, List<CorrGame> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].movesText != b[i].movesText ||
          a[i].status != b[i].status ||
          a[i].myTurn != b[i].myTurn ||
          a[i].unreadChat != b[i].unreadChat ||
          a[i].drawToAnswer != b[i].drawToAnswer) {
        return false;
      }
    }
    return true;
  }

  Future<void> _refreshUnread() => _online.messages.refresh(_online.client);

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

  /// Volet de choix d'un favori : son nom mène à son profil, « Défier » le
  /// défie, « Chat » lui écrit. Trois gestes distincts, comme on s'y attend
  /// d'une liste de gens.
  ///
  /// Tout y a l'allure d'une touche, y compris la fiche du joueur et le
  /// « Fermer » du bas. Ce dernier était une touche plate de Material, donc
  /// VIOLETTE : rien ne lui disait quelle couleur prendre, et `ThemeData`
  /// n'ayant pas de jeu de couleurs, elle prenait la graine d'usine de
  /// Material 3. Elle ne venait d'aucun thème de La Fuga.
  Future<FavoriteChoice?> _pickFavorite(
    List<Person> favorites,
    String title,
  ) => showDialog<FavoriteChoice>(
    context: context,
    builder: (context) {
      final palette = paletteOf(_axes.general);
      void choisir(String pseudo, FavoriteAction action) =>
          Navigator.of(context).pop((pseudo: pseudo, action: action));

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
                        padding: EdgeInsets.only(bottom: S(8)),
                        child: Row(
                          children: [
                            Icon(
                              f.online ? Icons.circle : Icons.circle_outlined,
                              size: S(12),
                              color: f.online ? Colors.green : Colors.grey,
                            ),
                            SizedBox(width: S(6)),
                            // La fiche du joueur EST une touche : elle mène à
                            // son profil, et elle en a maintenant l'allure.
                            Expanded(
                              child: _ficheFavori(
                                f,
                                onPressed: () =>
                                    choisir(f.pseudo, FavoriteAction.profil),
                              ),
                            ),
                            SizedBox(width: S(6)),
                            SizedBox(
                              width: kCoteActionFavori,
                              child: FugaButton(
                                text: T('Défier'),
                                color: palette.fonce,
                                fontSize: SF(13),
                                onPressed: () =>
                                    choisir(f.pseudo, FavoriteAction.defier),
                              ),
                            ),
                            SizedBox(width: S(6)),
                            SizedBox(
                              width: kCoteActionFavori,
                              child: FugaButton(
                                text: T('Chat'),
                                color: palette.clair,
                                textColor: Colors.black,
                                fontSize: SF(13),
                                onPressed: () =>
                                    choisir(f.pseudo, FavoriteAction.chat),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          SizedBox(
            width: S(140),
            child: FugaButton(
              text: T('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
              fontSize: SF(15),
            ),
          ),
        ],
      );
    },
  );

  /// La fiche d'un favori : son nom, son Mélo, et le relief d'une touche.
  Widget _ficheFavori(Person f, {required VoidCallback onPressed}) => Material(
    color: kFugaGrey,
    borderRadius: BorderRadius.circular(S(12)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(8)),
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
              T('Mélo : %d').replaceAll('%d', '${f.melo}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white70, fontSize: SF(12)),
            ),
          ],
        ),
      ),
    ),
  );

  /// Suite d'un choix de favori : le profil, la conversation, ou rien.
  ///
  /// Rend vrai quand tout est joué — il ne reste alors plus rien à défier.
  Future<bool> _handleFavoriteProfile(FavoriteChoice choice) async {
    switch (choice.action) {
      case FavoriteAction.defier:
        return false;
      case FavoriteAction.profil:
        await _push(AccountScreen(online: _online, pseudo: choice.pseudo));
        return true;
      case FavoriteAction.chat:
        await _push(ConversationScreen(online: _online, pseudo: choice.pseudo));
        return true;
    }
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
    await _openCorrGame(game);
  }

  /// Revoir une partie de correspondance TERMINÉE — la touche « Afficher ».
  ///
  /// Le même écran que pour jouer : il est déjà en lecture seule quand la
  /// partie n'est plus en cours (`_canPlay`), et il montre ce qu'on vient
  /// chercher — la position finale, le dernier coup encadré, et l'Héritier
  /// dans son ralliement s'il a fugué. Jusqu'ici une partie finie ne se
  /// rouvrait plus : on ne pouvait que la refermer.
  Future<void> _corrShow(CorrGame game) => _openCorrGame(game);

  Future<void> _openCorrGame(CorrGame game) async {
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
    // Le profil a pu être ouvert et refermé entre-temps : sans ce contrôle, on
    // ouvrirait une popup sur un écran qui n'existe plus.
    if (!mounted) return;

    // D'où part la partie ? La correspondance ne dépend PLUS de l'état du
    // menu : on ne peut plus partir en random sans l'avoir voulu, ni avoir à
    // basculer tout le menu pour défier quelqu'un en random.
    final mode = await askCorrMode(context);
    if (mode == null || !mounted) return;

    // Le mode personnalisé passe par le composeur. Sortir sans valider annule
    // le défi : on ne lance pas une partie sur une position qu'on n'a pas
    // confirmée.
    var position = '';
    if (mode == CorrMode.personnalise) {
      final composee = await Navigator.of(context)
          .push<({Board board, Camp turn})>(
            MaterialPageRoute<({Board board, Camp turn})>(
              builder: (_) => const PositionComposerScreen(),
            ),
          );
      if (composee == null || !mounted) return;
      position = fugEnUneLigne(fugEcrire(composee.board, composee.turn));
    }

    final couleur = await askCorrCouleur(context);
    if (couleur == null || !mounted) return;

    final error = await _corr.challenge(
      choice.pseudo,
      'partie',
      mode: mode,
      position: position,
      couleur: couleur.camp,
    );
    if (!mounted) return;
    if (error != null) _say(error);
    await _refreshCorr();
  }

  /// Ouvrir un défi reçu en grand : la position proposée, le mode, la couleur
  /// et le score, puis accepter ou refuser devant le plateau.
  ///
  /// L'aperçu ne porte plus ces deux touches : on ne dit plus oui à une partie
  /// sans avoir vu d'où elle part.
  Future<void> _corrShowChallenge(CorrGame game) async {
    final reponse = await Navigator.of(context).push<ChallengeAnswer>(
      MaterialPageRoute<ChallengeAnswer>(
        builder: (_) => ChallengeScreen(game: game),
      ),
    );
    if (reponse == null || !mounted) return;
    await _corrAnswer(game, reponse == ChallengeAnswer.accepte);
  }

  Future<void> _corrAnswer(CorrGame game, bool accept) async {
    await _corr.answerChallenge(game.id, accept);
    await _refreshCorr();
  }

  /// Annuler un défi de correspondance que J'AI envoyé.
  ///
  /// La touche ne faisait rien parce qu'elle appelait `corr_repondre`, que le
  /// serveur refuse au défieur : « Vous êtes le défieur ». Kivy passe par
  /// l'abandon, qui accepte le statut « defi » et clôt la partie sans compter
  /// de point ni l'archiver.
  Future<void> _corrCancelChallenge(CorrGame game) async {
    await _corr.resign(game.id);
    await _refreshCorr();
  }

  Future<void> _corrClose(CorrGame game) async {
    await _corr.close(game.id);
    await _refreshCorr();
  }

  /// Revanche : la même chose, d'où qu'elle soit partie.
  ///
  /// Elle ne portait que le drapeau Random : une revanche sur une partie à
  /// position composée repartait de la position standard, sans rien dire.
  /// Elle emporte maintenant le mode ET la position.
  Future<void> _corrRematch(CorrGame game) async {
    final error = await _corr.challenge(
      game.opponent,
      'partie',
      mode: game.mode,
      position: game.position,
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
      // Elle seule part d'une position quelconque : c'est donc la seule qui
      // offre d'en composer une autre.
      avecComposeur: true,
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
            // Pas de SafeArea autour du menu : Kivy donne au défilement TOUTE
            // la fenêtre (`ScrollView(size_hint=(1, 1))`) et l'appli est en
            // plein écran immersif. Une marge de sécurité en haut laissait une
            // bande vide que rien ne remplissait, et empêchait le menu de
            // défiler jusqu'au bord.
            _content(palette),
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
            // `logoAssetOf` et non le chemin à la main : trois thèmes ont
            // un logo dont le fichier ne porte pas leur nom, et l'image
            // manquante retombait silencieusement sur celle d'origine. Le
            // médiéval et les fleurs n'ont jamais montré la leur.
            child: Image.asset(
              logoAssetOf(_axes.logo),
              height: SH(0.13),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Image.asset(logoAssetOf(kDefaultTheme), height: SH(0.13)),
            ),
          ),
          SizedBox(height: SH(0.02) + S(gap)),

          SizedBox(
            height: labelHeight(0.04, 17),
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
            // Épaisseur d'une touche, comme les grandes touches d'en dessous :
            // une rangée plus fine se voyait tout de suite.
            height: touchHeight(),
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
              height: touchHeight(),
              fontSize: SF(16),
              onPressed: _startLocal,
            ),
          ),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(
            FugaButton(
              key: _tourKeys['online'],
              text: _libelleEnLigne(),
              color: palette.fonce,
              height: touchHeight(),
              fontSize: SF(16),
              onPressed: _searching ? null : _playOnline,
            ),
          ),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(_searchRow()),
          SizedBox(height: SH(0.012) + S(gap)),
          // Une pastille rouge, pas un compteur : l'intitulé ne bouge plus,
          // et elle s'allume à l'instant où un message arrive.
          _wide(
            AnimatedBuilder(
              animation: _online.messages,
              builder: (context, _) => UnreadDot(
                show: _online.messages.hasUnread,
                child: FugaButton(
                  text: T('Messages'),
                  height: touchHeight(),
                  fontSize: SF(16),
                  onPressed: _openMessages,
                ),
              ),
            ),
          ),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(
            FugaButton(
              key: _tourKeys['ai'],
              text: T('Jouer contre Deep Grey'),
              height: touchHeight(),
              fontSize: SF(16),
              onPressed: _startVsAi,
            ),
          ),
          SizedBox(height: SH(0.012) + S(gap)),
          _wide(
            FugaButton(
              key: _tourKeys['plus'],
              text: T('Plus'),
              height: touchHeight(),
              fontSize: SF(16),
              onPressed: _openPlus,
            ),
          ),
          SizedBox(height: SH(0.02) + S(gap)),

          _separateur(palette),
          SizedBox(height: SH(0.02)),

          _corrHeader(),
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
    // Même épaisseur que les touches du menu — pour la bande ET pour le champ
    // lui-même : un `TextField` prend sinon la hauteur de son texte, et la
    // ligne paraissait fine à côté de l'étoile.
    height: touchHeight(),
    child: Row(
      key: _tourKeys['search'],
      children: [
        Expanded(
          // Le fond gris est une boîte que NOUS dessinons, à la hauteur d'une
          // touche. La taille n'est plus confiée à `InputDecoration` :
          // `constraints: BoxConstraints.tightFor(...)` était pourtant bien là,
          // et mes rendus donnaient 52 px logiques — mais sur le téléphone de
          // Nino la barre sortait à 19, la valeur qu'elle prend SANS contrainte,
          // pendant que l'étoile juste à côté faisait bien ses 52. N'ayant pas
          // pu reproduire l'écart, je retire le mécanisme au lieu de le deviner :
          // un `Container` d'une hauteur donnée ne peut pas être réinterprété.
          child: GestureDetector(
            // Le champ ne remplit pas la boîte en hauteur : sans ça, toucher
            // le gris au-dessus ou en dessous du texte ne ferait rien.
            behavior: HitTestBehavior.opaque,
            onTap: _searchFocus.requestFocus,
            child: Container(
              // La clé sert au test qui compte les pixels peints de la barre.
              key: kBarreRechercheKey,
              height: touchHeight(),
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.symmetric(horizontal: S(12)),
              decoration: BoxDecoration(
                color: kFugaGrey,
                borderRadius: BorderRadius.circular(S(12)),
              ),
              // En premier plan : une bordure de fond repousserait le champ
              // de son épaisseur, et la ligne de recherche n'aurait plus
              // l'épaisseur d'une touche.
              foregroundDecoration: BoxDecoration(
                border: const Border.fromBorderSide(kTraitDeTouche),
                borderRadius: BorderRadius.circular(S(12)),
              ),
              child: TextField(
                controller: _searchField,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                style: TextStyle(color: Colors.white, fontSize: SF(14)),
                // `collapsed` : plus aucune mise en page de Material autour du
                // texte, donc plus rien qui puisse imposer une autre hauteur.
                decoration: InputDecoration.collapsed(
                  hintText: T('Rechercher un joueur…'),
                  hintStyle: TextStyle(color: Colors.white70, fontSize: SF(13)),
                ),
                onSubmitted: (_) => _searchPlayer(),
              ),
            ),
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

  /// Le trait qui ferme le menu et ouvre les parties par correspondance.
  ///
  /// Nino : « mets un trait de séparation entre le bouton "plus" et "parties
  /// par correspondance", assez épais stp et qui ne va pas jusqu'aux bords de
  /// l'écran. » Il s'arrête donc au même alignement que les touches, qui ne
  /// touchent pas les bords non plus — un trait qui irait d'un bord à l'autre
  /// couperait l'écran au lieu de séparer deux parties du menu.
  ///
  /// IL S'ALLUME QUAND UNE PARTIE ATTEND. Nino : « j'aimerais que le trait
  /// épais de séparation s'éclaire d'une couleur claire du thème lorsqu'il y
  /// a une ou plusieurs parties dans lesquelles c'est à notre tour de
  /// jouer. » Le trait devient alors un voyant : il se voit sans qu'on ait à
  /// défiler jusqu'aux plateaux, et il est juste au-dessus d'eux.
  Widget _separateur(ThemePalette palette) {
    final attend = _corrGames.any((g) => g.myTurn);
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.62,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          // DIX FOIS LE TRAIT, et non quatre. À quatre, Nino ne voyait pas
          // qu'elle était allumée : « c'est juste beaucoup trop fin. » Un
          // voyant doit se voir sans qu'on le cherche. Vu à ×2,5 sur les
          // dix-sept thèmes, essayé à ×3, revenu à ×2,5 : « finalement 2,5
          // c'était pas mal. »
          height: S(kTraitPicto * 10),
          decoration: BoxDecoration(
            color: attend ? palette.clair : const Color(0xFF000000),
            // LA MOITIÉ DE SA HAUTEUR : les bouts sont donc parfaitement
            // ronds, et le restent si l'épaisseur change encore.
            borderRadius: BorderRadius.circular(S(kTraitPicto * 5)),
            // Le trait noir des touches, autour du voyant : allumé, il reste
            // cerné comme tout le reste ; éteint, il ne se voit pas, puisque
            // le trait est noir sur noir.
            border: const Border.fromBorderSide(kTraitDeTouche),
          ),
        ),
      ),
    );
  }

  /// Le titre de la section. Plus de touche « Actualiser » à côté : la liste
  /// se tient à jour toute seule, comme sur les sites de jeu.
  Widget _corrHeader() => SizedBox(
    key: _tourKeys['corr'],
    height: labelHeight(0.04, 15),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        T('Parties par correspondance'),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: SF(15),
          color: kMenuInk,
        ),
      ),
    ),
  );

  /// Deux colonnes de plateaux : les parties en cours, et de quoi en lancer.
  ///
  /// Une ligne de cases vides n'apparaît que lorsque les DEUX du dessus sont
  /// prises. Il y a donc toujours une ou deux cases vides, jamais trois : on
  /// en ajoutait systématiquement deux, ce qui laissait une ligne entière
  /// vide sous une ligne à moitié remplie.
  ///
  /// Dix au maximum, comme le serveur, qui refuse une onzième partie
  /// simultanée : à dix, plus aucune case vide, et c'est juste.
  Widget _corrGrid(ThemePalette palette) {
    final jouees = _corrGames.length;
    final count = (jouees.isEven ? jouees + 2 : jouees + 1).clamp(2, 10);

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
          pieceTheme: _axes.pieces,
          onTap: () => _onCorrSlot(game),
          onAccept: (g) => _corrAnswer(g, true),
          onRefuse: (g) => _corrAnswer(g, false),
          onCancel: _corrCancelChallenge,
          onRematch: _corrRematch,
          onClose: _corrClose,
          onShow: _corrShow,
          onShowChallenge: _corrShowChallenge,
        );
      },
    );
  }

  /// Ce qui ne défile pas : Random et le pseudo à gauche, Compte à droite.
  ///
  /// Aligné en haut et de hauteur fixe : sinon la barre couvrirait tout
  /// l'écran et avalerait les touchers destinés aux boutons du menu.
  Widget _topBar(ThemePalette palette) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      // Kivy cale ces touches à 3 % du bord en largeur et à `top: 0.985`,
      // c'est-à-dire 1,5 % du haut de la FENÊTRE — pas d'une zone sûre :
      // l'appli est en plein écran immersif, il n'y a rien au-dessus.
      padding: EdgeInsets.only(
        left: MediaQuery.sizeOf(context).width * 0.03,
        right: MediaQuery.sizeOf(context).width * 0.03,
        top: SH(0.015),
      ),
      child: SizedBox(
        height: touchHeight(),
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
  );

  /// Ce qu'écrit le bouton Compte une fois connecté : le pseudo, et lui seul.
  ///
  /// Le mélo y figurait, comme en Kivy (`account_btn.text = "%s (%d)"`). Nino
  /// l'a déplacé : « j'aimerais que le classement soit sur le bouton jouer en
  /// ligne plutôt que sur le bouton d'accès au compte. » C'est là qu'il sert
  /// — on le lit au moment de chercher un adversaire, pas en allant régler
  /// son compte.
  String _accountLabel() => _online.pseudo ?? '?';

  /// Ce qu'écrit la touche « Jouer en ligne » : son intitulé, et mon mélo.
  ///
  /// Nino : « il doit dire "???? mélo" au lieu de juste "????" ». Le nombre
  /// seul ne disait pas ce qu'il était ; sur une touche qui parle déjà d'une
  /// autre chose, il le fallait.
  ///
  /// Le mélo suit le mode — Random Fuga a son propre classement —, et le
  /// libellé entier passe par la traduction : les dix langues ne mettent pas
  /// le nombre au même endroit.
  String _libelleEnLigne() {
    final session = _online.session;
    if (!_online.isLoggedIn || session == null) return T('Jouer en ligne');
    final melo = _random ? session.meloRandom : session.melo;
    return T('Jouer en ligne (%d mélo)').replaceAll('%d', '$melo');
  }
}
