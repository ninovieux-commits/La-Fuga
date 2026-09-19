/// Random Fuga : les 3 500 positions doivent être identiques à celles
/// produites par `rf_build_board` en Python.
library;

import 'dart:convert';
import 'dart:io';

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/engine/random_fuga.dart';
import 'package:test/test.dart';

void main() {
  group('Codes', () {
    test('analyse les codes valides', () {
      final c = parseRandomFugaCode('.03-09')!;
      expect(c.symbol, '.');
      expect(c.position, 3);
      expect(c.disposition, 9);
      expect(c.isRotation, isTrue);

      final d = parseRandomFugaCode('/18-54')!;
      expect(d.symbol, '/');
      expect(d.position, 18);
      expect(d.disposition, 54);
      expect(d.isRotation, isFalse);
    });

    test('rejette les codes invalides', () {
      expect(parseRandomFugaCode(''), isNull);
      expect(parseRandomFugaCode('x03-09'), isNull, reason: 'symbole inconnu');
      expect(parseRandomFugaCode('.00-09'), isNull, reason: 'position 0');
      expect(parseRandomFugaCode('.26-09'), isNull, reason: 'position > 25');
      expect(parseRandomFugaCode('.03-00'), isNull, reason: 'disposition 0');
      expect(parseRandomFugaCode('.03-71'), isNull, reason: 'disposition > 70');
      expect(parseRandomFugaCode('.0309'), isNull, reason: 'tiret manquant');
    });

    test('il y a bien 70 combinaisons de 4 Gardes parmi 8', () {
      expect(kRfCombos.length, 70);
      expect(kRfCombos.first, [0, 1, 2, 3]);
      expect(kRfCombos.last, [4, 5, 6, 7]);
    });

    test('randomFugaCode produit toujours un code analysable', () {
      for (var i = 0; i < 200; i++) {
        final code = randomFugaCode();
        expect(parseRandomFugaCode(code), isNotNull, reason: code);
      }
    });
  });

  group('Construction du plateau — fidélité au moteur Python', () {
    test('les 3 500 positions correspondent', () {
      final f = File('test/fixtures/random_fuga.json');
      final expected =
          (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)
              .cast<String, String>();
      expect(expected.length, 3500);

      for (final entry in expected.entries) {
        final board = buildRandomFugaBoard(entry.key);
        expect(board, isNotNull, reason: entry.key);
        expect(board!.key, entry.value, reason: 'code ${entry.key}');
      }
    });

    test('toutes les positions ont le matériel standard', () {
      for (final code in ['.01-01', '/13-35', '.25-70', '/07-42']) {
        final b = buildRandomFugaBoard(code)!;
        final counts = <String, int>{};
        for (var c = 0; c < kCols; c++) {
          for (var r = 0; r < kRows; r++) {
            final p = b.at(c, r);
            if (p == null) continue;
            counts.update('${p.type.wire}/${p.camp.wire}', (v) => v + 1,
                ifAbsent: () => 1);
          }
        }
        for (final camp in ['Blanc', 'Noir']) {
          expect(counts['Héritier/$camp'], 1, reason: code);
          expect(counts['Chevalier/$camp'], 1, reason: code);
          expect(counts['Nurse/$camp'], 5, reason: code);
          expect(counts['Garde/$camp'], 4, reason: code);
          expect(counts['Soldat/$camp'], 4, reason: code);
        }
      }
    });

    test('un code invalide ne construit pas de plateau', () {
      expect(buildRandomFugaBoard('bidon'), isNull);
    });

    test('la rotation inverse les colonnes, la réflexion les garde', () {
      final rot = buildRandomFugaBoard('.01-01')!;
      final refl = buildRandomFugaBoard('/01-01')!;
      // Héritier blanc : position 1 → colonne ré (index 1), rangée 0.
      expect(rot.at(1, 0), Piece.blancHeritier);
      expect(refl.at(1, 0), Piece.blancHeritier);
      // Son miroir noir : colonne 6-1=5 en rotation, colonne 1 en réflexion.
      expect(rot.at(5, 7), Piece.noirHeritier, reason: 'rotation 180°');
      expect(refl.at(1, 7), Piece.noirHeritier, reason: 'réflexion');
    });
  });
}
