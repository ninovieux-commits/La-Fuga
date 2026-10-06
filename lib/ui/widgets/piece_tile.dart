/// Une pièce seule, dessinée comme sur le plateau.
///
/// Le composeur de position offre une ligne de pièces à poser. Elles doivent
/// être les MÊMES que celles du plateau — même dessin, même thème, même
/// taille — sans quoi on choisit une chose et on en pose une autre.
///
/// C'est donc `paintPiece` qui peint ici, la fonction que `BoardPiecesPainter`
/// emploie case par case, et les images du thème viennent du même cache. Rien
/// n'est redessiné à côté.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import 'theme_image_cache.dart';
import '../../theme/themes.dart';
import 'piece_painter.dart';

class PieceTile extends StatefulWidget {
  const PieceTile({
    super.key,
    required this.piece,
    required this.palette,
    this.pieceTheme,
    this.selected = false,
    this.onTap,
  });

  final Piece piece;
  final ThemePalette palette;

  /// Thème des pièces, pour que celles de la ligne soient celles du plateau.
  final String? pieceTheme;

  /// Entourée quand elle est la pièce choisie.
  final bool selected;

  final VoidCallback? onTap;

  @override
  State<PieceTile> createState() => _PieceTileState();
}

class _PieceTileState extends State<PieceTile> {
  LoadedThemeImages? _images;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(PieceTile old) {
    super.didUpdateWidget(old);
    if (old.pieceTheme != widget.pieceTheme) _charger();
  }

  /// Comme le plateau : l'image si elle est déjà prête, sinon le rendu
  /// géométrique en attendant qu'elle arrive.
  Future<void> _charger() async {
    final theme = widget.pieceTheme;
    _images = theme == null ? null : ThemeImageCache.ready(theme);
    if (theme != null && _images == null) {
      final charge = await ThemeImageCache.load(theme);
      if (mounted) setState(() => _images = charge);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    behavior: HitTestBehavior.opaque,
    child: AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _TilePainter(
          piece: widget.piece,
          palette: widget.palette,
          images: _images,
          theme: widget.pieceTheme,
          selected: widget.selected,
        ),
      ),
    ),
  );
}

final class _TilePainter extends CustomPainter {
  const _TilePainter({
    required this.piece,
    required this.palette,
    required this.images,
    required this.theme,
    required this.selected,
  });

  final Piece piece;
  final ThemePalette palette;
  final LoadedThemeImages? images;
  final String? theme;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final cote = size.shortestSide;
    final rect = Rect.fromLTWH(
      (size.width - cote) / 2,
      (size.height - cote) / 2,
      cote,
      cote,
    );
    if (selected) {
      // La pièce choisie le reste : on pose plusieurs cases d'affilée. Il faut
      // donc voir laquelle est en main sans avoir à s'en souvenir.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cote * 0.14)),
        Paint()..color = palette.clair.withValues(alpha: 0.35),
      );
    }
    paintPiece(canvas, rect, piece, palette, images: images, theme: theme);
  }

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.piece != piece ||
      old.selected != selected ||
      old.images != images ||
      old.theme != theme;
}
