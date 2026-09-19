/// Livre d'ouvertures de Deep Grey — portage de `dg_load_openings`,
/// `dg_record_winning_line` et `dg_lookup_opening` (main.py).
///
/// Principe inchangé : pour une position donnée (plateau + camp au trait), on
/// mémorise les coups qui ont mené à une **victoire**, avec un compteur. Tant
/// que Deep Grey « connaît » la position, il rejoue le coup le plus souvent
/// gagnant. Le livre s'enrichit à chaque partie que l'IA perd : elle apprend
/// de celui qui l'a battue.
///
/// Dart pur : le livre traverse l'isolate comme le reste du moteur.
library;

import 'dart:convert';

import '../board.dart';
import '../move_generator.dart';
import '../piece.dart';

/// Clé d'une position dans le livre : plateau + camp au trait.
String openingKey(Board board, Camp camp) => '${board.key}|${camp.wire}';

/// La notation telle qu'elle est rangée : sans la marque de fin de partie.
///
/// `Mi7*` et `Mi7` sont le même coup ; seul le contexte différait.
String bookNotation(String notation) {
  var s = notation.trim();
  while (s.endsWith('#') || s.endsWith('*')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Coups gagnants mémorisés, par position.
final class OpeningBook {
  OpeningBook([Map<String, Map<String, int>>? entries])
    : _entries = {
        for (final e in (entries ?? const {}).entries)
          e.key: Map<String, int>.from(e.value),
      };

  final Map<String, Map<String, int>> _entries;

  bool get isEmpty => _entries.isEmpty;

  int get positionCount => _entries.length;

  /// Le coup le plus souvent gagnant dans cette position, ou `null` si elle
  /// est inconnue.
  ///
  /// [minCount] est le nombre de victoires à partir duquel on fait confiance à
  /// un coup.
  String? lookup(Board board, Camp camp, {int minCount = 1}) {
    final entry = _entries[openingKey(board, camp)];
    if (entry == null || entry.isEmpty) return null;

    String? best;
    var bestCount = 0;
    for (final e in entry.entries) {
      if (e.value > bestCount) {
        best = e.key;
        bestCount = e.value;
      }
    }
    return bestCount >= minCount ? best : null;
  }

  /// Nombre de victoires mémorisées pour un coup donné.
  int countOf(Board board, Camp camp, String notation) =>
      _entries[openingKey(board, camp)]?[bookNotation(notation)] ?? 0;

  /// Mémorise les coups joués par le **gagnant** d'une partie.
  ///
  /// La partie est rejouée depuis [initialBoard] : chaque coup du gagnant est
  /// enregistré avec la position qu'il avait devant lui. Un coup qui ne se
  /// relit pas arrête l'enregistrement — sans les positions suivantes, on ne
  /// saurait plus à quoi rattacher les coups d'après.
  ///
  /// Renvoie vrai si le livre a changé.
  bool recordWinningLine({
    required Board initialBoard,
    required List<String> moves,
    required Camp winner,
    Camp firstPlayer = Camp.blanc,
  }) {
    var board = initialBoard;
    var camp = firstPlayer;
    var changed = false;

    for (final raw in moves) {
      // On relit le coup tel qu'il a été écrit — l'étoile d'une fugue fait
      // partie de sa notation — mais on le range sans sa marque de fin.
      final move = resolveNotation(board, camp, raw.trim());
      if (move == null) break;
      final notation = bookNotation(raw);

      if (camp == winner && notation.isNotEmpty) {
        final entry = _entries.putIfAbsent(openingKey(board, camp), () => {});
        entry[notation] = (entry[notation] ?? 0) + 1;
        changed = true;
      }

      board = move.board;
      camp = camp.opposite;
    }
    return changed;
  }

  static OpeningBook fromJsonString(String s) {
    try {
      final raw = jsonDecode(s);
      if (raw is! Map) return OpeningBook();
      return OpeningBook({
        for (final e in raw.entries)
          if (e.value is Map)
            e.key as String: {
              for (final m in (e.value as Map).entries)
                if (m.value is num) m.key as String: (m.value as num).toInt(),
            },
      });
    } catch (_) {
      // Un livre illisible n'empêche pas de jouer : l'IA repart de zéro.
      return OpeningBook();
    }
  }

  String toJsonString() => jsonEncode(_entries);
}
