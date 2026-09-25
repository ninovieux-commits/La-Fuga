/// Écran de jeu.
///
/// L'interaction est celle de Kivy : on touche une pièce, on la déplace, on
/// pousse direction par direction ou on compose un groupe, puis on **valide en
/// retouchant la pièce**. Toute la logique vit dans [MoveController] (Dart
/// pur) ; cet écran ne fait que l'afficher et lui transmettre les gestes.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/ai/deep_grey_isolate.dart';
import '../../engine/ai/opening_book.dart';
import '../../engine/ai/weights.dart';
import '../../engine/board.dart';
import '../../engine/move.dart';
import '../../engine/move_generator.dart';
import '../../engine/piece.dart';
import '../../game/clock.dart';
import '../../game/game_archive.dart';
import '../../game/last_move.dart';
import '../../game/match_play.dart';
import '../../game/move_controller.dart';
import '../../game/captures.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../theme/themes.dart';
import '../../state/ai_memory.dart';
import '../../state/settings.dart';
import '../widgets/fuga_background.dart';
import '../widgets/deep_grey_dialog.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_layout.dart';
import '../widgets/end_dialogs.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/move_strip.dart';
import '../widgets/pause_dialog.dart';
import '../widgets/slide_animation.dart';
import '../widgets/player_panel.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.cadence = Cadence.zen,
    this.aiCamp = Camp.noir,
    this.aiDeepMode = false,
    this.themeName = kDefaultTheme,
    this.archive,
    this.memory,
    this.initialBoard,
    this.initialTurn = Camp.blanc,
    this.randomCode,
    this.analysis = false,
    this.analysisFromCorr = false,
    this.objectif = 'partie',
    this.initialFlipped,
  });

  /// Cadence de la partie.
  final Cadence cadence;

  /// Camp joué par Deep Grey ; `null` pour une partie locale à deux.
  final Camp? aiCamp;

  /// Mode profond de l'IA (top 5 à profondeur 2, puis profondeur 3).
  final bool aiDeepMode;

  final String themeName;

  /// Où ranger la partie une fois finie. Injectable pour les tests.
  final GameArchive? archive;

  /// Ce que Deep Grey a appris des parties précédentes. Injectable aussi.
  final AiMemory? memory;

  /// Position de départ, quand elle n'est pas la position standard :
  /// Random Fuga, ou analyse depuis une position rencontrée.
  final Board? initialBoard;

  /// Camp au trait dans cette position.
  final Camp initialTurn;

  /// Code de la position tirée au sort, à inscrire dans le `.nmc`. Sans lui,
  /// la partie serait irrejouable.
  final String? randomCode;

  /// Mode analyse : pas de chrono, pas de répétition, et rien n'est archivé —
  /// on explore.
  final bool analysis;

  /// Analyse ouverte depuis une partie de correspondance EN COURS. Deep Grey
  /// y est alors interdit : il soufflerait le coup à jouer.
  final bool analysisFromCorr;

  /// `partie` pour une partie unique, sinon le nombre de points du match.
  final String objectif;

  /// Sens du plateau à l'ouverture. Nul : les Blancs en bas, sauf si l'humain
  /// a les Noirs.
  ///
  /// L'analyse le reçoit de l'écran d'où elle vient : on y arrive pour
  /// réfléchir à la position qu'on a sous les yeux, et la voir se retourner
  /// oblige à tout relire à l'envers.
  final bool? initialFlipped;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SlideAnimation {
  late MoveController _game;
  late GameClock _clock;
  late FugaMatch _match;

  /// Camp de Deep Grey. Il change d'une partie à l'autre du match, puisque
  /// les couleurs alternent.
  Camp? _aiCamp;
  final DeepGreyEngine _engine = DeepGreyEngine();
  final SoundPlayer _sounds = SoundPlayer();
  late final GameArchive _archive = widget.archive ?? GameArchive();
  late final AiMemory _memory = widget.memory ?? AiMemory();

  /// Poids et livre d'ouvertures, chargés au lancement de la partie.
  DeepGreyWeights? _weights;
  OpeningBook? _book;

  /// Manœuvres de groupe jouées d'affilée par l'IA.
  int _consecutiveManeuvers = 0;

  /// Une partie ne s'archive qu'une fois, quel que soit le chemin par lequel
  /// elle se termine.
  bool _archived = false;

  /// Configurations de pièces déjà vues par l'IA : alimente sa pénalité anti
  /// allers-retours.
  final Map<String, int> _aiPositionCounts = {};

  LastMove? _lastMove;

  /// Score du match, affiché sous le verdict.
  String? _matchVerdict;

  /// Qui tiendra les Blancs à la partie suivante, quand le match continue.
  String? _nextGameFor;

  /// La partie suivante est l'ultime accordée au retardataire : Kivy le dit
  /// dans le titre du popup.
  bool _nextIsLastChance = false;

  /// Positions traversées depuis le début de la partie. Sert à revoir les
  /// coups passés sans quitter la partie, comme en Kivy.
  final List<Board> _snapshots = [];

  /// Coup regardé, ou `null` quand on est au présent.
  int? _viewingIndex;

  bool get _isViewing => _viewingIndex != null;

  /// Le plateau montré : la position regardée, ou celle de la partie.
  Board get _shownBoard =>
      _isViewing ? _snapshots[_viewingIndex! + 1] : _game.board;

  /// Mode profond de Deep Grey, basculable en cours de partie.
  late bool _deepMode = widget.aiDeepMode;

  /// Orientation choisie à la main par le bouton « < > », si elle l'a été —
  /// ou celle reçue de l'écran d'où l'on vient.
  late bool? _flipOverride = widget.initialFlipped;

  /// Orientation par défaut : les Blancs en bas, sauf si l'humain a les Noirs.
  bool get _defaultFlip => _aiCamp != Camp.blanc;

  bool get _flipped => _flipOverride ?? _defaultFlip;
  bool _thinking = false;
  String? _verdict;

  /// Nom du vainqueur de la dernière partie, pour le popup de fin.
  String? _lastWinner;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _aiCamp = widget.aiCamp;
    _match = FugaMatch(
      playerA: _players.$1,
      playerB: _players.$2,
      target: widget.analysis ? 'partie' : widget.objectif,
      firstBlanc: _playerOf(Camp.blanc),
    );
    _game = _newGame();
    _snapshots
      ..clear()
      ..add(_game.board.clone());
    _clock = GameClock(widget.analysis ? Cadence.zen : widget.cadence);
    if (_aiCamp != null) {
      _engine.start();
      _loadAiMemory();
    }
    _sounds.init();
    _startTicking();

    // Deep Grey ouvre la partie quand c'est lui qui a les Blancs. Kivy le
    // fait par `_maybe_ai_turn` après chaque nouvelle partie, avec un court
    // délai pour que le plateau s'affiche d'abord.
    if (_isAiTurn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playAi();
      });
    }
  }

  /// Charge ce que Deep Grey a appris. La partie peut commencer avant : sans
  /// cette mémoire, l'IA joue simplement avec ses poids par défaut.
  Future<void> _loadAiMemory() async {
    final weights = await _memory.weights();
    final book = await _memory.book();
    if (!mounted) return;
    setState(() {
      _weights = weights;
      _book = book;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _seconds.dispose();
    _sounds.dispose();
    _engine.dispose();
    super.dispose();
  }

  /// Le chrono tourne tant que la partie n'est pas finie — et **même en
  /// pause**, comme en Kivy : mettre en pause ne doit pas offrir du temps de
  /// réflexion supplémentaire.
  void _startTicking() {
    if (_clock.isUnlimited) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _game.gameOver) return;
      final loser = _clock.tick(_game.turn);
      if (loser == null) {
        // Une seconde qui passe ne concerne que les deux chronos : on ne
        // reconstruit pas tout l'écran pour elle.
        _seconds.value++;
        return;
      }
      setState(() {
        _finish(
          'temps',
          loser,
          '${T("Temps écoulé")} — ${_campLabel(loser.opposite)} ${T("gagne")}',
        );
      });
    });
  }

  /// Avance à chaque seconde : seuls les panneaux l'écoutent.
  final ValueNotifier<int> _seconds = ValueNotifier(0);

  /// Un panneau qui se refait à chaque seconde, et lui seul.
  Widget _tickingPanel(
    ThemePalette palette,
    Camp camp, {
    required bool mirrored,
  }) => ValueListenableBuilder<int>(
    valueListenable: _seconds,
    builder: (context, _, __) =>
        _playerPanel(palette, camp, mirrored: mirrored),
  );

  MoveController _newGame() => MoveController(
    board: widget.initialBoard?.clone(),
    turn: widget.initialTurn,
    countRepetitions: !widget.analysis,
  );

  bool get _isAiTurn => _aiCamp != null && _game.turn == _aiCamp;

  bool get _canPlay {
    if (_thinking || _isAiTurn) return false;
    // En analyse, toucher le plateau depuis une position passée repart de
    // là — même si la partie s'était terminée plus loin.
    if (_isViewing) return widget.analysis;
    return !_game.gameOver;
  }

  void _onTapCell(Cell cell) {
    if (!_canPlay) return;
    // On explorait le passé : les coups d'après sont oubliés et la partie
    // reprend ici. C'est tout l'intérêt d'une analyse — essayer autre chose.
    if (_isViewing) _branchFromViewed();
    final result = _game.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    // Kivy anime CHAQUE geste au moment où il est fait : le déplacement, le
    // saut, la manœuvre et chaque poussée. Attendre la validation du coup ne
    // ferait glisser que les coups de Deep Grey.
    rememberSlides(result.slides);
    setState(() {
      // Un coup joué annule les propositions de nulle en cours.
      if (result.notation != null) {
        _rememberLastMove(result);
        _resetDrawOffers();
      }
      if (result.effect == ControllerEffect.gameOver) {
        _finish(
          result.endReason ?? 'nulle',
          result.loser,
          _verdictText(result),
        );
      }
    });

    // Le son part APRÈS l'écran : c'est le plateau qui doit répondre au
    // doigt, pas l'inverse.
    if (result.notation != null) _sounds.playNotation(result.notation);

    if (result.effect == ControllerEffect.turnEnded && _isAiTurn) {
      _playAi();
    }
  }

  /// Retient de quoi mettre en évidence le coup qui vient d'être joué.
  ///
  /// La mise en évidence se reconstruit depuis la NOTATION, comme
  /// `_record_move` chez Kivy : c'est la même pour un coup joué au doigt, un
  /// coup de Deep Grey, un coup reçu du réseau ou un coup relu d'un `.nmc`.
  void _rememberLastMove(ControllerResult result) {
    rememberSlides(result.slides);
    _lastMove = lastMoveFromNotation(
      result.notation!,
      _snapshots.last,
      _game.board,
    );
    _snapshots.add(_game.board.clone());
  }

  /// Reprend la partie à la position regardée : les coups d'après sont
  /// oubliés, et on repart d'ici.
  ///
  /// Réservé à l'analyse. Sans cela, reculer d'un coup enfermait dans la
  /// suite déjà jouée : on pouvait la relire, jamais essayer autre chose.
  ///
  /// Le contrôleur est reconstruit sur la position regardée, avec les coups
  /// gardés pour le bandeau et les prises recomptées depuis les positions
  /// traversées — un contrôleur neuf croirait qu'aucune pièce n'est sortie.
  void _branchFromViewed() {
    final index = _viewingIndex;
    if (index == null) return;

    final kept = _game.history.sublist(0, index + 1);
    final boards = _snapshots.sublist(0, index + 2);
    final turn = kept.length.isEven
        ? widget.initialTurn
        : widget.initialTurn.opposite;

    final captured = <Camp, List<Piece>>{Camp.blanc: [], Camp.noir: []};
    for (var i = 0; i < kept.length; i++) {
      for (final piece in ejectedBetween(boards[i], boards[i + 1], kept[i])) {
        captured[piece.camp]!.add(piece);
      }
    }

    final game = MoveController(
      board: boards.last.clone(),
      turn: turn,
      countRepetitions: false,
      captured: captured,
    );
    game.history.addAll(kept);

    _game = game;
    _snapshots
      ..clear()
      ..addAll(boards);
    _lastMove = lastMoveFromNotation(kept.last, boards[index], boards.last);
    _viewingIndex = null;
    // La partie n'est plus finie : on vient d'en rouvrir le cours.
    _verdict = null;
    _lastWinner = null;
    _nextGameFor = null;
    _resetDrawOffers();
  }

  /// Revoir un coup passé. Le dernier coup, c'est le présent.
  void _viewMove(int? index) => setState(() {
    final wanted = index?.clamp(0, _game.history.length - 1);
    _viewingIndex = wanted == _game.history.length - 1 ? null : wanted;
  });

  Future<void> _playAi() async {
    final aiCamp = _aiCamp;
    if (aiCamp == null) return;
    setState(() => _thinking = true);

    final result = await _engine.think(
      board: _game.board,
      camp: aiCamp,
      deepMode: _deepMode,
      moveNumber: _game.history.length + 1,
      seenPositions: _aiPositionCounts,
      weights: _weights,
      bookMove: _book?.lookup(_game.board, aiCamp),
      avoidManeuver: _consecutiveManeuvers >= 2,
    );
    if (!mounted) return;

    if (!result.hasMove) {
      setState(() {
        _thinking = false;
        _finish(
          'papatte',
          aiCamp,
          '${T("Papatte")} — ${_campLabel(aiCamp.opposite)} ${T("gagne")}',
        );
      });
      return;
    }

    // L'isolate renvoie le plateau résultant ; on retrouve l'objet Move
    // correspondant, car les conditions de fin de partie en dépendent.
    //
    // Si on ne le retrouve pas — plateau reparti entre-temps, réponse d'une
    // recherche annulée — on ne joue RIEN plutôt que de tomber. Une partie ne
    // doit jamais se fermer sur une exception.
    final board = result.board;
    final move = board == null
        ? null
        : _moveMatching(Board.fromJson(board).key, aiCamp);
    if (move == null) {
      setState(() => _thinking = false);
      return;
    }
    final pushTargets = [for (final c in result.pushTargets) Cell(c[0], c[1])];

    _consecutiveManeuvers = move.kind == MoveKind.maneuver
        ? _consecutiveManeuvers + 1
        : 0;

    final applied = _game.applyGeneratedMove(move, pushTargets: pushTargets);
    final key = _game.board.ownPiecesKey(aiCamp);
    _aiPositionCounts[key] = (_aiPositionCounts[key] ?? 0) + 1;

    setState(() {
      _thinking = false;
      _rememberLastMove(applied);
      if (applied.effect == ControllerEffect.gameOver) {
        _finish(
          applied.endReason ?? 'nulle',
          applied.loser,
          _verdictText(applied),
        );
      }
    });
    _sounds.playNotation(applied.notation);
  }

  /// Le coup légal qui mène à cette position, s'il existe encore.
  Move? _moveMatching(String wantedKey, Camp camp) {
    for (final move in generateMoves(_game.board, camp)) {
      if (move.board.key == wantedKey) return move;
    }
    return null;
  }

  /// Les deux joueurs, dans l'ordre d'affichage — portage de `_players`.
  ///
  /// Contre Deep Grey, l'humain porte son pseudo quand il est connecté : son
  /// historique de compte doit être à son nom.
  late final (String, String) _players = widget.aiCamp == null
      ? ('Joueur 1', 'Joueur 2')
      : (OnlineService.instance.pseudo ?? 'Joueur 1', 'deep grey');

  /// Nom du joueur qui tient [camp].
  String _playerOf(Camp camp) {
    final (first, second) = _players;
    // Deep Grey tient son camp ; en local, Joueur 1 commence avec les Blancs.
    final blancIsFirst = _aiCamp != Camp.blanc;
    return (camp == Camp.blanc) == blancIsFirst ? first : second;
  }

  /// Termine la partie : verdict à l'écran, marque de fin sur le dernier coup,
  /// puis archivage. À appeler depuis un `setState`.
  void _finish(String method, Camp? loser, String verdict) {
    _verdict = verdict;
    _game.gameOver = true;
    _lastWinner = loser == null ? null : _playerOf(loser.opposite);

    final end = nmcMethod(method);
    final marked = withEndSuffix(_game.history, end);
    if (!identical(marked, _game.history)) {
      _game.history
        ..clear()
        ..addAll(marked);
    }

    // En analyse, rien n'est enregistré et l'IA n'apprend pas : ce n'est pas
    // une partie.
    if (_archived || widget.analysis) return;
    _archived = true;
    if (loser != null) unawaited(_learn(loser.opposite));
    _recordPoint(method, loser);
    _announceEnd();
    final (first, second) = _players;
    unawaited(
      _archive.store(
        buildArchive(
          player1: first,
          player2: second,
          blanc: _playerOf(Camp.blanc),
          winner: loser == null ? null : _playerOf(loser.opposite),
          method: method,
          history: List.of(_game.history),
          cadence: widget.cadence.wire,
          randomCode: widget.randomCode,
        ),
      ),
    );
  }

  /// Inscrit le point au match et, si le match continue, propose la partie
  /// suivante — couleurs inversées, comme en Kivy.
  void _recordPoint(String method, Camp? loser) {
    final step = _match.record(
      winner: loser == null ? null : _playerOf(loser.opposite),
      points: pointsForMethod(nmcMethod(method)),
    );
    if (step.outcome == MatchOutcome.singleGame) return;

    _matchVerdict = step.outcome == MatchOutcome.over
        ? '${step.winner} ${T("gagne le match")} — ${_match.scoreLine}'
        : _match.scoreLine;
    _nextGameFor = step.outcome == MatchOutcome.next
        ? step.nextFirstBlanc
        : null;
    _nextIsLastChance = step.lastChance;
  }

  /// Lance la partie suivante du match : les Blancs changent de main, donc
  /// Deep Grey aussi change de camp.
  void _startNextGame(String nextFirstBlanc) {
    _match.startNext(nextFirstBlanc);
    setState(() {
      if (_aiCamp != null) {
        _aiCamp = nextFirstBlanc == 'deep grey' ? Camp.blanc : Camp.noir;
      }
      _nextGameFor = null;
      _restartState();
    });
    if (_isAiTurn) _playAi();
  }

  /// Deep Grey apprend de la partie qui vient de finir.
  ///
  /// Les poids s'ajustent à chaque partie, gagnée ou perdue. Le livre
  /// d'ouvertures, lui, ne retient que les coups de celui qui a **battu**
  /// l'IA : c'est ainsi qu'elle progresse contre ce qui l'a mise en défaut.
  Future<void> _learn(Camp winner) async {
    if (_aiCamp == null) return;

    final weights = _weights ?? await _memory.weights();
    await _memory.saveWeights(weights.learn(winner, _game.board));

    if (winner == _aiCamp) return;
    final book = _book ?? await _memory.book();
    final learned = book.recordWinningLine(
      initialBoard: Board.initial(),
      moves: List.of(_game.history),
      winner: winner,
    );
    if (learned) await _memory.saveBook(book);
  }

  String _campLabel(Camp camp) => camp == Camp.blanc ? T('Blanc') : T('Noir');

  String _verdictText(ControllerResult r) {
    final winner = r.loser?.opposite;
    // Sans gagnant identifié, on annonce la raison sans nommer personne :
    // mieux vaut une phrase incomplète qu'une partie qui se ferme.
    String won(String reason) => winner == null
        ? T(reason)
        : '${T(reason)} — ${_campLabel(winner)} ${T("gagne")}';
    return switch (r.endReason) {
      'fugue' => won('Fugue'),
      'mat' => won('Mat'),
      'papatte' => won('Papatte'),
      'nulle_pat' => T('Trêve : plus aucune pièce carrée ne peut bouger'),
      'repetition' => T('Match nul par répétition'),
      'nulle' => T('Match nul'),
      _ => T('Partie terminée'),
    };
  }

  void _restartState() {
    _game = _newGame();
    _snapshots
      ..clear()
      ..add(_game.board.clone());
    _viewingIndex = null;
    _clock.reset();
    _aiPositionCounts.clear();
    _consecutiveManeuvers = 0;
    _lastMove = null;
    _verdict = null;
    _archived = false;
    _thinking = false;
  }

  /// Abandon — portage du bouton X. Deux points pour l'adversaire.
  ///
  /// Contre Deep Grey, c'est l'humain qui abandonne, même si c'est à l'IA de
  /// jouer : le bouton n'appartient qu'à lui.
  Future<void> _abandon(Camp quitter) async {
    final confirmed = await _confirm(
      T(
        '{name} confirme abandonner. L\'adversaire marquera 2 points.',
      ).replaceAll('{name}', _playerOf(quitter)),
      T('Oui, abandonner'),
    );
    if (!confirmed || !mounted) return;

    setState(
      () => _finish(
        'abandon',
        quitter,
        '${T("Abandon")} — ${_campLabel(quitter.opposite)} ${T("gagne")}',
      ),
    );
  }

  /// Proposition de nulle en local — portage de `_toggle_draw_offer`.
  ///
  /// Chaque camp a son ½ : il s'allume quand ce camp propose, et quand les
  /// deux sont allumés la partie est nulle par accord mutuel. Un coup joué
  /// remet les deux propositions à zéro (`_reset_draw_offers`).
  void _toggleDrawOffer(Camp camp) {
    setState(() {
      _drawOffers[camp] = !(_drawOffers[camp] ?? false);
      if (_drawOffers[Camp.blanc] == true && _drawOffers[Camp.noir] == true) {
        _drawOffers[Camp.blanc] = false;
        _drawOffers[Camp.noir] = false;
        _finish('nulle_accord', null, T('Partie nulle'));
      }
    });
  }

  /// Propositions de nulle en cours, par camp.
  final Map<Camp, bool> _drawOffers = {Camp.blanc: false, Camp.noir: false};

  void _resetDrawOffers() {
    _drawOffers[Camp.blanc] = false;
    _drawOffers[Camp.noir] = false;
  }

  Future<bool> _confirm(String message, String action) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  void _cancelMove() {
    if (!_canPlay) return;
    if (_game.cancelCurrentMove()) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(widget.themeName);
    final flipped = _flipped;

    final topCamp = flipped ? Camp.noir : Camp.blanc;
    final bottomCamp = flipped ? Camp.blanc : Camp.noir;

    return FugaScaffold(
      // Le bandeau touche le HAUT de l'écran, comme en Kivy : en plein
      // écran immersif il n'y a pas de barre d'état à éviter, et la bande
      // laissée au-dessus mangeait de la place au plateau.
      body: SafeArea(
        top: false,
        child: GameLayout(
          topBar: _topBar(palette, topCamp),
          // Pas de bandeaux en analyse : leur absence dit qu'on explore une
          // position au lieu de jouer une partie, et le plateau y gagne leur
          // place.
          topPanel: widget.analysis
              ? null
              : _tickingPanel(palette, topCamp, mirrored: false),
          board: GameBoardView(
            board: _shownBoard,
            palette: palette,
            flipped: flipped,
            onTapCell: _onTapCell,
            selected: _isViewing ? null : _game.selected,
            groupSelection: _isViewing ? const {} : _game.groupSelection,
            highlighted: _isViewing
                ? const {}
                : _game.availablePushCells.toSet(),
            lastMove: _isViewing ? null : _lastMove,
            pieceTheme: axes.pieces,
            boardTheme: axes.board,
            slides: slides,
            slideToken: slideToken,
            slideDuration: slideDuration,
          ),
          bottomPanel: widget.analysis
              ? null
              : _tickingPanel(palette, bottomCamp, mirrored: true),
          moveStrip: MoveStrip(
            moves: _game.history,
            activeIndex: _viewingIndex,
            color: _campColor(palette, bottomCamp),
            palette: palette,
            randomCode: widget.randomCode,
            onSelect: _viewMove,
          ),
        ),
      ),
    );
  }

  /// Couleur d'un camp, vive quand il a le trait — `vif` / `terne` de
  /// `_refresh_ui_no_board`.
  Color _campColor(ThemePalette palette, Camp camp) {
    final atTrait = _game.turn == camp && !_game.gameOver;
    if (camp == Camp.blanc) return atTrait ? palette.clair : palette.clairDim;
    return atTrait ? palette.fonce : palette.fonceDim;
  }

  /// Barre du haut — portage de `top_bar`. « Retour au menu » n'apparaît
  /// qu'une fois la partie finie : en cours de partie, on passe par la pause.
  Widget _topBar(ThemePalette palette, Camp topCamp) => GameTopBar(
    palette: palette,
    color: _campColor(palette, topCamp),
    onFlip: () =>
        setState(() => _flipOverride = !(_flipOverride ?? _defaultFlip)),
    // En analyse, il n'y a rien à suspendre : la touche ramène au menu.
    pauseLabel: widget.analysis ? '<<' : '| |',
    onPause: widget.analysis ? () => Navigator.of(context).pop() : _openPause,
    onMenu: _game.gameOver ? () => Navigator.of(context).pop() : null,
    // Reprendre la position affichée contre Deep Grey : Kivy l'offre en
    // analyse comme en relecture.
    onDeepGrey: widget.analysis && !widget.analysisFromCorr
        ? _playFromPosition
        : null,
    aiDeepMode: _deepMode,
    onToggleAiMode: _aiCamp == null
        ? null
        : () => setState(() => _deepMode = !_deepMode),
  );

  /// Reprendre la position affichée contre Deep Grey. Le camp au trait ne
  /// change pas : choisir l'autre couleur fait jouer l'IA en premier.
  Future<void> _playFromPosition() async {
    final mine = await askDeepGreyCamp(context);
    if (mine == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: Cadence.zen,
          aiCamp: mine.opposite,
          initialBoard: _shownBoard.clone(),
          initialTurn: _game.turn,
          themeName: widget.themeName,
        ),
      ),
    );
  }

  /// La pause. Le chrono continue : `_tick` ne s'arrête pas.
  Future<void> _openPause() async {
    final left = await showPauseDialog(
      context,
      palette: paletteOf(widget.themeName),
    );
    if (!mounted) return;
    // Les réglages s'ouvrent depuis la pause : instrument et volume ont pu
    // changer, et le changement doit s'entendre dès le coup suivant.
    _sounds.applySettings();
    setState(() {});
    if (left) Navigator.of(context).pop();
  }

  /// Panneau d'un joueur. Les trois gestes (↶ ½ X) ne s'affichent que du
  /// côté qui peut s'en servir, comme en Kivy : pas de nulle contre Deep
  /// Grey, et rien de tout cela en analyse ni en regardant le passé.
  Widget _playerPanel(
    ThemePalette palette,
    Camp camp, {
    required bool mirrored,
  }) {
    final isAi = _aiCamp == camp;
    final mine = !isAi;
    final canAct = mine && !widget.analysis && !_game.gameOver && !_isViewing;

    return PlayerPanel(
      name: isAi ? 'Deep Grey' : _playerOf(camp),
      clock: _clock.displayFor(camp),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _game.turn == camp && !_game.gameOver,
      captures: _game.captured[camp.opposite] ?? const [],
      photo: isAi ? 'deepgrey' : (OnlineService.instance.session?.photo ?? ''),
      // Kivy affiche toujours le score, dénominateur compris : « 0 / 1 »
      // pour une partie unique, « 0 / 5 » pour un match en cinq points.
      score:
          '${_match.scores[_playerOf(camp)] ?? 0} / '
          '${widget.objectif == 'partie' ? '1' : widget.objectif}',
      busy: isAi && _thinking,
      mirrored: mirrored,
      onUndo: canAct && _game.canValidate ? _cancelMove : null,
      onDraw: canAct && _aiCamp == null ? () => _toggleDrawOffer(camp) : null,
      drawOffered: _drawOffers[camp] ?? false,
      onResign: canAct ? () => _abandon(camp) : null,
    );
  }

  /// Fin de partie : Kivy ouvre un popup. S'il reste des parties au match,
  /// il propose la suivante ; sinon il annonce le vainqueur et ramène au
  /// menu. Dans les deux cas la touche « Retour au menu » du bandeau vient
  /// d'apparaître, pour qu'on puisse fermer le popup et regarder la position.
  void _announceEnd() {
    final palette = paletteOf(widget.themeName);
    final verdict = _verdict ?? T('Partie terminée');
    final next = _nextGameFor;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next != null) {
        unawaited(
          showContinueDialog(
            context,
            palette: palette,
            // La clé de traduction de Kivy porte le séparateur.
            title: _nextIsLastChance
                ? verdict +
                      T(
                        '  •  Ultime partie pour {loser}',
                      ).replaceAll('{loser}', next)
                : verdict,
            body: _match.scoreLine,
            nextFirstBlanc: next,
            onNext: () => _startNextGame(next),
          ),
        );
        return;
      }
      unawaited(
        showFinishDialog(
          context,
          palette: palette,
          title: verdict,
          body: _matchVerdict ?? _match.scoreLine,
          winner: _lastWinner,
          onMenu: () {
            if (mounted) Navigator.of(context).pop();
          },
        ),
      );
    });
  }
}
