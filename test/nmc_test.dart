/// Format `.nmc` : c'est le format d'échange avec le serveur, donc un
/// aller-retour doit rendre exactement ce qu'on y a mis.
library;

import 'package:lafuga/game/nmc.dart';
import 'package:test/test.dart';

const _meta = NmcMeta(
  date: '2026-09-19',
  player1: 'Nino',
  player2: 'Deep Grey',
  blanc: 'Nino',
  objectif: 'partie',
  cadence: '5min',
  result: '1-0',
  method: 'fugue',
  points: '2',
);

void main() {
  group('Formatage des coups', () {
    test('numérote par paires', () {
      expect(
        formatMoves(['Do1-Do2', 'Do8-Do7', 'Ré1-Ré2']),
        '1.Do1-Do2/Do8-Do7  2.Ré1-Ré2',
      );
    });

    test('un historique vide donne une chaîne vide', () {
      expect(formatMoves([]), '');
    });

    test('un seul coup ne porte pas de barre', () {
      expect(formatMoves(['Do1-Do2']), '1.Do1-Do2');
    });
  });

  group('Lecture des coups', () {
    test('retrouve les coups malgré les numéros de tour', () {
      expect(parseMoves('1.Do1-Do2/Do8-Do7  2.Ré1-Ré2'), [
        'Do1-Do2',
        'Do8-Do7',
        'Ré1-Ré2',
      ]);
    });

    test('tolère retours à la ligne et espaces multiples', () {
      expect(parseMoves('1.Do1-Do2/Do8-Do7\n\n   2.Ré1-Ré2  '), [
        'Do1-Do2',
        'Do8-Do7',
        'Ré1-Ré2',
      ]);
    });

    test('garde les notations particulières intactes', () {
      final moves = parseMoves('1.(Do1Ré1)-Do2/Fa7*  2.Mi3-Fa4>Sol5');
      expect(moves, ['(Do1Ré1)-Do2', 'Fa7*', 'Mi3-Fa4>Sol5']);
    });

    test('un texte vide ne donne aucun coup', () {
      expect(parseMoves(''), isEmpty);
      expect(parseMoves('   \n  '), isEmpty);
    });
  });

  group('Fichier complet', () {
    test('aller-retour : ce qu on écrit est ce qu on relit', () {
      const moves = ['Do1-Do2', 'Do8-Do7', '(Do1Ré1)-Do2', 'Fa7*'];
      final content = buildNmc(_meta, moves);
      final game = parseNmc(content);

      expect(game.moves, moves);
      expect(game.meta.date, _meta.date);
      expect(game.meta.player1, 'Nino');
      expect(game.meta.player2, 'Deep Grey');
      expect(game.meta.blanc, 'Nino');
      expect(game.meta.objectif, 'partie');
      expect(game.meta.cadence, '5min');
      expect(game.meta.result, '1-0');
      expect(game.meta.method, 'fugue');
      expect(game.meta.points, '2');
      expect(game.meta.random, isNull);
    });

    test('le code Random Fuga est conservé', () {
      const meta = NmcMeta(
        date: '2026-09-19',
        player1: 'A',
        player2: 'B',
        blanc: 'A',
        objectif: '5',
        cadence: 'illimité',
        result: '½-½',
        method: 'nulle',
        points: '0',
        random: '.03-09',
      );
      final game = parseNmc(buildNmc(meta, ['Do1-Do2']));
      expect(
        game.meta.random,
        '.03-09',
        reason: 'sans lui, la position de départ serait irrécupérable',
      );
    });

    test("l'en-tête s'arrête à la première ligne vide", () {
      const content =
          '[Date "2026-09-19"]\n'
          '[Joueur1 "Nino"]\n'
          '\n'
          '1.Do1-Do2/Do8-Do7\n'
          '2.Ré1-Ré2';
      final game = parseNmc(content);
      expect(game.meta.date, '2026-09-19');
      expect(game.moves.length, 3);
    });

    test('un contenu vide ne fait pas planter la lecture', () {
      final game = parseNmc('');
      expect(game.moves, isEmpty);
      expect(game.meta.player1, '');
    });

    test('un fichier sans en-tête donne quand même ses coups', () {
      final game = parseNmc('1.Do1-Do2/Do8-Do7');
      expect(game.moves, ['Do1-Do2', 'Do8-Do7']);
    });

    test('un pseudo avec espaces survit à l aller-retour', () {
      const meta = NmcMeta(
        date: '2026-09-19',
        player1: 'Jean Pierre',
        player2: 'Deep Grey',
        blanc: 'Jean Pierre',
        objectif: 'partie',
        cadence: 'illimité',
        result: '0-1',
        method: 'mat',
        points: '1',
      );
      final game = parseNmc(buildNmc(meta, ['Do1-Do2']));
      expect(game.meta.player1, 'Jean Pierre');
    });
  });

  group('Symbole de résultat', () {
    test('du point de vue des Blancs', () {
      expect(resultSymbol(loserCamp: 'Noir'), '1-0');
      expect(resultSymbol(loserCamp: 'Blanc'), '0-1');
      expect(resultSymbol(loserCamp: null), '½-½');
    });
  });
}
