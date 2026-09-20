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
import '../../game/match_play.dart';
import '../../game/move_controller.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../theme/themes.dart';
import '../../state/ai_memory.dart';
import '../../state/settings.dart';
import '../widgets/game_board_view.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.cadence = Cadence.illimitee,
    this.aiCamp = Camp.noir,
    this.aiDeepMode = false,
    this.themeName = kDefaultTheme,
    this.archive,
    this.memory,
    this.initialBoard,
    this.initialTurn = Camp.blanc,
    this.randomCode,
    this.analysis = false,
    this.objectif = 'partie',
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

  /// `partie` pour une partie unique, sinon le nombre de points du match.
  final String objectif;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
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

  Set<Cell> _lastMoveCells = {};

  /// Score du match, affiché sous le verdict.
  String? _matchVerdict;

  /// Qui tiendra les Blancs à la partie suivante, quand le match continue.
  String? _nextGameFor;
  bool _thinking = false;
  int? _lastThinkMicros;
  String? _verdict;
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
    _clock = GameClock(widget.analysis ? Cadence.illimitee : widget.cadence);
    if (_aiCamp != null) {
      _engine.start();
      _loadAiMemory();
    }
    _sounds.init();
    _startTicking();
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
      setState(() {
        if (loser != null) {
          _finish(
            'temps',
            loser,
            '${T("Temps écoulé")} — ${_campLabel(loser.opposite)} ${T("gagne")}',
          );
        }
      });
    });
  }

  MoveController _newGame() => MoveController(
    board: widget.initialBoard?.clone(),
    turn: widget.initialTurn,
    countRepetitions: !widget.analysis,
  );

  bool get _isAiTurn => _aiCamp != null && _game.turn == _aiCamp;

  bool get _canPlay => !_game.gameOver && !_thinking && !_isAiTurn;

  void _onTapCell(Cell cell) {
    if (!_canPlay) return;
    final result = _game.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    if (result.notation != null) {
      _sounds.playNotation(result.notation, hadEjection: result.hadEjection);
    }
    setState(() {
      if (result.notation != null) _rememberLastMove(result);
      if (result.effect == ControllerEffect.gameOver) {
        _finish(
          result.endReason ?? 'nulle',
          result.loser,
          _verdictText(result),
        );
      }
    });

    if (result.effect == ControllerEffect.turnEnded && _isAiTurn) {
      _playAi();
    }
  }

  void _rememberLastMove(ControllerResult result) {
    _lastMoveCells = {
      for (final (_, from, to) in result.slides) ...[from, to],
    }..removeWhere((c) => !c.onBoard);
  }

  Future<void> _playAi() async {
    final aiCamp = _aiCamp;
    if (aiCamp == null) return;
    setState(() => _thinking = true);

    final result = await _engine.think(
      board: _game.board,
      camp: aiCamp,
      deepMode: widget.aiDeepMode,
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
    final resultKey = Board.fromJson(result.board!).key;
    final move = generateMoves(
      _game.board,
      aiCamp,
    ).firstWhere((m) => m.board.key == resultKey);
    final pushTargets = [for (final c in result.pushTargets) Cell(c[0], c[1])];

    _consecutiveManeuvers = move.kind == MoveKind.maneuver
        ? _consecutiveManeuvers + 1
        : 0;

    final applied = _game.applyGeneratedMove(move, pushTargets: pushTargets);
    final key = _game.board.ownPiecesKey(aiCamp);
    _aiPositionCounts[key] = (_aiPositionCounts[key] ?? 0) + 1;

    _sounds.playNotation(applied.notation, hadEjection: applied.hadEjection);
    setState(() {
      _thinking = false;
      _lastThinkMicros = result.elapsedMicros;
      _rememberLastMove(applied);
      if (applied.effect == ControllerEffect.gameOver) {
        _finish(
          applied.endReason ?? 'nulle',
          applied.loser,
          _verdictText(applied),
        );
      }
    });
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
          cadence: widget.cadence.label,
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
    return switch (r.endReason) {
      'fugue' => '${T("Fugue")} — ${_campLabel(winner!)} ${T("gagne")}',
      'mat' => '${T("Mat")} — ${_campLabel(winner!)} ${T("gagne")}',
      'papatte' => '${T("Papatte")} — ${_campLabel(winner!)} ${T("gagne")}',
      'nulle_pat' => T('Trêve : plus aucune pièce carrée ne peut bouger'),
      'repetition' => T('Match nul par répétition'),
      'nulle' => T('Match nul'),
      _ => T('Partie terminée'),
    };
  }

  void _restart() {
    _sounds.stopAll();
    setState(_restartState);
  }

  void _restartState() {
    _game = _newGame();
    _clock.reset();
    _aiPositionCounts.clear();
    _consecutiveManeuvers = 0;
    _lastMoveCells = {};
    _game = _newGame();
    _clock.reset();
    _aiPositionCounts.clear();
    _consecutiveManeuvers = 0;
    _lastMoveCells = {};
    _verdict = null;
    _archived = false;
    _thinking = false;
    _lastThinkMicros = null;
  }

  /// Abandon — portage du bouton X. Deux points pour l'adversaire.
  ///
  /// Contre Deep Grey, c'est l'humain qui abandonne, même si c'est à l'IA de
  /// jouer : le bouton n'appartient qu'à lui.
  Future<void> _abandon() async {
    final ai = _aiCamp;
    final quitter = ai == null ? _game.turn : ai.opposite;
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

  /// Nulle par accord — portage du bouton ½, réservé aux parties à deux
  /// joueurs : on ne négocie pas avec Deep Grey.
  Future<void> _agreeDraw() async {
    final confirmed = await _confirm(
      T('Nulle par accord mutuel.\nAucun point accordé.'),
      T('Accepter'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _finish('nulle_accord', null, T('Partie nulle')));
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
    // Les Blancs sont en bas, sauf si le joueur humain tient les Noirs.
    final flipped = _aiCamp != Camp.blanc;

    return Scaffold(
      backgroundColor: palette.menu,
      body: SafeArea(
        child: Column(
          children: [
            _playerBanner(palette, flipped ? Camp.noir : Camp.blanc),
            Expanded(
              child: GameBoardView(
                board: _game.board,
                palette: palette,
                flipped: flipped,
                onTapCell: _onTapCell,
                selected: _game.selected,
                groupSelection: _game.groupSelection,
                highlighted: _game.availablePushCells.toSet(),
                lastMoveCells: _lastMoveCells,
                pieceTheme: axes.pieces,
                boardTheme: axes.board,
              ),
            ),
            _playerBanner(palette, flipped ? Camp.blanc : Camp.noir),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  Widget _playerBanner(ThemePalette palette, Camp camp) {
    return PlayerBanner(
      label: _aiCamp == camp ? 'Deep Grey' : _campLabel(camp),
      clock: _clock.displayFor(camp),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _game.turn == camp && !_game.gameOver,
      busy: _aiCamp == camp && _thinking,
    );
  }

  Widget _actionBar() {
    final last = _game.history.isEmpty ? '—' : _game.history.last;
    final next = _nextGameFor;
    final think = _lastThinkMicros == null
        ? ''
        : '  ·  ${(_lastThinkMicros! / 1000).round()} ms';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: Colors.black38,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _verdict == null
                  ? (_game.canValidate
                        ? T('Retouchez la pièce pour valider')
                        : '${_game.history.length} · $last$think')
                  // En match, le score suit le verdict de la partie.
                  : [_verdict, _matchVerdict].nonNulls.join('  ·  '),
              style: TextStyle(
                color: _verdict != null ? Colors.white : Colors.white70,
                fontWeight: _verdict != null
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: T('< Menu'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          // ½ et X : les gestes de Kivy, aux mêmes conditions — pas de nulle
          // par accord contre Deep Grey, et rien de tout cela en analyse.
          if (!widget.analysis && !_game.gameOver && _aiCamp == null)
            IconButton(
              icon: const Text('½', style: TextStyle(fontSize: 18)),
              tooltip: T('Proposer nulle'),
              onPressed: _agreeDraw,
            ),
          if (!widget.analysis && !_game.gameOver)
            IconButton(
              icon: const Icon(Icons.flag_outlined, size: 20),
              tooltip: T('Abandonner'),
              onPressed: _abandon,
            ),
          if (_game.canValidate)
            TextButton(onPressed: _cancelMove, child: Text(T('Annuler'))),
          if (next != null)
            TextButton(
              onPressed: () => _startNextGame(next),
              child: Text(T('Partie suivante')),
            )
          else
            TextButton(onPressed: _restart, child: Text(T('Nouvelle partie'))),
        ],
      ),
    );
  }
}
