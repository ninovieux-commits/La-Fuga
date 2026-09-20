/// Mécanique du glissement des pièces, partagée par les écrans de jeu.
///
/// Kivy anime CHAQUE coup — le sien, celui de l'adversaire, celui de Deep
/// Grey, et les pièces poussées — par `animate_slide`. Ici, chaque écran
/// retient le dernier lot de pièces à faire glisser et un jeton qui change à
/// chaque coup : c'est lui qui relance l'animation côté plateau.
library;

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../state/settings.dart';

mixin SlideAnimation {
  /// Pièces du dernier coup : (pièce, départ, arrivée).
  List<(Piece, Cell, Cell)> slides = const [];

  /// Change à chaque coup, même si les cases se répètent.
  int slideToken = 0;

  /// Retient un coup à animer. Sans rien à déplacer, on n'anime pas.
  void rememberSlides(List<(Piece, Cell, Cell)> moved) {
    if (moved.isEmpty) return;
    slides = moved;
    slideToken++;
  }

  /// Durée du glissement, telle que réglée dans les préférences.
  Duration get slideDuration =>
      Duration(milliseconds: (Settings.instance.slideSpeed * 1000).round());
}
