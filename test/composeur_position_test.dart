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
///
/// Puis : « on ne doit pas pouvoir mettre plus d'un chevalier par couleur (une
/// fois qu'un par couleur est mis, lorsque la pièce est sélectionnée, ça la
/// change de case au lieu d'en mettre aussi sur une nouvelle case). Mettre des
/// chevaliers n'est pas obligatoire par contre. Pareil pour l'héritier. […]
/// quand on swipe la couleur du sélectionneur de pièce, ça doit aussi swiper la
/// couleur de la pièce sélectionnée. Nouvelle contrainte pour la validité de la
/// position : au moins trois cases vides sur le plateau. »
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

  group('Une pièce unique par camp se DÉPLACE', () {
    /// Où se trouve cette pièce sur le plateau, et combien il y en a.
    ({List<Cell> ou, int combien}) cherche(WidgetTester tester, Piece p) {
      final b = vue(tester).board;
      final trouve = <Cell>[];
      for (var c = 0; c < kCols; c++) {
        for (var r = 0; r < kRows; r++) {
          if (b.at(c, r) == p) trouve.add(Cell(c, r));
        }
      }
      return (ou: trouve, combien: trouve.length);
    }

    testWidgets('l Héritier : le second clic le change de case', (
      tester,
    ) async {
      await ouvrir(tester);
      await choisir(tester, PieceType.heritier);
      vue(tester).onTapCell(const Cell(0, 0));
      await tester.pumpAndSettle();
      vue(tester).onTapCell(const Cell(4, 3));
      await tester.pumpAndSettle();

      final t = cherche(tester, Piece.blancHeritier);
      expect(
        t.combien,
        1,
        reason: 'deux Héritiers blancs : la position ne pourrait pas partir',
      );
      expect(t.ou.single, const Cell(4, 3), reason: 'il a suivi le doigt');
    });

    testWidgets('le Chevalier aussi', (tester) async {
      await ouvrir(tester);
      await choisir(tester, PieceType.chevalier);
      vue(tester).onTapCell(const Cell(1, 1));
      await tester.pumpAndSettle();
      vue(tester).onTapCell(const Cell(5, 6));
      await tester.pumpAndSettle();

      final t = cherche(tester, Piece.blancChevalier);
      expect(t.combien, 1, reason: 'il n existe qu un Chevalier par camp');
      expect(t.ou.single, const Cell(5, 6));
    });

    testWidgets('mais chaque camp garde LE SIEN', (tester) async {
      // Un par couleur : poser le noir ne doit pas emporter le blanc.
      await ouvrir(tester);
      await choisir(tester, PieceType.heritier);
      vue(tester).onTapCell(const Cell(0, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pumpAndSettle();
      vue(tester).onTapCell(const Cell(6, 7));
      await tester.pumpAndSettle();

      expect(cherche(tester, Piece.blancHeritier).combien, 1);
      expect(cherche(tester, Piece.noirHeritier).combien, 1);
      expect(vue(tester).board.at(0, 0), Piece.blancHeritier);
      expect(vue(tester).board.at(6, 7), Piece.noirHeritier);
    });

    testWidgets('les autres pièces, elles, se posent autant qu on veut', (
      tester,
    ) async {
      // La règle ne vaut QUE pour l Héritier et le Chevalier : dix Gardes d un
      // côté, c est permis.
      await ouvrir(tester);
      await choisir(tester, PieceType.garde);
      for (final c in [const Cell(0, 0), const Cell(1, 0), const Cell(2, 0)]) {
        vue(tester).onTapCell(c);
        await tester.pumpAndSettle();
      }
      expect(cherche(tester, Piece.blancGarde).combien, 3);
    });

    testWidgets('et on peut toujours gommer la pièce unique', (tester) async {
      // Mettre un Chevalier n est pas obligatoire : il faut donc pouvoir le
      // retirer, et non le traîner d une case à l autre pour l éternité.
      await ouvrir(tester);
      await choisir(tester, PieceType.chevalier);
      vue(tester).onTapCell(const Cell(3, 3));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pumpAndSettle();
      vue(tester).onTapCell(const Cell(3, 3));
      await tester.pumpAndSettle();
      expect(cherche(tester, Piece.blancChevalier).combien, 0);
    });
  });

  group('La bascule emporte la pièce DÉJÀ sélectionnée', () {
    testWidgets('on choisit, puis on bascule : la pièce posée est noire', (
      tester,
    ) async {
      // L ordre compte. Basculer d abord puis choisir marchait déjà ; c est
      // l inverse qui n était tenu par aucun test.
      await ouvrir(tester);
      await choisir(tester, PieceType.heritier);
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<PieceTile>(tuile(tester, PieceType.heritier).first)
            .piece
            .camp,
        Camp.noir,
        reason: 'la tuile choisie doit basculer elle aussi',
      );
      expect(
        tester
            .widget<PieceTile>(tuile(tester, PieceType.heritier).first)
            .selected,
        isTrue,
        reason: 'et rester choisie : on ne doit pas la reprendre',
      );

      vue(tester).onTapCell(const Cell(2, 2));
      await tester.pumpAndSettle();
      expect(vue(tester).board.at(2, 2), Piece.noirHeritier);
    });
  });

  group('Au moins trois cases libres', () {
    /// Un plateau plein, sauf [vides] cases, et jouable par ailleurs.
    Board presquePlein(int vides) {
      final b = Board.empty();
      for (var c = 0; c < kCols; c++) {
        for (var r = 0; r < kRows; r++) {
          b.set(c, r, r < 4 ? Piece.blancGarde : Piece.noirGarde);
        }
      }
      // Les deux Héritiers, et on vide ce qu il faut.
      b.set(0, 0, Piece.blancHeritier);
      b.set(6, 7, Piece.noirHeritier);
      var reste = vides;
      for (var c = kCols - 1; c >= 0 && reste > 0; c--) {
        for (var r = 3; r >= 0 && reste > 0; r--) {
          if (c == 0 && r == 0) continue;
          b.set(c, r, null);
          reste--;
        }
      }
      return b;
    }

    test('la règle est dans le moteur, pas seulement dans l écran', () {
      expect(kFugVidesMin, 3);
      expect(fugCasesVides(presquePlein(2)), 2);
      expect(fugRefus(presquePlein(2)), FugRefus.casesVides);
      expect(fugRefus(presquePlein(3)), isNull, reason: 'trois suffisent');
      expect(fugRefus(presquePlein(10)), isNull);
    });

    test('un plateau ENTIÈREMENT plein est refusé', () {
      expect(fugRefus(presquePlein(0)), FugRefus.casesVides);
    });

    testWidgets('le popup le dit, et donne la troisième contrainte', (
      tester,
    ) async {
      await ouvrir(tester, depart: presquePlein(2));
      await appuyer(tester, 'Valider la position');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('moins de trois cases libres'),
        findsOneWidget,
        reason: 'savoir qu on a tort sans savoir pourquoi n aide personne',
      );
      expect(find.textContaining('trois cases libres'), findsWidgets);
      expect(
        find.byType(PositionComposerScreen),
        findsOneWidget,
        reason: 'on reste dans le composeur pour corriger',
      );
    });
  });
}
