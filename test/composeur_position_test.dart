/// Composer une position de départ.
///
/// Nino : « un plateau vide apparaît, en dessous du plateau une ligne
/// contenant une pièce de chaque, juste à côté un bouton pour swiper la
/// couleur […] La pièce sélectionnée le reste de manière à ce qu'on puisse en
/// mettre plusieurs d'affilée sur plusieurs cases. »
///
/// Et : « Lorsqu'un joueur crée une position qui n'est pas valide, un popup
/// doit apparaître pour le lui dire et lui donner les contraintes de validité
/// d'une position. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/fug.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/position_composer_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/piece_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  Future<void> ouvrir(WidgetTester tester, {Board? depart}) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: PositionComposerScreen(depart: depart)),
    );
    await tester.pumpAndSettle();
  }

  GameBoardView vue(WidgetTester tester) =>
      tester.widget<GameBoardView>(find.byType(GameBoardView));

  /// La tuile de la ligne qui porte ce type de pièce.
  Finder tuile(WidgetTester tester, PieceType type) =>
      find.byWidgetPredicate((w) => w is PieceTile && w.piece.type == type);

  Future<void> choisir(WidgetTester tester, PieceType type) async {
    tester.widget<PieceTile>(tuile(tester, type).first).onTap!();
    await tester.pumpAndSettle();
  }

  Future<void> appuyer(WidgetTester tester, String texte) async {
    final f = find.text(texte);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('Poser des pièces', () {
    testWidgets('on part d un plateau vide', (tester) async {
      await ouvrir(tester);
      expect(
        vue(tester).board.positionKey(Camp.blanc),
        Board.empty().positionKey(Camp.blanc),
      );
    });

    testWidgets('les pièces ont la TAILLE d une case du plateau', (
      tester,
    ) async {
      // Nino : « représentées de la même manière que sur le plateau (même
      // taille) ». Cinq pièces, la gomme, la bascule : sept éléments, autant
      // que le plateau a de colonnes. Elles s'alignent donc exactement.
      await ouvrir(tester);
      final plateau = tester.getSize(find.byType(GameBoardView));
      final uneCase = plateau.width / kCols;
      for (final type in PieceType.values) {
        expect(
          tester.getSize(tuile(tester, type).first).width,
          moreOrLessEquals(uneCase, epsilon: 1),
          reason:
              '${type.wire} ne fait pas la taille d une case : on choisit une '
              'chose et on en pose une autre',
        );
      }
    });

    testWidgets('la ligne porte une pièce de chaque', (tester) async {
      await ouvrir(tester);
      for (final type in PieceType.values) {
        expect(
          tuile(tester, type),
          findsWidgets,
          reason: '${type.wire} manque à la ligne',
        );
      }
    });

    testWidgets('la pièce choisie le RESTE : on en pose plusieurs d affilée', (
      tester,
    ) async {
      await ouvrir(tester);
      await choisir(tester, PieceType.garde);
      for (final c in [const Cell(0, 0), const Cell(1, 0), const Cell(2, 0)]) {
        vue(tester).onTapCell(c);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final b = vue(tester).board;
      for (final c in [const Cell(0, 0), const Cell(1, 0), const Cell(2, 0)]) {
        expect(
          b.at(c.col, c.row),
          Piece.blancGarde,
          reason: 'il a fallu reprendre la pièce entre deux cases',
        );
      }
    });

    testWidgets('la bascule change la couleur de la ligne', (tester) async {
      await ouvrir(tester);
      expect(
        tester
            .widget<PieceTile>(tuile(tester, PieceType.garde).first)
            .piece
            .camp,
        Camp.blanc,
      );
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PieceTile>(tuile(tester, PieceType.garde).first)
            .piece
            .camp,
        Camp.noir,
        reason: 'la ligne doit passer des pièces blanches aux noires',
      );

      await choisir(tester, PieceType.garde);
      vue(tester).onTapCell(const Cell(0, 0));
      await tester.pumpAndSettle();
      expect(vue(tester).board.at(0, 0), Piece.noirGarde);
    });

    testWidgets('la gomme vide une case', (tester) async {
      await ouvrir(tester, depart: Board.initial());
      expect(vue(tester).board.at(0, 0), isNotNull);
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pumpAndSettle();
      vue(tester).onTapCell(const Cell(0, 0));
      await tester.pumpAndSettle();
      expect(vue(tester).board.at(0, 0), isNull);
    });
  });

  group('La touche du trait', () {
    testWidgets('elle dit Blancs, puis Noirs, et porte la couleur du mot', (
      tester,
    ) async {
      await ouvrir(tester);
      expect(find.text('Trait aux'), findsOneWidget);
      expect(find.text('Blancs'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Blancs')).style?.color,
        Colors.white,
        reason: 'le mot « Blancs » s écrit en blanc',
      );

      await tester.tap(find.text('Trait aux'));
      await tester.pumpAndSettle();
      expect(find.text('Noirs'), findsOneWidget);
      expect(find.text('Blancs'), findsNothing);
      expect(
        tester.widget<Text>(find.text('Noirs')).style?.color,
        Colors.black,
        reason: 'le mot « Noirs » s écrit en noir',
      );
    });
  });

  group('Coller un code .fug', () {
    testWidgets('un code valide crée la position directement', (tester) async {
      await ouvrir(tester);
      final code = fugEcrire(Board.initial(), Camp.noir);
      await tester.enterText(find.byType(TextField), code);
      await appuyer(tester, 'Coller');
      expect(
        vue(tester).board.positionKey(Camp.blanc),
        Board.initial().positionKey(Camp.blanc),
      );
      expect(
        find.text('Noirs'),
        findsOneWidget,
        reason: 'le trait vient aussi du code',
      );
    });

    testWidgets('un code abîmé dit ce qui ne va pas, sans rien casser', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.enterText(find.byType(TextField), 'B\n--x----');
      await appuyer(tester, 'Coller');
      expect(find.textContaining('huit rangées'), findsOneWidget);
      expect(
        vue(tester).board.positionKey(Camp.blanc),
        Board.empty().positionKey(Camp.blanc),
        reason: 'un code refusé ne doit pas abîmer ce qu on avait',
      );
    });
  });

  group('Valider la position', () {
    testWidgets('une position jouable sort de l écran', (tester) async {
      await ouvrir(tester, depart: Board.initial());
      await appuyer(tester, 'Valider la position');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byType(PositionComposerScreen),
        findsNothing,
        reason: 'une position valide doit refermer le composeur',
      );
    });

    testWidgets('sans Héritier : un popup, et les deux contraintes', (
      tester,
    ) async {
      final b = Board.initial();
      // On retire l'Héritier blanc.
      for (var c = 0; c < kCols; c++) {
        for (var r = 0; r < kRows; r++) {
          final p = b.at(c, r);
          if (p != null && p.isHeir && p.camp == Camp.blanc) b.set(c, r, null);
        }
      }
      await ouvrir(tester, depart: b);
      await appuyer(tester, 'Valider la position');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Héritier'), findsWidgets);
      expect(
        find.textContaining('pièce carrée'),
        findsWidgets,
        reason: 'le popup doit DONNER les contraintes, pas seulement refuser',
      );
      expect(
        find.byType(PositionComposerScreen),
        findsOneWidget,
        reason: 'on reste dans le composeur pour corriger',
      );
    });

    testWidgets('des carrées bloquées : le popup le dit en propre', (
      tester,
    ) async {
      final b = Board.empty();
      b.set(0, 0, Piece.blancHeritier);
      b.set(2, 0, Piece.blancSoldat);
      b.set(3, 0, Piece.blancGarde);
      b.set(0, 7, Piece.noirHeritier);
      // Une seule carrée noire, sans voisine : elle est figée.
      b.set(2, 7, Piece.noirSoldat);
      await ouvrir(tester, depart: b);
      await appuyer(tester, 'Valider la position');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('aucune pièce carrée capable de bouger'),
        findsOneWidget,
      );
    });
  });
}
