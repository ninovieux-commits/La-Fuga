/// Panneau d'un joueur — portage de `top_info` / `bot_info` (main.py).
///
/// Avatar, nom, chrono, score, pièces prises, et les trois gestes du côté :
/// annuler le coup en cours (↶), proposer la nulle (½), abandonner (X).
/// Le panneau du bas est le miroir de celui du haut, comme en Kivy.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import 'piece_painter.dart';
import 'profile_photo.dart';

/// Les pièces prises, dessinées en chevauchement — portage de
/// `CapturesWidget`.
class CapturesStrip extends StatelessWidget {
  const CapturesStrip({super.key, required this.pieces, required this.palette});

  final List<Piece> pieces;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _CapturesPainter(pieces, palette),
  );
}

class _CapturesPainter extends CustomPainter {
  const _CapturesPainter(this.pieces, this.palette);

  final List<Piece> pieces;
  final ThemePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (pieces.isEmpty || size.width < 10 || size.height < 10) return;

    // Chevauchement de 30 % : de quoi montrer beaucoup de prises dans peu de
    // place, sans qu'on cesse de les reconnaître.
    final each = pieces.length > 1
        ? size.width / (1 + 0.7 * (pieces.length - 1))
        : size.width;
    final side = math.min(math.min(size.height - 2, each), 34.0);
    final step = side * 0.7;
    final top = (size.height - side) / 2;

    for (var i = 0; i < pieces.length; i++) {
      paintPiece(
        canvas,
        Rect.fromLTWH(i * step, top, side, side),
        pieces[i],
        palette,
        outlineWidth: 1,
      );
    }
  }

  @override
  bool shouldRepaint(_CapturesPainter old) =>
      old.pieces.length != pieces.length || old.palette != palette;
}

/// Le panneau d'un joueur.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.name,
    required this.clock,
    required this.palette,
    required this.isWhite,
    required this.isTurn,
    required this.captures,
    this.photo = '',
    this.score,
    this.subtitle,
    this.busy = false,
    this.mirrored = false,
    this.onUndo,
    this.onDraw,
    this.onResign,
  });

  final String name;
  final String clock;
  final ThemePalette palette;
  final bool isWhite;
  final bool isTurn;

  /// Pièces prises par ce joueur.
  final List<Piece> captures;

  final String photo;

  /// Score du match, quand il y en a un (« 2 / 5 »).
  final String? score;

  /// Ligne d'état : Deep Grey réfléchit, adversaire déconnecté…
  final String? subtitle;

  final bool busy;

  /// Le panneau du bas inverse ses deux rangées, comme en Kivy.
  final bool mirrored;

  /// Annuler le coup en cours. Absent = geste indisponible de ce côté.
  final VoidCallback? onUndo;
  final VoidCallback? onDraw;
  final VoidCallback? onResign;

  @override
  Widget build(BuildContext context) {
    final base = isWhite ? palette.clair : palette.fonce;
    final dim = isWhite ? palette.clairDim : palette.fonceDim;

    final rows = [_identity(base), SizedBox(height: 30, child: _actions())];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: isTurn ? base : dim,
      child: Row(
        children: [
          ProfilePhoto(photo: photo, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: mirrored ? rows.reversed.toList() : rows,
            ),
          ),
        ],
      ),
    );
  }

  Widget _identity(Color base) => Row(
    children: [
      Expanded(
        child: Text(
          subtitle == null ? name : '$name  ·  $subtitle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      if (busy)
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      Text(
        clock,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      if (score != null) ...[
        const SizedBox(width: 10),
        Text(
          score!,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ],
  );

  Widget _actions() => Row(
    children: [
      Expanded(
        child: CapturesStrip(pieces: captures, palette: palette),
      ),
      if (onUndo != null) _button('↶', T('Annuler'), onUndo!),
      if (onDraw != null) _button('½', T('Proposer nulle'), onDraw!),
      if (onResign != null) _button('X', T('Abandonner'), onResign!),
    ],
  );

  Widget _button(String label, String tooltip, VoidCallback onPressed) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 30,
            height: 26,
            margin: const EdgeInsets.only(left: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
}
