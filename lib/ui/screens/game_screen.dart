/// Écran de jeu contre Deep Grey.
///
/// Cet écran est volontairement réduit pour l'instant : il valide la chaîne
/// complète — rendu GPU, moteur de règles vérifié, IA sur isolate — avant que
/// le portage des écrans n'ajoute le chrono, le chat, les modes en ligne et
/// correspondance, les thèmes à images et l'interaction incrémentale de Kivy
/// (poussée direction par direction, sélection de groupe).
library;

import 'package:flutter/material.dart';

import '../../engine/ai/deep_grey_isolate.dart';
import '../../engine/board.dart';
import '../../engine/move.dart';
import '../../engine/move_generator.dart';
import '../../engine/notation.dart';
import '../../engine/piece.dart';
import '../../theme/themes.dart';
import '../widgets/board_geometry.dart';
import '../widgets/board_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final DeepGreyEngine _engine = DeepGreyEngine();

  Board _board = Board.initial();
  Camp _turn = Camp.blanc;

  /// Camp joué par Deep Grey.
  final Camp _aiCamp = Camp.noir;

  Cell? _selected;
  Map<Cell, Move> _destinations = {};
  Set<Cell> _lastMoveCells = {};
  final List<String> _history = [];

  bool _thinking = false;
  int? _lastThinkMicros;
  String? _gameOver;

  @override
  void initState() {
    super.initState();
    _engine.start();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  bool get _myTurn => _turn != _aiCamp && !_thinking && _gameOver == null;

  void _onTapCell(Cell cell) {
    if (!_myTurn) return;

    // Une case d'arrivée proposée : on joue.
    final move = _destinations[cell];
    if (move != null) {
      _applyMove(move);
      return;
    }

    // Sinon, sélection d'une de nos pièces.
    final p = _board.atCell(cell);
    if (p == null || p.camp != _turn) {
      setState(() {
        _selected = null;
        _destinations = {};
      });
      return;
    }

    final legal = generateMoves(_board, _turn).where((m) => m.from == cell);
    setState(() {
      _selected = cell;
      // Une même case d'arrivée peut correspondre à plusieurs variantes de
      // poussée ; on garde la première, faute d'interface de choix pour
      // l'instant.
      _destinations = {for (final m in legal) m.to: m};
    });
  }

  void _applyMove(Move move) {
    final notation = notationOfMove(move);
    setState(() {
      _board = move.board;
      _history.add(notation);
      _lastMoveCells = {move.from, ...move.movedCells};
      _selected = null;
      _destinations = {};
    });

    if (_checkGameOver(move, _turn)) return;
    setState(() => _turn = _turn.opposite);
    if (_turn == _aiCamp) _playAi();
  }

  /// Fins de partie couvertes ici : fugue, mat, Papatte et Trêve.
  bool _checkGameOver(Move move, Camp mover) {
    String? verdict;
    if (move.fugue || move.fugueBy == mover) {
      // Règle auto : l'adversaire fugue-t-il en un coup ? Oui → nulle.
      verdict = campCanFugue(_board, mover.opposite)
          ? 'Nulle : les deux camps peuvent fuguer'
          : 'Fugue — ${mover.wire} gagne';
    } else if (move.fugueBy == mover.opposite) {
      verdict = 'Fugue — ${mover.opposite.wire} gagne';
    } else if (move.matOn != null) {
      verdict = 'Mat — ${move.matOn!.opposite.wire} gagne';
    } else if (!anySquareCanMove(_board)) {
      verdict = 'Trêve : plus aucune carrée ne peut bouger';
    } else if (!playerHasAnyMove(_board, mover.opposite)) {
      verdict = 'Papatte — ${mover.wire} gagne';
    }
    if (verdict == null) return false;
    setState(() => _gameOver = verdict);
    return true;
  }

  Future<void> _playAi() async {
    setState(() => _thinking = true);
    final result = await _engine.think(
      board: _board,
      camp: _aiCamp,
      deepMode: false,
      moveNumber: _history.length + 1,
    );
    if (!mounted) return;

    if (!result.hasMove) {
      setState(() {
        _thinking = false;
        _gameOver = 'Papatte — ${_aiCamp.opposite.wire} gagne';
      });
      return;
    }

    // L'isolate renvoie le plateau résultant ; on retrouve l'objet Move
    // correspondant, car les conditions de fin de partie (fugue, mat) en
    // dépendent. La clé de plateau identifie le coup sans ambiguïté.
    final resultKey = Board.fromJson(result.board!).key;
    final move = generateMoves(
      _board,
      _aiCamp,
    ).firstWhere((m) => m.board.key == resultKey);

    setState(() {
      _thinking = false;
      _lastThinkMicros = result.elapsedMicros;
    });
    _applyMove(move);
  }

  void _restart() {
    setState(() {
      _board = Board.initial();
      _turn = Camp.blanc;
      _selected = null;
      _destinations = {};
      _lastMoveCells = {};
      _history.clear();
      _gameOver = null;
      _thinking = false;
      _lastThinkMicros = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(kDefaultTheme);
    return Scaffold(
      backgroundColor: palette.menu,
      body: SafeArea(
        child: Column(
          children: [
            _statusBar(palette),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final geometry = BoardGeometry(
                    size: size,
                    flipped: _aiCamp == Camp.noir,
                  );
                  return GestureDetector(
                    onTapUp: (details) {
                      final cell = geometry.pixelToCell(details.localPosition);
                      if (cell != null) _onTapCell(cell);
                    },
                    child: Stack(
                      children: [
                        // Le décor ne se repeint qu'au changement de thème ou
                        // de taille : isolé derrière son RepaintBoundary.
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
                            board: _board,
                            selected: _selected,
                            destinations: _destinations.keys.toSet(),
                            lastMoveCells: _lastMoveCells,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _footer(palette),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(ThemePalette palette) {
    final String label;
    if (_gameOver != null) {
      label = _gameOver!;
    } else if (_thinking) {
      label = 'Deep Grey réfléchit…';
    } else {
      label = 'Trait aux ${_turn.wire}s';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: _turn == Camp.blanc ? palette.clair : palette.fonce,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          if (_thinking)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(ThemePalette palette) {
    final last = _history.isEmpty ? '—' : _history.last;
    final think = _lastThinkMicros == null
        ? ''
        : '  ·  réflexion ${(_lastThinkMicros! / 1000).round()} ms';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: Colors.black26,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Coup ${_history.length} : $last$think',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          TextButton(onPressed: _restart, child: const Text('Nouvelle partie')),
        ],
      ),
    );
  }
}
