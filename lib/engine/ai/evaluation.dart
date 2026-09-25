/// Évaluation de position de Deep Grey — portage de `dg_positional_strategy`,
/// `dg_evaluate` et `dg_move_bonus` (main.py). Dart pur : tourne en isolate.
library;

import '../board.dart';
import '../move.dart';
import '../threats.dart';
import '../piece.dart';
import 'weights.dart';

/// Cache d'évaluation, borné pour ne pas croître indéfiniment.
/// Vidé avant chaque réflexion, comme `_DG_EVAL_CACHE.clear()` en Python.
final class EvalCache {
  EvalCache({this.maxEntries = 50000});

  final int maxEntries;

  /// Une table par camp : concaténer le camp à la clé du plateau, c'était
  /// allouer et hacher une chaîne de soixante caractères à chaque consultation,
  /// pour une information qui tient dans le choix de la table.
  final Map<String, double> _blanc = {};
  final Map<String, double> _noir = {};

  Map<String, double> _table(Camp camp) => camp == Camp.blanc ? _blanc : _noir;

  double? get(String boardKey, Camp camp) => _table(camp)[boardKey];

  void put(String boardKey, Camp camp, double score) {
    final table = _table(camp);
    if (_blanc.length + _noir.length >= maxEntries) return;
    table[boardKey] = score;
  }

  void clear() {
    _blanc.clear();
    _noir.clear();
  }

  int get length => _blanc.length + _noir.length;
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

  // Les cases sont manipulées en index plat `c * kRows + r`, et les ensembles
  // en masque de bits : le plateau fait cinquante-six cases, elles tiennent
  // dans un entier. Allouer une vingtaine d'objets `Cell` et trois `Set` par
  // évaluation, c'était le gros du coût d'une fonction appelée des dizaines de
  // milliers de fois par coup de Deep Grey.
  var myHeir = -1, oppHeir = -1;
  final myNurses = <int>[], oppNurses = <int>[];
  final mySquares = <int>[], oppSquares = <int>[];
  var myNurseMask = 0, oppNurseMask = 0;

  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p == null || p.isKnight) continue;
      final index = c * kRows + r;
      final mine = p.camp == camp;
      switch (p.type) {
        case PieceType.heritier:
          mine ? myHeir = index : oppHeir = index;
        case PieceType.nurse:
          if (mine) {
            myNurses.add(index);
            myNurseMask |= 1 << index;
          } else {
            oppNurses.add(index);
            oppNurseMask |= 1 << index;
          }
        case PieceType.soldat:
        case PieceType.garde:
          (mine ? mySquares : oppSquares).add(index);
        case PieceType.chevalier:
          break;
      }
    }
  }

  // ── Héritiers (les deux camps) ──
  for (final (heir, cp) in [(myHeir, camp), (oppHeir, opp)]) {
    if (heir < 0) continue;
    final sign = cp == camp ? 1.0 : -1.0;
    final hc = heir ~/ kRows, hr = heir % kRows;
    final closeness = 8 - (hr - rally).abs();
    score += closeness * 15 * w['heir_adv'];
    if (hc == 0 || hc == kCols - 1) {
      score -= sign * 30 * w['heir_edge'];
    }
    if (isPieceStuck(board, hc, hr)) {
      score -= sign * 40 * w['heir_immo'];
    }
  }

  // ── Nurses ──
  for (final (lst, cp) in [(myNurses, camp), (oppNurses, opp)]) {
    final sign = cp == camp ? 1.0 : -1.0;
    for (final index in lst) {
      final nc = index ~/ kRows, nr = index % kRows;
      final closeness = 8 - (nr - rally).abs();
      score += closeness * 10 * w['nurse_adv'];
      if (nc == 0 || nc == kCols - 1) {
        score -= sign * 20 * w['nurse_edge'];
      }
      score += sign * 40 * w['nurse_mat'];
      if (isPieceStuck(board, nc, nr)) {
        score -= sign * 30 * w['nurse_immo'];
      }
    }
  }

  // ── Carrées ──
  for (final (lst, cp) in [(mySquares, camp), (oppSquares, opp)]) {
    final sign = cp == camp ? 1.0 : -1.0;
    for (final index in lst) {
      final sc = index ~/ kRows, sr = index % kRows;
      score += sign * 50 * w['square_mat'];
      if (isPieceStuck(board, sc, sr)) {
        score -= sign * 20 * w['square_immo'];
      }
      if (squareCanPushForward(board, sc, sr, cp)) {
        score += sign * 10 * w['square_push'];
      }
    }
  }

  // ── Cohésion des nurses : un seul bloc vaut mieux que plusieurs ──
  final mg = _countGroups(myNurseMask);
  final og = _countGroups(oppNurseMask);
  if (mg > 1) score -= (mg - 1) * 10 * w['nurse_groups'];
  if (og > 1) score += (og - 1) * 10 * w['nurse_groups'];

  // ── L'Héritier doit rester au contact d'une nurse de son camp ──
  if (!_heirTouches(myHeir, myNurseMask)) score -= 30 * w['heir_contact'];
  if (!_heirTouches(oppHeir, oppNurseMask)) score += 30 * w['heir_contact'];

  return score;
}

/// Nombre de groupes connectés (adjacence 8 directions) dans un masque de
/// cases.
int _countGroups(int mask) {
  var remaining = mask;
  var groups = 0;
  while (remaining != 0) {
    groups++;
    // Repartir de la case de poids le plus faible et vider tout son groupe.
    var frontier = remaining & -remaining;
    var group = 0;
    while (frontier != 0) {
      group |= frontier;
      var next = 0;
      var todo = frontier;
      while (todo != 0) {
        final bit = todo & -todo;
        todo ^= bit;
        final index = bit.bitLength - 1;
        final c = index ~/ kRows, r = index % kRows;
        for (final (dc, dr) in kAllDirs) {
          final nc = c + dc, nr = r + dr;
          if (!Board.onBoard(nc, nr)) continue;
          next |= 1 << (nc * kRows + nr);
        }
      }
      frontier = next & remaining & ~group;
    }
    remaining &= ~group;
  }
  return groups;
}

/// Un Héritier absent du plateau est considéré « au contact », pour ne pas
/// pénaliser à tort.
bool _heirTouches(int heir, int nurseMask) {
  if (heir < 0) return true;
  final hc = heir ~/ kRows, hr = heir % kRows;
  for (final (dx, dy) in kAllDirs) {
    final nc = hc + dx, nr = hr + dy;
    if (!Board.onBoard(nc, nr)) continue;
    if (nurseMask & (1 << (nc * kRows + nr)) != 0) return true;
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
  //
  // Détectées directement sur le plateau : générer les coups de l'adversaire
  // pour n'en garder qu'un booléen coûtait dix fois le reste de l'évaluation.
  final oppThreats = threatsOf(board, opp);
  if (oppThreats.canFugue) {
    score -= 10000;
  } else if (oppThreats.matOn(camp)) {
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
    final mine = threatsOf(board, camp);
    if (mine.canFugue) {
      score += 10000;
    } else if (mine.matOn(opp)) {
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
