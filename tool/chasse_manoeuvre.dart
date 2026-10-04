// Tout ce qu'un joueur peut jouer, l'adversaire doit pouvoir le rejouer.
//
// C'est l'invariant qu'une manœuvre partielle violait : le joueur compose sa
// sélection carré par carré, le générateur ne connaît que les groupes entiers,
// et le coup arrivait chez l'adversaire sans que rien ne corresponde — ignoré
// en silence, partie figée.
//
//     dart run tool/chasse_manoeuvre.dart
//
// Deux passes : les coups du générateur, et les manœuvres composées à la main
// à travers le VRAI contrôleur d'interaction.
import 'dart:io';
import 'dart:math';

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/move_controller.dart';

void main() {
  final rnd = Random(12345);
  var genVues = 0, genRatees = 0;
  var mainVues = 0, mainRatees = 0;
  final exemples = <String>[];

  for (var partie = 0; partie < 300; partie++) {
    var board = Board.initial();
    var camp = Camp.blanc;

    for (var ply = 0; ply < 60; ply++) {
      final moves = generateMoves(board, camp);
      if (moves.isEmpty) break;

      // ── 1. Les coups du générateur ───────────────────────────────────
      for (final mv in moves) {
        genVues++;
        final notation = notationOn(board, mv);
        final relu = resolveNotation(board, camp, notation);
        if (relu == null || relu.board.key != mv.board.key) {
          genRatees++;
          if (exemples.length < 5) {
            exemples.add('  générateur : « $notation » (${camp.wire})');
          }
        }
      }

      // ── 2. Les manœuvres composées à la main ─────────────────────────
      // Un groupe, un sous-ensemble au hasard, une direction au hasard :
      // exactement ce que fait un joueur avec ses doigts.
      for (final depart in _carresDu(board, camp)) {
        final groupe = board.groupOf(depart.col, depart.row).toList();
        if (groupe.length < 2) continue;
        final autres = groupe.where((c) => c != depart).toList();
        final choisis = [
          for (final c in autres)
            if (rnd.nextBool()) c,
        ];
        if (choisis.isEmpty) continue;

        final (dc, dr) = kAllDirs[rnd.nextInt(kAllDirs.length)];
        final jeu = MoveController(board: board.clone(), turn: camp);
        jeu.tapCell(depart);
        for (final c in choisis) {
          jeu.tapCell(c);
        }
        if (jeu.groupSelection.isEmpty) continue;
        final dest = Cell(depart.col + dc, depart.row + dr);
        if (!dest.onBoard) continue;
        jeu.tapCell(dest);
        final r = jeu.tapCell(dest); // second appui : validation
        final notation = r.notation;
        if (notation == null) continue; // le coup n'était pas jouable

        mainVues++;
        final relu = resolveNotation(board, camp, notation);
        if (relu == null || relu.board.key != jeu.board.key) {
          mainRatees++;
          if (exemples.length < 10) {
            exemples.add(
              '  à la main : « $notation » (${camp.wire}) → '
              '${relu == null ? "INTROUVABLE" : "AUTRE PLATEAU"}',
            );
          }
        }
      }

      final mv = moves[rnd.nextInt(moves.length)];
      if (mv.fugue || mv.matOn != null || mv.fugueBy != null) break;
      board = mv.board;
      camp = camp.opposite;
    }
  }

  stdout.writeln('coups du générateur      : $genVues vus, $genRatees ratés');
  stdout.writeln(
    'manœuvres à la main      : $mainVues vues, $mainRatees ratées',
  );
  if (exemples.isNotEmpty) {
    stdout.writeln('\nexemples :');
    for (final e in exemples) {
      stdout.writeln(e);
    }
  }
  final total = genRatees + mainRatees;
  stdout.writeln(
    total == 0
        ? '\n✓ tout ce qui se joue se rejoue'
        : '\n✗ $total coups injouables par l adversaire',
  );
  exit(total == 0 ? 0 : 1);
}

List<Cell> _carresDu(Board board, Camp camp) {
  final out = <Cell>[];
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p != null && p.isSquare && p.camp == camp) out.add(Cell(c, r));
    }
  }
  return out;
}
