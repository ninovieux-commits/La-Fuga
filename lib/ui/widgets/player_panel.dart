/// Panneau d'un joueur — portage de `top_info` / `bot_info` (main.py).
///
/// Avatar, nom, chrono, score, pièces prises, et les trois gestes du côté :
/// annuler le coup en cours (↶), proposer la nulle (½), abandonner (X).
/// Le panneau du bas est le miroir de celui du haut, comme en Kivy.
///
/// **Le panneau ne dit pas à qui est le tour.** Chez Kivy il est toujours du
/// gris des menus (`COL_BG_MENU`), texte noir ; ce sont les deux bandeaux
/// fins — celui des touches en haut, celui des coups en bas — qui prennent la
/// couleur du camp, vive quand il a le trait.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'piece_painter.dart';
import 'profile_photo.dart';

/// Encre des panneaux : le `(0.05, 0.05, 0.05)` de Kivy, sur le gris des
/// menus.
const Color kPanelInk = Color.fromRGBO(13, 13, 13, 1);

/// Rouge du bouton d'abandon — `(0.55, 0.1, 0.1)`.
const Color kResignRed = Color.fromRGBO(140, 26, 26, 1);

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
    // Kivy plafonne à 36 px de l'écran de référence.
    final side = math.min(math.min(size.height - S(2), each), S(36));
    final step = side * 0.7;
    final top = (size.height - side) / 2;

    for (var i = 0; i < pieces.length; i++) {
      paintPiece(
        canvas,
        Rect.fromLTWH(i * step, top, side, side),
        pieces[i],
        palette,
        outlineWidth: S(1),
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
    this.nameColor = kPanelInk,
    this.onNameTap,
    this.drawOffered = false,
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

  /// Couleur du nom. Kivy le passe en rouge pendant le décompte de
  /// déconnexion de l'adversaire.
  final Color nameColor;

  /// Toucher le nom ouvre le menu du joueur (profil, favori, message,
  /// blocage) — `_on_name_click`. Absent pour un joueur qui n'en est pas un.
  final VoidCallback? onNameTap;

  final bool busy;

  /// Le panneau du bas inverse ses deux rangées, comme en Kivy.
  final bool mirrored;

  /// Annuler le coup en cours. Absent = geste indisponible de ce côté.
  final VoidCallback? onUndo;
  final VoidCallback? onDraw;

  /// Ce camp a proposé la nulle : Kivy allume alors son ½ en orange.
  final bool drawOffered;
  final VoidCallback? onResign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Chez Kivy les deux rangées se partagent la hauteur du panneau. Ici on
      // fait de même quand la hauteur est donnée (écran de jeu) et on retombe
      // sur des hauteurs fixes quand elle ne l'est pas (colonne libre).
      // La rangée d'actions prend l'épaisseur d'une touche quand le panneau
      // la laisse passer, sinon tout ce qu'il peut lui donner sans écraser la
      // ligne d'identité. Ses touches faisaient jusqu'ici 45 là où le reste de
      // l'appli en fait 51.
      final actions = box.maxHeight.isFinite
          ? math.min(touchHeight(), (box.maxHeight - 2 * S(4)) * 0.55)
          : S(32);
      final rows = box.maxHeight.isFinite
          ? [
              Expanded(child: _identity()),
              SizedBox(height: actions, child: _actions()),
            ]
          : [
              SizedBox(height: S(34), child: _identity()),
              SizedBox(height: actions, child: _actions()),
            ];

      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(4)),
        decoration: BoxDecoration(
          color: palette.menu,
          borderRadius: BorderRadius.circular(S(14)),
        ),
        child: Row(
          children: [
            // L'avatar de Kivy est carré et occupe TOUTE la hauteur du
            // panneau : sa largeur suit sa hauteur (`bind(height=…)`), la
            // valeur `S(58)` du constructeur n'est qu'un point de départ.
            ProfilePhoto(
              photo: photo,
              size: box.maxHeight.isFinite ? box.maxHeight - 2 * S(4) : S(58),
            ),
            SizedBox(width: S(8)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: mirrored ? rows.reversed.toList() : rows,
              ),
            ),
          ],
        ),
      );
    },
  );

  /// Nom, chrono et score — la rangée « loin du plateau ».
  Widget _identity() => Row(
    children: [
      Expanded(
        flex: 42,
        child: GestureDetector(
          onTap: onNameTap,
          child: Text(
            subtitle == null ? name : '$name  ·  $subtitle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: nameColor,
              fontSize: SF(16),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      if (busy)
        Padding(
          padding: EdgeInsets.only(right: S(8)),
          child: SizedBox(
            width: S(14),
            height: S(14),
            child: CircularProgressIndicator(strokeWidth: S(2)),
          ),
        ),
      Expanded(
        flex: 36,
        child: Text(
          clock,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: kPanelInk,
            fontSize: SF(19),
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      if (score != null)
        Expanded(
          flex: 22,
          child: Text(
            score!,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: kPanelInk,
              fontSize: SF(16),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
    ],
  );

  /// Prises et gestes — la rangée « près du plateau ».
  Widget _actions() => Row(
    children: [
      Expanded(
        child: CapturesStrip(pieces: captures, palette: palette),
      ),
      if (onUndo != null) _button('↶', T('Annuler'), onUndo!),
      if (onDraw != null)
        _button(
          '½',
          T('Proposer nulle'),
          onDraw!,
          color: drawOffered ? palette.clair : kFugaGrey,
        ),
      // L'abandon est rouge sombre chez Kivy : on n'y touche pas par mégarde.
      if (onResign != null)
        _button(
          'X',
          T('Abandonner'),
          onResign!,
          color: kResignRed,
          fontSize: SF(17),
        ),
    ],
  );

  /// Touche carrée de la rangée d'actions : chez Kivy elle occupe 85 % de la
  /// hauteur de la rangée et sa largeur suit sa hauteur.
  Widget _button(
    String label,
    String tooltip,
    VoidCallback onPressed, {
    Color color = kFugaGrey,
    double? fontSize,
  }) => Tooltip(
    message: tooltip,
    child: Padding(
      padding: EdgeInsets.only(left: S(6)),
      child: FractionallySizedBox(
        // La rangée est déjà à la bonne épaisseur : la touche la remplit.
        heightFactor: 1,
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(S(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(S(16)),
              onTap: onPressed,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize ?? SF(18),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
