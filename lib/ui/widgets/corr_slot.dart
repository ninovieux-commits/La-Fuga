/// Emplacement de correspondance du menu — portage de `_make_corr_slot` et
/// `_build_corr_overlay` (main.py).
///
/// Chaque case montre le mini-plateau de la partie, mes pièces en bas, avec
/// par-dessus le nom de l'adversaire, le score, et ce qu'il y a à faire :
/// accepter un défi, jouer, ou refermer une partie finie. Une case vide sert
/// à lancer un nouveau défi.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/correspondence.dart';
import '../../i18n/translations.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'piece_painter.dart';
import 'theme_image_cache.dart';

/// Une case du damier de correspondance.
class CorrSlot extends StatelessWidget {
  const CorrSlot({
    super.key,
    required this.game,
    required this.palette,
    required this.boardTheme,
    required this.onTap,
    required this.onAccept,
    required this.onRefuse,
    required this.onCancel,
    required this.onRematch,
    required this.onClose,
  });

  /// La partie affichée, ou `null` pour une case vide.
  final CorrGame? game;

  final ThemePalette palette;
  final String boardTheme;

  final VoidCallback onTap;
  final void Function(CorrGame) onAccept;
  final void Function(CorrGame) onRefuse;
  final void Function(CorrGame) onCancel;
  final void Function(CorrGame) onRematch;
  final void Function(CorrGame) onClose;

  @override
  Widget build(BuildContext context) {
    final g = game;
    // Fond orange quand c'est à moi de jouer : la case se repère d'un coup
    // d'œil dans la grille.
    final background = (g?.myTurn ?? false) ? palette.clair : kFugaGrey;

    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        // La case a la forme du plateau : 7 colonnes sur 8 rangées.
        aspectRatio: 7 / 8,
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(S(10)),
          ),
          padding: EdgeInsets.all(S(6)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _MiniBoard(game: g, palette: palette, boardTheme: boardTheme),
              if (g != null) ..._overlay(g) else _emptyHint(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyHint() => Center(
    child: Icon(
      Icons.add_circle_outline,
      color: Colors.white.withValues(alpha: 0.75),
      size: S(32),
    ),
  );

  List<Widget> _overlay(CorrGame g) => [
    Align(
      alignment: Alignment.topCenter,
      child: _plate(
        '${g.opponent}\n'
        '${g.randomCode.isEmpty ? T('Standard') : 'Random'} · '
        '${g.myScore} - ${g.opponentScore}',
        bold: true,
      ),
    ),
    ...switch (g.status) {
      CorrStatus.defi => _challenge(g),
      CorrStatus.enCours => [
        Align(
          alignment: const Alignment(0, 0.92),
          child: _plate(
            g.myTurn
                ? T('À vous de jouer')
                : T("À votre adversaire\nde jouer").replaceAll('\n', ' '),
            bold: true,
          ),
        ),
      ],
      CorrStatus.termine => _finished(g),
    },
  ];

  /// Un défi : reçu, on accepte ou refuse ; envoyé, on attend ou on annule.
  List<Widget> _challenge(CorrGame g) => g.isChallenger
      ? [
          Align(alignment: Alignment.center, child: _plate(T('En attente…'))),
          Align(
            alignment: const Alignment(0, 0.92),
            child: _smallButton(
              T('Annuler'),
              const Color(0xFF8C1A1A),
              () => onCancel(g),
            ),
          ),
        ]
      : [
          Align(
            alignment: const Alignment(0, -0.1),
            child: _plate(
              '${T('vous défie !')}\n'
              '${T('Mélo : %d').replaceAll('%d', '${g.opponentMelo}')}'
              '${g.randomCode.isEmpty ? '' : '\nRandom Fuga'}',
              bold: true,
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.55),
            child: _smallButton(
              T('Accepter'),
              palette.fonce,
              () => onAccept(g),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.95),
            child: _smallButton(
              T('Refuser'),
              const Color(0xFF8C1A1A),
              () => onRefuse(g),
            ),
          ),
        ];

  List<Widget> _finished(CorrGame g) {
    final (text, color) = switch (g.won) {
      true => (T('Gagné !'), const Color(0xFF80E680)),
      false => (T('Perdu'), const Color(0xFFF28080)),
      null => (T('Nulle'), const Color(0xFFE6E699)),
    };
    return [
      Align(
        alignment: const Alignment(0, -0.1),
        child: _plate(text, bold: true, color: color),
      ),
      Align(
        alignment: const Alignment(0, 0.55),
        child: _smallButton(T('Revanche'), palette.fonce, () => onRematch(g)),
      ),
      Align(
        alignment: const Alignment(0, 0.95),
        child: _smallButton(T('Fermer'), kFugaGrey, () => onClose(g)),
      ),
    ];
  }

  /// Texte sur fond sombre : sans lui, rien ne se lit par-dessus le plateau.
  Widget _plate(String text, {bool bold = false, Color color = Colors.white}) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(S(6)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: SF(11),
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );

  Widget _smallButton(String text, Color color, VoidCallback onPressed) =>
      FractionallySizedBox(
        widthFactor: 0.82,
        child: FugaButton(
          text: text,
          color: color,
          onPressed: onPressed,
          height: S(26),
          fontSize: SF(10),
          radius: 8,
        ),
      );
}

/// Le mini-plateau : quadrillage, image de plateau du thème, et les pièces.
class _MiniBoard extends StatelessWidget {
  const _MiniBoard({
    required this.game,
    required this.palette,
    required this.boardTheme,
  });

  final CorrGame? game;
  final ThemePalette palette;
  final String boardTheme;

  @override
  Widget build(BuildContext context) {
    final g = game;
    // Position reconstruite depuis les coups ; pour un défi pas encore
    // accepté, c'est la position de départ.
    final state = g == null ? null : replay(g);
    final board = state?.board ?? g?.initialBoard;
    final asset = imagesFor(boardTheme)?.board;

    return ThemeImagesBuilder(
      theme: boardTheme,
      builder: (context, images) => CustomPaint(
        painter: _MiniBoardPainter(
          board: board,
          // Mes pièces en bas, comme sur le plateau de jeu.
          flipped: g?.myCamp != Camp.noir,
          palette: palette,
          images: asset == null ? null : images,
        ),
      ),
    );
  }
}

class _MiniBoardPainter extends CustomPainter {
  _MiniBoardPainter({
    required this.board,
    required this.flipped,
    required this.palette,
    this.images,
  }) : boardKey = board?.key;

  /// Empreinte de la position au moment de la construction : un plateau se
  /// mute en place, sa clé relue après coup ne dirait plus rien.
  final String? boardKey;

  final Board? board;
  final bool flipped;
  final ThemePalette palette;
  final LoadedThemeImages? images;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = (size.width / kCols) < (size.height / kRows)
        ? size.width / kCols
        : size.height / kRows;
    final width = cell * kCols;
    final height = cell * kRows;
    final left = (size.width - width) / 2;
    final top = (size.height - height) / 2;
    final rect = Rect.fromLTWH(left, top, width, height);

    final image = images?.board;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint(),
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(S(4))),
        Paint()..color = palette.board,
      );
    }

    // Le quadrillage passe TOUJOURS par-dessus : les images de plateau ne
    // l'incluent pas.
    final grid = Paint()
      ..color = palette.grid
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    for (var c = 0; c <= kCols; c++) {
      canvas.drawLine(
        Offset(left + c * cell, top),
        Offset(left + c * cell, top + height),
        grid,
      );
    }
    for (var r = 0; r <= kRows; r++) {
      canvas.drawLine(
        Offset(left, top + r * cell),
        Offset(left + width, top + r * cell),
        grid,
      );
    }

    final b = board;
    if (b == null) return;
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        final piece = b.at(c, r);
        if (piece == null) continue;
        final sc = flipped ? c : (kCols - 1 - c);
        final sr = flipped ? (kRows - 1 - r) : r;
        paintPiece(
          canvas,
          Rect.fromLTWH(left + sc * cell, top + sr * cell, cell, cell),
          piece,
          palette,
          outlineWidth: 1,
          flipped: flipped,
          images: images,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MiniBoardPainter old) =>
      old.boardKey != boardKey ||
      old.flipped != flipped ||
      old.palette != palette ||
      old.images != images;
}
