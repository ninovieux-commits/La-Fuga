/// Poids appris de Deep Grey — portage de `_dg_weights` / `dg_learn_weights`.
///
/// Chaque catégorie de la table d'évaluation porte un multiplicateur que l'IA
/// affine elle-même après chaque partie, sous garde-fous stricts :
///  - borné à [0.60, 1.40] : jamais plus de ±40 % de la valeur de base
///  - au plus 0.03 (±3 %) de mouvement par partie : changements progressifs
library;

import 'dart:convert';

import '../board.dart';
import '../piece.dart';

/// Les douze catégories pondérées.
const List<String> kWeightCategories = [
  'heir_adv',
  'heir_edge',
  'heir_immo',
  'heir_contact',
  'nurse_adv',
  'nurse_edge',
  'nurse_mat',
  'nurse_immo',
  'nurse_groups',
  'square_mat',
  'square_immo',
  'square_push',
];

const double kWeightMin = 0.60;
const double kWeightMax = 1.40;
const double kWeightStep = 0.03;

/// Multiplicateurs d'évaluation, avec valeur par défaut 1.0 pour toute
/// catégorie absente.
final class DeepGreyWeights {
  DeepGreyWeights([Map<String, double>? values])
      : _values = {
          for (final cat in kWeightCategories) cat: values?[cat] ?? 1.0,
        };

  final Map<String, double> _values;

  /// Poids effectif d'une catégorie.
  double operator [](String category) => _values[category] ?? 1.0;

  Map<String, double> get values => Map.unmodifiable(_values);

  static DeepGreyWeights fromJsonString(String s) {
    try {
      final raw = jsonDecode(s);
      if (raw is! Map) return DeepGreyWeights();
      return DeepGreyWeights({
        for (final e in raw.entries)
          if (e.value is num) e.key as String: (e.value as num).toDouble(),
      });
    } catch (_) {
      return DeepGreyWeights();
    }
  }

  String toJsonString() => jsonEncode(_values);

  /// Ajuste les poids après une partie, du point de vue du gagnant.
  ///
  /// Une catégorie qui a aidé le gagnant (contribution positive sur la
  /// position finale) monte un peu ; les autres descendent. L'amplitude est
  /// proportionnelle au poids relatif de la catégorie et plafonnée à
  /// [kWeightStep].
  DeepGreyWeights learn(Camp winner, Board finalBoard) {
    final contribs = categoryContributions(finalBoard, winner);
    final total =
        contribs.values.fold<double>(0, (a, v) => a + v.abs()).clamp(1e-9, double.infinity);

    final next = <String, double>{};
    for (final cat in kWeightCategories) {
      final contrib = contribs[cat] ?? 0.0;
      var delta = kWeightStep * (contrib / total);
      if (delta > kWeightStep) delta = kWeightStep;
      if (delta < -kWeightStep) delta = -kWeightStep;
      final updated =
          (this[cat] + delta).clamp(kWeightMin, kWeightMax).toDouble();
      next[cat] = double.parse(updated.toStringAsFixed(4));
    }
    return DeepGreyWeights(next);
  }
}

/// Contribution nette de chaque catégorie au score positionnel, du point de
/// vue de `camp`. Portage de `_dg_category_contributions`.
Map<String, double> categoryContributions(Board board, Camp camp) {
  final opp = camp.opposite;
  final rally = camp.rallyRow;
  final contribs = {for (final cat in kWeightCategories) cat: 0.0};

  Cell? myHeir, oppHeir;
  final myNurses = <Cell>[], oppNurses = <Cell>[];
  final mySquares = <Cell>[], oppSquares = <Cell>[];

  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p == null || p.isKnight) continue;
      final cell = Cell(c, r);
      switch (p.type) {
        case PieceType.heritier:
          p.camp == camp ? myHeir = cell : oppHeir = cell;
        case PieceType.nurse:
          (p.camp == camp ? myNurses : oppNurses).add(cell);
        case PieceType.soldat:
        case PieceType.garde:
          (p.camp == camp ? mySquares : oppSquares).add(cell);
        case PieceType.chevalier:
          break;
      }
    }
  }

  for (final (heir, cp) in [(myHeir, camp), (oppHeir, opp)]) {
    if (heir == null) continue;
    final sign = cp == camp ? 1.0 : -1.0;
    contribs['heir_adv'] =
        contribs['heir_adv']! + (8 - (heir.row - rally).abs()) * 15;
    if (heir.col == 0 || heir.col == kCols - 1) {
      contribs['heir_edge'] = contribs['heir_edge']! - sign * 30;
    }
    if (isPieceStuck(board, heir.col, heir.row)) {
      contribs['heir_immo'] = contribs['heir_immo']! - sign * 40;
    }
  }

  for (final (lst, cp) in [(myNurses, camp), (oppNurses, opp)]) {
    final sign = cp == camp ? 1.0 : -1.0;
    for (final cell in lst) {
      contribs['nurse_adv'] =
          contribs['nurse_adv']! + (8 - (cell.row - rally).abs()) * 10;
      if (cell.col == 0 || cell.col == kCols - 1) {
        contribs['nurse_edge'] = contribs['nurse_edge']! - sign * 20;
      }
      contribs['nurse_mat'] = contribs['nurse_mat']! + sign * 40;
      if (isPieceStuck(board, cell.col, cell.row)) {
        contribs['nurse_immo'] = contribs['nurse_immo']! - sign * 30;
      }
    }
  }

  for (final (lst, cp) in [(mySquares, camp), (oppSquares, opp)]) {
    final sign = cp == camp ? 1.0 : -1.0;
    for (final cell in lst) {
      contribs['square_mat'] = contribs['square_mat']! + sign * 50;
      if (isPieceStuck(board, cell.col, cell.row)) {
        contribs['square_immo'] = contribs['square_immo']! - sign * 20;
      }
      if (squareCanPushForward(board, cell.col, cell.row, cp)) {
        contribs['square_push'] = contribs['square_push']! + sign * 10;
      }
    }
  }

  return contribs;
}

/// Vrai si la pièce n'a aucune case libre dans ses directions naturelles.
///
/// Vérification légère : ne simule pas les poussées. Portage de
/// `_dg_is_immobile` et de l'`immobile()` local de `dg_positional_strategy`,
/// qui partagent la même logique.
bool isPieceStuck(Board board, int c, int r) {
  final p = board.at(c, r);
  if (p == null) return false;
  final dirs = switch (p.type) {
    PieceType.soldat => kSoldatPushDirs,
    PieceType.garde => kGardePushDirs,
    _ => kAllDirs, // rondes et Chevalier : 8 directions
  };
  for (final (dc, dr) in dirs) {
    final nc = c + dc, nr = r + dr;
    if (Board.onBoard(nc, nr) && board.at(nc, nr) == null) return false;
  }
  return true;
}

/// Vrai si la carrée est en position de pousser vers la zone-cible de son camp.
/// Portage de `_dg_square_can_push_forward`.
bool squareCanPushForward(Board board, int c, int r, Camp camp) {
  final p = board.at(c, r);
  if (p == null) return false;
  final fwd = camp.forward;
  final dirs = switch (p.type) {
    PieceType.soldat => [(-1, fwd), (1, fwd)], // diagonales avant
    PieceType.garde => [(0, fwd)], // orthogonale avant
    _ => const <(int, int)>[],
  };
  for (final (dc, dr) in dirs) {
    final tc = c + dc, tr = r + dr;
    if (!Board.onBoard(tc, tr)) continue;
    if (board.at(tc, tr) == null) continue;
    // Une pièce devant : y a-t-il de la place derrière, ou le bord (éjection) ?
    final bc = tc + dc, br = tr + dr;
    if (!Board.onBoard(bc, br)) return true;
    if (board.at(bc, br) == null) return true;
  }
  return false;
}
