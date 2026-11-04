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
import '../widgets/classement_volet.dart';
import '../widgets/corr_slot.dart';
import '../widgets/first_launch.dart';
import '../widgets/fuga_button.dart';
import '../widgets/picto_touche.dart';
import '../widgets/touche_chat.dart';
import '../widgets/corr_mode_dialog.dart';
import '../widgets/profile_photo.dart';
import '../widgets/unread_dot.dart';
import '../widgets/volet_menu.dart';
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

/// Marge, au bord de l'écran, de la bande où vivent les rangées de touches.
///
/// Les cadences la tenaient par deux marges emboîtées — S(14) sur la rangée,
/// S(3) autour de chaque touche ; c'est leur somme, et elle a maintenant un
/// nom, parce que la rangée des deux façons de jouer doit tomber EXACTEMENT
/// au même alignement.
const double kMargeDeLaBande = 17.0;

/// Écart entre deux touches voisines d'une rangée de trois.
const double kEcartDeLaBande = 6.0;

/// Combien d'interlignes le premier écran du menu contient.
///
/// Trois entre ses quatre rangées, un entre les deux rangées de grosses
/// touches, un sous la grille, un sous la barre de séparation.
const int kInterlignesDuMenu = 6;

/// Hauteur d'une des quatre grosses touches : DEUX touches ordinaires.
///
/// Nino : « c'est vraiment trop chargé pour les yeux. Réduis la taille des
/// 4 gros boutons. » Elle a été calculée un temps pour que la barre de
/// séparation ne bouge pas d'un pixel — une soustraction à trois étages dont
/// le résultat, 2,35 fois une touche, ne voulait rien dire. Elle vaut
/// maintenant deux fois une touche ordinaire, puisqu'elle porte deux choses
/// — un dessin et un mot — là où une touche ordinaire n'en porte qu'une.
double hauteurDesGrossesTouches() => touchHeight() * 2;

/// Ce que le premier écran du menu occupe SANS ses interlignes.
///
/// Tout y est connu d'avance : deux images à hauteur donnée, un intitulé,
/// trois rangées de touches, deux rangées de grosses touches et la barre.
/// On fait donc la somme à la main. `IntrinsicHeight` l'aurait faite pour
/// nous, mais il interroge les dimensions intrinsèques de ses enfants, et
/// les `LayoutBuilder` des grosses touches ne savent pas y répondre.
///
/// Cette somme doit suivre la colonne de `_content` : tout écart se voit
/// dans `menu_refonte_test`, qui mesure le bas de la barre de séparation.
double contenuFixeDuMenu() =>
    SH(0.06) + // sous le bandeau du haut
    SH(0.16) + // le titre
    S(kEcartDeLaBande) +
    SH(0.13) + // le logo
    SH(0.02) +
    S(kEcartDeLaBande) +
    labelHeight(0.04, 17) + // « Cadence (min / joueur) »
    S(kEcartDeLaBande) +
    3 * touchHeight() + // cadences, façons de jouer, recherche
    2 * hauteurDesGrossesTouches() + // les quatre grosses, en deux rangées
    S(kEpaisseurDuVoyant); // la barre de séparation

/// L'INTERLIGNE DU MENU : le même entre toutes ses touches, et c'est LUI qui
/// remplit l'écran.
///
/// Nino : « j'aimerais que l'intervalle entre les touches du menu soit
/// toujours le même histoire d'être logique », puis « t'as qu'à augmenter la
/// taille de tous les interstices (ce qui veut dire réduire la largeur de
/// certaines touches) pour que ça prenne toute la hauteur de l'écran ».
///
/// Ce n'est donc plus un nombre mais une CONSÉQUENCE : ce qui reste de
/// l'écran une fois les touches posées, partagé entre les six interlignes.
/// L'air qui s'entassait sous le logo se répand partout, horizontalement
/// aussi — les touches d'une même rangée s'écartent d'autant, donc
/// rétrécissent d'autant.
///
/// Son PLANCHER est l'ancien interligne hérité de Kivy : sur un écran trop
/// court le menu déborderait, et il vaut mieux qu'il défile que de voir les
/// touches se toucher.
double intervalleDuMenu() {
  final plancher = SH(0.012) + S(kEcartDeLaBande);
  final reste = (screenHeight - contenuFixeDuMenu()) / kInterlignesDuMenu;
  return reste > plancher ? reste : plancher;
}

/// Ce que chaque dessin laisse de vide SOUS lui, dans son carré de 192.
///
/// Un pictogramme est cadré sur son sujet, mais tous les sujets n'ont pas la
/// même forme : le podium, large et plat, laisse 43 points sous lui, le chat
/// 17, la silhouette et le « + » 10. Centrés dans leur touche, les quatre
/// flottent donc à des hauteurs différentes, et les deux plus plats
/// paraissent perchés. Nino : « descends un peu les symboles de
/// conversations et classement à l'intérieur de la touche. »
///
/// On les repose tous sur LE MÊME SOL, celui des deux qui descendent le plus
/// bas. Ces nombres sont une mesure, pas un réglage : `pictos_menu_test`
/// les relit dans les fichiers et refuse de laisser la table mentir.
const Map<String, double> kVideSousLeDessin = {
  'assets/images/chat.webp': 17,
  'assets/images/podium.webp': 43,
  'assets/images/deepgrey_silhouette.webp': 10,
  'assets/images/plus.webp': 10,
};

/// Le côté du carré dans lequel vit un dessin de touche.
const double kCarreDuDessin = 192;

/// Part de sa place qu'occupe le symbole d'une des quatre grosses touches.
///
/// Nino : « multiplie les symboles des 4 grosses touches par 0,75, là c'est
/// trop gros. » Ils remplissaient d'un bord à l'autre tout ce que le mot
/// leur laissait, et la touche n'était plus qu'un dessin.
const double kPartDuSymboleDesGrosses = 0.75;

/// « Deep Grey » est un NOM : une touche ne le coupe pas en deux lignes.
///
/// L'espace insécable ne change ni ce qui est lu, ni ce qui est traduit — la
/// clé reste « Affronter Deep Grey » — mais il décide OÙ la ligne se coupe :
/// « Affronter » puis « Deep Grey », et non « Affronter Deep » puis
/// « Grey ». Les dix langues portent ce nom tel quel, un seul remplacement
/// les sert donc toutes.
///
/// Les essais qui cherchent ce texte à l'écran passent par cette fonction :
/// c'est la forme AFFICHÉE, et `find.text` compare au caractère près.
String nomInsecable(String texte) =>
    texte.replaceAll('Deep Grey', 'Deep\u00A0Grey');

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
  /// AUCUNE au départ. Nino : « quand on arrive sur le menu, aucun des
  /// trois ne doit être sélectionné. » Une cadence cochée d'office se joue
  /// sans qu'on l'ait voulue ; nulle, elle oblige à choisir pour jouer en
  /// ligne, et laisse la partie locale se jouer sans chrono.
  Cadence? _cadence;

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
      // Les deux grosses touches nées de la refonte : la visite les montre
      // comme les autres, et le test des anneaux refuse une cible sans clé.
      'conv',
      'classement',
    ])
      name: GlobalKey(),
  };

  /// LE VOLET POSÉ SUR LE MENU, et non par-dessus toute l'application.
  ///
  /// Nino : « lorsqu'il apparaît les boutons "standard/random" et "nino"
  /// doivent rester accessibles. [...] Ce serait bien que le popup favoris
  /// en question ainsi que les autres popups qui s'affichent directement sur
  /// le menu laissent également accessibles les boutons "nino" et
  /// "standard/random". »
  ///
  /// `showDialog` ouvre une ROUTE par-dessus l'écran : plus rien de ce qui
  /// est dessous ne reçoit un doigt. Le volet vit donc dans la pile du menu
  /// lui-même, et le bandeau du haut se dessine APRÈS lui — ce qui suffit à
  /// lui rendre ses deux touches, celle qui est dessinée en dernier recevant
  /// le doigt la première.
  Widget Function(BuildContext)? _volet;

  /// Ce que le volet rendra en se refermant, pour qui l'attend.
  Completer<Object?>? _reponseDuVolet;

  /// La barre de séparation, pour savoir où elle est quand on la touche.
  final GlobalKey _cleDuTrait = GlobalKey();

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
    // Qui attendait la réponse du volet l'attendrait pour toujours.
    final attente = _reponseDuVolet;
    _reponseDuVolet = null;
    if (attente != null && !attente.isCompleted) attente.complete(null);
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
          // SANS CADENCE, SANS CHRONO. Nino : « si on clique sur jouer en
          // local, ça lance une partie en local sans limite chrono. »
          cadence: _cadence ?? Cadence.zen,
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

  /// La cadence choisie, ou rien — et alors on le dit plutôt que de partir.
  ///
  /// Nino : « si on clique sur jouer en ligne, popup message "sélectionner
  /// une cadence pour jouer en ligne". »
  ///
  /// SEULE CETTE TOUCHE-LÀ EXIGE UN CHOIX. Un défi part aussi d'ailleurs —
  /// d'une conversation, d'une partie de correspondance, de l'historique —
  /// par un relais qui passe par ici : lui barrer la route aurait fait
  /// répondre le menu, qu'on ne voit même pas depuis ces écrans. Il garde
  /// donc la cadence d'avant, quinze minutes, quand rien n'est choisi.
  Cadence? _cadenceExigee() {
    final cadence = _cadence;
    if (cadence == null) {
      _say(T('Sélectionnez une cadence pour jouer en ligne.'));
    }
    return cadence;
  }

  Future<void> _playOnline() async {
    // LE COMPTE D'ABORD, LA CADENCE ENSUITE : sans compte, réclamer une
    // cadence ne servirait à rien — il faudrait la choisir, puis se
    // connecter. Le plus bloquant des deux passe devant.
    if (!await _requireLogin()) return;
    final cadence = _cadenceExigee();
    if (cadence == null) return;
    final socket = _online.socket;
    if (socket == null) {
      _say(T('Hors ligne'));
      return;
    }

    if (!mounted) return;
    socket.chercherPartie(
      objectif: 'partie',
      cadence: cadence.wire,
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
            '${T('Cadence')} : ${cadence.label}',
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
    final cadence = _cadence ?? Cadence.parDefaut;
    final challenges = _challenges;
    if (challenges == null) {
      _say(T('Hors ligne'));
      return;
    }

    challenges.challenge(
      pseudo,
      objectif: 'partie',
      cadence: cadence.wire,
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
  Future<FavoriteChoice?> _pickFavorite(List<Person> favorites, String title) =>
      _ouvreVolet<FavoriteChoice>((context) {
        final palette = paletteOf(_axes.general);
        void choisir(String pseudo, FavoriteAction action) =>
            _fermeVolet((pseudo: pseudo, action: action));

        return PanneauDuVolet(
          titre: title,
          onFermer: _fermeVolet,
          enfant: favorites.isEmpty
              ? MotTouche(
                  texte: T(
                    'Aucun favori.\nAjoutez des favoris via la recherche.',
                  ),
                  couleur: Colors.white,
                  maxLines: 2,
                  style: TextStyle(fontSize: SF(14)),
                )
              : ListView(
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
                            // LA TOUCHE CHAT DES PARTIES, à l'identique.
                            // Nino : « il faudrait aussi que le bouton chat
                            // soit le symbole qu'on utilise ingame », puis,
                            // devant une touche seulement ressemblante : « la
                            // touche chat doit être exactement la même que
                            // ingame, ni plus ni moins ». C'est donc le même
                            // widget, [ToucheChat] — même gris, même rond,
                            // même dessin, même infobulle.
                            SizedBox.square(
                              dimension: kCoteActionFavori,
                              child: ToucheChat(
                                palette: palette,
                                onPressed: () =>
                                    choisir(f.pseudo, FavoriteAction.chat),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      });

  /// La fiche d'un favori : son nom, son Mélo, et le relief d'une touche.
  ///
  /// EXACTEMENT LA HAUTEUR DE « DÉFIER » ET DE « CHAT », ses voisines. Nino :
  /// « il faudrait que les boutons de profil fassent la même hauteur que les
  /// boutons défier et chat. » Elle dépassait d'un cheveu, ses deux lignes
  /// décidant seules de sa taille, et la rangée n'était alignée nulle part.
  Widget _ficheFavori(Person f, {required VoidCallback onPressed}) => SizedBox(
    height: kCoteActionFavori,
    child: Material(
      color: kGrisTouche,
      // Elle se touche pour défier : elle porte donc le trait noir comme les
      // autres touches, et comme les cartes de l'historique.
      shape: formeDeTouche(BorderRadius.circular(S(12))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(4)),
          // Les deux lignes se serrent plutôt que de déborder : une hauteur
          // imposée ne pardonne pas, et un gros réglage de police peut
          // toujours les faire grandir.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
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

  /// Pose un volet sur le menu, et rend ce qu'il répondra en se refermant.
  ///
  /// Un seul à la fois : en ouvrir un second referme le premier, comme une
  /// route en remplacerait une autre.
  Future<T?> _ouvreVolet<T extends Object>(
    Widget Function(BuildContext context) corps,
  ) {
    _fermeVolet();
    final attente = Completer<Object?>();
    setState(() {
      _volet = corps;
      _reponseDuVolet = attente;
    });
    return attente.future.then((v) => v is T ? v : null);
  }

  /// Referme le volet. Sans réponse, c'est un refus — comme un popup qu'on
  /// quitte par le voile ou par la touche « Fermer ».
  void _fermeVolet([Object? reponse]) {
    final attente = _reponseDuVolet;
    if (attente == null) return;
    _reponseDuVolet = null;
    _volet = null;
    if (mounted) setState(() {});
    if (!attente.isCompleted) attente.complete(reponse);
  }

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

  /// Les trente meilleurs mélos, dans un volet qui défile.
  ///
  /// Le volet suit le MODE de l'application : la touche « standard / random »
  /// du bandeau reste sous le doigt pendant qu'il est ouvert, elle ne le
  /// referme pas, et le classement change avec elle. Cela marche tout seul —
  /// le volet se reconstruit à chaque `setState` du menu, et il lit `_random`
  /// à ce moment-là.
  Future<void> _openClassement() async {
    if (!await _requireLogin()) return;
    final pseudo = await _ouvreVolet<String>(
      (context) => PanneauDuVolet(
        titre: _titreDuClassement(),
        onFermer: _fermeVolet,
        enfant: ClassementVolet(
          random: _random,
          online: _online,
          palette: paletteOf(_axes.general),
          surJoueur: _fermeVolet,
        ),
      ),
    );
    if (pseudo == null || !mounted) return;
    await _push(AccountScreen(online: _online, pseudo: pseudo));
  }

  Future<void> _openAccount() async {
    if (!await _requireLogin()) return;
    await _push(AccountScreen(online: _online));
  }

  /// Le bouton « Plus » de Kivy : cinq entrées, pas une de plus. Le lecteur
  /// `.nmc` est dans le menu de l'historique, et le composeur de thèmes dans
  /// les réglages — comme en Kivy.
  Future<void> _openPlus() async {
    await _ouvreVolet<Object>((context) {
      final palette = paletteOf(_axes.general);
      return PanneauDuVolet(
        titre: T('Autres'),
        onFermer: _fermeVolet,
        enfant: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, color, action)
                in <(String, Color, VoidCallback)>[
                  (T('Tuto'), palette.clair, _openTuto),
                  (
                    T('Historique'),
                    kGrisTouche,
                    () => _push(PartiesMenuScreen(online: _online)),
                  ),
                  (T('Analyse'), kGrisTouche, _openAnalysis),
                  (
                    T('Réglages'),
                    kGrisTouche,
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
                    _fermeVolet();
                    action();
                  },
                ),
              ),
          ],
        ),
      );
    });
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

    return PopScope(
      // Un volet se referme par le retour arrière, comme un popup.
      canPop: _volet == null,
      onPopInvokedWithResult: (sorti, _) {
        if (!sorti) _fermeVolet();
      },
      child: Scaffold(
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
              if (_volet != null) ...[
                // LE VOILE. Il assombrit le menu et le referme d'un doigt posé
                // à côté — mais il ne couvre PAS le bandeau du haut, qui se
                // dessine après lui et reçoit donc les doigts le premier.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _fermeVolet,
                    child: const ColoredBox(color: Colors.black54),
                  ),
                ),
                // Le volet lui-même. `Center` ne prend que la place de son
                // enfant pour les doigts : à côté du panneau, c'est le voile
                // qui répond, comme sous un vrai popup.
                Positioned.fill(
                  child: SafeArea(
                    child: Center(child: Builder(builder: _volet!)),
                  ),
                ),
              ],
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
          // LE MENU TIENT EN UN ÉCRAN, PILE, et la barre de séparation en
          // ferme le bas. Nino : « la barre de séparation doit arriver tout
          // en bas de l'écran (les touches plus la barre de séparation
          // doivent prendre tout l'écran, et on défile pour voir la partie
          // du menu avec la correspondance). »
          //
          // La hauteur est donc IMPOSÉE, et l'air en trop se partage entre
          // les TROIS vides du haut, chacun grandissant de ce qu'il pèse
          // déjà. Tout donner au seul vide sous le logo faisait un trou —
          // Nino : « c'est quoi cet énorme espace entre le logo et la
          // cadence ? C'est abusé. [...] Si tu dois ajouter un peu d'espace
          // entre le logo et la cadence, OK, d'accord, je veux bien. »
          //
          // Les `Spacer` ne touchent QUE la place libre : les trois écarts
          // gardent leur valeur d'origine comme plancher et se partagent le
          // reste dans leur proportion — 15 au-dessus du titre, 1 entre le
          // titre et le logo, 6 sous le logo.
          SizedBox(
            // UN ÉCRAN PLEIN — c'est l'interligne qui s'en charge — ou ce
            // que le contenu demande si c'est plus : sur une fenêtre basse,
            // l'interligne retombe à son plancher et le menu défile.
            height:
                contenuFixeDuMenu() + kInterlignesDuMenu * intervalleDuMenu(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Espace sous la zone du bouton Compte.
                SizedBox(height: SH(0.06)),
                // LE TITRE ET LE LOGO GARDENT LEUR TAILLE. Ils ont été
                // `Flexible` le temps d'une étape, pour ne jamais déborder
                // d'un écran trop court — mais `Flexible` les mettait en
                // concurrence avec l'air du bas pour la place libre, et ils
                // rapetissaient alors qu'il y avait de la place en trop.
                // Nino : « pourquoi t'as complètement réduit la taille de la
                // Fuga en haut ? Je t'ai pas dit de changer ça. Jamais. »
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
                  // `logoAssetOf` et non le chemin à la main : trois thèmes
                  // ont un logo dont le fichier ne porte pas leur nom, et
                  // l'image manquante retombait silencieusement sur celle
                  // d'origine. Le médiéval et les fleurs n'ont jamais montré
                  // la leur.
                  child: Image.asset(
                    logoAssetOf(_axes.logo),
                    height: SH(0.13),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Image.asset(
                      logoAssetOf(kDefaultTheme),
                      height: SH(0.13),
                    ),
                  ),
                ),
                SizedBox(height: SH(0.02) + S(gap)),

                SizedBox(
                  height: labelHeight(0.04, 17),
                  child: Center(
                    // EN COULEUR 1 DU THÈME, CERNÉ DE NOIR, comme les touches qu'il
                    // annonce. Nino : « le texte "cadence (min / joueur)" doit
                    // passer en couleur 1 du thème et prendre le contour noir. »
                    // L'encre presque noire des titres du menu lui venait de Kivy ;
                    // sur les fonds à image, elle se perdait dans les tourbillons.
                    child: MotTouche(
                      texte: T('Cadence (min / joueur)'),
                      // EN BLANC, comme toutes les écritures du menu. Nino : « je
                      // t'avais demandé de passer toutes les écritures en blanc
                      // aussi. Toutes les écritures du menu hein. » Les couleurs
                      // du thème restent aux DESSINS, qui n'ont qu'elles pour se
                      // distinguer ; un mot, lui, a déjà ses lettres.
                      couleur: Colors.white,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: SF(17),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: S(gap)),
                SizedBox(
                  // Épaisseur d'une touche, comme les grandes touches d'en dessous :
                  // une rangée plus fine se voyait tout de suite.
                  height: touchHeight(),
                  child: _rangee(
                    cle: _tourKeys['cad'],
                    touches: [
                      for (final c in Cadence.toutes)
                        FugaButton(
                          text: c.label,
                          fontSize: SF(15),
                          height: double.infinity,
                          // ÉTEINTE, ELLE EST DU GRIS DE TOUTES LES TOUCHES. Nino :
                          // « les touches de cadences ne changent que le fait de
                          // prendre le contour noir sur le texte et le fond gris
                          // médian quand elles ne sont pas sélectionnées. »
                          //
                          // ALLUMÉE, LES DEUX BORDS PRENNENT LA COULEUR 1 ET
                          // LE MILIEU LA COULEUR 2. Nino : « 5 min et 30 min
                          // doivent s'allumer en couleur 1 lorsque
                          // sélectionnés, alors que 15 min continue à
                          // s'allumer en couleur 2. »
                          color: _cadence != c
                              ? kGrisTouche
                              : (c == Cadence.quinze
                                    ? palette.fonce
                                    : palette.clair),
                          // TOUCHER CELLE QUI EST CHOISIE LA RETIRE. Nino :
                          // « il faut que cliquer sur une cadence
                          // sélectionnée la désélectionne. » C'est le seul
                          // moyen de revenir à une partie locale sans chrono
                          // une fois qu'on a choisi.
                          onPressed: () => setState(
                            () => _cadence = _cadence == c ? null : c,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: intervalleDuMenu()),

                // LES DEUX FAÇONS DE JOUER, CÔTE À CÔTE, chacune une moitié.
                // Nino : « en local et en ligne prennent chacun la moitié de
                // l'écran ». Elles gardent leur fond de thème et leur écriture
                // blanche : « en local et en ligne restent telles quelles, en
                // dehors du texte qui doit prendre le contour noir ».
                SizedBox(
                  height: touchHeight(),
                  child: _rangee(
                    touches: [
                      FugaButton(
                        key: _tourKeys['local'],
                        text: T('Jouer en local'),
                        color: palette.clair,
                        height: double.infinity,
                        fontSize: SF(16),
                        onPressed: _startLocal,
                      ),
                      FugaButton(
                        key: _tourKeys['online'],
                        color: palette.fonce,
                        height: double.infinity,
                        onPressed: _searching ? null : _playOnline,
                        // DEUX LIGNES : l'intitulé, et le mélo en dessous,
                        // plus petit. Nino : « le bouton jouer en ligne doit
                        // afficher "mélo ????" en dessous de "jouer en
                        // ligne". La taille de police de "jouer en ligne"
                        // doit rester la même mais celle de "mélo ????" peut
                        // être plus petite (par exemple même taille que
                        // "affronter Deep Grey"). »
                        enfant: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MotTouche(
                              texte: T('Jouer en ligne'),
                              couleur: Colors.white,
                              style: TextStyle(
                                fontSize: SF(16),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            MotTouche(
                              texte: _libelleDuMelo(),
                              couleur: Colors.white,
                              style: TextStyle(
                                fontSize: SF(14),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: intervalleDuMenu()),
                // LA RECHERCHE REMONTE D'UNE RANGÉE : elle en a gagné une, puisque
                // les deux façons de jouer n'en occupent plus qu'une.
                _wide(_searchRow(palette)),
                SizedBox(height: intervalleDuMenu()),
                _wide(_quatreTouches(palette)),

                // LE TRAIT PORTE SES DEUX INTERLIGNES : celui qui le sépare
                // des touches, et celui qui le sépare du bord de l'écran.
                // Nino : « il doit y avoir le même espace entre la barre de
                // séparation et le bord de l'écran qu'entre la barre de
                // séparation et les touches qui sont au-dessus. »
                _separateur(palette),
              ],
            ),
          ),
          SizedBox(height: SH(0.02)),

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

  /// Une rangée de touches, toutes de la même largeur, dans la bande.
  ///
  /// L'ÉCART EST CELUI DE PARTOUT, et la largeur des touches s'y plie.
  /// Nino : « j'aimerais que tu ajustes la largeur des touches de cadence et
  /// des touches "en ligne" et "en local" pour que l'interstice soit le même
  /// entre toutes les touches. »
  ///
  /// Les deux rangées gardent le même alignement à gauche et à droite ; ce
  /// qui change, c'est que trois touches laissent deux trous et deux touches
  /// un seul. Leurs largeurs additionnées diffèrent donc désormais d'un trou
  /// — c'est le prix d'un interstice unique, et c'est lui qui a été demandé
  /// en dernier.
  Widget _rangee({required List<Widget> touches, Key? cle}) {
    final ecart = intervalleDuMenu();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: S(kMargeDeLaBande)),
      child: Row(
        key: cle,
        children: [
          for (var i = 0; i < touches.length; i++) ...[
            if (i > 0) SizedBox(width: ecart),
            Expanded(child: touches[i]),
          ],
        ],
      ),
    );
  }

  /// Les quatre grosses touches, en deux sur deux, sous la recherche.
  ///
  /// Nino : « en dessous ça se sépare en quatre cases avec les symboles de
  /// chacun comme en partie, sauf que là on écrit également. » Elles tiennent
  /// dans la largeur des anciennes touches larges — « les quatre grosses
  /// touches avec les symboles doivent être séparées et prendre la même
  /// largeur que les actuelles touches » — c'est [_wide] qui la leur donne.
  ///
  /// LES COULEURS ALTERNENT EN DIAGONALE : « "conversations" et "autres"
  /// doivent avoir le texte et le symbole en couleur 1 du thème,
  /// "classement" et "affronter Deep Grey" en couleur 2. »
  Widget _quatreTouches(ThemePalette palette) {
    // L'interligne du menu, entre les deux rangées comme entre les deux
    // colonnes : une grille dont les écarts diffèrent d'un axe à l'autre se
    // voit tout de suite.
    final ecart = intervalleDuMenu();
    Widget deux(Widget gauche, Widget droite) => SizedBox(
      height: hauteurDesGrossesTouches(),
      child: Row(
        children: [
          Expanded(child: gauche),
          SizedBox(width: ecart),
          Expanded(child: droite),
        ],
      ),
    );
    return Column(
      children: [
        deux(
          // La pastille rouge reste sur les conversations, et seulement là.
          AnimatedBuilder(
            animation: _online.messages,
            builder: (context, _) => UnreadDot(
              show: _online.messages.hasUnread,
              child: _grosseTouche(
                cle: _tourKeys['conv'],
                dessin: 'assets/images/chat.webp',
                secours: '💬',
                texte: T('Conversations'),
                teinte: palette.clair,
                onPressed: _openMessages,
              ),
            ),
          ),
          _grosseTouche(
            cle: _tourKeys['classement'],
            dessin: 'assets/images/podium.webp',
            secours: '1·2·3',
            texte: T('Classement'),
            teinte: palette.fonce,
            onPressed: _openClassement,
          ),
        ),
        SizedBox(height: ecart),
        deux(
          _grosseTouche(
            cle: _tourKeys['ai'],
            dessin: 'assets/images/deepgrey_silhouette.webp',
            secours: '☗',
            texte: nomInsecable(T('Affronter Deep Grey')),
            teinte: palette.fonce,
            onPressed: _startVsAi,
          ),
          _grosseTouche(
            cle: _tourKeys['plus'],
            dessin: 'assets/images/plus.webp',
            secours: '+',
            texte: T('Autres'),
            teinte: palette.clair,
            onPressed: _openPlus,
          ),
        ),
      ],
    );
  }

  /// Une grosse touche : le symbole en haut, le mot en bas, tous deux de la
  /// même couleur de thème et cernés de noir.
  ///
  /// Elle ne passe pas par [FugaButton] : celui-ci réduit son contenu d'un
  /// bloc (`FittedBox`), ce qui laisse au symbole une largeur infinie à
  /// remplir et empêche « affronter Deep Grey » de se couper en deux lignes.
  /// Ici la place est partagée : au mot ce que deux lignes demandent, au
  /// symbole tout le reste.
  Widget _grosseTouche({
    required String dessin,
    required String secours,
    required String texte,
    required Color teinte,
    required VoidCallback onPressed,
    Key? cle,
  }) {
    final rayon = S(18);
    final marge = S(8);
    // De combien ce dessin-ci doit descendre pour poser sur le sol commun.
    final vide = kVideSousLeDessin[dessin] ?? 0;
    final sol = kVideSousLeDessin.values.reduce((a, b) => a < b ? a : b);
    return Material(
      key: cle,
      color: kGrisTouche,
      shape: formeDeTouche(BorderRadius.circular(rayon)),
      child: InkWell(
        borderRadius: BorderRadius.circular(rayon),
        onTap: onPressed,
        child: LayoutBuilder(
          builder: (context, boite) {
            final dedans = boite.maxHeight - 2 * marge;
            // DEUX LIGNES, TOUJOURS : les quatre symboles se tiennent alors
            // sur la même ligne d'horizon, que leur mot en prenne une ou
            // deux. Le facteur 1,35 dépasse la hauteur de ligne d'une police
            // (≈ 1,17) parce que la place RÉSERVÉE doit dépasser ce que le
            // texte demande, jamais l'inverse — un mot qui déborde d'un
            // dixième de point est un mot coupé.
            const parLigne = 1.35;
            // ET LA MOITIÉ DE LA TOUCHE AU PLUS. La hauteur d'une touche se
            // mesure sur la HAUTEUR de l'écran, la taille d'un texte sur sa
            // LARGEUR : sur une fenêtre large et basse, deux lignes à la
            // taille normale ne tenaient plus dedans, et la colonne
            // débordait. Le mot rapetisse alors plutôt que de déborder.
            final voulue = SF(14) * parLigne * 2;
            final hauteurDuMot = voulue < dedans / 2 ? voulue : dedans / 2;
            return Padding(
              padding: EdgeInsets.all(marge),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, place) {
                        // Le dessin occupe un carré de ce côté-là ; le vide
                        // qu'il laisse sous lui s'y réduit d'autant.
                        final cote = place.maxHeight * kPartDuSymboleDesGrosses;
                        final descente = (vide - sol) / kCarreDuDessin * cote;
                        // `Transform` et non une marge : la marge rognerait
                        // la place, donc le dessin, et il faudrait descendre
                        // davantage pour un dessin plus petit. Ici rien ne
                        // bouge que ce qu'on voit.
                        return Transform.translate(
                          offset: Offset(0, descente),
                          child: PictoTouche(
                            asset: dessin,
                            couleur: teinte,
                            secours: secours,
                            part: kPartDuSymboleDesGrosses,
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: S(4)),
                  SizedBox(
                    height: hauteurDuMot,
                    // LE MOT RÉTRÉCIT PLUTÔT QUE D'ÊTRE COUPÉ, comme dans
                    // [FugaButton] — et il rétrécit SANS perdre son retour à
                    // la ligne : la largeur donnée au-dedans est celle de la
                    // touche, donc « affronter Deep Grey » se coupe en deux
                    // lignes d'abord, et ces deux lignes-là rapetissent
                    // ensuite s'il le faut. Un `FittedBox` seul aurait offert
                    // au texte une largeur infinie, et le mot serait sorti de
                    // la touche en une seule ligne.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      // UNE LARGEUR MAXIMALE, ET NON UNE LARGEUR IMPOSÉE :
                      // le mot prend la place de ses lettres, pas celle de
                      // la touche. Imposée, elle décalait le contour — il se
                      // dessine sur la largeur de la boîte, les lettres se
                      // centrent dans celle-ci, et le mot se voyait DEUX
                      // fois, le noir à gauche et le coloré au milieu.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: boite.maxWidth - 2 * marge,
                        ),
                        child: MotTouche(
                          texte: texte,
                          // BLANC, comme toute écriture du menu : la couleur
                          // du thème reste au dessin.
                          couleur: Colors.white,
                          maxLines: 2,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: hauteurDuMot / (parLigne * 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _searchRow(ThemePalette palette) => SizedBox(
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
                // Le gris de toutes les touches : la barre fait rangée avec
                // l'étoile qui la suit, elles ne peuvent pas être de deux
                // gris différents.
                color: kGrisTouche,
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
        SizedBox(width: intervalleDuMenu()),
        // L'étoile est carrée : sa largeur suit la hauteur de la ligne.
        AspectRatio(
          aspectRatio: 1,
          child: FugaButton(
            key: _tourKeys['fav'],
            text: '★',
            // ×1,3 : seule de sa rangée à être un dessin, elle paraissait
            // menue à côté du mot d'à côté. Nino : « l'étoile est trop
            // petite. Multiplie-la par 1,3. »
            fontSize: SF(18 * 1.3),
            height: double.infinity,
            radius: S(12),
            // EN COULEUR 1 DU THÈME, et cernée comme le reste — le cerne lui
            // vient de la touche. Nino : « l'étoile (favoris) doit être en
            // couleur 1 du thème et avoir le contour. » Son jaune à elle ne
            // venait d'aucun thème.
            textColor: palette.clair,
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
    // CE QUI L'ALLUME : une partie qui attend notre coup, ou un défi qu'on
    // nous a envoyé et auquel on n'a pas répondu. Nino : « la barre de
    // séparation doit également s'allumer lorsqu'on a une invitation de défi
    // corresp. » Un défi qu'on a lancé SOI-MÊME n'attend rien de nous : il
    // n'allume pas.
    final attend = _corrGames.any(
      (g) => g.myTurn || (g.status == CorrStatus.defi && !g.isChallenger),
    );
    // ELLE PORTE SES DEUX INTERLIGNES, et c'est ce qui lui donne de quoi
    // être touchée. Nino : « lorsqu'on clique sur la barre de séparation, ça
    // fait défiler l'écran. » Un trait de onze points de haut est une cible
    // de quatre millimètres : en lui confiant l'écart qui le précède et
    // celui qui le suit — que la colonne posait à côté de lui —, la surface
    // sensible passe à cinquante points sans qu'un pixel bouge à l'écran.
    final interligne = intervalleDuMenu();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _versLesParties,
      child: SizedBox(
        height: 2 * interligne + S(kEpaisseurDuVoyant),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.62,
            child: AnimatedContainer(
              key: _cleDuTrait,
              duration: const Duration(milliseconds: 220),
              // DIX FOIS LE TRAIT, et non quatre. À quatre, Nino ne voyait pas
              // qu'elle était allumée : « c'est juste beaucoup trop fin. » Un
              // voyant doit se voir sans qu'on le cherche. Vu à ×2,5 sur les
              // dix-sept thèmes, essayé à ×3, revenu à ×2,5 : « finalement 2,5
              // c'était pas mal. »
              height: S(kEpaisseurDuVoyant),
              decoration: BoxDecoration(
                // ÉTEINTE, ELLE EST GRISE COMME UNE TOUCHE, pas noire : elle
                // appartient au menu, et seul son contour est noir — comme
                // pour tout le reste. Nino : « la barre de séparation doit
                // être grise comme les touches du menu. Seul le contour doit
                // être noir. »
                color: attend ? couleurAllumee(palette) : kGrisTouche,
                // LA MOITIÉ DE SA HAUTEUR : les bouts sont donc parfaitement
                // ronds, et le restent si l'épaisseur change encore.
                borderRadius: BorderRadius.circular(S(kEpaisseurDuVoyant / 2)),
                // Le trait noir des touches, autour du voyant.
                border: const Border.fromBorderSide(kTraitDeTouche),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Descend jusqu'aux parties par correspondance, d'un doigt sur le trait.
  ///
  /// Nino : « lorsqu'on clique sur la barre de séparation, ça fait défiler
  /// l'écran jusqu'à ce que ce soit comme sur la photo que je t'ai envoyée.
  /// S'il n'y a pas assez d'aperçus pour descendre aussi bas, ça descend le
  /// plus bas possible. »
  ///
  /// Sur sa photo, le trait vient se ranger juste sous les deux touches du
  /// bandeau, à un interligne d'elles : le menu disparaît, la liste des
  /// parties prend tout l'écran. On vise donc cette place-là, et le `clamp`
  /// fait le reste quand la liste est trop courte pour y arriver.
  Future<void> _versLesParties() async {
    final trait = _cleDuTrait.currentContext?.findRenderObject();
    if (trait is! RenderBox || !_scroll.hasClients) return;
    final hautDuTrait = trait.localToGlobal(Offset.zero).dy;
    // La place que prend le bandeau du haut, et l'interligne sous lui.
    final place = SH(0.015) + touchHeight() + intervalleDuMenu();
    final cible = (_scroll.offset + hautDuTrait - place).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    await _scroll.animateTo(
      cible,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  /// Le titre de la section. Plus de touche « Actualiser » à côté : la liste
  /// se tient à jour toute seule, comme sur les sites de jeu.
  Widget _corrHeader(ThemePalette palette) => SizedBox(
    key: _tourKeys['corr'],
    height: labelHeight(0.04, 15),
    // AU MILIEU, EN COULEUR 2, CERNÉ. Nino : « "parties par correspondance"
    // doit prendre la couleur 2 du thème et le contour noir, ainsi qu'être
    // recentré au milieu de l'écran. » Collé à gauche, il pendait sous une
    // grille, elle, centrée.
    child: Center(
      child: MotTouche(
        texte: T('Parties par correspondance'),
        couleur: Colors.white,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: SF(15)),
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
        // PLUS D'AIR ENTRE LES PLATEAUX depuis que leur cadre a doublé
        // d'épaisseur : deux cadres épais voisins se touchaient presque.
        // Nino : « écarte un peu plus les plateaux les uns des autres au
        // besoin. »
        mainAxisSpacing: S(14),
        crossAxisSpacing: S(14),
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
                // LA TOUCHE DIT LE MODE EN COURS, pas celui qu'elle
                // ouvrirait. Elle disait « Random » dans les deux cas, et
                // seule sa couleur distinguait l'un de l'autre. Nino : « il
                // doit y avoir écrit standard quand on est en mode standard,
                // random le remplace lorsque c'est activé. »
                text: _random ? 'Random' : T('Standard'),
                fontSize: SF(14),
                height: double.infinity,
                color: _random ? palette.clair : kGrisTouche,
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

  /// La seconde ligne de la touche « Jouer en ligne » : mon mélo.
  ///
  /// Nino : « il doit dire "???? mélo" au lieu de juste "????" ». Le nombre
  /// seul ne disait pas ce qu'il était.
  ///
  /// Le mélo suit le mode — Random Fuga a son propre classement — et le dit :
  /// « quand l'App passe en random, ça affiche "random mélo ????" ». Sans
  /// compte, le nombre n'existe pas encore : on écrit les points
  /// d'interrogation plutôt que d'effacer la ligne, pour que la touche ne
  /// change pas de hauteur en se connectant.
  String _libelleDuMelo() {
    final session = _online.session;
    final melo = (!_online.isLoggedIn || session == null)
        ? '????'
        : '${_random ? session.meloRandom : session.melo}';
    return _random ? 'Random ${T('mélo')} $melo' : '${T('mélo')} $melo';
  }

  /// L'intitulé du volet du classement : de quel mélo il parle.
  ///
  /// Nino : « l'intitulé du popup doit dire "classement mélo" ou "classement
  /// random mélo" ». Les deux classements se ressemblent trait pour trait —
  /// sans le dire, on ne saurait pas lequel on regarde.
  String _titreDuClassement() => _random
      ? '${T('Classement')} Random ${T('mélo')}'
      : '${T('Classement')} ${T('mélo')}';
}
