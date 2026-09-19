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
import 'theme_image_cache.dart';

class GameBoardView extends StatefulWidget {
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
    this.pieceTheme,
    this.boardTheme,
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

  /// Thème dont viennent les images de pièces (axe « pieces »).
  final String? pieceTheme;

  /// Thème dont vient l'image de plateau (axe « board »).
  ///
  /// Séparé du précédent : la composition à cinq axes permet de prendre les
  /// pièces d'un thème et le plateau d'un autre.
  final String? boardTheme;

  @override
  State<GameBoardView> createState() => _GameBoardViewState();
}

class _GameBoardViewState extends State<GameBoardView> {
  LoadedThemeImages? _pieceImages;
  LoadedThemeImages? _boardImages;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void didUpdateWidget(GameBoardView old) {
    super.didUpdateWidget(old);
    if (old.pieceTheme != widget.pieceTheme ||
        old.boardTheme != widget.boardTheme) {
      _loadImages();
    }
  }

  /// Charge les images des deux axes.
  ///
  /// Tant qu'elles ne sont pas prêtes, le rendu géométrique s'affiche : le
  /// plateau apparaît tout de suite plutôt que de rester blanc.
  Future<void> _loadImages() async {
    final pieceTheme = widget.pieceTheme;
    final boardTheme = widget.boardTheme;

    _pieceImages = pieceTheme == null
        ? null
        : ThemeImageCache.ready(pieceTheme);
    _boardImages = boardTheme == null
        ? null
        : ThemeImageCache.ready(boardTheme);

    if (pieceTheme != null && _pieceImages == null) {
      final loaded = await ThemeImageCache.load(pieceTheme);
      if (mounted) setState(() => _pieceImages = loaded);
    }
    if (boardTheme != null && _boardImages == null) {
      final loaded = await ThemeImageCache.load(boardTheme);
      if (mounted) setState(() => _boardImages = loaded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final geometry = BoardGeometry(size: size, flipped: widget.flipped);
        return GestureDetector(
          onTapUp: (details) {
            final cell = geometry.pixelToCell(details.localPosition);
            if (cell != null) widget.onTapCell(cell);
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
                    palette: widget.palette,
                    images: _boardImages,
                  ),
                ),
              ),
              CustomPaint(
                size: size,
                painter: BoardPiecesPainter(
                  geometry: geometry,
                  palette: widget.palette,
                  board: widget.board,
                  selected: widget.selected,
                  groupSelection: widget.groupSelection,
                  destinations: widget.highlighted,
                  lastMoveCells: widget.lastMoveCells,
                  images: _pieceImages,
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
