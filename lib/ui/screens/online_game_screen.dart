/// Partie en ligne.
///
/// Toute la logique vit dans [OnlineGame] ; cet écran l'affiche et lui passe
/// les gestes, exactement comme l'écran local le fait avec le contrôleur.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../suit_les_reglages.dart';

import '../../engine/board.dart';
import '../../engine/literal_replay.dart';
import '../../engine/piece.dart';
import '../../game/move_controller.dart';
import '../../game/game_archive.dart';
import '../../game/online_game.dart';
import '../../game/sound_player.dart';
import '../../game/last_move.dart';
import '../../i18n/translations.dart';
import '../../net/avatar_photos.dart';
import '../../net/decors_connus.dart';
import '../../net/message_hub.dart';
import '../../net/devises_connues.dart';
import '../../game/defi_relais.dart';
import '../../net/favoris_connus.dart';
import '../../net/profile.dart';
import '../../net/scores_directs.dart';
import '../../net/online_service.dart';
import '../../net/profils_connus.dart';
import '../../net/resolution_profil.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import 'conversations_screen.dart';
import '../palette_adverse.dart';
import '../retour_menu.dart';
import '../widgets/fuga_background.dart';
import '../widgets/end_dialogs.dart';
import '../widgets/game_board_view.dart';
import '../widgets/message_rapide.dart';
import '../widgets/bulles_en_jeu.dart';
import '../widgets/game_layout.dart';
import '../widgets/move_strip.dart';
import '../widgets/player_card.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/pause_dialog.dart';
import '../widgets/player_panel.dart';
import '../widgets/slide_animation.dart';

class OnlineGameScreen extends StatefulWidget {
  const OnlineGameScreen({
    super.key,
    required this.game,
    required this.myPseudo,
    this.archive,
    this.sounds,
  });

  final OnlineGame game;
  final String myPseudo;

  /// Où ranger chaque partie une fois finie. Injectable pour les tests.
  final GameArchive? archive;

  /// Le lecteur de sons. Injectable pour les tests : sans quoi « le coup de
  /// l'adversaire s'entend-il ? » ne se vérifie qu'à l'oreille.
  final SoundPlayer? sounds;

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen>
    with SlideAnimation, SuitLesReglages {
  late final SoundPlayer _sounds = widget.sounds ?? SoundPlayer();
  LastMove? _lastMove;

  /// Position d'avant le coup : la mise en évidence en a besoin (type de la
  /// pièce qui pousse, chemin d'un saut).
  Board? _boardBefore;

  /// Toutes les positions traversées : `_steps[0]` est la position de départ,
  /// `_steps[k]` celle d'après le k-ième coup.
  ///
  /// C'est ce qui permet de revoir un coup passé. En partie de matchmaking,
  /// les flèches du bandeau n'étaient câblées sur rien — `onSelect: (_) {}` —
  /// là où la correspondance et le jeu local les câblaient depuis le début.
  List<Board> _steps = const [];

  /// La partie dont `_steps` a été tiré. Un match enchaîne plusieurs parties,
  /// et chacune remplace `game` : il faut rejouer depuis SA position.
  MoveController? _stepsDe;

  /// Coup regardé. `null` = le présent, c'est-à-dire le dernier.
  int? _viewingIndex;

  bool get _isViewing => _viewingIndex != null;

  OnlineGame get _g => widget.game;

  /// La photo de l'adversaire : le serveur ne l'envoie pas avec la partie, on
  /// va la chercher par son pseudo (voir `AvatarPhotos`). Vide en attendant.
  String _photoAdverse = '';

  /// Le score des parties en direct entre nous — « 6 » d'un côté, « 17 » de
  /// l'autre. `null` tant qu'on ne l'a pas : le bandeau n'écrit alors rien.
  ///
  /// Nino : « ce système de score doit aussi marcher pour les parties en
  /// direct ». C'est le même cumul qu'en correspondance, à ceci près qu'en
  /// direct il vient du profil et non de la partie.
  HeadToHead? _scoreDirect;

  /// Demande la photo de l'adversaire et redessine son avatar à l'arrivée.
  Future<void> _chargerPhotoAdverse() async {
    // SON PROFIL EST RELU À CHAQUE OUVERTURE. Nino : « si un adversaire
    // change sa devise, je dois relancer mon app pour que ça m'affiche la
    // nouvelle dans les parties. » Les caches ne demandent qu'une fois par
    // session — c'est ce qui évite d'interroger le serveur à chaque image, et
    // c'est aussi ce qui faisait tenir une devise périmée jusqu'au
    // redémarrage.
    //
    // Une requête, pas deux : c'est celle que les `resolve` d'en dessous
    // faisaient déjà, et ils trouvent tout en cache ensuite. Ils restent
    // malgré tout — si la relecture échoue, le réseau ayant toussé, ce sont
    // eux qui vont chercher ce qui manque, exactement comme avant.
    await rafraichisProfil(_g.info.opponent);
    // Le décor, et pas seulement la photo : c'est son thème qui donne leurs
    // couleurs aux bulles de messages qui passent dans son bandeau. Et c'est
    // `DecorsConnus` qui décide de demander — une photo déjà connue ne doit
    // pas faire sauter la question du thème.
    await DecorsConnus.resolve(_g.info.opponent);
    // Et sait-on s'il est dans mes favoris ? L'étoile du bandeau en dépend.
    await FavorisConnus.instance.demande(_g.info.opponent);
    final photo = await AvatarPhotos.resolve(_g.info.opponent);
    // Et le score de nos parties en direct. Les quatre réponses sortent du
    // même `/get_profile` : celle-ci est déjà en cache quand on la demande.
    await ScoresDirects.resolve(_g.info.opponent);
    if (!mounted) return;
    setState(() {
      _photoAdverse = photo;
      _scoreDirect = ScoresDirects.connu(_g.info.opponent);
    });
    unawaited(_annonceSaDevise());
  }

  /// Sa devise, montrée au DÉBUT de la partie — comme un mot qu'il aurait dit
  /// en s'asseyant.
  ///
  /// Nino : « qu'au début d'une partie direct […] la devise du joueur
  /// apparaisse quelques secondes sur la partie comme les messages. Mais ça
  /// ne doit pas apparaître dans la boîte de chat. » Elle ne passe donc par
  /// aucun envoi : elle est posée directement dans la bande, et le serveur de
  /// messages n'en entend jamais parler.
  Future<void> _annonceSaDevise() async {
    final devise = await DevisesConnues.resolve(_g.info.opponent);
    if (!mounted || devise.isEmpty || _bulles.isClosed) return;
    _bulles.add((texte: devise, deMoi: false));
  }

  /// Le score a bougé : une partie du match vient de finir, le serveur en
  /// tient un nouveau. On repose la question plutôt que d'afficher l'ancien.
  Future<void> _rafraichirScore() async {
    await ScoresDirects.resolve(_g.info.opponent, force: true);
    if (!mounted) return;
    setState(() => _scoreDirect = ScoresDirects.connu(_g.info.opponent));
  }

  @override
  void initState() {
    super.initState();
    // Une partie en direct est en cours : « Défier » s'éteint PARTOUT, ici
    // comme dans le chat ouvert d'ici. On ne joue pas deux parties à la fois.
    DefiRelais.enPartieDirecte = true;
    _photoAdverse = AvatarPhotos.known(_g.info.opponent);
    _scoreDirect = ScoresDirects.connu(_g.info.opponent);
    _ecouteBulles = OnlineService.instance.messages.incoming
        .where((m) => m.from == _g.info.opponent)
        .listen((m) => _bulles.add((texte: m.text, deMoi: false)));
    // Et les miens, d'où que je les écrive : depuis le plateau comme depuis
    // la boîte de messages. Avant, la bande ne voyait que les premiers.
    _ecouteMesBulles = OnlineService.instance.messages.outgoing
        .where((m) => m.to == _g.info.opponent)
        .listen((m) => _bulles.add((texte: m.text, deMoi: true)));
    _chargerPhotoAdverse();
    _sounds.init();
    _rebuildSteps();
    _g.onChanged = _handleEvent;
    // La pastille du bouton Chat suit les messages en direct.
    OnlineService.instance.messages.addListener(_onMessages);
    // L'étoile du bandeau suit la touche « Favori / Retirer », qui vit dans
    // un popup : le cache partagé fait le lien.
    FavorisConnus.instance.addListener(_onMessages);
    // Et son profil : une devise ou une photo changée pendant que je
    // regarde l'écran doit s'y voir, sans attendre une réouverture.
    profilsConnus.addListener(_onMessages);
  }

  void _onMessages() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DefiRelais.enPartieDirecte = false;
    OnlineService.instance.messages.removeListener(_onMessages);
    FavorisConnus.instance.removeListener(_onMessages);
    profilsConnus.removeListener(_onMessages);
    _ecouteBulles?.cancel();
    _ecouteMesBulles?.cancel();
    unawaited(_bulles.close());
    _sounds.dispose();
    _g.dispose();
    super.dispose();
  }

  /// TOUT ce qui paraît dans la bande des bulles : les messages reçus, ceux
  /// que j'écris depuis le plateau, et sa devise à l'ouverture.
  ///
  /// Un seul flux, composé ici : la bande ne connaît que des mots et leur
  /// provenance. Rien de ce qui part d'ici ne touche la conversation — Nino,
  /// à propos de la devise : « ça ne doit pas apparaître dans la boîte de
  /// chat. »
  final StreamController<BulleEnJeu> _bulles =
      StreamController<BulleEnJeu>.broadcast();
  StreamSubscription<IncomingMessage>? _ecouteBulles;
  StreamSubscription<OutgoingMessage>? _ecouteMesBulles;

  /// Cette partie est-elle une Random Fuga ? C'est son code qui le dit.
  bool get _estRandom => _g.info.randomCode != null;

  /// Le popup de fin n'est montré qu'une fois par partie.
  bool _endShown = false;

  /// Parties du match déjà rangées dans l'historique, par identifiant.
  final Set<String> _archivedGames = {};

  late final GameArchive _store = widget.archive ?? GameArchive();

  void _handleEvent(OnlineEvent event) {
    if (!mounted) return;
    if (event == OnlineEvent.drawOffered && _g.drawOffered) {
      _askDraw();
    }
    if (event == OnlineEvent.nextGameStarted) {
      _endShown = false;
      _lastMove = null;
      _viewingIndex = null;
    }

    // Coup de l'adversaire : on reprend sa mise en évidence et son glissement.
    final incoming = _g.pendingHighlight;
    if (incoming != null) {
      _g.pendingHighlight = null;
      _lastMove = incoming.lastMove;
      // Et on revient au présent. La pendule tourne : laisser le joueur sur
      // une position passée, c'est le laisser perdre au temps en regardant
      // ailleurs. Son coup glisse donc sur le plateau d'aujourd'hui, et pas
      // sur celui qu'on était en train de revoir.
      _viewingIndex = null;
      rememberSlides(
        incoming.slides,
        jumpPath: incoming.lastMove?.jumpPath ?? const [],
      );
    }
    // Les coups ont peut-être bougé : les positions retenues suivent.
    _ajusterSteps();
    setState(() {});
    // Et il s'entend. Le son partait au doigt et nulle part ailleurs : on
    // voyait le coup de l'adversaire arriver sans l'entendre, là où celui de
    // Deep Grey sonnait. Après l'écran, comme pour un coup joué à la main —
    // le plateau passe d'abord.
    if (incoming != null && incoming.notation.isNotEmpty) {
      _sounds.playNotation(incoming.notation);
    }

    if (_g.endReason != null && !_endShown) {
      _endShown = true;
      _archive();
      // La partie est finie : le serveur a compté une victoire de plus pour
      // l'un de nous deux.
      unawaited(_rafraichirScore());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEnd();
      });
    }
  }

  /// Rejoue les coups depuis le départ pour retenir chaque position.
  ///
  /// À la lettre, comme en correspondance : c'est ce qui garantit que les deux
  /// téléphones reconstruisent la même partie à partir du même texte.
  void _rebuildSteps() {
    var board = _g.startBoard.clone();
    final steps = <Board>[board];
    for (final notation in _g.game.history) {
      board = applyNotationLiterally(board, notation).board;
      steps.add(board);
    }
    _steps = steps;
    _stepsDe = _g.game;
  }

  /// Rejoue si, et seulement si, les coups ont bougé.
  ///
  /// L'écran se reconstruit une fois par seconde à cause du chrono : rejouer
  /// la partie entière à chaque fois serait du gaspillage pur.
  void _ajusterSteps() {
    if (identical(_stepsDe, _g.game) &&
        _steps.length == _g.game.history.length + 1) {
      return;
    }
    _rebuildSteps();
  }

  /// Revoir un coup passé, en le montrant se jouer. Le dernier, c'est le
  /// présent : on y revient et la partie redevient jouable.
  void _viewMove(int index) {
    final total = _g.game.history.length;
    if (total == 0) return;
    // `-1` : la position de départ, avant le premier coup.
    final voulu = index.clamp(-1, total - 1);
    final avant = _viewingIndex ?? total - 1;
    setState(() {
      _viewingIndex = voulu == total - 1 ? null : voulu;
      // En reculant, le coup à défaire est celui qu'on QUITTE.
      _animerCoup(
        voulu < avant ? avant + 1 : voulu + 1,
        recule: voulu < avant,
        versIndex: voulu + 1,
      );
    });
    // La position de départ n'a pas de coup : rien à faire entendre.
    if (voulu >= 0) _sounds.playNotation(_g.game.history[voulu]);
  }

  /// Fait glisser les pièces du coup numéro [index] (1 = le premier coup).
  void _animerCoup(int index, {bool recule = false, int? versIndex}) {
    animerCoupDe(
      positions: _steps,
      notations: _g.game.history,
      index: index,
      recule: recule,
      versIndex: versIndex,
    );
  }

  /// Plateau affiché : celui du coup regardé, ou la position courante.
  Board get _shownBoard {
    final index = _viewingIndex;
    if (index == null) return _g.game.board;
    if (index < 0) return _steps.isEmpty ? _g.game.board : _steps.first;
    return index + 1 < _steps.length ? _steps[index + 1] : _g.game.board;
  }

  /// Mise en évidence du coup affiché.
  LastMove? get _shownLastMove {
    final index = _viewingIndex;
    if (index == null) return _lastMove;
    final notations = _g.game.history;
    // Position de départ : aucun coup n'y a mené.
    if (index < 0) return null;
    if (index >= notations.length || index + 1 >= _steps.length) return null;
    return lastMoveFromNotation(
      notations[index],
      _steps[index],
      _steps[index + 1],
    );
  }

  void _onTapCell(Cell cell) {
    // En train de revoir un coup : le doigt ne joue pas. Une partie en ligne
    // ne se rebranche pas comme une analyse locale — le serveur tient le
    // cours de la partie, et il n'y a qu'un cours.
    if (_isViewing) return;
    // La position d'avant le coup est prise au premier geste du tour.
    if (!_g.game.moved) _boardBefore = _g.game.board.clone();
    final result = _g.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    // Chaque geste glisse au moment où il est fait, comme en Kivy.
    rememberSlides(result.slides, jumpPath: result.jumpPath);
    final notation = result.notation;
    if (notation != null) {
      _lastMove = lastMoveFromNotation(
        notation,
        _boardBefore ?? Board.initial(),
        _g.game.board,
      );
    }
    if (notation != null) _ajusterSteps();
    setState(() {});
    // Le son part après l'écran : le plateau doit répondre au doigt.
    if (notation != null) _sounds.playNotation(notation);
  }

  Future<void> _askDraw() async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Nulle')),
        content: Text('${_g.info.opponent} ${T('propose la nulle')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Refuser')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Accepter')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    accept == true ? _g.acceptDraw() : _g.declineDraw();
  }

  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Abandonner')),
        content: Text(T('Abandonner cette partie ?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Abandonner')),
          ),
        ],
      ),
    );
    if (ok == true) _g.resign();
  }

  /// La boîte de messages UNIFIÉE avec l'adversaire — `_open_chat`.
  ///
  /// La même conversation qu'au menu : Kivy ne tient pas de chat séparé par
  /// partie.
  Future<void> _openChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          online: OnlineService.instance,
          pseudo: _g.info.opponent,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String? get _verdict {
    final reason = _g.endReason;
    if (reason == null) return null;
    final winner = _g.loser?.opposite;
    final base = switch (reason) {
      'fugue' => T('Fugue'),
      'mat' => T('Mat'),
      'papatte' => T('Papatte'),
      'temps' => T('Temps écoulé'),
      'abandon' => T('Abandon'),
      'nulle' || 'nulle_pat' || 'nulle_accord' => T('Match nul'),
      'repetition' => T('Match nul par répétition'),
      _ => T('Partie terminée'),
    };
    if (winner == null) return base;
    final who = winner == _g.myCamp ? T('Gagné !') : T('Perdu');
    return '$base — $who';
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    // Mon camp est toujours en bas — sauf si le joueur retourne le plateau.
    final flipped = _flipOverride ?? (_g.myCamp == Camp.blanc);
    final topCamp = flipped ? Camp.noir : Camp.blanc;
    final bottomCamp = flipped ? Camp.blanc : Camp.noir;

    return FugaScaffold(
      // Le bandeau touche le HAUT de l'écran, comme en Kivy : en plein
      // écran immersif il n'y a pas de barre d'état à éviter, et la bande
      // laissée au-dessus mangeait de la place au plateau.
      body: SafeArea(
        top: false,
        child: GameLayout(
          // Les messages de l'adversaire passent dans SON bandeau, rognés à
          // lui : ni le plateau ni les touches n'en voient rien.
          topOverlay: BullesEnJeu(
            flux: _bulles.stream,
            palette: paletteDe(_g.info.opponent),
            mienne: palette,
          ),
          topBar: GameTopBar(
            palette: palette,
            color: _campColor(palette, topCamp),
            onFlip: _toggleFlip,
            onChat: _openChat,
            // La touche Chat ouvre la conversation privée avec l'adversaire :
            // sa pastille s'allume pour un message de LUI, et pour lui seul.
            unreadChat: OnlineService.instance.messages.unreadFrom(
              _g.info.opponent,
            ),
            onPause: _openPause,
            onMenu: _g.endReason != null ? () => retourAuMenu(context) : null,
          ),
          topPanel: _banner(palette, topCamp),
          board: GameBoardView(
            board: _shownBoard,
            palette: palette,
            flipped: flipped,
            onTapCell: _onTapCell,
            selected: _isViewing ? null : _g.game.selected,
            groupSelection: _isViewing ? const {} : _g.game.groupSelection,
            highlighted: _isViewing
                ? const {}
                : _g.game.availablePushCells.toSet(),
            lastMove: _shownLastMove,
            // La fugue clôt la partie : en revoyant un coup passé, l'Héritier
            // n'a pas encore rejoint son ralliement.
            fuguedHeirs: _isViewing ? const {} : _g.game.fuguedHeirs,
            pieceTheme: axes.pieces,
            boardTheme: axes.board,
            slides: slides,
            slideJumpPath: slideJumpPath,
            slideToken: slideToken,
            slideDuration: slideDuration,
          ),
          bottomPanel: _banner(palette, bottomCamp),
          moveStrip: MoveStrip(
            moves: _g.game.history,
            activeIndex: _viewingIndex,
            color: _campColor(palette, bottomCamp),
            palette: palette,
            randomCode: _g.info.randomCode,
            // Les flèches et le bandeau ne faisaient RIEN : on ne pouvait pas
            // revoir un coup sans quitter la partie.
            onSelect: _viewMove,
          ),
        ),
      ),
    );
  }

  /// Couleur d'un camp, vive quand il a le trait.
  Color _campColor(ThemePalette palette, Camp camp) {
    final atTrait = _g.game.turn == camp && !_g.game.gameOver;
    if (camp == Camp.blanc) return atTrait ? palette.clair : palette.clairDim;
    return atTrait ? palette.fonce : palette.fonceDim;
  }

  /// Retourner le plateau : Kivy l'autorise même en ligne.
  bool? _flipOverride;

  void _toggleFlip() => setState(
    () => _flipOverride = !(_flipOverride ?? (_g.myCamp == Camp.blanc)),
  );

  /// La pause. En ligne, elle ne propose pas de quitter : on abandonne la
  /// partie par le [×] de son panneau, et le match entre deux parties.
  Future<void> _openPause() async {
    await showPauseDialog(
      context,
      palette: paletteOf(Settings.instance.themeAxes.general),
      quit: PauseQuit.none,
    );
    if (!mounted) return;
    _sounds.applySettings();
    setState(() {});
  }

  Widget _banner(ThemePalette palette, Camp camp) {
    final isMine = camp == _g.myCamp;
    // Kivy écrivait le mélo À CÔTÉ du nom — « Nino  (1500) » — et sur un
    // téléphone l'ellipse le mangeait. Il passe SOUS le pseudo.
    //
    // Et c'est CELUI DU MODE JOUÉ. Nino : « il faudrait que le mélo indiqué
    // durant une partie soit le mélo du mode correspondant ». Le sien arrive
    // déjà juste : le serveur met dans `partie_trouvee` le mélo du mode,
    // choisi au moment d'entrer dans la file. Le mien venait de ma session,
    // qui porte les deux — on y prenait toujours le standard.
    final session = OnlineService.instance.session;
    final melo = isMine
        ? (_g.newMelo ??
              (_estRandom ? session?.meloRandom : session?.melo) ??
              1500)
        : _g.info.opponentMelo;
    var label = isMine ? widget.myPseudo : _g.info.opponent;
    var nameColor = kPanelInk;

    // Adversaire déconnecté : son nom porte le décompte, en rouge — c'est lui
    // qui perd le match si le compte arrive à zéro.
    if (!isMine && !_g.opponentConnected) {
      final delay = _g.disconnectGrace;
      label = delay == null || delay <= 0
          ? T('%s (abandon…)').replaceFirst('%s', _g.info.opponent)
          : T(
              '%s (déco %ds)',
            ).replaceFirst('%s', _g.info.opponent).replaceFirst('%d', '$delay');
      nameColor = const Color.fromRGBO(230, 102, 102, 1);
    }

    String? subtitle;
    if (isMine && _g.meloDelta != null) {
      final d = _g.meloDelta!;
      subtitle = '${d >= 0 ? '+' : ''}$d';
    }

    // Les gestes (↶ ½ X) n'appartiennent qu'à MON panneau : en ligne, je ne
    // peux ni annuler ni abandonner à la place de l'adversaire.
    final canAct = isMine && !_g.game.gameOver;

    return PlayerPanel(
      name: label,
      nameColor: nameColor,
      // LA FICHE, la même partout. Nino : « lors d'une partie en direct, ce
      // popup doit avoir la touche défier […] désactivée » — on joue déjà
      // contre lui, et on ne quitte pas une partie en direct pour en lancer
      // une autre. (Elle s'est hachurée le temps d'un essai ; elle pâlit
      // depuis qu'il les a vues en vrai.)
      onNameTap: () => showPlayerCard(
        context,
        online: OnlineService.instance,
        palette: palette,
        pseudo: isMine
            ? (OnlineService.instance.pseudo ?? '')
            : _g.info.opponent,
      ),
      // L'étoile ne vaut que pour l'ADVERSAIRE : se mettre soi-même en
      // favori n'a pas de sens, et la touche n'est pas proposée non plus.
      favori:
          !isMine && (FavorisConnus.instance.connu(_g.info.opponent) ?? false),
      rating: '$melo',
      subtitle: subtitle,
      clock: _g.clock.displayFor(camp),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _g.game.turn == camp && !_g.game.gameOver,
      captures: _g.game.captured[camp.opposite] ?? const [],
      photo: isMine
          ? (OnlineService.instance.session?.photo ?? '')
          : _photoAdverse,
      // LE CUMUL DE NOS PARTIES EN DIRECT, et non le score du match.
      //
      // Nino, sur le score du bandeau : « juste 4 et 15 […] ce système de
      // score doit aussi marcher pour les parties en direct ». C'est donc le
      // même nombre qu'en correspondance — combien de parties chacun a
      // gagnées contre l'autre — et non le compte de ce match-ci.
      score: _scoreDirect == null
          ? null
          : '${isMine ? _scoreDirect!.mine : _scoreDirect!.theirs}',
      busy: !isMine && !_g.opponentConnected,
      mirrored: isMine,
      onUndo: canAct && _g.game.canValidate
          ? () {
              if (_g.game.cancelCurrentMove()) setState(() {});
            }
          : null,
      onDraw: canAct ? _g.offerDraw : null,
      onResign: canAct ? _confirmResign : null,
      // Écrire n'est pas jouer : la touche reste là jusqu'au bout, même
      // partie finie — on se dit encore « bien joué » après le dernier coup.
      onMessageRapide: isMine
          ? () => envoyerMessageRapide(
              context,
              palette: palette,
              adversaire: _g.info.opponent,
            )
          : null,
    );
  }

  /// Quitter un match en cours : c'est un abandon du match entier.
  Future<void> _quitMatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(T('Quitter le match ?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Quitter le match')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _g.resignMatch();
    if (mounted) Navigator.of(context).pop();
  }

  /// Range la partie finie dans l'historique en ligne du compte.
  ///
  /// Ce port ne le faisait qu'au départ de l'écran de jeu local : une partie
  /// en ligne n'entrait donc dans l'historique de personne. Chaque partie d'un
  /// match a son propre identifiant serveur, donc sa propre entrée — et le
  /// même des deux côtés.
  void _archive() {
    final id = _g.info.gameId;
    if (id.isEmpty || _archivedGames.contains(id)) return;
    _archivedGames.add(id);
    unawaited(
      _store.store(
        buildOpponentArchive(
          myPseudo: widget.myPseudo,
          opponent: _g.info.opponent,
          myCamp: _g.myCamp,
          winner: _g.loser?.opposite,
          method: _g.endReason ?? 'nulle',
          history: List.of(_g.game.history),
          objectif: _g.info.objectif,
          cadence: _g.info.cadence,
          randomCode: _g.info.randomCode,
          onlineGameId: id,
        ),
      ),
    );
  }

  /// Fin de partie : le popup de Kivy. Si le match continue, il propose la
  /// partie suivante ; sinon il annonce le résultat, le mélo, et le retour au
  /// menu.
  void _showEnd() {
    final palette = paletteOf(Settings.instance.themeAxes.general);
    final title = _verdict ?? T('Partie terminée');

    if (_g.matchContinues) {
      unawaited(
        showOnlineContinueDialog(
          context,
          palette: palette,
          title: title,
          body: _g.scoreLine,
          readySent: _g.readySent,
          onReady: () => setState(_g.readyForNext),
          onQuit: _quitMatch,
        ),
      );
      return;
    }

    final melo = _g.newMelo;
    final delta = _g.meloDelta;
    unawaited(
      showFinishDialog(
        context,
        palette: palette,
        title: title,
        body: _g.scoreLine,
        winner: switch (_g.loser?.opposite) {
          null => null,
          final Camp w => w == _g.myCamp ? widget.myPseudo : _g.info.opponent,
        },
        meloLine: (melo == null || delta == null)
            ? T('Mise à jour du mélo…')
            : T('Mélo : %d  (%s%d)')
                  .replaceFirst('%d', '$melo')
                  .replaceFirst('%s', delta >= 0 ? '+' : '')
                  .replaceFirst('%d', '$delta'),
        onMenu: () {
          if (mounted) retourAuMenu(context);
        },
      ),
    );
  }
}
