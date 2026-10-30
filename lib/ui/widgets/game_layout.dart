/// Disposition d'un écran de jeu — portage de la pile de `GameScreen._build`
/// (main.py).
///
/// Cinq bandes, aux proportions de Kivy : bandeau des touches (7 %), panneau
/// du joueur du haut (12 %), plateau (66 %), panneau du bas (12 %), bandeau
/// des coups (7 %).
///
/// Le plateau est posé **par-dessus** le reste, sur l'emplacement qui lui est
/// réservé : ses zones de ralliement débordent volontairement dans les
/// panneaux, comme chez Kivy où `board_w` est ajouté au FloatLayout APRÈS la
/// pile et calé sur `_board_slot`. Sans cela, la bande de ralliement du bas
/// est mangée par le panneau.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';

import '../scale.dart';

/// Les parts de hauteur d'un écran de jeu : 7 + 12 + 66 + 12 + 7 = 104.
const int kPartsEcran = 104;

/// Ce qu'un bandeau peut au plus céder au plateau, en fraction de sa
/// hauteur.
///
/// Un cinquième : de quoi absorber le débordement des téléphones courants
/// sans écraser ce qu'un bandeau de joueur contient. Au-delà — une tablette,
/// où le plateau dépasse de bien plus — les bandeaux gardent leur hauteur :
/// les rétrécir à moitié ne réglerait rien et couperait leur contenu.
const double kBandeauRetraitMax = 0.2;

/// Parts prises par un bandeau de joueur.
const int kPartsBandeauJoueur = 12;

/// Parts prises par un bandeau FIN — celui des touches, en haut, et celui
/// des coups, en bas.
const int kPartsBarre = 7;

/// Hauteur d'un bandeau fin, en pixels logiques.
///
/// Le tuto s'en sert pour que sa rangée du haut ait l'épaisseur de celle
/// d'une partie, et donc sa touche de pause la même taille.
double hauteurBarre() => screenHeight * kPartsBarre / kPartsEcran;

/// Hauteur d'un bandeau de joueur, en pixels logiques.
///
/// C'est une mesure que les autres écrans empruntent : le profil s'en sert
/// pour se décaler d'autant du haut de l'écran. Nino : « le tout doit être
/// décalé vers le bas de la taille des bandeaux dans les parties. »
double hauteurBandeauJoueur() =>
    screenHeight * kPartsBandeauJoueur / kPartsEcran;

/// Hauteur d'un bandeau de joueur EN PARTIE, le retrait compris.
///
/// [hauteurBandeauJoueur] donne les douze parts brutes ; celle-ci donne ce
/// qu'il RESTE au bandeau une fois qu'il a cédé au plateau ce qui lui
/// manquait (voir le calcul du `build`, qui aboutit au même nombre).
///
/// L'analyse en a besoin : sa touche d'annulation doit tomber exactement là
/// où elle est en partie, à la même taille, et sa taille se déduit de la
/// hauteur du bandeau. Nino : « il doit être LE MÊME et placé AU MÊME
/// ENDROIT qu'en partie. »
double hauteurBandeauEnPartie(Size ecran) {
  final unit = ecran.height / kPartsEcran;
  final bandeau = unit * kPartsBandeauJoueur;
  final deux = 2 * bandeau;
  final naturel = ecran.width * kExtRows / kCols;
  final manque = deux + naturel - (ecran.height - 2 * (unit * kPartsBarre));
  if (manque > 0 && manque <= deux * kBandeauRetraitMax) {
    return bandeau - bandeau * (manque / deux);
  }
  return bandeau;
}

class GameLayout extends StatefulWidget {
  const GameLayout({
    super.key,
    required this.topBar,
    required this.topPanel,
    required this.board,
    required this.bottomPanel,
    required this.moveStrip,
    this.notice,
    this.bottomParts = 12,
    this.topOverlay,
    this.topPanelDevant = false,
    this.topHeight,
    this.bottomHeight,
  });

  final Widget topBar;

  /// Bandeau du joueur du haut. Nul en analyse : leur absence est le signe
  /// qu'on explore une position au lieu de jouer une partie.
  final Widget? topPanel;

  final Widget board;

  /// Bandeau du joueur du bas. Nul en analyse, comme [topPanel].
  final Widget? bottomPanel;

  final Widget moveStrip;

  /// Parts de hauteur données au panneau du BAS, sur 104. Douze par défaut,
  /// comme Kivy. La lecture automatique en demande davantage : un curseur et
  /// trois touches ne tiennent pas dans la bande d'un panneau de joueur, et
  /// ce qu'elle prend, elle le prend au plateau.
  final int bottomParts;

  /// Bandeau d'avertissement facultatif, sous le bandeau des touches.
  final Widget? notice;

  /// Posé PAR-DESSUS le bandeau de l'adversaire, et rogné à sa boîte.
  ///
  /// C'est là que passent les messages reçus en cours de partie. En le plaçant
  /// dans la boîte du bandeau plutôt qu'en surimpression de l'écran, on obtient
  /// gratuitement ce que Nino demande : « il ne faut pas que ça déborde sur le
  /// plateau ni sur les touches du haut. » Aucun message, si long soit-il, ne
  /// peut en sortir.
  final Widget? topOverlay;

  /// Le bandeau du haut passe DEVANT les bulles, au lieu d'être dessous.
  ///
  /// Les bulles sont posées par-dessus le bandeau de l'adversaire : c'est
  /// leur place, et un message doit se lire sans quitter le plateau. Mais ce
  /// bandeau cède parfois la place à une proposition de nulle, et une
  /// question à laquelle il faut répondre ne se laisse pas recouvrir par un
  /// message qui passe. Nino : « la proposition de nulle doit passer devant
  /// la bulle de texte ingame et pas l'inverse. »
  ///
  /// Les bulles ne sont pas cachées pour autant : elles continuent de défiler
  /// derrière, et reparaissent dès que la question est répondue.
  final bool topPanelDevant;

  /// Hauteur imposée au bandeau du haut, au lieu de ses 12 parts.
  ///
  /// L'analyse et les pré-coups n'y mettent que deux lignes de pièces
  /// prises : elles n'ont pas besoin de la hauteur d'un bandeau de joueur,
  /// qui loge un nom, un chrono et des touches.
  final double? topHeight;

  /// Hauteur imposée au bandeau du BAS, comme [topHeight] pour celui du
  /// haut. L'analyse n'y met qu'une touche : lui laisser les douze parts
  /// d'un bandeau de joueur mangerait le plateau pour rien.
  final double? bottomHeight;

  @override
  State<GameLayout> createState() => _GameLayoutState();
}

class _GameLayoutState extends State<GameLayout> {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // 7 + 12 + 66 + 12 + 7 = 104 parts. Sans les bandeaux, leurs 12 parts
      // reviennent au plateau : il n'y a pas de bande vide à regarder.
      final unit = box.maxHeight / kPartsEcran;
      final bar = unit * kPartsBarre;
      var top = widget.topPanel == null
          ? 0.0
          : (widget.topHeight ?? unit * kPartsBandeauJoueur);
      var bottom = widget.bottomPanel == null
          ? 0.0
          : (widget.bottomHeight ?? unit * widget.bottomParts);

      // LES BANDEAUX CÈDENT CE QUI MANQUE AU PLATEAU.
      //
      // Un plateau dessine DIX rangées de haut — les huit jouables et les
      // deux zones de ralliement — pour sept de large : sa hauteur naturelle
      // vaut donc 10/7 de la largeur, et il est centré dans la place qu'on
      // lui réserve. Quand cette place est plus courte, il déborde des deux
      // côtés et vient peindre sur les bandeaux. Nino : « rétrécis très
      // légèrement les bandeaux pour que le plateau ne déborde plus
      // dessus. »
      //
      // Les parts fixes (12 + 66 + 12) ne peuvent pas convenir à toutes les
      // formes d'écran : plus un téléphone est étroit, plus son plateau est
      // haut. On mesure donc le manque, et les bandeaux le rendent — au
      // prorata de ce qu'ils occupent, et sans jamais perdre plus de
      // [kBandeauRetraitMax] de leur hauteur, pour que le nom, le chrono et
      // les touches y tiennent encore.
      if (widget.topHeight == null &&
          widget.bottomHeight == null &&
          top + bottom > 0) {
        final naturel = box.maxWidth * kExtRows / kCols;
        final manque = top + bottom + naturel - (box.maxHeight - 2 * bar);
        // ET SEULEMENT SI CELA SUFFIT. Sur une tablette, large, le plateau
        // dépasse de bien plus que ce que les bandeaux peuvent céder : les
        // rétrécir quand même les abîmerait sans rien régler — le « ∞ » du
        // chrono n'y tenait plus. Quand le manque dépasse ce qu'ils ont à
        // donner, ils gardent leur hauteur.
        if (manque > 0 && manque <= (top + bottom) * kBandeauRetraitMax) {
          final part = manque / (top + bottom);
          top -= top * part;
          bottom -= bottom * part;
        }
      }

      final board = box.maxHeight - 2 * bar - top - bottom;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              SizedBox(height: bar, child: widget.topBar),
              if (widget.notice != null) widget.notice!,
              if (widget.topPanel != null)
                SizedBox(
                  height: top,
                  child: widget.topOverlay == null
                      ? widget.topPanel
                      : ClipRect(
                          child: Stack(
                            children: widget.topPanelDevant
                                ? [
                                    Positioned.fill(child: widget.topOverlay!),
                                    Positioned.fill(child: widget.topPanel!),
                                  ]
                                : [
                                    Positioned.fill(child: widget.topPanel!),
                                    Positioned.fill(child: widget.topOverlay!),
                                  ],
                          ),
                        ),
                ),
              SizedBox(height: board),
              if (widget.bottomPanel != null)
                SizedBox(height: bottom, child: widget.bottomPanel),
              SizedBox(height: bar, child: widget.moveStrip),
            ],
          ),
          Positioned(
            top: bar + top,
            left: 0,
            right: 0,
            height: board,
            child: widget.board,
          ),
        ],
      );
    },
  );
}
