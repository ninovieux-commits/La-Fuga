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
import 'etoile_favori.dart';
import 'fuga_button.dart';
import 'hachures.dart';
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
    this.rating,
    this.subtitle,
    this.nameColor = kPanelInk,
    this.onNameTap,
    this.favori = false,
    this.drawOffered = false,
    this.drawEnabled = true,
    this.onDrawBlocked,
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

  /// Le classement, écrit SOUS le pseudo.
  ///
  /// Kivy l'écrivait à la suite du nom — « mesange  (1530) » — et c'est lui
  /// que l'ellipse mangeait en premier : sur un téléphone, le bandeau de
  /// l'adversaire affichait « mesange  (1… ». Nino : « durant les parties, le
  /// classement de la personne doit être en dessous du pseudo. Ainsi il ne
  /// sera jamais coupé. »
  final String? rating;

  /// Ce qui s'ajoute à la ligne du classement : la variation de mélo en fin
  /// de partie (« +8 »).
  final String? subtitle;

  /// Couleur du nom. Kivy le passe en rouge pendant le décompte de
  /// déconnexion de l'adversaire.
  final Color nameColor;

  /// Toucher le nom — OU LA PHOTO — ouvre la fiche du joueur.
  ///
  /// Nino : « ce même popup doit également apparaître si on clique sur le nom
  /// ou l'image de profil où qu'ils soient. » Absent pour un joueur qui n'en
  /// est pas un : Deep Grey et « Joueur 1 » n'ont pas de fiche.
  final VoidCallback? onNameTap;

  /// Dans MES favoris : une étoile paraît à côté du nom.
  ///
  /// Nino : « il doit y avoir une étoile dans les infos de joueur s'il est
  /// favori et cette étoile doit disparaître s'il est retiré. »
  final bool favori;

  final bool busy;

  /// Le panneau du bas inverse ses deux rangées, comme en Kivy.
  final bool mirrored;

  /// Annuler le coup en cours. Absent = geste indisponible de ce côté.
  final VoidCallback? onUndo;
  final VoidCallback? onDraw;

  /// Le ½ est-il actionnable ? Faux : il reste VISIBLE mais éteint.
  ///
  /// Le cacher serait plus simple, mais un bouton qui disparaît n'apprend
  /// rien : on ne sait pas qu'il existe, ni pourquoi il n'est pas là. Éteint,
  /// il se montre et son infobulle dit ce qui manque.
  final bool drawEnabled;

  /// Touché alors qu'il est éteint. L'infobulle demande de rester appuyé —
  /// personne ne le fait : c'est ce rappel-ci qui dit ce qui manque, au
  /// moment où on se pose la question.
  final VoidCallback? onDrawBlocked;

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
            GestureDetector(
              onTap: onNameTap,
              child: ProfilePhoto(
                photo: photo,
                size: box.maxHeight.isFinite ? box.maxHeight - 2 * S(4) : S(58),
              ),
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

  /// La ligne sous le pseudo : le classement, et la variation de mélo quand
  /// la partie vient de finir. `null` quand il n'y a ni l'un ni l'autre —
  /// une partie locale, par exemple.
  String? get _ligneBasse {
    final morceaux = [
      if (rating != null && rating!.isNotEmpty) rating!,
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
    ];
    return morceaux.isEmpty ? null : morceaux.join('   ');
  }

  /// Nom, chrono et score — la rangée « loin du plateau ».
  Widget _identity() => Row(
    children: [
      Expanded(
        flex: 42,
        child: GestureDetector(
          onTap: onNameTap,
          // DEUX LIGNES DANS UNE RANGÉE QUI N'EN PRÉVOYAIT QU'UNE.
          //
          // La rangée d'identité n'a que la hauteur que le bandeau lui laisse
          // — mesuré, une quarantaine de points sur un téléphone, mais 27 sur
          // un écran large et court, où les lettres suivent la LARGEUR et le
          // bandeau la HAUTEUR. Les deux lignes y débordaient de 5,8 points.
          //
          // `scaleDown` ne fait que rétrécir : à l'aise, rien ne bouge ; à
          // l'étroit, le bloc entier diminue au lieu de déborder. La largeur
          // reste celle de la case, pour que l'ellipse du pseudo continue de
          // jouer son rôle.
          child: LayoutBuilder(
            builder: (context, cellule) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: cellule.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // UN SEUL texte, étoile comprise, et non une rangée : voir
                    // `nomEtoile`, qui dit pourquoi.
                    Text.rich(
                      nomEtoile(name, favori: favori, taille: SF(16)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: nameColor,
                        fontSize: SF(16),
                        fontWeight: FontWeight.bold,
                        // Interligne serré : deux lignes à 1,43 — l'interligne
                        // d'usine — ne tiennent pas dans la rangée.
                        height: 1.1,
                      ),
                    ),
                    if (_ligneBasse != null)
                      Text(
                        _ligneBasse!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: SF(13),
                          height: 1.1,
                        ),
                      ),
                  ],
                ),
              ),
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
          drawEnabled
              ? (drawOffered ? T('Nulle proposée') : T('Proposer nulle'))
              : T('Jouez votre coup d abord'),
          onDraw!,
          color: drawOffered ? palette.clair : kFugaGrey,
          enabled: drawEnabled,
          onBlocked: onDrawBlocked,
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
    bool enabled = true,
    VoidCallback? onBlocked,
  }) => Tooltip(
    message: tooltip,
    child: Padding(
      padding: EdgeInsets.only(left: S(6)),
      child: FractionallySizedBox(
        // La rangée est déjà à la bonne épaisseur : la touche la remplit.
        heightFactor: 1,
        child: AspectRatio(
          aspectRatio: 1,
          // Éteinte, la touche garde sa couleur et se HACHURE — comme toutes
          // les touches hors service de l'application. Elle se fondait à
          // moitié dans le panneau ; on la prenait pour une touche terne.
          //
          // Elle reste touchable : c'est `onBlocked` qui dit ce qui manque,
          // au moment où l'on se pose la question.
          child: HorsService(
            actif: enabled,
            rayon: S(16),
            child: Material(
              color: color,
              borderRadius: BorderRadius.circular(S(16)),
              child: InkWell(
                borderRadius: BorderRadius.circular(S(16)),
                onTap: enabled ? onPressed : onBlocked,
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
    ),
  );
}
