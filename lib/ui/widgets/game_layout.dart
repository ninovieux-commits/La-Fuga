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

class GameLayout extends StatelessWidget {
  const GameLayout({
    super.key,
    required this.topBar,
    required this.topPanel,
    required this.board,
    required this.bottomPanel,
    required this.moveStrip,
    this.notice,
  });

  final Widget topBar;
  final Widget topPanel;
  final Widget board;
  final Widget bottomPanel;
  final Widget moveStrip;

  /// Bandeau d'avertissement facultatif, sous le bandeau des touches.
  final Widget? notice;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // 7 + 12 + 66 + 12 + 7 = 104 parts.
      final unit = box.maxHeight / 104;
      final bar = unit * 7;
      final panel = unit * 12;
      final board = unit * 66;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              SizedBox(height: bar, child: topBar),
              if (notice != null) notice!,
              SizedBox(height: panel, child: topPanel),
              SizedBox(height: board),
              SizedBox(height: panel, child: bottomPanel),
              SizedBox(height: bar, child: moveStrip),
            ],
          ),
          Positioned(
            top: bar + panel,
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
