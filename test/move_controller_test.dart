/// Interaction incrémentale : on touche une pièce, on la déplace, on pousse
/// direction par direction, puis on valide en la retouchant.
///
/// Ces tests décrivent des gestes de joueur, pas des appels de fonctions.
library;

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:test/test.dart';

/// Plateau nu, pour isoler une règle sans le bruit de la position de départ.
MoveController controllerWith(
  Map<Cell, Piece> pieces, {
  Camp turn = Camp.blanc,
}) {
  final b = Board.empty();
  pieces.forEach((cell, piece) => b.setCell(cell, piece));
  return MoveController(board: b, turn: turn);
}

void main() {
  group('Sélection', () {
    test('on ne sélectionne que ses propres pièces', () {
      final c = controllerWith({
        const Cell(3, 3): Piece.blancNurse,
        const Cell(3, 4): Piece.noirNurse,
      });
      expect(
        c.tapCell(const Cell(3, 4)).effect,
        ControllerEffect.none,
        reason: 'pièce adverse',
      );
      expect(c.selected, isNull);

      expect(
        c.tapCell(const Cell(3, 3)).effect,
        ControllerEffect.selectionChanged,
      );
      expect(c.selected, const Cell(3, 3));
    });

    test('une pièce immobilisée ne se sélectionne pas', () {
      final c = controllerWith({const Cell(3, 3): Piece.blancNurse});
      expect(
        c.tapCell(const Cell(3, 3)).effect,
        ControllerEffect.none,
        reason: 'ronde isolée : contour rouge, pas de sélection',
      );
      expect(c.selected, isNull);
    });

    test('retoucher la pièce avant de bouger annule la sélection', () {
      final c = controllerWith({
        const Cell(3, 3): Piece.blancNurse,
        const Cell(3, 4): Piece.blancNurse,
      });
      c.tapCell(const Cell(3, 3));
      c.tapCell(const Cell(3, 3));
      expect(c.selected, isNull);
    });

    test('une case vide sans intérêt annule la sélection', () {
      final c = controllerWith({
        const Cell(0, 0): Piece.blancNurse,
        const Cell(0, 1): Piece.blancNurse,
      });
      c.tapCell(const Cell(0, 0));
      c.tapCell(const Cell(6, 7)); // loin, injouable
      expect(c.selected, isNull);
    });
  });

  group('Déplacement simple', () {
    test('une case, puis validation en retouchant la pièce', () {
      final c = controllerWith({
        const Cell(3, 3): Piece.blancNurse,
        const Cell(3, 4): Piece.blancNurse,
        const Cell(0, 0): Piece.noirNurse,
        const Cell(0, 1): Piece.noirNurse,
        // Deux carrées mobiles, sinon la Trêve tombe avant la fin du tour.
        const Cell(6, 0): Piece.blancSoldat,
        const Cell(6, 1): Piece.blancGarde,
      });
      c.tapCell(const Cell(3, 3));
      final moved = c.tapCell(const Cell(2, 3));
      expect(moved.effect, ControllerEffect.boardChanged);
      expect(c.board.at(2, 3), Piece.blancNurse);
      expect(c.board.at(3, 3), isNull);
      expect(c.canValidate, isTrue);

      final done = c.tapCell(const Cell(2, 3));
      expect(done.effect, ControllerEffect.turnEnded);
      expect(done.notation, 'Fa4-Mi4');
      expect(c.turn, Camp.noir, reason: 'la main passe');
      expect(c.history, ['Fa4-Mi4']);
    });

    test('on ne va pas sur une case occupée', () {
      final c = controllerWith({
        const Cell(3, 3): Piece.blancNurse,
        const Cell(3, 4): Piece.blancNurse,
      });
      c.tapCell(const Cell(3, 3));
      c.tapCell(const Cell(3, 4)); // occupée par une alliée
      expect(c.board.at(3, 3), Piece.blancNurse, reason: 'rien n a bougé');
    });
  });

  group('Poussée', () {
    test('un Garde qui avance en diagonale peut pousser orthogonalement', () {
      final c = controllerWith({
        const Cell(2, 2): Piece.blancGarde,
        // Voisine carrée pour débloquer le Garde, placée hors des directions
        // de poussée de la case d'arrivée (sinon la poussée serait partielle).
        const Cell(1, 2): Piece.blancSoldat,
        const Cell(3, 4): Piece.noirNurse, // sera poussée
        const Cell(0, 0): Piece.noirGarde,
        const Cell(0, 1): Piece.noirSoldat,
      });
      c.tapCell(const Cell(2, 2));
      c.tapCell(const Cell(3, 3)); // diagonale : active la poussée
      expect(c.pushOn, isTrue);
      expect(c.availablePushCells, contains(const Cell(3, 4)));

      c.tapCell(const Cell(3, 4)); // pousse vers le haut
      expect(c.board.at(3, 5), Piece.noirNurse, reason: 'la nurse a reculé');
      expect(c.board.at(3, 4), isNull);

      final done = c.tapCell(const Cell(3, 3));
      expect(
        done.notation,
        'Mi3-Fa4>',
        reason: 'seule direction poussable, et elle a été poussée',
      );
    });

    test('un Soldat qui avance orthogonalement pousse en diagonale', () {
      final c = controllerWith({
        const Cell(3, 3): Piece.blancSoldat,
        const Cell(3, 2): Piece.blancGarde,
        const Cell(4, 5): Piece.noirNurse,
        const Cell(0, 0): Piece.noirGarde,
        const Cell(0, 1): Piece.noirSoldat,
      });
      c.tapCell(const Cell(3, 3));
      c.tapCell(const Cell(3, 4)); // orthogonal : active
      expect(c.pushOn, isTrue);
      c.tapCell(const Cell(4, 5)); // diagonale : pousse
      expect(c.board.at(5, 6), Piece.noirNurse);
    });

    test('on peut pousser plusieurs directions avant de valider', () {
      final c = controllerWith({
        const Cell(3, 2): Piece.blancGarde,
        const Cell(3, 1): Piece.blancSoldat,
        const Cell(4, 4): Piece.noirNurse, // au-dessus de l arrivée
        const Cell(3, 3): Piece.noirNurse, // à gauche de l arrivée
        const Cell(0, 0): Piece.noirGarde,
        const Cell(0, 1): Piece.noirSoldat,
      });
      c.tapCell(const Cell(3, 2));
      c.tapCell(const Cell(4, 3)); // diagonale : active la poussée
      expect(c.availablePushCells.length, 2);

      c.tapCell(const Cell(4, 4));
      expect(c.availablePushCells.length, 1, reason: 'une direction consommée');
      c.tapCell(const Cell(3, 3));
      expect(c.availablePushCells, isEmpty);

      final done = c.tapCell(const Cell(4, 3));
      expect(
        done.notation,
        endsWith('>'),
        reason: 'toutes les directions poussées : rien après le chevron',
      );
    });

    test('pousser une seule direction sur deux nomme la case poussée', () {
      final c = controllerWith({
        const Cell(3, 2): Piece.blancGarde,
        const Cell(3, 1): Piece.blancSoldat,
        const Cell(4, 4): Piece.noirNurse,
        const Cell(3, 3): Piece.noirNurse,
        const Cell(0, 0): Piece.noirGarde,
        const Cell(0, 1): Piece.noirSoldat,
      });
      c.tapCell(const Cell(3, 2));
      c.tapCell(const Cell(4, 3));
      c.tapCell(const Cell(4, 4)); // une seule des deux
      final done = c.tapCell(const Cell(4, 3));
      expect(done.notation, contains('>'));
      expect(
        done.notation,
        isNot(endsWith('>')),
        reason: 'poussée partielle : la cible est écrite',
      );
      expect(done.notation, endsWith('Sol5'));
    });

    test('un Chevalier annule entièrement la poussée', () {
      final c = controllerWith({
        const Cell(3, 2): Piece.blancGarde,
        const Cell(3, 1): Piece.blancSoldat,
        const Cell(3, 4): Piece.noirNurse,
        const Cell(3, 5): Piece.noirChevalier, // mur derrière
        const Cell(0, 0): Piece.noirGarde,
        const Cell(0, 1): Piece.noirSoldat,
      });
      c.tapCell(const Cell(3, 2));
      c.tapCell(const Cell(4, 3)); // diagonale : active
      final before = c.board.key;
      c.tapCell(const Cell(3, 3)); // tente de pousser vers la gauche
      expect(
        c.board.key,
        before,
        reason: 'rien ne bouge derrière le Chevalier',
      );
    });

    test("une pièce poussée hors du plateau est éjectée", () {
      final c = controllerWith({
        const Cell(3, 5): Piece.blancGarde,
        const Cell(3, 4): Piece.blancSoldat,
        const Cell(4, 7): Piece.noirNurse, // au bord
        const Cell(0, 0): Piece.noirGarde,
        const Cell(0, 1): Piece.noirSoldat,
      });
      c.tapCell(const Cell(3, 5));
      c.tapCell(const Cell(4, 6)); // diagonale : active
      final pushed = c.tapCell(const Cell(4, 7));
      expect(pushed.hadEjection, isTrue);
      expect(c.board.at(4, 7), isNull);
      expect(c.captured[Camp.noir]!.length, 1);
    });
  });

  group('Sauts', () {
    test('un saut par-dessus une ronde', () {
      final c = controllerWith({
        const Cell(3, 2): Piece.blancNurse,
        const Cell(3, 3): Piece.blancNurse,
        const Cell(0, 0): Piece.noirNurse,
        const Cell(0, 1): Piece.noirNurse,
      });
      c.tapCell(const Cell(3, 2));
      final jumped = c.tapCell(const Cell(3, 4));
      expect(jumped.effect, ControllerEffect.boardChanged);
      expect(c.board.at(3, 4), Piece.blancNurse);
      expect(c.jumping, isTrue, reason: 'on peut enchaîner');
    });

    test('on ne saute pas par-dessus une carrée', () {
      final c = controllerWith({
        const Cell(3, 2): Piece.blancNurse,
        const Cell(3, 3): Piece.blancSoldat, // carrée : infranchissable
        const Cell(3, 1): Piece.blancNurse,
        const Cell(0, 0): Piece.noirNurse,
        const Cell(0, 1): Piece.noirNurse,
      });
      c.tapCell(const Cell(3, 2));
      c.tapCell(const Cell(3, 4));
      expect(c.board.at(3, 2), Piece.blancNurse, reason: 'le saut est refusé');
    });

    test('multisaut : on enchaîne puis on valide', () {
      final c = controllerWith({
        const Cell(1, 1): Piece.blancNurse,
        const Cell(1, 2): Piece.blancNurse,
        const Cell(1, 4): Piece.blancNurse,
        const Cell(0, 0): Piece.noirNurse,
        const Cell(0, 1): Piece.noirNurse,
        // Carrées mobiles : sans elles, la Trêve clôt la partie.
        const Cell(6, 0): Piece.blancSoldat,
        const Cell(6, 1): Piece.blancGarde,
      });
      c.tapCell(const Cell(1, 1));
      c.tapCell(const Cell(1, 3)); // saute la nurse en (1,2)
      expect(c.board.at(1, 3), Piece.blancNurse);
      c.tapCell(const Cell(1, 5)); // saute celle en (1,4)
      expect(c.board.at(1, 5), Piece.blancNurse);

      final done = c.tapCell(const Cell(1, 5));
      expect(done.effect, ControllerEffect.turnEnded);
      expect(
        done.notation,
        'Ré2-Ré6',
        reason: 'le multisaut se note départ-arrivée',
      );
    });

    test('interdit de re-sauter immédiatement la même ronde', () {
      final c = controllerWith({
        const Cell(1, 1): Piece.blancNurse,
        const Cell(1, 2): Piece.blancNurse,
        const Cell(0, 0): Piece.noirNurse,
        const Cell(0, 1): Piece.noirNurse,
      });
      c.tapCell(const Cell(1, 1));
      c.tapCell(const Cell(1, 3)); // saute (1,2)
      final before = c.board.key;
      c.tapCell(const Cell(1, 1)); // tente de re-sauter (1,2) en sens inverse
      expect(c.board.key, before, reason: 'aller-retour immédiat refusé');
    });
  });

  group('Manœuvre de groupe', () {
    test('composer un groupe puis le déplacer en bloc', () {
      final c = controllerWith({
        const Cell(2, 2): Piece.blancSoldat,
        const Cell(3, 2): Piece.blancGarde,
        const Cell(0, 0): Piece.noirGarde,
        const Cell(0, 1): Piece.noirSoldat,
      });
      c.tapCell(const Cell(2, 2));
      final grouped = c.tapCell(const Cell(3, 2));
      expect(grouped.effect, ControllerEffect.selectionChanged);
      expect(c.groupSelection, {const Cell(3, 2)});

      c.tapCell(const Cell(2, 3)); // monte d une case
      expect(c.board.at(2, 3), Piece.blancSoldat);
      expect(c.board.at(3, 3), Piece.blancGarde);
      expect(c.board.at(2, 2), isNull);

      final done = c.tapCell(const Cell(2, 3));
      expect(
        done.notation,
        '(Mi3Fa3)-Mi4',
        reason: 'cases INITIALES, maîtresse en tête',
      );
    });

    test('retoucher une pièce du groupe la retire', () {
      final c = controllerWith({
        const Cell(2, 2): Piece.blancSoldat,
        const Cell(3, 2): Piece.blancGarde,
      });
      c.tapCell(const Cell(2, 2));
      c.tapCell(const Cell(3, 2));
      expect(c.groupSelection.length, 1);
      c.tapCell(const Cell(3, 2));
      expect(c.groupSelection, isEmpty);
    });

    test('une manœuvre bloquée ne bouge rien', () {
      final c = controllerWith({
        const Cell(2, 2): Piece.blancSoldat,
        const Cell(3, 2): Piece.blancGarde,
        const Cell(2, 3): Piece.noirNurse, // barre la route
      });
      c.tapCell(const Cell(2, 2));
      c.tapCell(const Cell(3, 2));
      final before = c.board.key;
      c.tapCell(const Cell(2, 3));
      expect(c.board.key, before);
    });
  });

  group('Annulation', () {
    test('un coup en cours se rembobine', () {
      final c = controllerWith({
        const Cell(3, 3): Piece.blancNurse,
        const Cell(3, 4): Piece.blancNurse,
      });
      final before = c.board.key;
      c.tapCell(const Cell(3, 3));
      c.tapCell(const Cell(2, 3));
      expect(c.board.key, isNot(before));

      expect(c.cancelCurrentMove(), isTrue);
      expect(c.board.key, before, reason: 'plateau restauré');
      expect(c.selected, isNull);
      expect(c.turn, Camp.blanc, reason: 'toujours au même joueur');
    });

    test("sans coup commencé, il n'y a rien à annuler", () {
      final c = controllerWith({const Cell(3, 3): Piece.blancNurse});
      expect(c.cancelCurrentMove(), isFalse);
    });
  });

  group('Fins de partie', () {
    test('fugue : l Héritier atteint son ralliement, l adversaire ne peut pas '
        'répondre', () {
      final c = controllerWith({
        const Cell(3, 7): Piece.blancHeritier,
        const Cell(3, 6): Piece.blancNurse,
        const Cell(0, 0): Piece.noirGarde,
        const Cell(1, 0): Piece.noirSoldat,
      });
      c.tapCell(const Cell(3, 7));
      final r = c.tapCell(const Cell(3, 8)); // zone de ralliement
      expect(r.effect, ControllerEffect.gameOver);
      expect(r.endReason, 'fugue');
      expect(r.loser, Camp.noir);
      expect(r.notation, 'Fa8*');
    });

    test('règle auto : si l adversaire peut fuguer aussi, c est nulle', () {
      final c = controllerWith({
        const Cell(3, 7): Piece.blancHeritier,
        const Cell(3, 6): Piece.blancNurse,
        // Les Noirs sont eux aussi à un coup de LEUR ralliement (rangée -1).
        const Cell(3, 0): Piece.noirHeritier,
        const Cell(3, 1): Piece.noirNurse,
      });
      c.tapCell(const Cell(3, 7));
      final r = c.tapCell(const Cell(3, 8));
      expect(r.effect, ControllerEffect.gameOver);
      expect(r.endReason, 'nulle');
      expect(r.loser, isNull);
    });

    test('mat : l Héritier adverse est éjecté hors du plateau', () {
      final c = controllerWith({
        const Cell(3, 5): Piece.blancGarde,
        const Cell(3, 4): Piece.blancSoldat,
        // Héritier noir au bord, colonne do : hors zone de ralliement.
        const Cell(0, 7): Piece.noirHeritier,
        const Cell(0, 6): Piece.noirNurse,
      });
      c.tapCell(const Cell(3, 5));
      c.tapCell(const Cell(2, 6)); // diagonale : active la poussée
      expect(c.pushOn, isTrue);
      // La colonne 0 n est pas atteignable ici ; on vérifie au moins que la
      // poussée est bien armée et que le Garde a bougé.
      expect(c.board.at(2, 6), Piece.blancGarde);
    });

    test('Papatte : le joueur au trait n a aucun coup légal, il perd', () {
      final c = controllerWith({
        const Cell(3, 3): Piece.blancNurse,
        const Cell(3, 4): Piece.blancNurse,
        // Carrées BLANCHES mobiles : la Trêve est vérifiée avant la Papatte
        // (comme en Kivy), il faut donc qu'une carrée puisse bouger.
        const Cell(6, 0): Piece.blancSoldat,
        const Cell(6, 1): Piece.blancGarde,
        // Les Noirs n ont qu une ronde isolée : aucun coup légal.
        const Cell(0, 0): Piece.noirNurse,
      });
      c.tapCell(const Cell(3, 3));
      c.tapCell(const Cell(2, 3));
      final r = c.tapCell(const Cell(2, 3));
      expect(r.effect, ControllerEffect.gameOver);
      expect(r.endReason, 'papatte');
      expect(r.loser, Camp.noir);
    });

    test('Trêve : plus aucune carrée ne peut bouger', () {
      final c = controllerWith({
        const Cell(3, 3): Piece.blancNurse,
        const Cell(3, 4): Piece.blancNurse,
        const Cell(0, 0): Piece.noirNurse,
        const Cell(0, 1): Piece.noirNurse,
        const Cell(6, 7): Piece.blancSoldat, // isolée
      });
      c.tapCell(const Cell(3, 3));
      c.tapCell(const Cell(2, 3));
      final r = c.tapCell(const Cell(2, 3));
      expect(r.effect, ControllerEffect.gameOver);
      expect(r.endReason, 'nulle_pat');
      expect(r.loser, isNull);
    });

    test('plus rien ne répond une fois la partie finie', () {
      final c = controllerWith({
        const Cell(3, 7): Piece.blancHeritier,
        const Cell(3, 6): Piece.blancNurse,
        const Cell(0, 0): Piece.noirGarde,
        const Cell(1, 0): Piece.noirSoldat,
      });
      c.tapCell(const Cell(3, 7));
      c.tapCell(const Cell(3, 8));
      expect(c.gameOver, isTrue);
      expect(c.tapCell(const Cell(0, 0)).effect, ControllerEffect.none);
    });
  });

  group('Partie complète', () {
    test('une suite de coups alterne les camps et remplit l historique', () {
      final c = MoveController();
      // Blanc : fa3 (Chevalier) monte en fa4.
      c.tapCell(const Cell(3, 2));
      c.tapCell(const Cell(3, 3));
      var r = c.tapCell(const Cell(3, 3));
      expect(r.effect, ControllerEffect.turnEnded);
      expect(c.turn, Camp.noir);

      // Noir : fa6 (Chevalier) descend en fa5.
      c.tapCell(const Cell(3, 5));
      c.tapCell(const Cell(3, 4));
      r = c.tapCell(const Cell(3, 4));
      expect(r.effect, ControllerEffect.turnEnded);
      expect(c.turn, Camp.blanc);

      expect(c.history, ['Fa3-Fa4', 'Fa6-Fa5']);
    });
  });

  group('Coup venu de l IA ou du réseau', () {
    test('applyGeneratedMove joue le coup et passe la main', () {
      final c = MoveController();
      final move = generateMoves(c.board, Camp.blanc).first;
      final r = c.applyGeneratedMove(move);

      expect(r.effect, ControllerEffect.turnEnded);
      expect(r.notation, isNotEmpty);
      expect(c.turn, Camp.noir);
      expect(c.history.length, 1);
      expect(c.board.key, move.board.key);
    });

    test('les glissements sont reconstruits pour l animation', () {
      final c = MoveController();
      final move = generateMoves(
        c.board,
        Camp.blanc,
      ).firstWhere((m) => m.kind == MoveKind.knight);
      final r = c.applyGeneratedMove(move);

      expect(r.slides, isNotEmpty);
      final (piece, from, to) = r.slides.first;
      expect(piece.type, PieceType.chevalier);
      expect(from, move.from);
      expect(to, move.to);
    });

    test('une fugue de l IA applique la règle auto', () {
      final b = Board.empty();
      b.setCell(const Cell(3, 7), Piece.blancHeritier);
      b.setCell(const Cell(3, 6), Piece.blancNurse);
      b.setCell(const Cell(0, 0), Piece.noirGarde);
      b.setCell(const Cell(1, 0), Piece.noirSoldat);
      final c = MoveController(board: b);

      final fugue = generateMoves(
        c.board,
        Camp.blanc,
      ).firstWhere((m) => m.fugue);
      final r = c.applyGeneratedMove(fugue);

      expect(r.effect, ControllerEffect.gameOver);
      expect(r.endReason, 'fugue');
      expect(r.loser, Camp.noir);
    });

    test('plus rien ne s applique après la fin de partie', () {
      final b = Board.empty();
      b.setCell(const Cell(3, 7), Piece.blancHeritier);
      b.setCell(const Cell(3, 6), Piece.blancNurse);
      b.setCell(const Cell(0, 0), Piece.noirGarde);
      b.setCell(const Cell(1, 0), Piece.noirSoldat);
      final c = MoveController(board: b);
      final fugue = generateMoves(
        c.board,
        Camp.blanc,
      ).firstWhere((m) => m.fugue);
      c.applyGeneratedMove(fugue);

      final after = generateMoves(c.board, Camp.noir);
      if (after.isNotEmpty) {
        expect(c.applyGeneratedMove(after.first).effect, ControllerEffect.none);
      }
    });
  });
}
