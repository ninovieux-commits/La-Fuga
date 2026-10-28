/// Rendu du plateau — portage de `BoardWidget._redraw` (main.py).
///
/// Le dessin est séparé en deux peintres pour que l'animation d'une pièce ne
/// force pas la reconstruction du décor : [BoardBackgroundPainter] ne change
/// qu'au changement de thème ou de taille, [BoardPiecesPainter] à chaque coup.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/last_move.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'board_geometry.dart';
import 'fuga_button.dart' show kOpaciteEteinte;
import 'logo_painter.dart';
import 'picto_touche.dart';
import 'piece_painter.dart';
import 'theme_image_cache.dart';

/// Décor : zones de ralliement, fond du plateau, grille. Statique.
final class BoardBackgroundPainter extends CustomPainter {
  const BoardBackgroundPainter({
    required this.geometry,
    required this.palette,
    this.images,
    this.motRalliement,
    this.ralliementEnEdition,
  });

  final BoardGeometry geometry;
  final ThemePalette palette;

  /// Images du thème, quand il en a.
  final LoadedThemeImages? images;

  /// Mot écrit SUR les zones de ralliement — « Modifier », dans le composeur.
  ///
  /// Nino : « ce serait bien qu'il y ait écrit "modifier" sur les zones de
  /// ralliement. » Nulle part ailleurs : en partie, elles ne se touchent pas.
  final String? motRalliement;

  /// Le camp dont on est en train de choisir la zone.
  ///
  /// Sa rangée montre alors ses SEPT cases possibles, encadrées — celles qui
  /// rallient sont déjà peintes, les autres sont vides et attendent le doigt.
  final Camp? ralliementEnEdition;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final radius = Radius.circular(g.cellSize * 0.22);

    // Zones de ralliement : chaque camp a la sienne, à sa couleur d'accent.
    // Arrondies vers l'extérieur, droites du côté du plateau.
    for (final row in [8, -1]) {
      final isTop = g.rowToIndex(row) == 0;
      for (final rect in g.rallyRects(row)) {
        final rrect = RRect.fromRectAndCorners(
          rect,
          topLeft: isTop ? radius : Radius.zero,
          topRight: isTop ? radius : Radius.zero,
          bottomLeft: isTop ? Radius.zero : radius,
          bottomRight: isTop ? Radius.zero : radius,
        );
        canvas.drawRRect(
          rrect,
          Paint()..color = row == 8 ? palette.clair : palette.fonce,
        );
        // Contour foncé : le débordement dans les cadres info doit paraître net.
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = const Color(0xFF1A1A1A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = S(2),
        );
      }
      _motEtCadres(canvas, g, row);
    }

    // Plateau.
    final boardRect = Rect.fromLTWH(
      g.colToX(0) < g.colToX(6) ? g.colToX(0) : g.colToX(6),
      g.rowToY(g.indexToRow(1)),
      g.cellSize * kCols,
      g.cellSize * kRows,
    );
    final boardImage = images?.board;
    if (boardImage != null) {
      canvas.drawImageRect(
        boardImage,
        Rect.fromLTWH(
          0,
          0,
          boardImage.width.toDouble(),
          boardImage.height.toDouble(),
        ),
        boardRect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawRect(boardRect, Paint()..color = palette.board);
    }

    // LE BORD DU PLATEAU, en haut et en bas SEULEMENT.
    //
    // Nino : « les bords du plateau (il y est déjà pour les zones de
    // ralliement depuis longtemps) mais pas les bords droite et gauche qui
    // sont contre le bord de l'écran. » Un trait collé au bord de l'écran ne
    // sépare rien : il n'y a rien de l'autre côté.
    //
    // Le trait est posé À L'INTÉRIEUR du plateau, comme celui des touches :
    // la case du bord garde sa taille.
    final bord = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = S(kTraitPicto * 2);
    final demi = bord.strokeWidth / 2;
    canvas
      ..drawLine(
        Offset(boardRect.left, boardRect.top + demi),
        Offset(boardRect.right, boardRect.top + demi),
        bord,
      )
      ..drawLine(
        Offset(boardRect.left, boardRect.bottom - demi),
        Offset(boardRect.right, boardRect.bottom - demi),
        bord,
      );

    final gridPaint = Paint()
      ..color = palette.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = S(1);
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        canvas.drawRect(g.cellRect(c, r), gridPaint);
      }
    }

    // Rosace au centre du plateau, en contours seuls : elle passe sous les
    // pièces sans gêner la lecture de la position.
    paintLogoOutline(
      canvas,
      boardRect.center.dx,
      boardRect.center.dy,
      g.cellSize * 0.42,
      color: palette.grid,
      strokeWidth: S(1.6),
    );

    _paintAnnotations(canvas, g);
  }

  /// Chiffres 1 à 8 dans la colonne la plus à gauche, et notes do…si sous le
  /// plateau — portage de `_draw_annotations`.
  void _paintAnnotations(Canvas canvas, BoardGeometry g) {
    final cs = g.cellSize;
    // La colonne qui se trouve visuellement à gauche change avec
    // l'orientation : côté Noir, le plateau est tourné à 180°.
    final leftCol = g.flipped ? 0 : kCols - 1;

    for (var r = 0; r < kRows; r++) {
      final cell = g.cellRect(leftCol, r);
      _text(
        canvas,
        '${r + 1}',
        Offset(cell.left + cs * 0.08, cell.bottom - cs * 0.04),
        fontSize: math.max(10, cs * 0.20),
        color: const Color(0xFF000000),
        anchor: _Anchor.bottomLeft,
      );
    }

    // Les notes sont sous le plateau, chacune sous SA colonne.
    final noteY = g.rowToY(g.flipped ? -1 : 8) + cs * 0.20;
    for (var c = 0; c < kCols; c++) {
      _text(
        canvas,
        kBoardNotes[c],
        Offset(g.cellRect(c, 0).center.dx, noteY),
        fontSize: math.max(11, cs * 0.26),
        color: const Color(0xFFFFFFFF),
        anchor: _Anchor.center,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    required double fontSize,
    required Color color,
    required _Anchor anchor,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = switch (anchor) {
      _Anchor.bottomLeft => Offset(at.dx, at.dy - painter.height),
      _Anchor.center => Offset(
        at.dx - painter.width / 2,
        at.dy - painter.height / 2,
      ),
    };
    painter.paint(canvas, offset);
  }

  /// Le mot « Modifier » sur la bande, et les sept cases encadrées quand on
  /// choisit la zone de ce camp.
  void _motEtCadres(Canvas canvas, BoardGeometry g, int row) {
    final camp = BoardGeometry.campDeLaRangee(row);
    if (ralliementEnEdition == camp) {
      // LES SEPT CASES POSSIBLES. Celles qui rallient sont déjà peintes de la
      // couleur du camp ; le cadre dit où l'on peut appuyer, pas ce qui est
      // déjà choisi.
      for (var c = 0; c < kCols; c++) {
        canvas.drawRect(
          g.cellRect(c, row).deflate(S(1)),
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = S(2),
        );
      }
      return;
    }
    final mot = motRalliement;
    if (mot == null || mot.isEmpty) return;
    // SUR TOUTE LA RANGÉE, et pas seulement sur la bande peinte. Une zone
    // d'une seule case n'a pas la largeur du mot, et une zone VIDE n'a pas
    // de bande du tout — il faut pourtant pouvoir y revenir.
    final rangee = Rect.fromLTWH(
      g.colToX(0) < g.colToX(kCols - 1) ? g.colToX(0) : g.colToX(kCols - 1),
      g.rowToY(row),
      g.cellSize * kCols,
      g.cellSize,
    );
    final peintre = TextPainter(
      text: TextSpan(
        text: mot,
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: g.cellSize * 0.34,
          fontWeight: FontWeight.bold,
          // Un liseré sombre : le mot passe sur la bande claire des Blancs
          // comme sur le fond du plateau là où la zone s'arrête.
          shadows: const [
            Shadow(color: Color(0xCC000000), blurRadius: 3),
            Shadow(color: Color(0xCC000000), blurRadius: 6),
          ],
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    // Il RÉTRÉCIT plutôt que d'être coupé : « Modifier » est plus long dans
    // d'autres langues, et une rangée fait sept cases, pas davantage.
    final echelle = peintre.width > rangee.width * 0.9
        ? rangee.width * 0.9 / peintre.width
        : 1.0;
    canvas.save();
    canvas.translate(rangee.center.dx, rangee.center.dy);
    canvas.scale(echelle);
    peintre.paint(canvas, Offset(-peintre.width / 2, -peintre.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardBackgroundPainter old) =>
      old.palette != palette ||
      old.images != images ||
      old.motRalliement != motRalliement ||
      old.ralliementEnEdition != ralliementEnEdition ||
      old.geometry.rall != geometry.rall ||
      old.geometry.cellSize != geometry.cellSize ||
      old.geometry.flipped != geometry.flipped;
}

/// Ce qu'il reste d'une pièce CHOISIE : elle s'enfonce au lieu de s'encadrer.
///
/// Un cadre coloré autour d'une pièce ne disait pas grand-chose — jaune
/// d'abord, puis blanc sur les noires et noir sur les blanches. Nino : « la
/// couleur de sélection ne me convient pas, c'est pas clair. Et pourquoi on
/// mettrait pas plutôt la pièce en "enfoncée" ? Je veux dire, comme les
/// boutons quand ils ne peuvent pas être utilisés. »
///
/// C'est donc la MÊME atténuation que celle d'une touche éteinte,
/// [kOpaciteEteinte] : le geste parle déjà le langage des touches, autant
/// qu'il le parle partout pareil.
const double kOpaciteChoisie = kOpaciteEteinte;

/// Ce qu'il reste d'une pièce choisie des thèmes à IMAGES.
///
/// Ceux-là — medieval, fleur, insectes, dragon — sont des images, et tout ce
/// qu'elles contiennent s'atténue : les ombres, les reliefs, les détails. Le
/// contour, lui, est retracé net par-dessus, mais il ne suffit pas à les
/// tenir. Au tiers, elles se dissolvaient dans le plateau. Nino : « pour les thèmes spéciaux, la transparence doit
/// être moins marquée » — puis, six dixièmes essayés : « fais la
/// transparence entre l'ancien et le nouveau, maintenant c'est plus assez
/// transparent. » D'où ce milieu exact entre les deux.
const double kOpaciteChoisieImage = 0.48;

/// De combien s'atténue cette pièce-ci quand on la choisit.
///
/// Les dessins géométriques gardent leur contour net : ils peuvent s'effacer
/// franchement. Les images, non.
double opaciteChoisie(Piece piece, LoadedThemeImages? images) =>
    images?.pieceFor(piece) != null ? kOpaciteChoisieImage : kOpaciteChoisie;

/// Ouvre la couche qui ENFONCE une pièce. À refermer par [refermeChoisie].
void ouvreChoisie(
  Canvas canvas,
  Rect rect,
  Piece piece,
  LoadedThemeImages? images,
) => canvas.saveLayer(
  rect.inflate(rect.width * 0.1),
  Paint()
    ..color = const Color(
      0xFF000000,
    ).withValues(alpha: opaciteChoisie(piece, images)),
);

/// Referme la couche, et repose le contour NET par-dessus.
void refermeChoisie(
  Canvas canvas,
  Rect rect,
  Piece piece,
  LoadedThemeImages? images,
  String? theme,
) {
  canvas.restore();
  // LE CONTOUR N'EST PAS ATTÉNUÉ : repeint par-dessus, à pleine opacité, il
  // garde à la pièce enfoncée une forme franche. Nino : « j'aimerais que le
  // trait noir qui fait le tour de la pièce (ou blanc quand il s'agit des
  // blancs) ne soit pas concerné par la transparence. »
  paintPieceContour(canvas, rect, piece, images: images, theme: theme);
}

/// Pièces, sélection et mise en évidence du dernier coup.
final class BoardPiecesPainter extends CustomPainter {
  BoardPiecesPainter({
    required this.geometry,
    required this.palette,
    required this.board,
    this.selected,
    this.groupSelection = const {},
    this.destinations = const {},
    this.lastMove,
    this.images,
    this.theme,
    this.flying = const {},
    this.fuguedHeirs = const {},
  }) : boardKey = board.key;

  final BoardGeometry geometry;
  final ThemePalette palette;
  final Board board;

  /// Empreinte de la position AU MOMENT DE LA CONSTRUCTION.
  ///
  /// Le plateau est muté en place : le peintre précédent et celui-ci pointent
  /// souvent sur le MÊME objet, et comparer l'objet — ou sa clé, relue après
  /// coup — dirait toujours « rien n'a changé ». Une poussée ne se serait
  /// jamais affichée avant la validation du coup. La clé est donc figée ici,
  /// à la construction, c'est-à-dire à chaque reconstruction de l'écran.
  final String boardKey;

  /// Pièce actuellement sélectionnée.
  final Cell? selected;

  /// Autres pièces du groupe sélectionné (manœuvre).
  final Set<Cell> groupSelection;

  /// Cases d'arrivée légales, à pointer.
  final Set<Cell> destinations;

  /// Dernier coup joué, à mettre en évidence.
  final LastMove? lastMove;

  /// Thème des pièces : deepgrey et arc-en-ciel ont leur propre rendu.
  final String? theme;

  /// Images du thème, quand il en a.
  final LoadedThemeImages? images;

  /// Cases dont la pièce est en vol : le plateau donné est celui d'APRÈS le
  /// coup, mais tant que le glissement dure la pièce n'est pas dessinée là.
  /// Elle l'est entre deux cases, par [FlyingPiecesPainter].
  final Set<Cell> flying;

  /// Camps dont l'Héritier a rejoint son ralliement : il y est dessiné, au
  /// milieu de la zone, et il y reste. Sans cela il disparaissait du plateau
  /// au moment même où il gagnait la partie.
  /// Où se tient l'Héritier de chaque camp qui a fugué.
  ///
  /// Sa VRAIE case de ralliement, celle où il est allé ou a été poussé — le
  /// plateau ne la porte plus, puisqu'il a quitté le jeu.
  final Map<Camp, Cell> fuguedHeirs;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;

    // Pastilles des destinations légales, sous les pièces.
    if (destinations.isNotEmpty) {
      final paint = Paint()..color = const Color(0x99FFFF00);
      for (final cell in destinations) {
        canvas.drawCircle(
          g.cellCenter(cell.col, cell.row),
          g.cellSize * 0.16,
          paint,
        );
      }
    }

    // Pièces.
    final pushDirs = lastMove?.pushDirs;
    final hasPushDirs = pushDirs != null && pushDirs.isNotEmpty;
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        final p = board.at(c, r);
        if (p == null) continue;
        final cell = Cell(c, r);
        if (flying.contains(cell)) continue;

        // LA PIÈCE CHOISIE S'ENFONCE. On passe par une couche plutôt que de
        // baisser l'opacité pièce par pièce : `paintPiece` empile une image,
        // un contour, des points de poussée — atténuer chacun séparément les
        // laisserait transparaître les uns à travers les autres.
        final choisie = cell == selected || groupSelection.contains(cell);
        if (choisie) ouvreChoisie(canvas, g.cellRect(c, r), p, images);
        paintPiece(
          canvas,
          g.cellRect(c, r),
          p,
          palette,
          // Les points de poussée grossis, sur la pièce qui vient de pousser.
          pushHighlightDirs: hasPushDirs
              ? (pushDirs[cell] ?? const [])
              : const [],
          flipped: g.flipped,
          boardColor: palette.board,
          images: images,
          theme: theme,
          rainbowFraction: rainbowFractionOf(c, r),
        );
        if (choisie) {
          refermeChoisie(canvas, g.cellRect(c, r), p, images, theme);
        }
      }
    }

    // Héritiers qui ont fugué, dessinés dans leur ralliement — hors de la
    // zone de jeu, donc hors de la double boucle ci-dessus. Sans contour :
    // la partie est finie, il n'y a plus rien à y désigner.
    for (final MapEntry(key: camp, value: cell) in fuguedHeirs.entries) {
      // Tant que la glissée l'emmène encore vers le ralliement, c'est la
      // couche des pièces en vol qui le dessine : le dessiner ici aussi le
      // ferait apparaître en double, arrivé avant d'être parti.
      if (flying.any((c) => !c.onBoard && c.row == camp.rallyRow)) continue;
      paintPiece(
        canvas,
        g.cellRect(cell.col, cell.row),
        camp == Camp.blanc ? Piece.blancHeritier : Piece.noirHeritier,
        palette,
        flipped: g.flipped,
        boardColor: palette.board,
        images: images,
        theme: theme,
        rainbowFraction: rainbowFractionOf(cell.col, cell.row),
      );
    }

    // ── Cadres, PAR-DESSUS les pièces et VERS L'INTÉRIEUR de la case ──
    //
    // Au premier plan : un cadre à moitié caché par une pièce voisine ou par
    // une image de thème ne se voit pas. Vers l'intérieur : le trait tient
    // entièrement dans sa case, il ne mord pas sur les voisines.
    void frame(Cell cell, Color color, double width) {
      // Les zones de ralliement sont à l'écran : un Héritier qui vient d'y
      // entrer s'encadre comme n'importe quelle case d'arrivée.
      if (!cell.onBoard &&
          !board.estCaseDeRalliement(
            BoardGeometry.campDeLaRangee(cell.row),
            cell.col,
            cell.row,
          )) {
        return;
      }
      canvas.drawRect(
        g.cellRect(cell.col, cell.row).deflate(width / 2),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }

    // Dernier coup : cases de départ et d'arrivée, et petits carrés sur les
    // rebonds d'un multisaut. La couleur est l'inverse du camp qui a joué —
    // noire pour les Blancs, blanche pour les Noirs — pour rester lisible sur
    // toutes les pièces.
    final last = lastMove;
    if (last != null && !last.isEmpty) {
      final color = last.camp == Camp.blanc
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF);
      for (final cell in last.framedCells) {
        frame(cell, color, S(2.4));
      }
      final dot = Paint()..color = color;
      for (final cell in last.jumpPath) {
        if (!cell.onBoard) continue;
        final d = g.cellSize * 0.16;
        canvas.drawRect(
          Rect.fromCenter(
            center: g.cellCenter(cell.col, cell.row),
            width: d,
            height: d,
          ),
          dot,
        );
      }
    }

    // Pièces immobilisées, dessinées en dernier. La sélection, elle, ne
    // s'encadre plus : la pièce choisie s'est enfoncée avec les autres.
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        if (board.at(c, r) == null) continue;
        final cell = Cell(c, r);
        if (flying.contains(cell)) continue;
        if (cell == selected || groupSelection.contains(cell)) continue;
        // Même condition que la règle : une pièce au contour rouge ne peut
        // pas bouger.
        if (board.isImmobilised(c, r)) {
          frame(cell, FugaColors.immobile, S(3));
        }
      }
    }
  }

  @override
  bool shouldRepaint(BoardPiecesPainter old) =>
      old.boardKey != boardKey ||
      old.images != images ||
      old.selected != selected ||
      old.palette != palette ||
      old.geometry.flipped != geometry.flipped ||
      !setEquals(old.destinations, destinations) ||
      !setEquals(old.groupSelection, groupSelection) ||
      !setEquals(old.flying, flying) ||
      !mapEquals(old.fuguedHeirs, fuguedHeirs) ||
      old.theme != theme ||
      old.lastMove != lastMove;
}

/// Où se trouve, à cet avancement, la pièce qui va vers [arrivee].
///
/// Nulle quand rien ne vole, ou quand aucune glissée ne va là. Le chevron de
/// la meneuse s'en sert pour suivre sa pièce au lieu de l'attendre à
/// l'arrivée — Nino : « pendant une manœuvre, le symbole de meneuse doit
/// glisser avec la pièce » — et la couche des pièces en vol s'en sert pour
/// les placer, afin qu'il n'y ait qu'un seul calcul pour les deux.
Rect? placeEnVol(
  BoardGeometry g,
  List<(Piece, Cell, Cell)> slides,
  List<Cell> jumpPath,
  double progress,
  Cell arrivee,
) {
  if (progress >= 1 || slides.isEmpty) return null;
  // Toutes les pièces vont à la MÊME vitesse : celle qui va le plus loin
  // occupe toute l'animation, les autres arrivent avant et s'y posent.
  final span = slideSpan(slides, jumpPath);
  for (final (_, from, to) in slides) {
    if (to != arrivee) continue;
    // Le multisaut suit ses atterrissages ; tout le reste va tout droit.
    final etapes = slideSteps(
      from,
      to,
      jumpPath,
      isJumper: to == slides.last.$3,
    );
    final mienne = pathLength(etapes);
    final avance = (mienne <= 0 || span <= 0)
        ? 1.0
        : (progress * span / mienne).clamp(0.0, 1.0);
    return slidePosition(g, etapes, avance);
  }
  return null;
}

/// Où se trouve une pièce qui glisse, à cet avancement, le long d'un chemin.
///
/// [etapes] va du départ à l'arrivée, atterrissages intermédiaires compris.
/// Chaque bond dure le même temps : c'est ce qui donne le rythme d'une pièce
/// qui rebondit, là où un découpage à la distance parcourue la ferait ralentir
/// sur les bonds courts. À mi-parcours d'un double saut, la pièce est donc
/// EXACTEMENT sur son atterrissage intermédiaire — la case où s'affiche le
/// petit carré du dernier coup.
Rect slidePosition(BoardGeometry g, List<Cell> etapes, double t) {
  if (etapes.length < 2) {
    final seule = etapes.isEmpty ? const Cell(0, 0) : etapes.first;
    return g.cellRect(seule.col, seule.row);
  }
  // Le temps se répartit selon la DISTANCE, pas selon le nombre de bonds.
  // À temps égal par bond, un multisaut de trois bonds couvrait six cases
  // dans le temps d'une seule : la pièce filait trois fois plus vite.
  final total = pathLength(etapes);
  if (total <= 0) return g.cellRect(etapes.last.col, etapes.last.row);
  var reste = t.clamp(0.0, 1.0) * total;
  for (var i = 0; i < etapes.length - 1; i++) {
    final bond = cellDistance(etapes[i], etapes[i + 1]);
    if (reste <= bond || i == etapes.length - 2) {
      return Rect.lerp(
        g.cellRect(etapes[i].col, etapes[i].row),
        g.cellRect(etapes[i + 1].col, etapes[i + 1].row),
        bond <= 0 ? 1.0 : (reste / bond).clamp(0.0, 1.0),
      )!;
    }
    reste -= bond;
  }
  return g.cellRect(etapes.last.col, etapes.last.row);
}

/// Distance entre deux cases, en cases : un pas de diagonale en vaut UNE,
/// comme un pas droit. C'est la distance que l'œil perçoit.
double cellDistance(Cell a, Cell b) {
  final dc = (b.col - a.col).abs();
  final dr = (b.row - a.row).abs();
  return (dc > dr ? dc : dr).toDouble();
}

/// Longueur d'un chemin, en cases.
double pathLength(List<Cell> etapes) {
  var total = 0.0;
  for (var i = 0; i < etapes.length - 1; i++) {
    total += cellDistance(etapes[i], etapes[i + 1]);
  }
  return total;
}

/// Le chemin que suit une pièce : tout droit, sauf le multisaut qui passe
/// par ses atterrissages.
List<Cell> slideSteps(
  Cell from,
  Cell to,
  List<Cell> jumpPath, {
  required bool isJumper,
}) => isJumper && jumpPath.isNotEmpty
    ? <Cell>[from, ...jumpPath, to]
    : <Cell>[from, to];

/// La plus longue distance parcourue par ce lot de glissées, en cases.
///
/// C'est elle qui donne la durée : à vitesse constante, l'animation dure le
/// temps qu'il faut à la pièce qui va le plus loin. Les autres arrivent
/// avant, chacune à sa propre distance.
double slideSpan(List<(Piece, Cell, Cell)> slides, List<Cell> jumpPath) {
  var plus = 0.0;
  for (final (_, from, to) in slides) {
    final d = pathLength(
      slideSteps(from, to, jumpPath, isJumper: to == slides.last.$3),
    );
    if (d > plus) plus = d;
  }
  return plus;
}

/// Les pièces en vol, par-dessus le reste — l'équivalent de la couche animée
/// que Kivy dessine au-dessus du plateau (`animate_slide`).
///
/// Couche séparée pour que les soixante images par seconde d'un glissement ne
/// redessinent que la pièce qui bouge : les quarante autres, elles, ne
/// changent pas d'une image à l'autre.
final class FlyingPiecesPainter extends CustomPainter {
  const FlyingPiecesPainter({
    required this.geometry,
    required this.palette,
    required this.slides,
    required this.progress,
    this.jumpPath = const [],
    this.images,
    this.theme,
    this.choisies = const {},
  });

  final BoardGeometry geometry;
  final ThemePalette palette;

  /// Les cases CHOISIES, à l'arrivée.
  ///
  /// Une pièce reste enfoncée tant qu'on la tient — y compris en vol. Sans
  /// cela, une manœuvre reprenait sa pleine couleur le temps du glissement
  /// et la perdait en se posant : la pièce clignotait. Nino : « la pièce doit
  /// rester enfoncée tant qu'elle est sélectionnée, y compris pendant qu'elle
  /// glisse. » On les reconnaît à leur ARRIVÉE : la sélection a déjà suivi le
  /// coup quand le dessin commence.
  final Set<Cell> choisies;

  /// Pièces en train de glisser : (pièce, départ, arrivée).
  final List<(Piece, Cell, Cell)> slides;

  /// Avancement du glissement, de 0 à 1. À 1, plus rien ne vole.
  final double progress;

  /// Atterrissages intermédiaires d'un multisaut, sans le départ ni l'arrivée.
  ///
  /// La pièce y PASSE, au lieu de couper en ligne droite jusqu'au bout. Ce
  /// sont exactement les cases où s'affichent les petits carrés du dernier
  /// coup : on doit la voir sauter de l'une à l'autre, sinon le chemin
  /// parcouru reste une devinette.
  final List<Cell> jumpPath;

  final LoadedThemeImages? images;
  final String? theme;

  /// Cases d'arrivée, celles que la couche du dessous doit laisser vides.
  Set<Cell> get flying =>
      progress >= 1 ? const {} : {for (final (_, _, to) in slides) to};

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    final g = geometry;
    for (final (piece, _, to) in slides) {
      final place = placeEnVol(g, slides, jumpPath, progress, to)!;
      final choisie = choisies.contains(to);
      if (choisie) ouvreChoisie(canvas, place, piece, images);
      paintPiece(
        canvas,
        place,
        piece,
        palette,
        flipped: g.flipped,
        boardColor: palette.board,
        images: images,
        theme: theme,
        rainbowFraction: rainbowFractionOf(to.col, to.row),
      );
      if (choisie) refermeChoisie(canvas, place, piece, images, theme);
    }
  }

  @override
  bool shouldRepaint(FlyingPiecesPainter old) =>
      old.progress != progress ||
      old.slides.length != slides.length ||
      !listEquals(old.jumpPath, jumpPath) ||
      old.images != images ||
      old.palette != palette ||
      old.geometry.flipped != geometry.flipped ||
      !setEquals(old.choisies, choisies) ||
      old.theme != theme;
}

/// Notes telles qu'elles s'écrivent SOUS le plateau : en minuscules. La
/// notation `.nmc`, elle, les capitalise.
const List<String> kBoardNotes = ['do', 'ré', 'mi', 'fa', 'sol', 'la', 'si'];

/// Où ancrer un texte dessiné sur le plateau.
enum _Anchor { bottomLeft, center }
