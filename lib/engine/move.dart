/// Représentation d'un coup de La Fuga — Dart pur.
library;

import 'board.dart';
import 'piece.dart';

/// Nature d'un coup, reprise telle quelle du moteur Python (`kind`).
enum MoveKind {
  /// Déplacement simple d'une ronde.
  move,

  /// Saut (ou multisaut) d'une ronde.
  jump,

  /// L'Héritier atteint sa zone de ralliement.
  fugue,

  /// Déplacement d'une carrée, avec ou sans poussée.
  square,

  /// Manœuvre de groupe de carrées.
  maneuver,

  /// Déplacement du Chevalier.
  knight,
}

/// Un coup légal et le plateau qui en résulte.
///
/// Miroir exact du dict produit par `dg_generate_moves`, afin que le portage
/// reste vérifiable ligne à ligne face au moteur Python.
final class Move {
  Move({
    required this.board,
    required this.kind,
    required this.from,
    required this.movedCells,
    this.fugue = false,
    this.fugueBy,
    this.matOn,
    this.ejAlly = 0,
    this.ejOpp = 0,
    this.totalPushed = 0,
    this.pushDirsUsed = const [],
    this.fromCells,
  });

  /// Plateau résultant du coup.
  final Board board;

  final MoveKind kind;

  /// Case de départ (pièce maîtresse pour une manœuvre).
  final Cell from;

  /// Cases d'arrivée. Pour une manœuvre, la maîtresse est en premier : la
  /// notation et la mise en évidence en dépendent.
  final List<Cell> movedCells;

  /// Vrai si ce coup fait fuguer l'Héritier du camp qui joue.
  final bool fugue;

  /// Camp dont l'Héritier a été poussé jusqu'à SA zone de ralliement.
  /// Distinct de [fugue] : ici la fugue résulte d'une poussée.
  final Camp? fugueBy;

  /// Camp dont l'Héritier a été éjecté du plateau (mat).
  final Camp? matOn;

  /// Nombre de pièces alliées éjectées par la poussée.
  final int ejAlly;

  /// Nombre de pièces adverses éjectées par la poussée.
  final int ejOpp;

  /// Nombre total de pièces déplacées par la poussée.
  final int totalPushed;

  /// Directions effectivement poussées.
  final List<(int, int)> pushDirsUsed;

  /// Cases initiales d'une manœuvre (maîtresse en premier).
  final List<Cell>? fromCells;

  int get ejected => ejAlly + ejOpp;

  /// Case d'arrivée de la pièce maîtresse.
  Cell get to => movedCells.isNotEmpty ? movedCells.first : from;

  @override
  String toString() =>
      'Move(${kind.name} $from→$to${fugue ? ' FUGUE' : ''}'
      '${matOn != null ? ' MAT:${matOn!.wire}' : ''})';
}
