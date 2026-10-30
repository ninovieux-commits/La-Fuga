/// L'Héritier qui fugue au bout d'un MULTISAUT passe par ses atterrissages.
///
/// Nino, en mode lecture : « l'héritier doit effectuer le multisaut même quand
/// il va à fugue, là on le voit sauter tout droit vers la case. »
///
/// Une partie enregistrée écrit la fugue « Mi5* » : la case de départ, et rien
/// d'autre. Faute de chemin, l'Héritier traversait le plateau en diagonale
/// jusqu'au milieu de sa zone, alors qu'il y était arrivé de bond en bond.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/last_move.dart';
import 'package:lafuga/game/move_controller.dart';

/// L'Héritier blanc de Mi5 saute en diagonale par-dessus la Nurse de Fa6,
/// atterrit en Sol7, puis saute par-dessus la Nurse de Sol8 : il sort en
/// colonne « sol », pas au milieu de sa zone.
Board _position() {
  final b = Board.empty();
  b.set(2, 4, Piece.blancHeritier);
  b.set(3, 5, Piece.blancNurse);
  b.set(4, 7, Piece.blancNurse);
  b.set(0, 0, Piece.noirHeritier);
  return b;
}

const _depart = Cell(2, 4);
const _etape = Cell(4, 6);
const _sortie = Cell(4, 8);

void main() {
  test('le chemin se reconstruit, et il sort par où son bond le dépose', () {
    final chemin = cheminDeFugue(_position(), _depart);

    expect(chemin, isNotNull);
    expect(chemin!.etapes, [_etape]);
    expect(chemin.sortie, _sortie);
    expect(
      _position().caseDeFugueAffichee(Camp.blanc, depuis: _depart),
      isNot(_sortie),
      reason:
          'la déduction « un seul pas » visait ailleurs : '
          'sans chemin, il glissait tout droit vers cette autre case',
    );
  });

  test('un pas suffisait : on ne devine rien', () {
    // L'Héritier est à un pas de sa zone : il a pu marcher, et la glissée
    // droite est alors exacte.
    final b = Board.empty();
    b.set(3, 7, Piece.blancHeritier);
    b.set(3, 6, Piece.blancNurse);
    b.set(0, 0, Piece.noirHeritier);

    expect(cheminDeFugue(b, const Cell(3, 7)), isNull);
  });

  test('au doigt, le coup emporte ses atterrissages', () {
    final c = MoveController(board: _position(), turn: Camp.blanc);
    c.tapCell(_depart);
    final r = c.tapCell(_etape);
    expect(r.jumpPath, isEmpty, reason: 'le saut n est pas fini');

    final fin = c.tapCell(_sortie);
    expect(fin.endReason, 'fugue');
    expect(fin.jumpPath, [
      _etape,
    ], reason: 'sans cela, il file tout droit vers son ralliement');
  });

  test('relue, la fugue glisse jusqu à la case de son dernier bond', () {
    final relu = applyNotationLiterally(_position(), 'Mi5*');

    expect(relu.ok, isTrue);
    expect(relu.fugued, {Camp.blanc});
    expect(relu.slides.single.$3, _sortie);
  });

  test('relue, la mise en évidence porte le chemin du multisaut', () {
    final avant = _position();
    final apres = applyNotationLiterally(avant, 'Mi5*').board;
    final mise = lastMoveFromNotation('Mi5*', avant, apres);

    expect(mise, isNotNull);
    expect(mise!.jumpPath, [_etape]);
  });
}
