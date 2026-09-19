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

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late MoveController _game;
  late GameClock _clock;
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
  bool _thinking = false;
  int? _lastThinkMicros;
  String? _verdict;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _game = MoveController();
    _clock = GameClock(widget.cadence);
    if (widget.aiCamp != null) {
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

  bool get _isAiTurn => widget.aiCamp != null && _game.turn == widget.aiCamp;

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
    final aiCamp = widget.aiCamp;
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
    // Deep Grey tient son camp ; en local, Joueur 1 a les Blancs.
    final blancIsFirst = widget.aiCamp != Camp.blanc;
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

    if (_archived) return;
    _archived = true;
    if (loser != null) unawaited(_learn(loser.opposite));
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
        ),
      ),
    );
  }

  /// Deep Grey apprend de la partie qui vient de finir.
  ///
  /// Les poids s'ajustent à chaque partie, gagnée ou perdue. Le livre
  /// d'ouvertures, lui, ne retient que les coups de celui qui a **battu**
  /// l'IA : c'est ainsi qu'elle progresse contre ce qui l'a mise en défaut.
  Future<void> _learn(Camp winner) async {
    if (widget.aiCamp == null) return;

    final weights = _weights ?? await _memory.weights();
    await _memory.saveWeights(weights.learn(winner, _game.board));

    if (winner == widget.aiCamp) return;
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
    setState(() {
      _game = MoveController();
      _clock.reset();
      _aiPositionCounts.clear();
      _consecutiveManeuvers = 0;
      _lastMoveCells = {};
      _verdict = null;
      _archived = false;
      _thinking = false;
      _lastThinkMicros = null;
    });
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
    final flipped = widget.aiCamp != Camp.blanc;

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
      label: widget.aiCamp == camp ? 'Deep Grey' : _campLabel(camp),
      clock: _clock.displayFor(camp),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _game.turn == camp && !_game.gameOver,
      busy: widget.aiCamp == camp && _thinking,
    );
  }

  Widget _actionBar() {
    final last = _game.history.isEmpty ? '—' : _game.history.last;
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
              _verdict ??
                  (_game.canValidate
                      ? T('Retouchez la pièce pour valider')
                      : '${_game.history.length} · $last$think'),
              style: TextStyle(
                color: _verdict != null ? Colors.white : Colors.white70,
                fontWeight: _verdict != null
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          if (_game.canValidate)
            TextButton(onPressed: _cancelMove, child: Text(T('Annuler'))),
          TextButton(onPressed: _restart, child: Text(T('Nouvelle partie'))),
        ],
      ),
    );
  }
}
