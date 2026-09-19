/// Vue du plateau : décor, pièces, et gestes.
///
/// Partagée par la partie locale, la partie contre Deep Grey et la partie en
/// ligne — le plateau doit se comporter exactement pareil dans les trois cas.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../theme/themes.dart';
import 'board_geometry.dart';
import 'board_painter.dart';

class GameBoardView extends StatelessWidget {
  const GameBoardView({
    super.key,
    required this.board,
    required this.palette,
    required this.flipped,
    required this.onTapCell,
    this.selected,
    this.groupSelection = const {},
    this.highlighted = const {},
    this.lastMoveCells = const {},
  });

  final Board board;
  final ThemePalette palette;

  /// Vrai quand les Blancs sont en bas.
  final bool flipped;

  final void Function(Cell cell) onTapCell;

  final Cell? selected;
  final Set<Cell> groupSelection;

  /// Cases à pointer : directions de poussée encore disponibles.
  final Set<Cell> highlighted;

  final Set<Cell> lastMoveCells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final geometry = BoardGeometry(size: size, flipped: flipped);
        return GestureDetector(
          onTapUp: (details) {
            final cell = geometry.pixelToCell(details.localPosition);
            if (cell != null) onTapCell(cell);
          },
          child: Stack(
            children: [
              // Le décor ne dépend que du thème et de la taille : isolé
              // derrière son RepaintBoundary, il n'est pas redessiné à chaque
              // coup.
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
                  board: board,
                  selected: selected,
                  groupSelection: groupSelection,
                  destinations: highlighted,
                  lastMoveCells: lastMoveCells,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Bandeau d'un camp : nom, chrono, et accentuation quand c'est son tour.
class PlayerBanner extends StatelessWidget {
  const PlayerBanner({
    super.key,
    required this.label,
    required this.clock,
    required this.palette,
    required this.isWhite,
    required this.isTurn,
    this.busy = false,
    this.subtitle,
  });

  final String label;
  final String clock;
  final ThemePalette palette;
  final bool isWhite;
  final bool isTurn;

  /// Affiche un indicateur d'activité (Deep Grey réfléchit, adversaire parti…).
  final bool busy;

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final base = isWhite ? palette.clair : palette.fonce;
    final dim = isWhite ? palette.clairDim : palette.fonceDim;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: isTurn ? base : dim,
      child: Row(
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (busy) ...[
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
            clock,
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
}
