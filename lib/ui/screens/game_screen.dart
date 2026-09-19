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
import '../../engine/board.dart';
import '../../engine/move_generator.dart';
import '../../engine/piece.dart';
import '../../game/clock.dart';
import '../../game/move_controller.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../widgets/board_geometry.dart';
import '../widgets/board_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.cadence = Cadence.illimitee,
    this.aiCamp = Camp.noir,
    this.aiDeepMode = false,
    this.themeName = kDefaultTheme,
  });

  /// Cadence de la partie.
  final Cadence cadence;

  /// Camp joué par Deep Grey ; `null` pour une partie locale à deux.
  final Camp? aiCamp;

  /// Mode profond de l'IA (top 5 à profondeur 2, puis profondeur 3).
  final bool aiDeepMode;

  final String themeName;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late MoveController _game;
  late GameClock _clock;
  final DeepGreyEngine _engine = DeepGreyEngine();

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
    if (widget.aiCamp != null) _engine.start();
    _startTicking();
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
          _game.gameOver = true;
          _verdict =
              '${T("Temps écoulé")} — '
              '${_campLabel(loser.opposite)} ${T("gagne")}';
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

    setState(() {
      if (result.notation != null) _rememberLastMove(result);
      if (result.effect == ControllerEffect.gameOver) {
        _verdict = _verdictText(result);
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
    );
    if (!mounted) return;

    if (!result.hasMove) {
      setState(() {
        _thinking = false;
        _game.gameOver = true;
        _verdict =
            '${T("Papatte")} — ${_campLabel(aiCamp.opposite)} ${T("gagne")}';
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

    final applied = _game.applyGeneratedMove(move, pushTargets: pushTargets);
    final key = _game.board.ownPiecesKey(aiCamp);
    _aiPositionCounts[key] = (_aiPositionCounts[key] ?? 0) + 1;

    setState(() {
      _thinking = false;
      _lastThinkMicros = result.elapsedMicros;
      _rememberLastMove(applied);
      if (applied.effect == ControllerEffect.gameOver) {
        _verdict = _verdictText(applied);
      }
    });
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
    setState(() {
      _game = MoveController();
      _clock.reset();
      _aiPositionCounts.clear();
      _lastMoveCells = {};
      _verdict = null;
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final geometry = BoardGeometry(size: size, flipped: flipped);
                  return GestureDetector(
                    onTapUp: (details) {
                      final cell = geometry.pixelToCell(details.localPosition);
                      if (cell != null) _onTapCell(cell);
                    },
                    child: Stack(
                      children: [
                        // Le décor ne dépend que du thème et de la taille :
                        // isolé derrière son RepaintBoundary, il n'est pas
                        // redessiné à chaque coup.
                        RepaintBoundary(
                          child: CustomPaint(
                            size: size,
                            painter: BoardBackgroundPainter(
                              geometry: geometry,
                              palette: palette,
                            ),
                          ),
                        ),
                        CustomPaint(
                          size: size,
                          painter: BoardPiecesPainter(
                            geometry: geometry,
                            palette: palette,
                            board: _game.board,
                            selected: _game.selected,
                            groupSelection: _game.groupSelection,
                            destinations: _game.availablePushCells.toSet(),
                            lastMoveCells: _lastMoveCells,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _playerBanner(palette, flipped ? Camp.blanc : Camp.noir),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  /// Bandeau d'un camp : nom, chrono, et accentuation quand c'est son tour.
  Widget _playerBanner(ThemePalette palette, Camp camp) {
    final isTurn = _game.turn == camp && !_game.gameOver;
    final base = camp == Camp.blanc ? palette.clair : palette.fonce;
    final dim = camp == Camp.blanc ? palette.clairDim : palette.fonceDim;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: isTurn ? base : dim,
      child: Row(
        children: [
          Text(
            widget.aiCamp == camp ? 'Deep Grey' : _campLabel(camp),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (widget.aiCamp == camp && _thinking) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ],
          const Spacer(),
          Text(
            _clock.displayFor(camp),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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
