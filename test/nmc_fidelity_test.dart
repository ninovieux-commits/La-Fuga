/// Test de fidélité du format `.nmc` : l'app Flutter doit écrire et relire
/// exactement ce que l'app Kivy écrit et relit. Le fichier est le format
/// d'échange avec le serveur — une divergence rendrait une partie enregistrée
/// depuis un téléphone illisible depuis l'autre.
///
/// Les vecteurs de `test/fixtures/nmc_vectors.json` sont produits par
/// `tool/gen_nmc_vectors.py`, qui exécute la couche `.nmc` recopiée de
/// `main.py` (`tool/py_nmc_ref.py`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:test/test.dart';

/// Ordonne les cases d'une manœuvre : maîtresse en tête, reste trié.
///
/// L'ordre de Kivy vient de l'itération d'un `set` Python — un artefact
/// d'implémentation, que la relecture ignore (seule la maîtresse compte, elle
/// donne le delta). On compare donc le contenu, qui seul fait sens.
String normalized(String notation) {
  final m = RegExp(r'^\((.*)\)-(.+)$').firstMatch(notation);
  if (m == null) return notation;
  final cells = parseCellsConcat(m.group(1)!);
  if (cells == null || cells.isEmpty) return notation;
  final others = cells.skip(1).toList()
    ..sort((a, b) => a.col != b.col ? a.col - b.col : a.row - b.row);
  final str = [cells.first, ...others].map(cellToNotationOf).join();
  return '($str)-${m.group(2)}';
}

void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    vectors =
        jsonDecode(File('test/fixtures/nmc_vectors.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  test('les vecteurs sont chargés', () {
    expect((vectors['notations'] as List).length, greaterThan(50));
    expect((vectors['files'] as List), isNotEmpty);
    expect((vectors['parses'] as List), isNotEmpty);
  });

  test('chaque coup légal porte la notation de Kivy', () {
    var checked = 0;
    for (var i = 0; i < (vectors['notations'] as List).length; i++) {
      final v = (vectors['notations'] as List)[i] as Map<String, dynamic>;
      final board = Board.fromJson(v['board'] as List<dynamic>);
      final camp = Camp.fromWire(v['camp'] as String);
      final expected = (v['moves'] as List).cast<Map<String, dynamic>>();

      final moves = generateMoves(board, camp);
      expect(moves.length, expected.length, reason: 'position #$i');

      // La manœuvre est le seul coup dont l'ordre des cases dépend de
      // l'itération d'un `set` Python : on compare les notations par paquets,
      // appariés sur le plateau d'après, qui lui est sans ambiguïté.
      final byBoard = <String, List<String>>{};
      for (final e in expected) {
        final key = Board.fromJson(e['after'] as List<dynamic>).key;
        byBoard
            .putIfAbsent(key, () => [])
            .add(normalized(e['notation'] as String));
      }

      for (final mv in moves) {
        final mine = normalized(notationOn(board, mv));
        final theirs = byBoard[mv.board.key];
        expect(
          theirs,
          isNotNull,
          reason: 'position #$i : aucun coup Kivy ne mène à ce plateau',
        );
        expect(
          theirs,
          contains(mine),
          reason:
              'position #$i : notation « $mine » absente de Kivy '
              '(${theirs!.join(", ")})\n${board.render()}',
        );
        checked++;
      }
    }
    // ignore: avoid_print
    print('$checked notations vérifiées contre Kivy');
  });

  test('toute notation de Kivy se relit vers le bon coup', () {
    var checked = 0;
    var ambiguous = 0;
    for (var i = 0; i < (vectors['notations'] as List).length; i++) {
      final v = (vectors['notations'] as List)[i] as Map<String, dynamic>;
      final board = Board.fromJson(v['board'] as List<dynamic>);
      final camp = Camp.fromWire(v['camp'] as String);
      final expected = (v['moves'] as List).cast<Map<String, dynamic>>();

      // Une notation portée par deux coups distincts est ambiguë chez Kivy
      // aussi : on ne peut rien exiger de sa relecture.
      final boardsOf = <String, Set<String>>{};
      for (final e in expected) {
        boardsOf
            .putIfAbsent(e['notation'] as String, () => {})
            .add(Board.fromJson(e['after'] as List<dynamic>).key);
      }

      for (final e in expected) {
        final notation = e['notation'] as String;
        final after = Board.fromJson(e['after'] as List<dynamic>).key;
        if (boardsOf[notation]!.length > 1) {
          ambiguous++;
          continue;
        }
        final resolved = resolveNotation(board, camp, notation);
        expect(
          resolved,
          isNotNull,
          reason:
              'position #$i : « $notation » (${e["kind"]}) refusée\n'
              '${board.render()}',
        );
        expect(
          resolved!.board.key,
          after,
          reason: 'position #$i : « $notation » rejouée autrement',
        );
        checked++;
      }
    }
    // ignore: avoid_print
    print(
      '$checked notations relues ($ambiguous ambiguës chez Kivy, ignorées)',
    );
  });

  test('le fichier écrit est celui de Kivy, octet pour octet', () {
    for (final f in (vectors['files'] as List).cast<Map<String, dynamic>>()) {
      final m = f['meta'] as Map<String, dynamic>;
      final meta = NmcMeta(
        date: m['date'] as String,
        player1: m['player1'] as String,
        player2: m['player2'] as String,
        blanc: m['blanc'] as String,
        objectif: m['objectif'] as String,
        cadence: m['cadence'] as String,
        result: m['result'] as String,
        method: m['method'] as String,
        points: m['points'] as String,
        random: m['random'] as String?,
      );
      final moves = (f['moves'] as List).cast<String>();
      expect(buildNmc(meta, moves), f['content'] as String);
    }
  });

  test('une partie entière se rejoue de bout en bout', () {
    var replayed = 0;
    for (final f in (vectors['files'] as List).cast<Map<String, dynamic>>()) {
      final game = parseNmc(f['content'] as String);
      expect(game.moves, f['moves'] as List);

      var board = Board.initial();
      var camp = Camp.blanc;
      for (final notation in game.moves) {
        final mv = resolveNotation(board, camp, notation);
        expect(
          mv,
          isNotNull,
          reason: 'coup « $notation » refusé\n${board.render()}',
        );
        board = mv!.board;
        camp = camp == Camp.blanc ? Camp.noir : Camp.blanc;
        replayed++;
      }
    }
    expect(replayed, greaterThan(50));
    // ignore: avoid_print
    print('$replayed coups rejoués depuis des fichiers .nmc de Kivy');
  });

  test("l'en-tête et les coups se relisent comme chez Kivy", () {
    for (final p in (vectors['parses'] as List).cast<Map<String, dynamic>>()) {
      final content = p['content'] as String;
      final expectedMeta = (p['meta'] as Map).cast<String, String>();
      final expectedMoves = (p['moves'] as List).cast<String>();

      final game = parseNmc(content);
      expect(
        game.moves,
        expectedMoves,
        reason: 'coups différents pour :\n$content',
      );

      // Les champs que Kivy a lus doivent se retrouver un à un.
      final fields = game.meta.toFields().map(
        (k, v) => MapEntry(k.toLowerCase(), v),
      );
      expectedMeta.forEach((key, value) {
        expect(
          fields[key],
          value,
          reason: 'en-tête « $key » différent pour :\n$content',
        );
      });
    }
  });
}
