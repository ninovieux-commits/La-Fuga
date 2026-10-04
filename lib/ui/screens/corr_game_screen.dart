/// Une partie de correspondance : on rejoue l'historique, on joue son coup,
/// on l'envoie, et on repart.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../engine/literal_replay.dart';
import '../../game/correspondence.dart';
import '../../game/game_archive.dart';
import '../../game/move_controller.dart';
import '../../game/slides.dart';
import '../../game/sound_player.dart';
import '../../game/last_move.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../../net/avatar_photos.dart';
import '../../net/corr_hub.dart';
import '../../net/filet_relecture.dart';
import '../../net/online_service.dart';
import '../widgets/end_dialogs.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_layout.dart';
import '../../game/clock.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/move_strip.dart';
import '../widgets/name_menu.dart';
import '../widgets/pause_dialog.dart';
import '../widgets/draw_offer_panel.dart';
import '../widgets/player_panel.dart';
import '../widgets/slide_animation.dart';
import 'conversations_screen.dart';
import 'game_screen.dart';

class CorrGameScreen extends StatefulWidget {
  const CorrGameScreen({
    super.key,
    required this.game,
    required this.service,
    required this.myPseudo,
    this.archive,
    this.initialBoard,
  });

  final CorrGame game;
  final CorrespondenceService service;
  final String myPseudo;

  /// Où ranger la partie une fois finie. Injectable pour les tests.
  final GameArchive? archive;

  /// Position de départ imposée. Injectable pour les tests : certaines fins de
  /// partie — pousser l'Héritier adverse dans son ralliement, éjecter le sien —
  /// ne s'atteignent pas en un coup depuis la position standard, et ce sont
  /// justement celles où le gagnant n'est pas celui qui joue.
  final Board? initialBoard;

  @override
  State<CorrGameScreen> createState() => _CorrGameScreenState();
}

class _CorrGameScreenState extends State<CorrGameScreen> with SlideAnimation {
  final SoundPlayer _sounds = SoundPlayer();

  MoveController? _controller;
  LastMove? _lastMove;

  /// Position d'avant le coup : la mise en évidence en a besoin (type de la
  /// pièce qui pousse, chemin d'un saut).
  Board? _boardBefore;
  bool _sending = false;
  bool _played = false;

  /// Vrai quand MON coup vient de terminer la partie : le serveur n'a pas
  /// encore renvoyé le nouveau statut, mais il n'y a plus rien à jouer.
  bool _finished = false;

  /// La partie est déjà rangée dans l'historique.
  bool _archived = false;

  late final GameArchive _store = widget.archive ?? GameArchive();

  /// La partie, telle qu'on la connaît. Elle CHANGE : le serveur en renvoie
  /// une version plus récente dès que l'adversaire a joué.
  late CorrGame _g = widget.game;

  /// Le direct : le coup de l'adversaire arrive ici, à l'instant où il le
  /// joue. Le serveur n'émettait rien pour la correspondance — rien ne
  /// réveillait cet écran, et il fallait le quitter et y revenir.
  StreamSubscription<CorrChange>? _ecouteCorr;

  /// Et la relecture périodique derrière, en filet : espacée tant que le
  /// direct répond, au rythme rapide dès qu'il se tait.
  Timer? _poll;
  bool _polling = false;
  final FiletRelecture _filet = FiletRelecture();

  /// Même cadence que les aperçus du menu.
  static const Duration _pollInterval = Duration(seconds: 4);

  /// Toutes les positions de la partie : `_steps[0]` est la position de
  /// départ, `_steps[k]` celle d'après le k-ième coup. C'est ce qui permet de
  /// revoir un coup passé — le bandeau du bas et ses flèches ne faisaient
  /// rien du tout — et de faire glisser les pièces d'une position à l'autre.
  List<Board> _steps = const [];

  /// Coup regardé. `null` = le présent, c'est-à-dire le dernier.
  int? _viewingIndex;

  bool get _isViewing => _viewingIndex != null;

  /// Combien de coups ont déjà été montrés en train de se jouer. Sans ce
  /// compte, la relecture périodique rejouerait l'animation de notre propre
  /// coup quand le serveur nous le renvoie.
  int _dejaAnime = 0;

  /// La photo de l'adversaire : le serveur ne l'envoie pas avec la partie, on
  /// va la chercher par son pseudo (voir `AvatarPhotos`). Vide en attendant.
  String _photoAdverse = '';

  /// Demande la photo de l'adversaire et redessine son avatar à l'arrivée.
  Future<void> _chargerPhotoAdverse() async {
    final photo = await AvatarPhotos.resolve(_g.opponent);
    if (mounted && photo != _photoAdverse) {
      setState(() => _photoAdverse = photo);
    }
  }

  @override
  void initState() {
    super.initState();
    _photoAdverse = AvatarPhotos.known(_g.opponent);
    _chargerPhotoAdverse();
    _sounds.init();
    // La pastille du bouton Chat suit les messages en direct.
    OnlineService.instance.messages.addListener(_onMessages);
    _ecouteCorr = OnlineService.instance.corr.changes.listen(_surChangement);
    _restore();
    _poll = Timer.periodic(_pollInterval, (_) {
      if (!_filet.fautRelire(
        directVivant: OnlineService.instance.socket?.isConnected ?? false,
      )) {
        return;
      }
      _filet.note();
      unawaited(_refresh());
    });
  }

  /// Quelque chose a bougé en correspondance : est-ce NOTRE partie ?
  ///
  /// On ne relit que pour elle. Un coup joué dans une autre partie ne doit
  /// pas redessiner ce plateau-ci — et surtout pas rejouer son animation.
  void _surChangement(CorrChange c) {
    if (!mounted) return;
    if (c.gameId.isNotEmpty && c.gameId != _g.id) return;
    _filet.note();
    unawaited(_refresh());
  }

  /// Redemande la partie au serveur et redessine si elle a bougé.
  ///
  /// Trois gardes, et chacune répare un dégât précis :
  ///   — un coup en cours de composition ne doit pas être effacé sous le doigt ;
  ///   — un envoi en vol non plus, le serveur ne connaît pas encore le coup ;
  ///   — et on ne redessine que si le texte des coups a VRAIMENT changé, sinon
  ///     on reconstruirait le plateau toutes les quatre secondes pour rien.
  Future<void> _refresh() async {
    if (!mounted || _polling || _sending) return;
    if (_controller?.moved ?? false) return;
    _polling = true;
    try {
      final games = await widget.service.list();
      if (!mounted || games == null) return;
      final fraiche = games.where((g) => g.id == _g.id).firstOrNull;
      if (fraiche == null) return;
      // Une proposition de nulle ne change NI les coups NI le statut : s'en
      // tenir à ces deux-là la laissait passer sous le nez, et l'offre
      // n'apparaissait qu'en rouvrant la partie.
      final memeNulle =
          fraiche.drawToAnswer == _g.drawToAnswer &&
          fraiche.drawOfferedByMe == _g.drawOfferedByMe;
      if (fraiche.movesText == _g.movesText &&
          fraiche.status == _g.status &&
          memeNulle) {
        return;
      }
      final memeCoups = fraiche.movesText == _g.movesText;
      _g = fraiche;
      // L'adversaire a répondu : c'est de nouveau à nous.
      if (fraiche.myTurn) _played = false;
      // Rien qu'une nulle a bougé : rejouer la partie rembobinerait le
      // plateau sous les yeux pour rien.
      if (memeCoups && _controller != null) {
        setState(() {});
        return;
      }
      _restore();
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ecouteCorr?.cancel();
    OnlineService.instance.messages.removeListener(_onMessages);
    _sounds.dispose();
    super.dispose();
  }

  /// Rejoue l'historique pour retrouver la position courante.
  ///
  /// La relecture est littérale et ne échoue jamais : une notation qu'on ne
  /// sait pas appliquer est sautée, comme chez Kivy. Une partie en cours
  /// s'affiche donc toujours.
  void _restore() {
    final state = replay(_g);
    // La position imposée ne vaut qu'avant le premier coup : dès qu'il y en a,
    // c'est la relecture du serveur qui fait foi.
    final depart = _g.movesText.trim().isEmpty && widget.initialBoard != null
        ? widget.initialBoard!.clone()
        : state.board;
    setState(() {
      _controller = MoveController(
        board: depart,
        turn: state.turn,
        // Les prises des coups déjà joués : sans elles, les panneaux d'une
        // partie en correspondance restaient vides du début à la fin.
        captured: state.captured,
        // Et l'Héritier qui a fugué : la partie est finie, il est dans son
        // ralliement, et c'est la relecture des coups qui le sait.
        fugued: state.fugued,
      );
      // Le dernier coup de l'adversaire reste encadré à l'ouverture.
      _lastMove = state.lastMove;
      _viewingIndex = null;
      _rebuildSteps();
    });
    _animerDernierCoupArrive();

    // Close par l'adversaire pendant notre absence : elle a sa place dans
    // l'historique, et nous sommes peut-être les seuls à pouvoir l'y mettre.
    if (_g.status == CorrStatus.termine) {
      _archive(
        method: _g.method.isEmpty ? 'nulle' : _g.method,
        winner: switch (_g.won) {
          null => null,
          true => _g.myCamp,
          false => _g.opponentCamp,
        },
      );
    }
  }

  /// Rejoue les coups depuis le départ pour retenir chaque position.
  ///
  /// À la lettre, comme partout ailleurs : c'est ce qui garantit que les deux
  /// téléphones reconstruisent la même partie à partir du même texte.
  void _rebuildSteps() {
    var board = _g.movesText.trim().isEmpty && widget.initialBoard != null
        ? widget.initialBoard!.clone()
        : _g.initialBoard;
    final steps = <Board>[board];
    for (final notation in _allMoves()) {
      board = applyNotationLiterally(board, notation).board;
      steps.add(board);
    }
    _steps = steps;
  }

  /// Montre le dernier coup ARRIVÉ en train de se jouer.
  ///
  /// À l'ouverture d'une partie, on tombait directement sur la position : le
  /// coup de l'adversaire s'était joué sans qu'on le voie. Pareil quand il
  /// répond pendant qu'on regarde. Le compte `_dejaAnime` évite de rejouer
  /// notre propre coup quand le serveur nous le renvoie.
  void _animerDernierCoupArrive() {
    final dernier = _steps.length - 1;
    if (dernier <= 0 || dernier <= _dejaAnime) {
      _dejaAnime = dernier;
      return;
    }
    _dejaAnime = dernier;
    _animerCoup(dernier);
  }

  /// Fait glisser les pièces du coup numéro [index] (1 = le premier coup).
  void _animerCoup(int index, {bool recule = false, int? versIndex}) {
    if (index <= 0 || index >= _steps.length) return;
    final avant = _steps[index - 1];
    final apres = _steps[index];
    final notations = _allMoves();
    final notation = index - 1 < notations.length ? notations[index - 1] : '';
    final chemin =
        lastMoveFromNotation(notation, avant, apres)?.jumpPath ??
        const <Cell>[];
    // On saute de plusieurs coups d'un coup : l'animation doit finir sur la
    // position affichée, pas sur celle d'un coup intermédiaire.
    final cible = recule ? (versIndex ?? index - 1) : index;
    final saut = recule && cible != index - 1;
    rememberSlides(
      glisseesDuCoup(
        avant: avant,
        apres: saut ? _steps[cible] : apres,
        notation: saut ? '' : notation,
        recule: recule,
      ),
      jumpPath: saut
          ? const <Cell>[]
          : (recule ? chemin.reversed.toList() : chemin),
    );
  }

  /// Revoir un coup passé, en le montrant se jouer. Le dernier, c'est le
  /// présent : on y revient et la partie redevient jouable.
  void _viewMove(int index) {
    final total = _allMoves().length;
    if (total == 0) return;
    final voulu = index.clamp(0, total - 1);
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
    _sounds.playNotation(_allMoves()[voulu]);
  }

  /// Plateau affiché : celui du coup regardé, ou la position courante.
  Board? get _shownBoard {
    final index = _viewingIndex;
    if (index == null) return _controller?.board;
    return index + 1 < _steps.length ? _steps[index + 1] : _controller?.board;
  }

  /// Mise en évidence du coup affiché.
  LastMove? get _shownLastMove {
    final index = _viewingIndex;
    if (index == null) return _lastMove;
    final notations = _allMoves();
    if (index >= notations.length || index + 1 >= _steps.length) return null;
    return lastMoveFromNotation(
      notations[index],
      _steps[index],
      _steps[index + 1],
    );
  }

  bool get _canPlay =>
      _g.status == CorrStatus.enCours &&
      _g.myTurn &&
      !_played &&
      !_sending &&
      !_isViewing &&
      _controller != null;

  Future<void> _onTapCell(Cell cell) async {
    if (!_canPlay) return;
    final c = _controller!;
    if (!c.moved) _boardBefore = c.board.clone();
    final result = c.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    // Chaque geste glisse au moment où il est fait, comme en Kivy.
    rememberSlides(result.slides, jumpPath: result.jumpPath);
    final notation = result.notation;
    if (notation != null) {
      _lastMove = lastMoveFromNotation(
        notation,
        _boardBefore ?? Board.initial(),
        c.board,
      );
    }
    setState(() {
      // Notre coup entre dans la liste des positions, et il est déjà montré :
      // sans ce compte, la relecture le rejouerait en animation quand le
      // serveur nous le renverra.
      _rebuildSteps();
      _dejaAnime = _steps.length - 1;
    });
    // Le son part après l'écran : le plateau doit répondre au doigt.
    if (notation != null) _sounds.playNotation(notation);

    // Le coup est validé : on l'envoie.
    if (result.notation != null &&
        (result.effect == ControllerEffect.turnEnded ||
            result.effect == ControllerEffect.gameOver)) {
      await _send(result);
    }
  }

  Future<void> _send(ControllerResult result) async {
    setState(() => _sending = true);

    // Un coup qui clôt la partie part AVEC sa méthode : corr_jouer enregistre
    // le coup et clôt la partie en une seule requête. Deux appels séparés
    // ouvriraient la porte aux doubles envois.
    final method = result.effect == ControllerEffect.gameOver
        ? result.endReason
        : null;

    // QUI gagne. Pas forcément celui qui joue : pousser l'Héritier adverse
    // dans son ralliement le fait fuguer — donc gagner — et éjecter le sien
    // est un mat contre soi-même. Le serveur donnait la partie au joueur qui
    // venait de jouer, c'est-à-dire au perdant.
    final winner = result.loser?.opposite;

    final ok = await widget.service.play(
      _g.id,
      result.notation!,
      method: method,
      winner: method == null ? null : winner,
    );
    if (!mounted) return;

    final over = result.effect == ControllerEffect.gameOver;
    setState(() {
      _sending = false;
      _played = ok;
      _finished = ok && over;
    });

    // La partie finie entre dans l'historique du compte, comme toute autre —
    // c'est ce que fait Kivy pour TOUS ses modes depuis le même endroit.
    if (ok && over) {
      _archive(
        method: result.endReason ?? 'nulle',
        winner: result.loser?.opposite,
      );
    }

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(T("Impossible d'envoyer le coup."))),
      );
      return;
    }

    // On RESTE sur la partie : le coup vient d'être joué, on veut voir la
    // position. Le bandeau montre que ce n'est plus à nous, et la pause
    // ramène au menu quand on le décide.
    if (!over) return;

    await showFinishDialog(
      context,
      palette: paletteOf(Settings.instance.themeAxes.general),
      title: T('Partie terminée'),
      body: _verdictOf(result),
      winner: _winnerOf(result),
      onMenu: () {
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  /// Range la partie finie dans l'historique en ligne du compte.
  ///
  /// Une partie par correspondance est une partie EN LIGNE : Kivy lui donne un
  /// identifiant `online_corr<id>` et la range là. Ce port ne le faisait
  /// qu'au départ de l'écran de jeu local — les parties par correspondance
  /// n'entraient donc dans l'historique de personne.
  ///
  /// L'identifiant étant le même pour les deux joueurs, réenregistrer la même
  /// partie ne la duplique pas : elle se remplace.
  void _archive({required String method, required Camp? winner}) {
    if (_archived) return;
    _archived = true;
    unawaited(
      _store.store(
        buildOpponentArchive(
          myPseudo: widget.myPseudo,
          opponent: _g.opponent,
          myCamp: _g.myCamp,
          winner: winner,
          method: method,
          history: _allMoves(),
          objectif: _g.objectif,
          randomCode: _g.randomCode,
          corrGameId: _g.id,
        ),
      ),
    );
  }

  /// Tous les coups de la partie : ceux du serveur, plus celui qu'on vient de
  /// jouer — le serveur l'a reçu, mais notre copie de la partie l'ignore
  /// encore.
  List<String> _allMoves() => [
    ...corrMoveLines(_g.movesText),
    ...?_controller?.history,
  ];

  /// Ce qui s'est passé, en une ligne — mêmes formules que l'écran de jeu.
  String _verdictOf(ControllerResult r) => switch (r.endReason) {
    'fugue' => T('Fugue'),
    'mat' => T('Mat'),
    'papatte' => T('Papatte'),
    'nulle_pat' => T('Trêve : plus aucune pièce carrée ne peut bouger'),
    'repetition' => T('Match nul par répétition'),
    'nulle' => T('Match nul'),
    _ => T('Partie terminée'),
  };

  /// Qui gagne, par son pseudo. Nul : match nul.
  String? _winnerOf(ControllerResult r) {
    final winner = r.loser?.opposite;
    if (winner == null) return null;
    return winner == _g.myCamp ? widget.myPseudo : _g.opponent;
  }

  /// Une réponse à la nulle est en vol : on ne répond pas deux fois.
  bool _repondNulle = false;

  /// Répondre à la nulle proposée par l'adversaire.
  ///
  /// Sans popup : l'offre est dans le bandeau du haut, le plateau reste
  /// entier et l'analyse reste atteignable. C'est tout l'intérêt — on
  /// n'accepte pas une nulle sans avoir pu regarder la position.
  Future<void> _answerDraw(bool accept) async {
    if (_repondNulle) return;
    setState(() => _repondNulle = true);
    try {
      await widget.service.answerDraw(_g.id, accept);
      if (!mounted) return;
      if (accept) {
        Navigator.of(context).pop();
        return;
      }
      // Refusée : le serveur a effacé la proposition, on redemande la partie
      // pour que le bandeau reprenne sa place.
      await _refresh();
    } finally {
      if (mounted) setState(() => _repondNulle = false);
    }
  }

  /// Le ½ est éteint et on vient d'appuyer dessus : dire pourquoi.
  ///
  /// L'infobulle ne suffit pas — elle demande de rester appuyé, et personne
  /// ne le fait. Ici la question est posée au moment où elle se pose.
  Future<void> _expliquerNulle() async {
    final texte = _g.drawToAnswer
        ? T('Répondez d abord à la nulle proposée')
        : T('Jouez votre coup pour pouvoir proposer la nulle');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kFugaGrey,
        content: Text(texte, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(T('Fermer')),
          ),
        ],
      ),
    );
  }

  /// Proposer la nulle. Possible seulement quand on a déjà joué son coup :
  /// tant qu'on a le trait, on joue, on ne négocie pas.
  Future<void> _offerDraw() async {
    if (_offreNulle) return;
    setState(() => _offreNulle = true);
    try {
      await widget.service.offerDraw(_g.id);
      if (mounted) await _refresh();
    } finally {
      if (mounted) setState(() => _offreNulle = false);
    }
  }

  bool _offreNulle = false;

  /// Ai-je déjà joué mon coup ? Le serveur met un temps à le savoir : après
  /// l'envoi, [_played] l'affirme avant que la partie ne revienne.
  bool get _aJoue => _played || !_g.myTurn;

  Future<void> _resign() async {
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
    if (ok != true) return;
    await widget.service.resign(_g.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// Chat de la partie — les deux routes existaient côté serveur sans être
  /// utilisées par l'app Kivy.
  /// La boîte de messages UNIFIÉE avec l'adversaire — `_open_chat`.
  ///
  /// C'est la même conversation partout : depuis le menu, depuis une partie
  /// en direct ou depuis une correspondance. Kivy y tient, et c'est ce qu'on
  /// attend d'une messagerie.
  Future<void> _openChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          online: OnlineService.instance,
          pseudo: _g.opponent,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _onMessages() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final flipped = _flipOverride ?? (_g.myCamp == Camp.blanc);
    final c = _controller;

    return FugaScaffold(
      // Le bandeau touche le HAUT de l'écran, comme en Kivy : en plein
      // écran immersif il n'y a pas de barre d'état à éviter, et la bande
      // laissée au-dessus mangeait de la place au plateau.
      body: SafeArea(
        top: false,
        child: c == null
            ? Column(
                children: [
                  _bar(palette, flipped),
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : GameLayout(
                topBar: _bar(palette, flipped),
                topPanel: _panel(palette, flipped ? Camp.noir : Camp.blanc, c),
                board: GameBoardView(
                  board: _shownBoard ?? c.board,
                  palette: palette,
                  flipped: flipped,
                  onTapCell: _onTapCell,
                  selected: _isViewing ? null : c.selected,
                  groupSelection: _isViewing ? const {} : c.groupSelection,
                  highlighted: _isViewing
                      ? const {}
                      : c.availablePushCells.toSet(),
                  lastMove: _shownLastMove,
                  // La fugue clôt la partie : en revoyant un coup passé,
                  // l'Héritier n'a pas encore rejoint son ralliement.
                  fuguedHeirs: _isViewing ? const {} : c.fuguedHeirs,
                  pieceTheme: axes.pieces,
                  boardTheme: axes.board,
                  slides: slides,
                  slideJumpPath: slideJumpPath,
                  slideToken: slideToken,
                  slideDuration: slideDuration,
                ),
                bottomPanel: _panel(
                  palette,
                  flipped ? Camp.blanc : Camp.noir,
                  c,
                ),
                moveStrip: MoveStrip(
                  // Nos propres coups compris : le bandeau n'affichait que
                  // ceux que le serveur avait déjà renvoyés, donc le dernier
                  // coup joué manquait jusqu'à la relecture suivante.
                  moves: _allMoves(),
                  activeIndex: _viewingIndex,
                  color: _campColor(palette, flipped ? Camp.blanc : Camp.noir),
                  palette: palette,
                  // Les flèches et le bandeau ne faisaient RIEN : on ne
                  // pouvait pas revoir un coup sans quitter la partie.
                  onSelect: _viewMove,
                  randomCode: _g.randomCode.isEmpty ? null : _g.randomCode,
                ),
              ),
      ),
    );
  }

  /// Analyser LA POSITION AFFICHÉE — pas forcément la dernière.
  ///
  /// On part en analyse depuis ce qu'on a sous les yeux : si on revoit le
  /// coup 7 d'une partie qui en compte 20, c'est le coup 7 qu'on veut
  /// examiner, pas le dernier.
  ///
  /// Et l'analyse emporte L'HISTOIRE de la partie jusque-là, pour qu'on
  /// puisse y remonter encore et essayer autre chose. Sans elle, elle
  /// s'ouvrait sur une position orpheline : les flèches ne menaient nulle
  /// part.
  ///
  /// L'IA y est interdite : elle soufflerait le coup d'une partie en cours.
  Future<void> _openAnalysis() async {
    final c = _controller;
    if (c == null) return;
    // Le plateau garde le sens qu'il a ici.
    final flipped = _flipOverride ?? (_g.myCamp == Camp.blanc);
    final coups = _allMoves();
    // Le coup affiché : le dernier quand on ne revoit rien.
    final jusque = ((_viewingIndex ?? coups.length - 1) + 1).clamp(
      0,
      coups.length,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: Cadence.zen,
          aiCamp: null,
          // La position de DÉPART de la partie, Random Fuga compris : les
          // coups qui suivent la rejouent jusqu'à celle qu'on regarde.
          initialBoard: _steps.isEmpty ? null : _steps.first.clone(),
          initialTurn: Camp.blanc,
          initialMoves: coups.take(jusque).toList(),
          analysis: true,
          analysisFromCorr: true,
          initialFlipped: flipped,
          randomCode: _g.randomCode.isEmpty ? null : _g.randomCode,
          themeName: Settings.instance.themeAxes.general,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Couleur d'un camp, vive quand il a le trait.
  Color _campColor(ThemePalette palette, Camp camp) {
    final atTrait =
        _controller?.turn == camp && _g.status == CorrStatus.enCours;
    if (camp == Camp.blanc) return atTrait ? palette.clair : palette.clairDim;
    return atTrait ? palette.fonce : palette.fonceDim;
  }

  /// Le bandeau du haut, tel que Kivy le compose en correspondance.
  Widget _bar(ThemePalette palette, bool flipped) => GameTopBar(
    palette: palette,
    color: _campColor(palette, flipped ? Camp.noir : Camp.blanc),
    onFlip: _toggleFlip,
    onChat: _openChat,
    // La touche Chat ouvre la conversation privée avec l'adversaire : sa
    // pastille s'allume pour un message de LUI, et pour lui seul. La boîte
    // aux lettres est la seule source — le compteur du serveur, lui, reste
    // celui d'avant l'ouverture de la partie.
    unreadChat: OnlineService.instance.messages.unreadFrom(_g.opponent),
    // Kivy garde « Analyser » en correspondance : on peut essayer des coups
    // avant de jouer le sien.
    onAnalyse: _controller == null ? null : _openAnalysis,
    onPause: _openPause,
    // La touche « Retour au menu » apparaît dès que la partie est finie,
    // que ce soit par le serveur ou par le coup qu'on vient de jouer.
    onMenu: (_g.status == CorrStatus.termine || _finished)
        ? () => Navigator.of(context).pop()
        : null,
  );

  /// Retourner le plateau. Mon camp est en bas par défaut.
  bool? _flipOverride;

  void _toggleFlip() => setState(
    () => _flipOverride = !(_flipOverride ?? (_g.myCamp == Camp.blanc)),
  );

  /// La pause d'une partie de correspondance ne propose pas d'abandonner :
  /// on revient au menu, la partie reste en cours sur le serveur.
  Future<void> _openPause() async {
    final leave = await showPauseDialog(
      context,
      palette: paletteOf(Settings.instance.themeAxes.general),
      quit: PauseQuit.menu,
    );
    if (!mounted) return;
    _sounds.applySettings();
    setState(() {});
    if (leave) Navigator.of(context).pop();
  }

  /// Le panneau d'un joueur, comme en partie en ligne. La correspondance n'a
  /// pas de chrono : Kivy y affiche l'infini.
  Widget _panel(ThemePalette palette, Camp camp, MoveController c) {
    final isMine = camp == _g.myCamp;
    final canAct = isMine && _g.status == CorrStatus.enCours && !_played;
    final enCours = _g.status == CorrStatus.enCours;

    // L'adversaire propose la nulle : son panneau cède la place à l'offre.
    // Le plateau reste entier derrière, et l'analyse à portée de touche.
    if (!isMine && enCours && _g.drawToAnswer) {
      return DrawOfferPanel(
        proposer: _g.drawProposer.isEmpty ? _g.opponent : _g.drawProposer,
        palette: palette,
        busy: _repondNulle,
        onAccept: () => unawaited(_answerDraw(true)),
        onRefuse: () => unawaited(_answerDraw(false)),
      );
    }

    return PlayerPanel(
      // Comme en ligne, le mélo suit le nom.
      name: isMine ? widget.myPseudo : '${_g.opponent}  (${_g.opponentMelo})',
      clock: '∞',
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: c.turn == camp && _g.status == CorrStatus.enCours,
      captures: c.captured[camp.opposite] ?? const [],
      photo: isMine
          ? (OnlineService.instance.session?.photo ?? '')
          : _photoAdverse,
      // En correspondance le score est cumulatif, sans objectif fixe : Kivy
      // écrit « X / ... ».
      score: '${isMine ? _g.myScore : _g.opponentScore} / ...',
      mirrored: isMine,
      onNameTap: () => showNameMenu(
        context,
        online: OnlineService.instance,
        pseudo: isMine ? widget.myPseudo : _g.opponent,
      ),
      onUndo: canAct && c.canValidate
          ? () {
              if (c.cancelCurrentMove()) setState(() {});
            }
          : null,
      // Le ½ EXISTE en correspondance — Kivy le cachait. Mais on ne le
      // touche qu'une fois son coup joué : tant qu'on a le trait, on joue.
      // Éteint plutôt que caché, pour qu'on voie qu'il est là et pourquoi
      // il ne répond pas.
      onDraw: (isMine && enCours) ? () => unawaited(_offerDraw()) : null,
      drawEnabled: _aJoue && !_g.drawToAnswer && !_offreNulle,
      onDrawBlocked: _expliquerNulle,
      drawOffered: isMine && _g.drawOfferedByMe,
      onResign: canAct ? _resign : null,
    );
  }
}
