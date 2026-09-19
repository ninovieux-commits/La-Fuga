// Diagnostic : cherche deux coups distincts partageant la même notation.
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:lafuga/engine/piece.dart';

void main() {
  var board = Board.initial();
  var camp = Camp.blanc;

  for (var ply = 0; ply < 12; ply++) {
    final moves = generateMoves(board, camp);
    if (moves.isEmpty) break;

    final byNotation = <String, List<int>>{};
    for (var i = 0; i < moves.length; i++) {
      final n = notationOfMove(
        moves[i],
        pushTargets: pushTargetsOf(board, moves[i]),
        pushableCells: pushableCellsOf(board, moves[i]),
      );
      byNotation.putIfAbsent(n, () => []).add(i);
    }

    for (final entry in byNotation.entries) {
      final distinct = entry.value
          .map((i) => moves[i].board.key)
          .toSet();
      if (distinct.length > 1) {
        print('demi-coup $ply (${camp.wire}) : « ${entry.key} » '
            '-> ${distinct.length} plateaux differents');
        for (final i in entry.value) {
          final m = moves[i];
          print('   kind=${m.kind.name} from=${m.from} to=${m.to} '
              'pushDirs=${m.pushDirsUsed} ejAlly=${m.ejAlly} ejOpp=${m.ejOpp}');
        }
        return;
      }
    }

    final mv = moves[ply % moves.length];
    if (mv.fugue || mv.matOn != null || mv.fugueBy != null) break;
    board = mv.board;
    camp = camp.opposite;
  }
  print('aucune collision trouvee');
}
