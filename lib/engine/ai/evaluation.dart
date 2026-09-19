/// Évaluation de position de Deep Grey — portage de `dg_positional_strategy`,
/// `dg_evaluate` et `dg_move_bonus` (main.py). Dart pur : tourne en isolate.
library;

import '../board.dart';
import '../move.dart';
import '../move_generator.dart';
import '../piece.dart';
import 'weights.dart';

/// Cache d'évaluation, borné pour ne pas croître indéfiniment.
/// Vidé avant chaque réflexion, comme `_DG_EVAL_CACHE.clear()` en Python.
final class EvalCache {
  EvalCache({this.maxEntries = 50000});

  final int maxEntries;
  final Map<String, double> _entries = {};

  double? get(String boardKey, Camp camp) => _entries['$boardKey|${camp.wire}'];

  void put(String boardKey, Camp camp, double score) {
    if (_entries.length >= maxEntries) return;
    _entries['$boardKey|${camp.wire}'] = score;
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}

/// Valeurs de position, calibrées sur la table du concepteur (unité ×10).
///
/// Un seul balayage du plateau, puis calculs sur les listes collectées.
///
/// Noter que `heir_adv` et `nurse_adv` sont comptés **sans signe** : avancer
/// une ronde vers la zone-cible est bon quel que soit son camp. C'est
/// volontaire dans le moteur d'origine, et conservé tel quel.
double positionalStrategy(Board board, Camp camp, DeepGreyWeights w) {
  final opp = camp.opposite;
  final rally = camp.rallyRow;
  var score = 0.0;

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

  // ── Héritiers (les deux camps) ──
  for (final (heir, cp) in [(myHeir, camp), (oppHeir, opp)]) {
    if (heir == null) continue;
    final sign = cp == camp ? 1.0 : -1.0;
    final closeness = 8 - (heir.row - rally).abs();
    score += closeness * 15 * w['heir_adv'];
    if (heir.col == 0 || heir.col == kCols - 1) {
      score -= sign * 30 * w['heir_edge'];
    }
    if (isPieceStuck(board, heir.col, heir.row)) {
      score -= sign * 40 * w['heir_immo'];
    }
  }

  // ── Nurses ──
  for (final (lst, cp) in [(myNurses, camp), (oppNurses, opp)]) {
    final sign = cp == camp ? 1.0 : -1.0;
    for (final cell in lst) {
      final closeness = 8 - (cell.row - rally).abs();
      score += closeness * 10 * w['nurse_adv'];
      if (cell.col == 0 || cell.col == kCols - 1) {
        score -= sign * 20 * w['nurse_edge'];
      }
      score += sign * 40 * w['nurse_mat'];
      if (isPieceStuck(board, cell.col, cell.row)) {
        score -= sign * 30 * w['nurse_immo'];
      }
    }
  }

  // ── Carrées ──
  for (final (lst, cp) in [(mySquares, camp), (oppSquares, opp)]) {
    final sign = cp == camp ? 1.0 : -1.0;
    for (final cell in lst) {
      score += sign * 50 * w['square_mat'];
      if (isPieceStuck(board, cell.col, cell.row)) {
        score -= sign * 20 * w['square_immo'];
      }
      if (squareCanPushForward(board, cell.col, cell.row, cp)) {
        score += sign * 10 * w['square_push'];
      }
    }
  }

  // ── Cohésion des nurses : un seul bloc vaut mieux que plusieurs ──
  final mg = _countGroups(myNurses);
  final og = _countGroups(oppNurses);
  if (mg > 1) score -= (mg - 1) * 10 * w['nurse_groups'];
  if (og > 1) score += (og - 1) * 10 * w['nurse_groups'];

  // ── L'Héritier doit rester au contact d'une nurse de son camp ──
  if (!_heirTouches(myHeir, myNurses)) score -= 30 * w['heir_contact'];
  if (!_heirTouches(oppHeir, oppNurses)) score += 30 * w['heir_contact'];

  return score;
}

/// Nombre de groupes connectés (adjacence 8 directions) dans un ensemble de
/// cases.
int _countGroups(List<Cell> cells) {
  final set = cells.toSet();
  final seen = <Cell>{};
  var groups = 0;
  for (final cell in set) {
    if (seen.contains(cell)) continue;
    groups++;
    final stack = <Cell>[cell];
    seen.add(cell);
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final (dx, dy) in kAllDirs) {
        final nb = Cell(cur.col + dx, cur.row + dy);
        if (set.contains(nb) && seen.add(nb)) stack.add(nb);
      }
    }
  }
  return groups;
}

/// Un Héritier absent du plateau est considéré « au contact », pour ne pas
/// pénaliser à tort.
bool _heirTouches(Cell? heir, List<Cell> nurses) {
  if (heir == null) return true;
  final set = nurses.toSet();
  for (final (dx, dy) in kAllDirs) {
    if (set.contains(Cell(heir.col + dx, heir.row + dy))) return true;
  }
  return false;
}

/// Évalue une position du point de vue de `camp`. Score élevé = bon pour
/// Deep Grey.
///
/// Deux niveaux :
///  1. **sécurité** (fin de partie), qui domine tout : pouvoir fuguer +10000,
///     pouvoir mater +5000, laisser fuguer −10000, laisser mater −5000 ;
///  2. **valeurs de position** (table calibrée), via [positionalStrategy].
double evaluate(
  Board board,
  Camp camp, {
  required DeepGreyWeights weights,
  EvalCache? cache,
}) {
  final boardKey = board.key;
  final cached = cache?.get(boardKey, camp);
  if (cached != null) return cached;

  final opp = camp.opposite;
  var score = 0.0;

  // ── 1. Menaces adverses ──
  var oppCanFugue = false;
  var matThreat = false;
  for (final mv in generateMoves(board, opp)) {
    if (mv.fugue || mv.fugueBy == opp) {
      oppCanFugue = true;
      break; // rien de pire : inutile de continuer
    }
    if (mv.matOn == camp) matThreat = true;
  }
  if (oppCanFugue) {
    score -= 10000;
  } else if (matThreat) {
    score -= 5000;
  }

  // ── 1 bis. Nos opportunités gagnantes au coup suivant ──
  // Détection coûteuse : on ne la fait que si la position semble propice.
  final rallyCamp = camp.rallyRow;
  var propice = false;
  for (var c = 0; c < kCols && !propice; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p == null || !p.isHeir) continue;
      if (p.camp == camp && (r - rallyCamp).abs() <= 2) {
        propice = true;
        break;
      }
      if (p.camp == opp &&
          (c == 0 || c == kCols - 1 || r == 0 || r == kRows - 1)) {
        propice = true;
        break;
      }
    }
  }
  if (propice) {
    var ownCanFugue = false;
    var ownCanMat = false;
    for (final mv in generateMoves(board, camp)) {
      if (mv.fugue || mv.fugueBy == camp) {
        ownCanFugue = true;
        break;
      }
      if (mv.matOn == opp) ownCanMat = true;
    }
    if (ownCanFugue) {
      score += 10000;
    } else if (ownCanMat) {
      score += 5000;
    }
  }

  // ── 2. Valeurs de position ──
  score += positionalStrategy(board, camp, weights);

  cache?.put(boardKey, camp, score);
  return score;
}

/// Bonus lié à l'action décisive que porte le coup lui-même.
///
/// Hiérarchie voulue :
/// `fuguer (+200000) > mater (+100000) > … > se faire mater (−100000)
/// > se faire fuguer (−200000)`.
///
/// L'ordre compte : contrainte à perdre, Deep Grey doit préférer se faire
/// mater plutôt que se faire fuguer.
double moveBonus(Move mv, Camp camp) {
  final opp = camp.opposite;
  if (mv.fugue || mv.fugueBy == camp) return 200000;
  if (mv.fugueBy == opp) return -200000;
  if (mv.matOn == opp) return 100000;
  if (mv.matOn == camp) return -100000;
  return 0;
}
