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

import '../scale.dart';

/// Les parts de hauteur d'un écran de jeu : 7 + 12 + 66 + 12 + 7 = 104.
const int kPartsEcran = 104;

/// Parts prises par un bandeau de joueur.
const int kPartsBandeauJoueur = 12;

/// Hauteur d'un bandeau de joueur, en pixels logiques.
///
/// C'est une mesure que les autres écrans empruntent : le profil s'en sert
/// pour se décaler d'autant du haut de l'écran. Nino : « le tout doit être
/// décalé vers le bas de la taille des bandeaux dans les parties. »
double hauteurBandeauJoueur() =>
    screenHeight * kPartsBandeauJoueur / kPartsEcran;

class GameLayout extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // 7 + 12 + 66 + 12 + 7 = 104 parts. Sans les bandeaux, leurs 12 parts
      // reviennent au plateau : il n'y a pas de bande vide à regarder.
      final unit = box.maxHeight / kPartsEcran;
      final bar = unit * 7;
      final top = topPanel == null ? 0.0 : unit * kPartsBandeauJoueur;
      final bottom = bottomPanel == null ? 0.0 : unit * bottomParts;
      final board = box.maxHeight - 2 * bar - top - bottom;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              SizedBox(height: bar, child: topBar),
              if (notice != null) notice!,
              if (topPanel != null)
                SizedBox(
                  height: top,
                  child: topOverlay == null
                      ? topPanel
                      : ClipRect(
                          child: Stack(
                            children: topPanelDevant
                                ? [
                                    Positioned.fill(child: topOverlay!),
                                    Positioned.fill(child: topPanel!),
                                  ]
                                : [
                                    Positioned.fill(child: topPanel!),
                                    Positioned.fill(child: topOverlay!),
                                  ],
                          ),
                        ),
                ),
              SizedBox(height: board),
              if (bottomPanel != null)
                SizedBox(height: bottom, child: bottomPanel),
              SizedBox(height: bar, child: moveStrip),
            ],
          ),
          Positioned(
            top: bar + top,
            left: 0,
            right: 0,
            height: board,
            child: this.board,
          ),
        ],
      );
    },
  );
}
