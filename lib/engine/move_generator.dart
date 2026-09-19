/// Générateur de coups légaux de La Fuga — Dart pur, portage fidèle de
/// `dg_generate_moves` / `_dg_apply_pushes` (main.py).
///
/// Aucun import Flutter : ce code tourne aussi bien sur le thread UI que dans
/// l'`Isolate` de l'IA.
library;

import 'board.dart';
import 'move.dart';
import 'piece.dart';

/// Résultat d'une application de poussées sur un plateau déjà muté.
final class PushOutcome {
  const PushOutcome({
    required this.ejAlly,
    required this.ejOpp,
    required this.matOn,
    required this.fugueBy,
    required this.totalPushed,
  });

  final int ejAlly;
  final int ejOpp;
  final Camp? matOn;
  final Camp? fugueBy;
  final int totalPushed;
}

/// Directions de poussée d'un type de pièce carrée.
List<(int, int)> pushDirsFor(PieceType type) =>
    type == PieceType.soldat ? kSoldatPushDirs : kGardePushDirs;

/// La poussée s'active-t-elle pour ce type et ce déplacement ?
///
/// Soldat : déplacement orthogonal. Garde : déplacement diagonal.
bool pushActivated(PieceType type, int dc, int dr) {
  if (type == PieceType.soldat) return dc.abs() + dr.abs() == 1;
  if (type == PieceType.garde) return dc.abs() == 1 && dr.abs() == 1;
  return false;
}

/// La direction (dc,dr) est-elle une direction de poussée valide ?
///
/// Soldat : pousse en diagonale. Garde : pousse orthogonalement.
/// Noter l'inversion volontaire par rapport à [pushActivated] — c'est la règle.
bool pushValid(PieceType type, int dc, int dr) {
  if (type == PieceType.soldat) return dc.abs() == 1 && dr.abs() == 1;
  if (type == PieceType.garde) return dc.abs() + dr.abs() == 1;
  return false;
}

/// Applique les poussées depuis (c,r) sur `board`, **muté en place**.
///
/// Chaque direction pousse la ligne contiguë de pièces d'une case. Un
/// Chevalier dans la ligne annule complètement la poussée de cette direction.
/// Une pièce poussée hors du plateau est éjectée — sauf un Héritier poussé
/// dans SA propre zone de ralliement, qui fugue.
PushOutcome applyPushes(
  Board board,
  int c,
  int r,
  PieceType type,
  Camp camp, {
  List<(int, int)>? dirsToUse,
}) {
  final dirs = dirsToUse ?? pushDirsFor(type);
  var ejAlly = 0;
  var ejOpp = 0;
  var totalPushed = 0;
  Camp? matOn;
  Camp? fugueBy;

  for (final (dc, dr) in dirs) {
    // Construire la ligne de pièces consécutives depuis (c+dc, r+dr).
    final line = <(int, int, Piece)>[];
    var blocked = false;
    var cc = c + dc, rr = r + dr;
    while (Board.onBoard(cc, rr)) {
      final p = board.at(cc, rr);
      if (p == null) break;
      if (p.isKnight) {
        // Le Chevalier est un mur : toute la poussée de cette direction tombe.
        blocked = true;
        break;
      }
      line.add((cc, rr, p));
      cc += dc;
      rr += dr;
    }
    if (blocked || line.isEmpty) continue;

    // Déplacer depuis la fin de la ligne pour ne pas écraser une case occupée.
    for (final (pc, pr, p) in line.reversed) {
      final nc = pc + dc, nr = pr + dr;
      board.set(pc, pr, null);
      if (Board.onBoard(nc, nr)) {
        board.set(nc, nr, p);
        totalPushed++;
      } else {
        final ownRally = kRally.contains(nc) && nr == p.camp.rallyRow;
        if (p.isHeir && ownRally) {
          fugueBy = p.camp;
        } else {
          if (p.isHeir) matOn = p.camp;
          if (p.camp == camp) {
            ejAlly++;
          } else {
            ejOpp++;
          }
        }
        totalPushed++;
      }
    }
  }

  return PushOutcome(
    ejAlly: ejAlly,
    ejOpp: ejOpp,
    matOn: matOn,
    fugueBy: fugueBy,
    totalPushed: totalPushed,
  );
}

/// Génère tous les coups légaux de `camp` sur `board`.
///
/// Les sous-choix de poussée sont développés exhaustivement : pour une carrée
/// dont la poussée s'active, on produit le déplacement sans poussée puis
/// **toutes** les combinaisons non vides de directions effectivement
/// poussables (masque binaire), comme le moteur Python.
List<Move> generateMoves(Board board, Camp camp) {
  final moves = <Move>[];

  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p == null || p.camp != camp) continue;

      if (p.isRound) {
        _generateRoundMoves(board, camp, c, r, p, moves);
      } else if (p.isSquare) {
        _generateSquareMoves(board, camp, c, r, p, moves);
      } else if (p.isKnight) {
        _generateKnightMoves(board, c, r, moves);
      }
    }
  }
  return moves;
}

void _generateRoundMoves(
    Board board, Camp camp, int c, int r, Piece p, List<Move> moves) {
  // Une ronde isolée est immobile.
  if (!board.hasRoundNeighbour(c, r)) return;

  // ── Déplacements simples (8 directions, 1 case) ──
  for (final (dc, dr) in kAllDirs) {
    final nc = c + dc, nr = r + dr;

    // La fugue se teste AVANT l'appartenance au plateau : la case de
    // ralliement est hors plateau.
    if (p.isHeir && Board.isFugueDest(nc, nr, p)) {
      final nb = board.clone();
      nb.set(c, r, null);
      moves.add(Move(
        board: nb,
        kind: MoveKind.fugue,
        fugue: true,
        from: Cell(c, r),
        movedCells: [Cell(nc, nr)],
      ));
      continue;
    }
    if (!Board.onBoard(nc, nr)) continue;
    if (board.at(nc, nr) != null) continue;

    final nb = board.clone();
    nb.set(nc, nr, nb.at(c, r));
    nb.set(c, r, null);
    moves.add(Move(
      board: nb,
      kind: MoveKind.move,
      from: Cell(c, r),
      movedCells: [Cell(nc, nr)],
    ));
  }

  // ── Sauts simples et multisauts ──
  //
  // `simBoard` retire la pièce de sa case de départ mais ne la repose jamais
  // aux positions intermédiaires : c'est exactement le comportement du moteur
  // Python, et cela autorise un saut par-dessus la case libérée.
  final simBoard = board.clone();
  simBoard.set(c, r, null);

  final jumpDestinations = <Cell>{};
  // (col, row, cases visitées, dernière ronde sautée)
  final toExplore = <(int, int, Set<Cell>, Cell?)>[
    (c, r, {Cell(c, r)}, null)
  ];

  while (toExplore.isNotEmpty) {
    final (curC, curR, visited, lastJumped) = toExplore.removeLast();

    for (final (jdc, jdr) in kAllDirs) {
      final mc = curC + jdc, mr = curR + jdr; // case sautée
      final nc = curC + 2 * jdc, nr = curR + 2 * jdr; // case d'arrivée

      // Anti-aller-retour : interdit de re-sauter immédiatement par-dessus la
      // même ronde qu'au saut précédent (on peut la re-sauter plus tard).
      if (lastJumped != null && mc == lastJumped.col && mr == lastJumped.row) {
        continue;
      }

      // Fugue par saut (Héritier seulement).
      if (p.isHeir && Board.isFugueDest(nc, nr, p)) {
        final jumped = Board.onBoard(mc, mr) ? simBoard.at(mc, mr) : null;
        if (jumped != null && jumped.isRound) {
          final nb = board.clone();
          nb.set(c, r, null);
          moves.add(Move(
            board: nb,
            kind: MoveKind.fugue,
            fugue: true,
            from: Cell(c, r),
            movedCells: [Cell(nc, nr)],
          ));
        }
        continue;
      }

      if (!Board.onBoard(mc, mr)) continue;
      if (!Board.onBoard(nc, nr)) continue;
      final jumped = simBoard.at(mc, mr);
      if (jumped == null || !jumped.isRound) continue;
      if (simBoard.at(nc, nr) != null) continue;
      final dest = Cell(nc, nr);
      if (visited.contains(dest)) continue;

      if (jumpDestinations.add(dest)) {
        final nb = board.clone();
        nb.set(nc, nr, nb.at(c, r));
        nb.set(c, r, null);
        moves.add(Move(
          board: nb,
          kind: MoveKind.jump,
          from: Cell(c, r),
          movedCells: [dest],
        ));
      }
      toExplore.add((nc, nr, {...visited, dest}, Cell(mc, mr)));
    }
  }
}

void _generateSquareMoves(
    Board board, Camp camp, int c, int r, Piece p, List<Move> moves) {
  // Une carrée isolée est immobile.
  if (!board.hasSquareNeighbour(c, r)) return;

  // ── Déplacement simple, éventuellement suivi de poussées ──
  for (final (dc, dr) in kAllDirs) {
    final nc = c + dc, nr = r + dr;
    if (!Board.onBoard(nc, nr)) continue;
    if (board.at(nc, nr) != null) continue;

    final nb = board.clone();
    nb.set(nc, nr, nb.at(c, r));
    nb.set(c, r, null);

    if (!pushActivated(p.type, dc, dr)) {
      moves.add(Move(
        board: nb,
        kind: MoveKind.square,
        from: Cell(c, r),
        movedCells: [Cell(nc, nr)],
      ));
      continue;
    }

    // Directions où il y a effectivement quelque chose à pousser.
    final availableDirs = <(int, int)>[];
    for (final (pdc, pdr) in pushDirsFor(p.type)) {
      final ac = nc + pdc, ar = nr + pdr;
      if (Board.onBoard(ac, ar) && nb.at(ac, ar) != null) {
        availableDirs.add((pdc, pdr));
      }
    }

    // Variante sans poussée : toujours proposée.
    moves.add(Move(
      board: nb.clone(),
      kind: MoveKind.square,
      from: Cell(c, r),
      movedCells: [Cell(nc, nr)],
    ));

    // Puis toutes les combinaisons non vides de directions poussées.
    final nDirs = availableDirs.length;
    for (var mask = 1; mask < (1 << nDirs); mask++) {
      final chosen = <(int, int)>[
        for (var i = 0; i < nDirs; i++)
          if (mask & (1 << i) != 0) availableDirs[i],
      ];
      final nbVar = nb.clone();
      final out =
          applyPushes(nbVar, nc, nr, p.type, camp, dirsToUse: chosen);
      moves.add(Move(
        board: nbVar,
        kind: MoveKind.square,
        from: Cell(c, r),
        movedCells: [Cell(nc, nr)],
        fugueBy: out.fugueBy,
        matOn: out.matOn,
        ejAlly: out.ejAlly,
        ejOpp: out.ejOpp,
        totalPushed: out.totalPushed,
        pushDirsUsed: chosen,
      ));
    }
  }

  // ── Manœuvres de groupe : tout le groupe avance d'une case ──
  final grp = board.groupOf(c, r);
  if (grp.length < 2) return;

  for (final (dc, dr) in kAllDirs) {
    var ok = true;
    for (final g in grp) {
      final tc = g.col + dc, tr = g.row + dr;
      if (!Board.onBoard(tc, tr)) {
        ok = false;
        break;
      }
      final tgt = board.at(tc, tr);
      if (tgt != null && !grp.contains(Cell(tc, tr))) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;

    final nb = board.clone();
    final pieces = <Cell, Piece?>{for (final g in grp) g: nb.atCell(g)};
    for (final g in grp) {
      nb.setCell(g, null);
    }
    pieces.forEach((g, piece) => nb.set(g.col + dc, g.row + dr, piece));

    // La maîtresse doit rester en tête : la notation et la mise en évidence
    // parsent `movedCells.first`.
    final master = Cell(c, r);
    final others = grp.where((g) => g != master).toList()
      ..sort((a, b) => a.col != b.col ? a.col - b.col : a.row - b.row);
    final moved = <Cell>[
      Cell(c + dc, r + dr),
      for (final g in others) Cell(g.col + dc, g.row + dr),
    ];
    final fromOrdered = <Cell>[master, ...others];

    moves.add(Move(
      board: nb,
      kind: MoveKind.maneuver,
      from: master,
      movedCells: moved,
      fromCells: fromOrdered,
    ));
  }
}

void _generateKnightMoves(Board board, int c, int r, List<Move> moves) {
  // Le Chevalier bouge d'une case dans les 8 directions vers une case vide,
  // sans condition de voisinage et sans pousser.
  for (final (dc, dr) in kAllDirs) {
    final nc = c + dc, nr = r + dr;
    if (!Board.onBoard(nc, nr)) continue;
    if (board.at(nc, nr) != null) continue;
    final nb = board.clone();
    nb.set(nc, nr, nb.at(c, r));
    nb.set(c, r, null);
    moves.add(Move(
      board: nb,
      kind: MoveKind.knight,
      from: Cell(c, r),
      movedCells: [Cell(nc, nr)],
    ));
  }
}

/// Vrai si `camp` possède au moins un coup légal.
///
/// Portage de `_player_has_any_move` : on ne génère pas les coups, on teste
/// seulement l'existence d'une destination.
bool playerHasAnyMove(Board board, Camp camp) {
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p == null || p.camp != camp) continue;

      if (p.isKnight) {
        for (final (dc, dr) in kAllDirs) {
          if (board.isEmpty(c + dc, r + dr) &&
              Board.onBoard(c + dc, r + dr)) {
            return true;
          }
        }
      } else if (p.isRound) {
        if (!board.hasRoundNeighbour(c, r)) continue;
        for (final (dc, dr) in kAllDirs) {
          final nc = c + dc, nr = r + dr;
          if (Board.onBoard(nc, nr) && board.at(nc, nr) == null) return true;
          if (Board.isFugueDest(nc, nr, p)) return true;
        }
      } else if (p.isSquare) {
        if (!board.hasSquareNeighbour(c, r)) continue;
        for (final (dc, dr) in kAllDirs) {
          final nc = c + dc, nr = r + dr;
          if (Board.onBoard(nc, nr) && board.at(nc, nr) == null) return true;
        }
      }
    }
  }
  return false;
}

/// Vrai s'il existe au moins une carrée non immobilisée sur tout le plateau.
///
/// Sa négation est la nulle par blocage (« Trêve ») : sans carrée mobile,
/// plus aucune poussée n'est possible et aucun camp ne peut progresser.
bool anySquareCanMove(Board board) {
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p == null || !p.isSquare) continue;
      if (board.hasSquareNeighbour(c, r)) return true;
    }
  }
  return false;
}

/// Vrai si `camp` peut amener SON Héritier au ralliement en un seul coup,
/// par déplacement, saut ou poussée. Sert à la règle auto de rattrapage.
bool campCanFugue(Board board, Camp camp) {
  for (final mv in generateMoves(board, camp)) {
    if (mv.fugue || mv.fugueBy == camp) return true;
  }
  return false;
}
