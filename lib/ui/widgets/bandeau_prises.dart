/// Le matériel mangé, quand il n'y a pas de bandeau de joueur pour le porter.
///
/// Nino : « en mode analyse, il doit y avoir le matériel mangé qui apparaît
/// autour du plateau comme en partie. Ainsi que dans tous les modes
/// comprenant un plateau de jeu et des pièces pouvant être mangées. »
///
/// En partie, les prises vivent dans le bandeau du joueur, à côté de son nom
/// et de son chrono. L'analyse n'a ni nom ni chrono — on explore une
/// position, on ne joue pas contre quelqu'un —, et ses bandeaux étaient donc
/// retirés tout entiers. Le matériel partait avec eux, alors que c'est
/// justement ce qu'on regarde en analysant.
///
/// Même place, même hauteur et mêmes couleurs qu'un bandeau de partie : ce
/// n'est pas un autre écran, c'est le même sans ce qui ne sert pas.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'player_panel.dart';

class BandeauPrises extends StatelessWidget {
  const BandeauPrises({
    super.key,
    required this.pieces,
    required this.palette,
    required this.isWhite,
    this.miroir = false,
  });

  /// Les pièces prises PAR ce camp — celles de l'autre.
  final List<Piece> pieces;

  final ThemePalette palette;

  /// Le camp dont c'est le bandeau : il donne sa couleur de fond.
  final bool isWhite;

  /// Bandeau du bas : les prises s'alignent à droite, comme dans un bandeau
  /// de joueur retourné.
  final bool miroir;

  @override
  Widget build(BuildContext context) => Container(
    // La teinte atténuée : personne n'a le trait en analyse, et un bandeau
    // vif dirait le contraire.
    color: isWhite ? palette.clairDim : palette.fonceDim,
    padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(6)),
    child: Align(
      alignment: miroir ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.6,
        child: CapturesStrip(pieces: pieces, palette: palette),
      ),
    ),
  );
}
