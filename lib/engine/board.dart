/// Plateau de La Fuga et constantes de géométrie — Dart pur.
library;

import 'piece.dart';

/// Colonnes du plateau (notes do…si).
const int kCols = 7;

/// Rangées jouables.
const int kRows = 8;

/// Rangées affichées : 8 jouables + 2 zones de ralliement.
const int kExtRows = 10;

/// Colonnes sur lesquelles existent les zones de ralliement.
const Set<int> kRally = {2, 3, 4};

/// Une case du plateau. Les zones de ralliement ont `row == 8` (Blanc) ou
/// `row == -1` (Noir) et ne sont donc pas « sur le plateau ».
final class Cell {
  const Cell(this.col, this.row);

  final int col;
  final int row;

  bool get onBoard => col >= 0 && col < kCols && row >= 0 && row < kRows;

  Cell shifted(int dc, int dr) => Cell(col + dc, row + dr);

  @override
  bool operator ==(Object other) =>
      other is Cell && other.col == col && other.row == row;

  @override
  int get hashCode => col * 31 + row;

  @override
  String toString() => '($col,$row)';
}

/// Les 8 directions, dans l'ordre de balayage du moteur Python
/// (`for dc in (-1,0,1): for dr in (-1,0,1)`), en sautant (0,0).
const List<(int, int)> kAllDirs = [
  (-1, -1),
  (-1, 0),
  (-1, 1),
  (0, -1),
  (0, 1),
  (1, -1),
  (1, 0),
  (1, 1),
];

/// Directions dans lesquelles un Soldat pousse (diagonales).
const List<(int, int)> kSoldatPushDirs = [(-1, -1), (1, -1), (-1, 1), (1, 1)];

/// Directions dans lesquelles un Garde pousse (orthogonales).
const List<(int, int)> kGardePushDirs = [(0, -1), (0, 1), (-1, 0), (1, 0)];

/// Plateau : `kCols` colonnes de `kRows` cases, indexé `[col][row]`.
///
/// Représentation identique au Python (`board[c][r]`) pour que le portage du
/// moteur reste ligne à ligne vérifiable. Les pièces étant immuables, cloner
/// un plateau ne copie que la structure des colonnes.
final class Board {
  Board._(this._cols);

  final List<List<Piece?>> _cols;

  /// Plateau vide.
  factory Board.empty() => Board._(
    List.generate(
      kCols,
      (_) => List<Piece?>.filled(kRows, null),
      growable: false,
    ),
  );

  /// Position de départ standard (`_setup_pieces`).
  ///
  /// Le Python pose d'abord un layout puis l'écrase deux fois ; seul l'état
  /// final compte et il est reproduit directement ici.
  factory Board.initial() {
    final b = Board.empty();
    const layout = [
      PieceType.soldat,
      PieceType.garde,
      PieceType.soldat,
      PieceType.chevalier, // écrasé plus bas par la variante colonne fa
      PieceType.garde,
      PieceType.soldat,
      PieceType.garde,
    ];

    for (var c = 0; c < kCols; c++) {
      b.set(c, 0, Piece.of(layout[c], Camp.blanc));
      b.set(c, 7, Piece.of(layout[c], Camp.noir));
    }
    for (final c in [1, 2, 4, 5]) {
      b.set(c, 1, Piece.blancNurse);
      b.set(c, 6, Piece.noirNurse);
    }
    // Pièces supplémentaires sur les ailes.
    b.set(0, 1, Piece.blancGarde); // do2
    b.set(6, 1, Piece.blancSoldat); // si2
    b.set(0, 6, Piece.noirGarde); // do7
    b.set(6, 6, Piece.noirSoldat); // si7

    // Variante colonne fa : Héritier au fond, Nurse devant, Chevalier ensuite.
    b.set(3, 0, Piece.blancHeritier); // fa1
    b.set(3, 1, Piece.blancNurse); // fa2
    b.set(3, 2, Piece.blancChevalier); // fa3
    b.set(3, 7, Piece.noirHeritier); // fa8
    b.set(3, 6, Piece.noirNurse); // fa7
    b.set(3, 5, Piece.noirChevalier); // fa6

    return b;
  }

  /// Copie. Les pièces sont immuables : on ne duplique que les colonnes.
  Board clone() {
    final copy = Board._(
      List.generate(kCols, (c) => List<Piece?>.of(_cols[c]), growable: false),
    );
    copy._key = _key; // même contenu : la clé déjà calculée reste valable.
    return copy;
  }

  Piece? at(int c, int r) {
    if (c < 0 || c >= kCols || r < 0 || r >= kRows) return null;
    return _cols[c][r];
  }

  Piece? atCell(Cell cell) => at(cell.col, cell.row);

  void set(int c, int r, Piece? p) {
    _cols[c][r] = p;
    _key = null;
  }

  void setCell(Cell cell, Piece? p) => set(cell.col, cell.row, p);

  bool isEmpty(int c, int r) {
    if (c < 0 || c >= kCols || r < 0 || r >= kRows) return true;
    return _cols[c][r] == null;
  }

  static bool onBoard(int c, int r) =>
      c >= 0 && c < kCols && r >= 0 && r < kRows;

  /// Une ronde peut bouger si elle touche une autre ronde (n'importe quel camp).
  bool hasRoundNeighbour(int c, int r) {
    for (final (dc, dr) in kAllDirs) {
      final p = at(c + dc, r + dr);
      if (p != null && p.isRound) return true;
    }
    return false;
  }

  /// Une carrée peut bouger si elle touche une autre carrée (n'importe quel
  /// camp). Le Chevalier ne compte pas comme carrée.
  bool hasSquareNeighbour(int c, int r) {
    for (final (dc, dr) in kAllDirs) {
      final p = at(c + dc, r + dr);
      if (p != null && p.isSquare) return true;
    }
    return false;
  }

  /// Vrai si la pièce en (c,r) est immobilisée par la règle de voisinage.
  /// C'est exactement la condition du contour rouge à l'écran.
  bool isImmobilised(int c, int r) {
    final p = at(c, r);
    if (p == null) return false;
    if (p.isRound) return !hasRoundNeighbour(c, r);
    if (p.isSquare) return !hasSquareNeighbour(c, r);
    return false; // le Chevalier bouge toujours
  }

  /// Groupe connexe (8 directions) de carrées du même camp contenant (c,r).
  Set<Cell> groupOf(int c, int r) {
    final p = at(c, r);
    if (p == null || !p.isSquare) return const {};
    final camp = p.camp;
    final seen = <Cell>{Cell(c, r)};
    final stack = <Cell>[Cell(c, r)];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final (dc, dr) in kAllDirs) {
        final nc = cur.col + dc, nr = cur.row + dr;
        final n = Cell(nc, nr);
        if (seen.contains(n)) continue;
        if (!onBoard(nc, nr)) continue;
        final q = _cols[nc][nr];
        if (q != null && q.isSquare && q.camp == camp) {
          seen.add(n);
          stack.add(n);
        }
      }
    }
    return seen;
  }

  /// Vrai si (c,r) est une case de fugue valide pour `piece`.
  static bool isFugueDest(int c, int r, Piece piece) {
    if (!piece.isHeir) return false;
    if (!kRally.contains(c)) return false;
    return r == piece.camp.rallyRow;
  }

  /// Clé compacte de la position (`_dg_board_key`) : 56 caractères.
  ///
  /// Mémorisée : la recherche de l'IA et le repeint du plateau la demandent
  /// plusieurs fois pour un même plateau. `set` l'invalide, et c'est le seul
  /// point de mutation.
  String get key => _key ??= _buildKey();

  String? _key;

  String _buildKey() {
    final sb = StringBuffer();
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        final p = _cols[c][r];
        sb.write(p == null ? '.' : p.key);
      }
    }
    return sb.toString();
  }

  /// Clé incluant le camp au trait (anti-répétition).
  String positionKey(Camp turn) => '$key|${turn.wire}';

  /// Clé ne codant que la configuration des pièces d'un camp
  /// (`_dg_own_pieces_key`), pour la pénalité anti allers-retours de l'IA.
  String ownPiecesKey(Camp camp) {
    final parts = <String>[];
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        final p = _cols[c][r];
        if (p != null && p.camp == camp) {
          parts.add('${p.type.wire[0]}$c$r');
        }
      }
    }
    return parts.join('|');
  }

  /// Sérialisation pour passage à un `Isolate` et pour les snapshots.
  List<List<Map<String, String>?>> toJson() => [
    for (var c = 0; c < kCols; c++)
      [for (var r = 0; r < kRows; r++) _cols[c][r]?.toJson()],
  ];

  static Board fromJson(List<dynamic> j) {
    final b = Board.empty();
    for (var c = 0; c < kCols; c++) {
      final col = j[c] as List<dynamic>;
      for (var r = 0; r < kRows; r++) {
        final cell = col[r];
        if (cell != null) {
          b.set(c, r, Piece.fromJson(Map<String, dynamic>.from(cell as Map)));
        }
      }
    }
    return b;
  }

  /// Rendu texte, utile aux tests et au diagnostic.
  String render() {
    final sb = StringBuffer();
    for (var r = kRows - 1; r >= 0; r--) {
      sb.write('${r + 1} ');
      for (var c = 0; c < kCols; c++) {
        final p = _cols[c][r];
        sb.write(p == null ? ' . ' : ' ${p.key} ');
      }
      sb.writeln();
    }
    sb.writeln('   do  ré  mi  fa sol  la  si');
    return sb.toString();
  }
}
