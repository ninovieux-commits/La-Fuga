/// Panneau d'un joueur — portage de `top_info` / `bot_info` (main.py).
///
/// Avatar, nom, chrono, score, pièces prises, et les gestes du côté :
/// annuler le coup en cours (↶), le message rapide, et le drapeau — qui
/// réunit la nulle (½) et l'abandon (X) de Kivy derrière un popup.
/// Le panneau du bas est le miroir de celui du haut, comme en Kivy.
///
/// **Le panneau ne dit pas à qui est le tour.** Chez Kivy il est toujours du
/// gris des menus (`COL_BG_MENU`), texte noir ; ce sont les deux bandeaux
/// fins — celui des touches en haut, celui des coups en bas — qui prennent la
/// couleur du camp, vive quand il a le trait.
library;

import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'etoile_favori.dart';
import 'drapeau_dialog.dart';
import 'fuga_button.dart';
import 'picto_touche.dart';
import 'bandeau_prises.dart';
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

/// La touche carrée des rangées d'action — ↶, message rapide, drapeau.
///
/// Elle vivait en privé dans le panneau du joueur. L'analyse a la sienne, et
/// Nino : « le bouton d'annulation de coup en analyse doit être identique et
/// au même endroit qu'en partie. » Identique veut dire le même widget, pas
/// deux dessins qui se ressemblent : c'est la seule façon qu'ils ne divergent
/// plus jamais.
class ToucheAction extends StatelessWidget {
  const ToucheAction({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.enfant,
    required this.palette,
    this.color = kGrisTouche,
    this.enabled = true,
    this.onBlocked,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget enfant;
  final ThemePalette palette;
  final Color color;

  /// Éteinte, la touche se fond à moitié dans le panneau et son libellé
  /// pâlit : elle reste lisible, mais visiblement hors d'usage. Elle a porté
  /// des hachures le temps d'un essai ; Nino, les ayant vues en vrai, a
  /// demandé qu'on revienne à ceci.
  final bool enabled;

  /// Elle reste touchable éteinte : c'est lui qui dit ce qui manque, au
  /// moment où l'on se pose la question.
  final VoidCallback? onBlocked;

  /// Hauteur d'une rangée qui ne porte que des touches d'action.
  ///
  /// Celle qu'elles occupent dans un bandeau de joueur : la touche y est
  /// carrée et remplit la rangée, donc son côté EST cette hauteur.
  static double hauteurRangee() => S(kLignePrises) * 1.2;

  /// Place qu'une touche prend dans la rangée, son écart de gauche compris.
  ///
  /// Une rangée qui n'a pas toutes les touches réserve la place des
  /// absentes : c'est ce qui tient les touches à la même abscisse d'un
  /// écran à l'autre.
  static double largeur(double rangee) => S(6) + rangee;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Padding(
      padding: EdgeInsets.only(left: S(6)),
      child: FractionallySizedBox(
        // La rangée est déjà à la bonne épaisseur : la touche la remplit.
        heightFactor: 1,
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: enabled ? color : Color.lerp(color, palette.menu, 0.6)!,
            borderRadius: BorderRadius.circular(S(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(S(16)),
              onTap: enabled ? onPressed : onBlocked,
              // Éteinte, le DESSIN pâlit avec le fond — la même pâleur que
              // partout ailleurs dans l'appli. Le libellé le faisait de
              // lui-même tant que ces touches portaient des lettres ; elles
              // portent maintenant des dessins, qui n'en savent rien.
              child: Center(
                child: enabled
                    ? enfant
                    : Opacity(opacity: kOpaciteEteinte, child: enfant),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Le dessin de la touche d'annulation : la flèche qui revient en arrière.
///
/// Comme la boule, l'avion et le drapeau : un fichier blanc sur fond
/// transparent, teinté par le thème, qui prend la part d'une lettre pour
/// laisser voir le carré de la touche. Le ↶ reste en secours.
Widget glypheAnnuler(ThemePalette palette) => PictoTouche(
  asset: 'assets/images/annuler.webp',
  couleur: palette.clair,
  secours: '↶',
);

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
    this.raisonNulle,
    this.busy = false,
    this.mirrored = false,
    this.onUndo,
    this.messageAbandon,
    this.onDraw,
    this.onResign,
    this.onMessageRapide,
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

  /// Ce que la confirmation d'abandon dit sous son titre.
  ///
  /// Une partie locale nomme qui abandonne et ce que l'autre marque ; une
  /// partie en ligne n'a rien à ajouter. L'écran sait, le bandeau non.
  final String? messageAbandon;
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
  /// Pourquoi la nulle n'est pas proposable, quand elle ne l'est pas.
  ///
  /// Le ½ éteint répondait par une boîte de dialogue : il fallait le toucher
  /// pour apprendre ce qui manquait. La raison est maintenant ÉCRITE dans le
  /// popup du drapeau, au-dessus de la touche pâlie — on la lit sans rien
  /// demander. L'écran la fournit parce qu'il la connaît : en
  /// correspondance, « répondez d'abord à la nulle proposée » n'est pas la
  /// même chose que « jouez votre coup ».
  final String? raisonNulle;

  /// Ce camp a proposé la nulle : Kivy allume alors son ½ en orange.
  final bool drawOffered;
  final VoidCallback? onResign;

  /// Écrire un mot à l'adversaire sans quitter le plateau des yeux.
  ///
  /// N'appartient qu'à MON panneau : on n'écrit pas à sa propre place.
  final VoidCallback? onMessageRapide;

  /// Épaisseur de la rangée d'actions dans un bandeau de [hauteurBandeau].
  ///
  /// L'analyse s'en sert pour poser SA touche d'annulation à la même taille
  /// et à la même place : même formule, même bandeau, même touche.
  static double hauteurActions(double hauteurBandeau) =>
      math.min(touchHeight(), (hauteurBandeau - 2 * margeV()) * 0.55);

  /// Marges du bandeau, qu'un autre écran doit reprendre pour aligner ses
  /// touches sur les siennes.
  static double margeH() => S(10);
  static double margeV() => S(4);

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
          ? hauteurActions(box.maxHeight)
          : S(32);
      final rows = box.maxHeight.isFinite
          ? [
              Expanded(child: _identity()),
              SizedBox(height: actions, child: _actions(context)),
            ]
          : [
              SizedBox(height: S(34), child: _identity()),
              SizedBox(height: actions, child: _actions(context)),
            ];

      // DES BORDS CARRÉS, JUSQU'AU BORD DE L'ÉCRAN. Les coins arrondis
      // laissaient paraître le fond aux quatre angles, et le bandeau
      // semblait flotter au-dessus de la page alors que les bandeaux fins,
      // eux, vont d'un bord à l'autre. Nino : « les angles des bandeaux ne
      // doivent plus être arrondis, ils doivent aller jusqu'aux bords de
      // l'écran comme les bandeaux fins le font. »
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: margeH(), vertical: margeV()),
        color: palette.menu,
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
  Widget _actions(BuildContext context) => Row(
    children: [
      Expanded(
        child: CapturesStrip(pieces: captures, palette: palette),
      ),
      // L'ANNULATION EN TÊTE, et c'est une question de place fixe. Nino :
      // « chaque bouton sur les écrans de jeux doit être fixé, ne jamais
      // changer de place. Ce qui veut dire, dans le bandeau large du bas,
      // que le bouton pour annuler le coup doit être celui qui est le plus à
      // gauche, autrement il est obligé de décaler le bouton de message
      // rapide. »
      //
      // Les prises occupent tout ce qui reste à gauche : le groupe de
      // touches est donc collé à DROITE.
      //
      // ELLE NE DISPARAÎT PLUS. Nino : « le bouton annulation de coup ne
      // doit plus disparaître lorsqu'il n'est pas cliquable, il doit faire
      // comme les autres touches quand elles ne sont pas cliquables. » Sans
      // coup à annuler, elle s'éteint donc au lieu de s'en aller — comme le
      // drapeau quand la nulle est fermée. C'est aussi ce qui tient la
      // rangée immobile sans avoir à la ranger dans un ordre particulier.
      _carre(
        T('Annuler'),
        onUndo ?? () {},
        enabled: onUndo != null,
        enfant: glypheAnnuler(palette),
      ),
      // LE MESSAGE RAPIDE, ensuite. Nino l'a dessiné là, à gauche du geste
      // qui termine la partie : la place la plus éloignée de l'abandon.
      //
      // L'AVION EN PAPIER, et non plus une bulle de dialogue de Material :
      // « accordé au thème comme le bouton boule de voyance et le bouton
      // drapeau ». Même recette que les deux autres — blanc sur fond
      // transparent, teinté par la palette (cf. [PictoTouche]).
      if (onMessageRapide != null)
        _carre(
          T('Message rapide'),
          onMessageRapide!,
          enfant: PictoTouche(
            asset: 'assets/images/avion.webp',
            // L'AUTRE COULEUR DU THÈME, pour équilibrer la rangée : le
            // drapeau et l'annulation en clair, l'avion en foncé.
            couleur: palette.fonce,
            secours: '✈',
          ),
        ),
      // LE DRAPEAU remplace le ½ et le X. Nino : « le bouton abandonner et
      // le bouton match nul doivent disparaître. À la place on met un bouton
      // avec ce drapeau. » Ce sont les deux seuls gestes qui terminent une
      // partie sans la jouer : ils tenaient chacun leur carré à côté de ceux
      // dont on se sert à chaque coup, et le rouge de l'abandon était à un
      // doigt du reste.
      if (onDraw != null || onResign != null)
        _carre(
          T('Abandonner ou proposer la nulle ?'),
          () => unawaited(
            ouvrirDrapeau(
              context,
              palette: palette,
              nulleActive: drawEnabled && onDraw != null,
              nulleProposee: drawOffered,
              messageAbandon: messageAbandon ?? '',
              raisonNulle: raisonNulle,
              onNulle: onDraw,
              onAbandon: onResign,
            ),
          ),
          // Le dessin suit le thème, comme les instruments des réglages :
          // blanc sur fond transparent, teinté ici. Garder son fond
          // d'origine, qui est blanc, aurait troué le bandeau. Il n'occupe
          // que la part d'une lettre, pour que la touche reste un carré —
          // cf. [PictoTouche].
          enfant: PictoTouche(
            asset: 'assets/images/drapeau.webp',
            couleur: palette.clair,
            secours: '⚑',
          ),
        ),
    ],
  );

  /// Touche carrée de la rangée d'actions : chez Kivy elle occupe 85 % de la
  /// hauteur de la rangée et sa largeur suit sa hauteur.
  Widget _carre(
    String tooltip,
    VoidCallback onPressed, {
    required Widget enfant,
    Color color = kFugaGrey,
    bool enabled = true,
    VoidCallback? onBlocked,
  }) => ToucheAction(
    tooltip: tooltip,
    onPressed: onPressed,
    enfant: enfant,
    palette: palette,
    color: color,
    enabled: enabled,
    onBlocked: onBlocked,
  );
}
