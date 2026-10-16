/// Mécanique du glissement des pièces, partagée par les écrans de jeu.
///
/// Kivy anime CHAQUE coup — le sien, celui de l'adversaire, celui de Deep
/// Grey, et les pièces poussées — par `animate_slide`. Ici, chaque écran
/// retient le dernier lot de pièces à faire glisser et un jeton qui change à
/// chaque coup : c'est lui qui relance l'animation côté plateau.
library;

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/last_move.dart';
import '../../game/slides.dart';
import '../../state/settings.dart';

mixin SlideAnimation {
  /// Pièces du dernier coup : (pièce, départ, arrivée).
  List<(Piece, Cell, Cell)> slides = const [];

  /// Change à chaque coup, même si les cases se répètent.
  int slideToken = 0;

  /// Atterrissages intermédiaires du multisaut en cours d'animation, s'il y en
  /// a un. La pièce doit y passer au lieu de couper tout droit.
  List<Cell> slideJumpPath = const [];

  /// Retient un coup à animer. Sans rien à déplacer, on n'anime pas.
  void rememberSlides(
    List<(Piece, Cell, Cell)> moved, {
    List<Cell> jumpPath = const [],
  }) {
    if (moved.isEmpty) return;
    slides = moved;
    slideJumpPath = jumpPath;
    slideToken++;
  }

  /// Fait glisser les pièces du coup numéro [index] (1 = le premier coup).
  ///
  /// [positions] porte les positions successives — `positions[0]` est le
  /// départ, `positions[k]` l'état d'après le k-ième coup — et [notations]
  /// les coups eux-mêmes.
  ///
  /// Les trois écrans de jeu avaient chacun leur copie de ces vingt lignes,
  /// à trois mots près : le nom de leur liste de positions, et la façon d'y
  /// prendre les notations. Une correction de l'animation devait donc être
  /// faite trois fois, et une seule oubliée suffisait à ce que la relecture
  /// d'une correspondance saute là où celle d'une partie locale glissait.
  void animerCoupDe({
    required List<Board> positions,
    required List<String> notations,
    required int index,
    bool recule = false,
    int? versIndex,
  }) {
    if (index <= 0 || index >= positions.length) return;
    final avant = positions[index - 1];
    final apres = positions[index];
    final notation = index - 1 < notations.length ? notations[index - 1] : '';
    final chemin =
        lastMoveFromNotation(notation, avant, apres)?.jumpPath ??
        const <Cell>[];
    // On saute de plusieurs coups d'un coup : l'animation doit finir sur la
    // position affichée, pas sur celle d'un coup intermédiaire.
    final cible = recule ? (versIndex ?? index - 1) : index;
    final saut = recule && cible != index - 1;
    rememberSlides(
      glisseesDuCoup(
        avant: avant,
        apres: saut ? positions[cible] : apres,
        notation: saut ? '' : notation,
        recule: recule,
      ),
      jumpPath: saut
          ? const <Cell>[]
          : (recule ? chemin.reversed.toList() : chemin),
    );
  }

  /// Durée du glissement, telle que réglée dans les préférences.
  Duration get slideDuration =>
      Duration(milliseconds: (Settings.instance.slideSpeed * 1000).round());
}
