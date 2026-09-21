/// L'histoire de La Fuga — portage de `_show_story_popup` (main.py).
///
/// Un calque PLEIN ÉCRAN, tout en pourcentages : titre en haut, le récit au
/// milieu, et en bas les cinq pièces du thème avec leur nom. On l'ouvre en
/// touchant le titre « La Fuga » ou le logo, juste en dessous.
///
/// Le fond est celui du thème, voilé de parchemin pour que le texte se lise.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'piece_painter.dart';

/// Encres du parchemin — les couleurs de Kivy.
const Color _titleInk = Color.fromRGBO(56, 33, 13, 1);
const Color _bodyInk = Color.fromRGBO(51, 31, 10, 1);
const Color _parchment = Color.fromRGBO(237, 222, 184, 1);
const Color _veil = Color.fromRGBO(242, 227, 189, 0.86);
const Color _closeRed = Color.fromRGBO(140, 41, 41, 1);

/// Les cinq pièces montrées en bas, dans l'ordre de Kivy.
const List<(PieceType, Camp)> _shownPieces = [
  (PieceType.heritier, Camp.blanc),
  (PieceType.chevalier, Camp.noir),
  (PieceType.nurse, Camp.blanc),
  (PieceType.soldat, Camp.noir),
  (PieceType.garde, Camp.blanc),
];

/// Ouvre l'histoire, en plein écran.
Future<void> showStory(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Colors.transparent,
  builder: (_) => const StoryView(),
);

class StoryView extends StatelessWidget {
  const StoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.pieces);
    final background = imagesFor(axes.menu)?.background;
    final screen = MediaQuery.sizeOf(context);
    final closeSide = screen.height * 0.05;

    return Dialog.fullscreen(
      backgroundColor: _parchment,
      child: Stack(
        children: [
          if (background != null) ...[
            Positioned.fill(child: Image.asset(background, fit: BoxFit.cover)),
            const Positioned.fill(child: ColoredBox(color: _veil)),
          ],
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: screen.width * 0.06,
              vertical: screen.height * 0.02,
            ),
            child: Column(
              children: [
                SizedBox(
                  height: screen.height * 0.09,
                  child: Center(
                    child: Text(
                      T("L'histoire de La Fuga"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: SF(21),
                        fontWeight: FontWeight.bold,
                        color: _titleInk,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Text(
                        Translations.current.story,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: SF(17), color: _bodyInk),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: screen.height * 0.19,
                  child: Row(
                    children: [
                      for (final (type, camp) in _shownPieces)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: screen.width * 0.005,
                            ),
                            child: _PieceCell(
                              piece: Piece(type, camp),
                              palette: palette,
                              side: screen.height * 0.05,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: screen.width * 0.01,
            top: screen.height * 0.01,
            child: SizedBox(
              width: closeSide,
              height: closeSide,
              child: Material(
                color: _closeRed,
                borderRadius: BorderRadius.circular(S(14)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(S(14)),
                  onTap: () => Navigator.of(context).pop(),
                  child: Center(
                    child: Text(
                      'X',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: SF(16),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une pièce et son nom. Toujours le dessin géométrique, jamais l'image d'un
/// thème (`force_normal=True`) : ce sont les FORMES qu'on présente, dans les
/// couleurs du thème courant.
class _PieceCell extends StatelessWidget {
  const _PieceCell({
    required this.piece,
    required this.palette,
    required this.side,
  });

  final Piece piece;
  final ThemePalette palette;
  final double side;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: Center(
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(painter: _PiecePainter(piece, palette)),
          ),
        ),
      ),
      SizedBox(
        height: side * 0.7,
        child: Center(
          child: Text(
            T(piece.type.wire),
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(fontSize: SF(10), color: _bodyInk),
          ),
        ),
      ),
    ],
  );
}

class _PiecePainter extends CustomPainter {
  const _PiecePainter(this.piece, this.palette);

  final Piece piece;
  final ThemePalette palette;

  @override
  void paint(Canvas canvas, Size size) => paintPiece(
    canvas,
    Rect.fromLTWH(0, 0, size.shortestSide, size.shortestSide),
    piece,
    palette,
  );

  @override
  bool shouldRepaint(_PiecePainter old) =>
      old.piece != piece || old.palette != palette;
}
