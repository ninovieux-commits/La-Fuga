/// Le `.nmc` sait partir d'une position composée.
///
/// Nino : « Il faut ajouter au nmc la possibilité de partir d'un code .fug !
/// Quand c'est une position random, il le fait déjà avec un code plus court. »
///
/// C'est exactement le même rôle que l'en-tête `Random`, pour les positions
/// qu'un code de 3 500 possibilités ne sait pas écrire. Sans cela, une partie
/// composée se relirait depuis la position STANDARD : chacun de ses coups
/// atterrirait ailleurs, et la partie serait illisible.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/fug.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/game/replay_controller.dart';

/// Une position reconnaissable, qui n'est NI la standard NI une Random Fuga.
Board _composee() {
  final b = Board.empty();
  b.set(0, 0, Piece.blancHeritier);
  b.set(2, 2, Piece.blancSoldat);
  b.set(3, 2, Piece.blancGarde);
  b.set(0, 7, Piece.noirHeritier);
  b.set(2, 5, Piece.noirSoldat);
  b.set(3, 5, Piece.noirGarde);
  return b;
}

void main() {
  group('L en-tête Position', () {
    test('il s écrit et se relit comme Random', () {
      final fug = fugEnUneLigne(fugEcrire(_composee(), Camp.noir));
      const base = NmcMeta(
        date: '2026-10-06 12:00',
        player1: 'nino',
        player2: 'celia',
        blanc: 'nino',
        objectif: 'partie',
        cadence: 'corr',
        result: '1-0',
        method: 'mat',
        points: '1',
      );
      final texte = buildNmc(
        NmcMeta(
          date: base.date,
          player1: base.player1,
          player2: base.player2,
          blanc: base.blanc,
          objectif: base.objectif,
          cadence: base.cadence,
          result: base.result,
          method: base.method,
          points: base.points,
          position: fug,
        ),
        const [],
      );
      expect(texte.contains('[Position "$fug"]'), isTrue, reason: texte);
      expect(parseNmc(texte).meta.position, fug);
    });

    test('une partie sans position n en écrit pas', () {
      const meta = NmcMeta(
        date: '2026-10-06 12:00',
        player1: 'nino',
        player2: 'celia',
        blanc: 'nino',
        objectif: 'partie',
        cadence: 'zen',
        result: '1-0',
        method: 'mat',
        points: '1',
      );
      expect(buildNmc(meta, const []).contains('Position'), isFalse);
      expect(parseNmc(buildNmc(meta, const [])).meta.position, isNull);
    });
  });

  group('La relecture repart de la position écrite', () {
    test('le plateau de départ est la position composée', () {
      final depart = _composee();
      final archive = buildOpponentArchive(
        myPseudo: 'nino',
        opponent: 'celia',
        myCamp: Camp.noir,
        winner: Camp.noir,
        method: 'mat',
        history: const [],
        position: fugEnUneLigne(fugEcrire(depart, Camp.noir)),
        corrGameId: '7',
      );
      final relu = ReplayController.fromNmc(
        buildNmc(archive.meta, archive.moves),
      );
      expect(
        relu.steps.first.board.positionKey(Camp.blanc),
        depart.positionKey(Camp.blanc),
        reason: 'la partie se relit depuis la position STANDARD',
      );
    });

    test('et du bon camp au trait', () {
      final archive = buildOpponentArchive(
        myPseudo: 'nino',
        opponent: 'celia',
        myCamp: Camp.noir,
        winner: null,
        method: 'nulle',
        history: const [],
        position: fugEnUneLigne(fugEcrire(_composee(), Camp.noir)),
      );
      expect(
        ReplayController.fromNmc(
          buildNmc(archive.meta, archive.moves),
        ).steps.first.turn,
        Camp.noir,
        reason:
            'une position composée peut mettre les NOIRS au trait ; son '
            'premier coup n est alors pas blanc',
      );
    });

    test('les coups se rejouent par-dessus, et ils aboutissent', () {
      final depart = _composee();
      // Un coup réellement jouable dans CETTE position.
      const coup = 'Mi3-Mi4';
      expect(applyNotationLiterally(depart, coup).ok, isTrue);
      final attendu = applyNotationLiterally(depart, coup).board;

      final archive = buildOpponentArchive(
        myPseudo: 'nino',
        opponent: 'celia',
        myCamp: Camp.noir,
        winner: Camp.blanc,
        method: 'mat',
        history: const [coup],
        position: fugEnUneLigne(fugEcrire(depart, Camp.blanc)),
      );
      final relu = ReplayController.fromNmc(
        buildNmc(archive.meta, archive.moves),
      );
      expect(relu.isTruncated, isFalse, reason: 'le coup ne se relit pas');
      expect(
        relu.steps.last.board.positionKey(Camp.blanc),
        attendu.positionKey(Camp.blanc),
      );
    });

    test('une position abîmée retombe sur la standard, sans tomber', () {
      const meta = NmcMeta(
        date: '2026-10-06 12:00',
        player1: 'nino',
        player2: 'celia',
        blanc: 'nino',
        objectif: 'partie',
        cadence: 'corr',
        result: '1-0',
        method: 'mat',
        points: '1',
        position: 'n importe quoi',
      );
      final relu = ReplayController.fromNmc(buildNmc(meta, const []));
      expect(
        relu.steps.first.board.positionKey(Camp.blanc),
        Board.initial().positionKey(Camp.blanc),
      );
    });

    test('Random continue de marcher comme avant', () {
      const meta = NmcMeta(
        date: '2026-10-06 12:00',
        player1: 'nino',
        player2: 'celia',
        blanc: 'nino',
        objectif: 'partie',
        cadence: 'zen',
        result: '1-0',
        method: 'mat',
        points: '1',
        random: '.03-09',
      );
      final relu = ReplayController.fromNmc(buildNmc(meta, const []));
      expect(
        relu.steps.first.board.positionKey(Camp.blanc),
        isNot(Board.initial().positionKey(Camp.blanc)),
        reason: 'la position Random Fuga n est plus reconstruite',
      );
      expect(relu.steps.first.turn, Camp.blanc);
    });
  });
}
