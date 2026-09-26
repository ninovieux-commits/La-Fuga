/// La marque de fin de partie dans le `.nmc` : `*` et `#`.
///
/// Le dernier coup d'une partie porte son résultat : `*` pour un gain à deux
/// points — fugue, abandon, temps écoulé — et `#` pour un gain simple, un
/// Héritier éjecté hors du plateau.
///
/// Deux choses se jouent ici.
///
/// D'abord, la marque doit être ÉCRITE. Une fugue par poussée s'écrivait
/// « Mi6-Fa7>Fa8 », sans rien qui dise que la partie était gagnée, là où une
/// fugue marchée s'écrit « Fa8* » et le dit. Le fichier ne décrivait pas le
/// même événement selon la façon de l'obtenir.
///
/// Ensuite, elle doit être RELUE sans casser le coup. Collée à la dernière case
/// poussée, « Mi6-Fa7>Fa8* » ne se relisait pas du tout : la liste des cases
/// était refusée, la poussée n'était pas appliquée, la position d'arrivée était
/// fausse et le lecteur annonçait une partie interrompue. Cette forme-là
/// existait DÉJÀ : tout abandon qui suit une poussée la produit.
///
/// Et la marque ne dit jamais, à elle seule, qu'un Héritier a fugué : un
/// abandon porte le même `*`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/game/last_move.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/game/replay_controller.dart';

/// Un Garde noir en (2,5) qui peut aller en (3,6) EN DIAGONALE — c'est ce qui
/// active sa poussée — puis pousser ce qui est en (3,6)+(0,1).
Board _positionDePoussee({required Piece? sur37}) {
  final b = Board.empty();
  b.set(2, 5, const Piece(PieceType.garde, Camp.noir));
  b.set(1, 5, const Piece(PieceType.garde, Camp.noir));
  if (sur37 != null) b.set(3, 7, sur37);
  b.set(0, 0, Piece.noirHeritier);
  return b;
}

const NmcMeta _meta = NmcMeta(
  date: '2026-09-26',
  player1: 'Nino',
  player2: 'Ana',
  blanc: 'Nino',
  objectif: 'partie',
  cadence: 'zen',
  result: '1-0',
  method: 'fugue',
  points: '2',
);

void main() {
  group('Séparer le coup de sa marque', () {
    test('une fugue sans case nommable garde son étoile', () {
      // « Fa8* » n'a pas de tiret : l'étoile EST le coup, elle dit que la pièce
      // quitte le plateau. La confondre avec une marque de résultat ferait
      // disparaître le coup.
      final r = splitEndMark('Fa8*');
      expect(r.move, 'Fa8*', reason: 'l étoile fait partie du coup');
      expect(r.mark, '');
    });

    test('après une poussée, l étoile est une marque', () {
      final r = splitEndMark('Mi6-Fa7>Fa8*');
      expect(r.move, 'Mi6-Fa7>Fa8');
      expect(r.mark, '*');
    });

    test('le dièse aussi, et sur une manœuvre', () {
      expect(splitEndMark('Do1-Do2#').move, 'Do1-Do2');
      expect(splitEndMark('(Do1Mi1)-Ré2#').move, '(Do1Mi1)-Ré2');
      expect(splitEndMark('(Do1Mi1)-Ré2#').mark, '#');
    });

    test('un coup ordinaire n a pas de marque', () {
      expect(splitEndMark('Do1-Do2').mark, '');
      expect(splitEndMark('Do1-Do2>Ré3Mi4').mark, '');
    });
  });

  group('La marque ne casse plus le coup', () {
    // Le cœur du bug : ces trois notations décrivent le MÊME déplacement.
    const memeCoup = ['Mi6-Fa7>Fa8', 'Mi6-Fa7>Fa8*', 'Mi6-Fa7>Fa8#'];

    test('la poussée est appliquée, marque ou pas', () {
      final attendu = applyNotationLiterally(
        _positionDePoussee(sur37: Piece.blancHeritier),
        memeCoup.first,
      );
      expect(attendu.ok, isTrue, reason: 'le coup nu ne passe pas : test vain');

      for (final notation in memeCoup) {
        final r = applyNotationLiterally(
          _positionDePoussee(sur37: Piece.blancHeritier),
          notation,
        );
        expect(r.ok, isTrue, reason: '« $notation » est refusée');
        expect(
          r.board.render(),
          attendu.board.render(),
          reason:
              '« $notation » ne donne pas la même position que le coup nu : '
              'la poussée a été perdue avec la marque',
        );
        expect(r.fugued, {
          Camp.blanc,
        }, reason: '« $notation » : la fugue par poussée n est pas vue');
      }
    });

    test('le réseau résout les trois formes de la même façon', () {
      for (final notation in memeCoup) {
        final parts = parseNotation(notation);
        expect(parts, isA<SimpleNotation>(), reason: '« $notation » illisible');
        expect((parts! as SimpleNotation).pushed, [const Cell(3, 7)]);
      }
    });

    test('les cases poussées se retrouvent malgré la marque', () {
      for (final notation in memeCoup) {
        expect(
          reconstructPushTargets(notation, null),
          [const Cell(3, 7)],
          reason:
              '« $notation » : les points de poussée du dernier coup '
              'disparaissaient sur le coup qui clôt la partie',
        );
      }
    });

    test('la mise en évidence est la même', () {
      final avant = _positionDePoussee(sur37: Piece.blancHeritier);
      final apres = applyNotationLiterally(avant, memeCoup.first).board;
      final nu = lastMoveFromNotation(memeCoup.first, avant, apres)!;
      for (final notation in memeCoup) {
        final m = lastMoveFromNotation(notation, avant, apres)!;
        expect(m.framedCells, nu.framedCells, reason: '« $notation »');
      }
    });
  });

  group('Ce que le fichier écrit', () {
    test('une fugue par POUSSÉE porte l étoile', () {
      expect(
        withEndSuffix(['Do2-Do3', 'Mi6-Fa7>Fa8'], 'fugue').last,
        'Mi6-Fa7>Fa8*',
        reason: 'rien ne disait que ce coup gagnait la partie',
      );
    });

    test('une fugue marchée n en prend pas une deuxième', () {
      expect(withEndSuffix(['Fa8*'], 'fugue').last, 'Fa8*');
    });

    test('un Héritier éjecté porte le dièse', () {
      expect(
        withEndSuffix(['Do2-Do3', 'Ré6-Do7>Do8'], 'mat').last,
        'Ré6-Do7>Do8#',
      );
    });

    test('un abandon et un temps écoulé portent l étoile aussi', () {
      expect(withEndSuffix(['Mi6-Fa7>Fa8'], 'abandon').last, 'Mi6-Fa7>Fa8*');
      expect(withEndSuffix(['Mi6-Fa7>Fa8'], 'temps').last, 'Mi6-Fa7>Fa8*');
    });

    test('une nulle ne marque rien', () {
      expect(withEndSuffix(['Do1-Do2'], 'nulle').last, 'Do1-Do2');
    });
  });

  group('Du plateau au fichier et retour', () {
    /// Rejoue un `.nmc` depuis une position donnée et rend la dernière étape.
    ReplayStep relire(List<String> coups, Board depart, String methode) {
      final nmc = buildNmc(_meta, withEndSuffix(coups, methode));
      final replay = ReplayController.fromNmc(nmc, initialBoard: depart);
      expect(
        replay.isTruncated,
        isFalse,
        reason:
            'lecture interrompue au coup ${replay.brokenMoveNumber} : '
            'le fichier que nous écrivons ne se relit pas',
      );
      expect(replay.moveCount, coups.length);
      replay.toEnd();
      return replay.current;
    }

    test('une fugue par poussée : étoile écrite, Héritier relu', () {
      // Le coup est joué pour de vrai, sa notation vient du moteur.
      final depart = _positionDePoussee(sur37: Piece.blancHeritier);
      final game = MoveController(board: depart.clone(), turn: Camp.noir);
      final coup = generateMoves(game.board, Camp.noir).firstWhere(
        (m) {
          final essai = MoveController(board: depart.clone(), turn: Camp.noir);
          essai.applyGeneratedMove(m);
          return essai.fuguedHeirs.contains(Camp.blanc);
        },
        orElse: () => throw StateError('aucune fugue par poussée : test vain'),
      );
      game.applyGeneratedMove(coup);

      final marques = withEndSuffix(game.history, 'fugue');
      expect(
        marques.last.endsWith('*'),
        isTrue,
        reason: 'le coup gagnant n est pas marqué : ${marques.last}',
      );

      final fin = relire(game.history, depart, 'fugue');
      expect(
        fin.fugued,
        {Camp.blanc},
        reason: 'relu depuis le fichier, l Héritier n est pas dans sa zone',
      );
    });

    test('ABANDON : l étoile ne met aucun Héritier dans le ralliement', () {
      // Le piège. Un abandon marque le dernier coup d'une étoile, exactement
      // comme une fugue. Si l'affichage s'appuyait sur la marque, l'Héritier
      // apparaîtrait dans son ralliement sur une partie abandonnée.
      final depart = _positionDePoussee(
        sur37: const Piece(PieceType.nurse, Camp.blanc),
      );
      final fin = relire(['Mi6-Fa7>Fa8'], depart, 'abandon');

      expect(
        fin.fugued,
        isEmpty,
        reason: 'un abandon fait apparaître un Héritier qui n a jamais fugué',
      );
      // Et la poussée a bien eu lieu : la Nurse est sortie du plateau.
      expect(
        fin.board.at(3, 7),
        isNull,
        reason: 'la poussée a été perdue avec la marque',
      );
      expect(fin.board.at(2, 5), isNull, reason: 'le Garde n a pas avancé');
      expect(fin.board.at(3, 6)?.type, PieceType.garde);
    });

    test('un Héritier ÉJECTÉ : dièse écrit, et pas de fugue', () {
      // Poussé hors du plateau par une colonne sans ralliement : il est pris,
      // pas arrivé. Le fichier dit `#`, et la relecture ne le met nulle part.
      final depart = Board.empty();
      depart.set(1, 5, const Piece(PieceType.garde, Camp.noir));
      depart.set(2, 5, const Piece(PieceType.garde, Camp.noir));
      depart.set(0, 7, Piece.blancHeritier);
      depart.set(0, 0, Piece.noirHeritier);

      final marques = withEndSuffix(['Ré6-Do7>Do8'], 'mat');
      expect(marques.last, 'Ré6-Do7>Do8#');

      final fin = relire(['Ré6-Do7>Do8'], depart, 'mat');
      expect(
        fin.fugued,
        isEmpty,
        reason: 'un Héritier éjecté n a pas rejoint de ralliement',
      );
      expect(fin.board.at(0, 7), isNull, reason: 'il est toujours là');
    });
  });
}
