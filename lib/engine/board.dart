/// Plateau de La Fuga et constantes de géométrie — Dart pur.
library;

import 'dart:typed_data';

import 'piece.dart';

/// Colonnes du plateau (notes do…si).
const int kCols = 7;

/// Rangées jouables.
const int kRows = 8;

/// Rangées affichées : 8 jouables + 2 zones de ralliement.
const int kExtRows = 10;

/// La colonne du MILIEU des zones d'origine.
///
/// Elle ne sert plus qu'à ce qui se joue forcément sur les zones d'origine —
/// le tuto, dont les étapes sont écrites pour elles. Une partie, elle, lit la
/// médiane de SA zone : `board.caseDeFugueAffichee`.
const int kRallyMilieuStandard = 3;

/// La case d'affichage d'une fugue sur les zones d'ORIGINE.
Cell caseDeFugueStandard(Camp camp) =>
    Cell(kRallyMilieuStandard, camp.rallyRow);

/// Les colonnes de ralliement d'origine : les trois du milieu, `--rrr--`.
const Set<int> kRallyStandard = {2, 3, 4};

/// LES ZONES DE RALLIEMENT D'UNE POSITION, un camp après l'autre.
///
/// Elles valaient `--rrr--` pour tout le monde et pour toujours. Nino :
/// « en personnalisé […] on peut choisir entre 0 et 7 cases possibles pour le
/// ralliement (si 0 cases, fugue impossible (logique)). » Elles font donc
/// maintenant partie de la POSITION, et voyagent avec elle dans le `.fug`.
///
/// Un masque de sept bits par camp, le bit 0 étant la colonne « do ». Un
/// plateau se clone des milliers de fois dans la recherche de l'IA : deux
/// entiers partagés par référence n'y coûtent rien, là où deux ensembles
/// recopiés coûteraient à chaque nœud.
final class Ralliements {
  const Ralliements({required this.blanc, required this.noir});

  /// Celles de toujours, et ce qu'on lit d'un `.fug` qui n'en dit rien.
  static const Ralliements standard = Ralliements(
    blanc: _masqueStandard,
    noir: _masqueStandard,
  );

  static const int _masqueStandard = 1 << 2 | 1 << 3 | 1 << 4;

  final int blanc;
  final int noir;

  int masque(Camp camp) => camp == Camp.blanc ? blanc : noir;

  /// Vrai si [col] est une case de ralliement de [camp].
  bool contient(Camp camp, int col) =>
      col >= 0 && col < kCols && (masque(camp) >> col) & 1 == 1;

  /// Les colonnes de ralliement de [camp], de gauche à droite.
  List<int> colonnes(Camp camp) => [
    for (var c = 0; c < kCols; c++)
      if (contient(camp, c)) c,
  ];

  /// Vrai si [camp] ne peut pas fuguer : il n'a aucune case où aller.
  bool estFerme(Camp camp) => masque(camp) == 0;

  bool get estStandard => blanc == _masqueStandard && noir == _masqueStandard;

  /// La MÉDIANE des colonnes de ralliement de [camp], ou `null` s'il n'en a
  /// aucune.
  ///
  /// C'est là que s'affiche un Héritier qui a fugué, quelle que soit la
  /// colonne par laquelle il est sorti. Le `.nmc` ne l'écrit pas — « Mi7* »
  /// dit d'où l'Héritier part, pas vers quelle case il va — et une seule
  /// case possible est donc le seul choix qui donne la même image en direct
  /// et en relecture.
  int? milieu(Camp camp) {
    final cols = colonnes(camp);
    return cols.isEmpty ? null : cols[cols.length ~/ 2];
  }

  /// Avec la zone de [camp] remplacée.
  Ralliements avec(Camp camp, int masque) => Camp.blanc == camp
      ? Ralliements(blanc: masque, noir: noir)
      : Ralliements(blanc: blanc, noir: masque);

  /// La zone de [camp], avec [col] mise ou retirée.
  Ralliements bascule(Camp camp, int col) =>
      avec(camp, masque(camp) ^ (1 << col));

  @override
  bool operator ==(Object other) =>
      other is Ralliements && other.blanc == blanc && other.noir == noir;

  @override
  int get hashCode => blanc * 128 + noir;

  @override
  String toString() =>
      'Ralliements(${blanc.toRadixString(2)}, '
      '${noir.toRadixString(2)})';
}

/// Une case du plateau. Les zones de ralliement ont `row == 8` (Blanc) ou
/// `row == -1` (Noir) et ne sont donc pas « sur le plateau ».
///
/// Savoir si une case EST une case de ralliement demande la position : les
/// zones ne sont plus les mêmes d'une partie à l'autre. C'est donc
/// [Board.estCaseDeRalliement] qui le dit, et non la case elle-même.
final class Cell {
  const Cell(this.col, this.row);

  final int col;
  final int row;

  bool get onBoard => col >= 0 && col < kCols && row >= 0 && row < kRows;

  /// Sur l'une des deux RANGÉES de ralliement — celles qu'on voit au-dessus
  /// et au-dessous du plateau. Dit où est la case, pas si elle rallie.
  bool get surUneRangeeDeRalliement => row == 8 || row == -1;

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
  Board._(this._cols, this.rall);

  final List<List<Piece?>> _cols;

  /// Les zones de ralliement de CETTE position.
  final Ralliements rall;

  /// Plateau vide.
  factory Board.empty({Ralliements rall = Ralliements.standard}) => Board._(
    List.generate(
      kCols,
      (_) => List<Piece?>.filled(kRows, null),
      growable: false,
    ),
    rall,
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
      rall,
    );
    copy._key = _key; // même contenu : la clé déjà calculée reste valable.
    return copy;
  }

  /// Le même plateau, avec d'autres zones de ralliement.
  Board avecRalliements(Ralliements autres) {
    final copy = Board._(
      List.generate(kCols, (c) => List<Piece?>.of(_cols[c]), growable: false),
      autres,
    );
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

  /// Vrai si (c,r) est une case de ralliement de [camp] — Héritier ou non.
  bool estCaseDeRalliement(Camp camp, int c, int r) =>
      r == camp.rallyRow && rall.contient(camp, c);

  /// Vrai si (c,r) est une case de fugue valide pour `piece`.
  ///
  /// Seul l'Héritier fugue, et seulement vers SA zone. Un camp dont la zone
  /// est vide ne fugue pas du tout — c'est ce que Nino appelle « si 0 cases,
  /// fugue impossible (logique) », et ça tombe tout seul : aucune colonne
  /// n'est dans le masque.
  bool isFugueDest(int c, int r, Piece piece) =>
      piece.isHeir && estCaseDeRalliement(piece.camp, c, r);

  /// Où s'affiche l'Héritier de [camp] une fois qu'il a fugué.
  ///
  /// La médiane de sa zone. Un camp sans zone ne fugue jamais : on rend
  /// alors la colonne du milieu du plateau, pour n'avoir nulle part à se
  /// demander ce que vaut une case qui n'existe pas.
  Cell caseDeFugueAffichee(Camp camp) =>
      Cell(rall.milieu(camp) ?? kCols ~/ 2, camp.rallyRow);

  /// Clé compacte de la position (`_dg_board_key`) : 56 caractères.
  ///
  /// Mémorisée : la recherche de l'IA et le repeint du plateau la demandent
  /// plusieurs fois pour un même plateau. `set` l'invalide, et c'est le seul
  /// point de mutation.
  String get key => _key ??= _buildKey();

  String? _key;

  /// Une case vide s'écrit `.`, une case occupée sur deux lettres : la clé
  /// fait donc entre 56 et 112 caractères. Elle est assemblée en points de
  /// code puis convertie d'un coup — écrire cinquante-six petites chaînes dans
  /// un tampon coûtait presque autant que toute l'évaluation qui la demande.
  String _buildKey() {
    final codes = Uint8List(kCols * kRows * 2);
    var n = 0;
    for (var c = 0; c < kCols; c++) {
      final col = _cols[c];
      for (var r = 0; r < kRows; r++) {
        final p = col[r];
        if (p == null) {
          codes[n++] = 0x2E; // .
        } else {
          codes[n++] = p.typeCode;
          codes[n++] = p.campCode;
        }
      }
    }
    final plateau = String.fromCharCodes(codes, 0, n);
    // LES ZONES NE S'ÉCRIVENT QUE SI ELLES SORTENT DE L'ORDINAIRE. Elles font
    // partie de la position — deux plateaux identiques aux zones différentes
    // ne se jouent pas pareil, et la mémoire de l'IA survit aux parties. Les
    // taire quand elles sont standard garde intactes les clés déjà apprises.
    return rall.estStandard ? plateau : '$plateau|${rall.blanc}:${rall.noir}';
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
