/// Random Fuga — variante à position de départ tirée au sort (façon
/// Fischer-random). Portage de `rf_parse_code` / `rf_build_board` (main.py).
///
/// Un code s'écrit `[symbole][Position]-[Disposition]`, ex. `.03-09`, `/18-54` :
///  - symbole `.` = rotation 180° (colonnes inversées do↔si, ré↔la, mi↔sol)
///  - symbole `/` = réflexion horizontale (colonnes gardées, Héritiers face à face)
///  - Position 1..25 = (Héritier × Chevalier) sur `[ré, mi, fa, sol, la]`
///  - Disposition 1..70 = la D-ième combinaison de 4 Gardes parmi 8 carrées
///
/// Soit 2 × 25 × 70 = 3 500 positions, toutes avec le même matériel que la
/// position standard.
library;

import 'dart:math';

import 'board.dart';
import 'piece.dart';

/// Code Random Fuga analysé.
final class RandomFugaCode {
  const RandomFugaCode(this.symbol, this.position, this.disposition);

  /// `.` (rotation 180°) ou `/` (réflexion horizontale).
  final String symbol;

  /// 1..25 : (Héritier × Chevalier) sur les colonnes ré..la.
  final int position;

  /// 1..70 : combinaison de 4 Gardes parmi 8 carrées.
  final int disposition;

  bool get isRotation => symbol == '.';

  @override
  String toString() =>
      '$symbol${position.toString().padLeft(2, '0')}'
      '-${disposition.toString().padLeft(2, '0')}';
}

/// Les 70 combinaisons de 4 parmi 8, dans l'ordre de `itertools.combinations`.
final List<List<int>> kRfCombos = _buildCombos();

List<List<int>> _buildCombos() {
  final out = <List<int>>[];
  for (var a = 0; a < 8; a++) {
    for (var b = a + 1; b < 8; b++) {
      for (var c = b + 1; c < 8; c++) {
        for (var d = c + 1; d < 8; d++) {
          out.add([a, b, c, d]);
        }
      }
    }
  }
  return out;
}

/// Analyse un code. `null` si invalide.
RandomFugaCode? parseRandomFugaCode(String? code) {
  final s = (code ?? '').trim();
  if (s.length < 4) return null;
  final sym = s[0];
  if (sym != '.' && sym != '/') return null;
  final rest = s.substring(1).split('-');
  if (rest.length != 2) return null;
  final p = int.tryParse(rest[0]);
  final d = int.tryParse(rest[1]);
  if (p == null || d == null) return null;
  if (p < 1 || p > 25 || d < 1 || d > 70) return null;
  return RandomFugaCode(sym, p, d);
}

/// Tire un code au hasard parmi les 3 500 positions.
String randomFugaCode([Random? rng]) {
  final r = rng ?? Random();
  final sym = r.nextBool() ? '.' : '/';
  final p = r.nextInt(25) + 1;
  final d = r.nextInt(70) + 1;
  return '$sym${p.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// Construit le plateau correspondant à un code. `null` si le code est invalide.
Board? buildRandomFugaBoard(String code) {
  final parsed = parseRandomFugaCode(code);
  if (parsed == null) return null;

  final board = Board.empty();
  final iH = (parsed.position - 1) ~/ 5; // colonne Héritier : ré..la
  final iC = (parsed.position - 1) % 5; // colonne Chevalier : ré..la
  final colH = 1 + iH;
  final colC = 1 + iC;

  // ── Camp Blanc, rangées 0 à 2 ──
  board.set(colH, 0, Piece.blancHeritier);
  board.set(colC, 2, Piece.blancChevalier);
  for (var c = 1; c <= 5; c++) {
    board.set(c, 1, Piece.blancNurse);
  }

  // Les 8 emplacements de carrées, lus en U : do2, do1, milieu, si1, si2.
  final milieu = [
    for (var c = 1; c <= 5; c++)
      if (c != colH) c,
  ];
  final slots = <(int, int)>[
    (0, 1),
    (0, 0),
    for (final c in milieu) (c, 0),
    (6, 0),
    (6, 1),
  ];
  final gardeIdx = kRfCombos[parsed.disposition - 1].toSet();
  for (var i = 0; i < slots.length; i++) {
    final (c, r) = slots[i];
    board.set(
      c,
      r,
      gardeIdx.contains(i) ? Piece.blancGarde : Piece.blancSoldat,
    );
  }

  // ── Camp Noir : symétrie des pièces blanches ──
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < 3; r++) {
      final p = board.at(c, r);
      if (p == null) continue;
      final nc = parsed.isRotation ? 6 - c : c;
      final nr = 7 - r;
      board.set(nc, nr, Piece.of(p.type, Camp.noir));
    }
  }

  return board;
}
