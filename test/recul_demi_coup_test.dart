/// Reculer d'un DEMI-COUP, jamais de deux.
///
/// Nino : « en analyse corresp on ne peut pas forcément revenir en arrière de
/// seulement le coup noir, ça peut aussi enlever le coup blanc. »
///
/// Le bandeau n'offrait qu'une touche par TOUR, et elle menait toujours au
/// demi-coup noir : pour revenir sur le coup blanc, il fallait l'enjamber.
/// Et une touche ratée sur le plateau, en analyse, coupait la suite de la
/// partie sans rien redessiner.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Six demi-coups : trois tours complets, Blanc et Noir.
const _coups = [
  'Fa3-Sol4',
  'Fa6-Sol5',
  'Sol2-Fa3',
  '(Si7Si8)-Si6',
  'Fa2-Fa4',
  'Do7-Do6',
];

Board _apres(int n) {
  var b = Board.initial();
  for (final c in _coups.take(n)) {
    b = applyNotationLiterally(b, c).board;
  }
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(400, 800));
  });

  group('Le bandeau des coups', () {
    /// Tous les indices que le bandeau sait atteindre au doigt.
    Future<Set<int>> indicesAtteignables(WidgetTester tester) async {
      final vus = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 56,
              child: MoveStrip(
                moves: _coups,
                color: Colors.grey,
                palette: paletteOf('foret'),
                onSelect: vus.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // On appelle le rappel de CHAQUE touche : le défilement cacherait les
      // premières, et un doigt qui rate ne prouverait rien.
      for (final bouton
          in find
              .descendant(
                of: find.byType(MoveStrip),
                matching: find.byType(TextButton),
              )
              .evaluate()) {
        (bouton.widget as TextButton).onPressed!();
      }
      return vus;
    }

    testWidgets('chaque demi-coup a sa touche', (tester) async {
      expect(
        await indicesAtteignables(tester),
        {0, 1, 2, 3, 4, 5},
        reason:
            'un demi-coup qu on ne peut pas toucher est un demi-coup '
            'qu on ne peut atteindre qu en enjambant son voisin',
      );
    });
  });

  group('La flèche en arrière, en analyse', () {
    Future<void> ouvrir(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            cadence: Cadence.zen,
            aiCamp: null,
            initialBoard: Board.initial(),
            initialTurn: Camp.blanc,
            initialMoves: _coups,
            analysis: true,
            analysisFromCorr: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Combien de coups la position affichée compte-t-elle ?
    int coupsAffiches(WidgetTester tester) {
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      final clef = vue.board.positionKey(Camp.blanc);
      for (var n = 0; n <= _coups.length; n++) {
        if (_apres(n).positionKey(Camp.blanc) == clef) return n;
      }
      return -1;
    }

    testWidgets('un appui = un demi-coup, jusqu a la position de depart', (
      tester,
    ) async {
      await ouvrir(tester);
      expect(coupsAffiches(tester), _coups.length);

      final fleche = find.descendant(
        of: find.byType(MoveStrip),
        matching: find.text('<'),
      );
      // Un appui par demi-coup : on doit tous les traverser, et finir sur la
      // position de départ.
      for (var attendu = _coups.length - 1; attendu >= 0; attendu--) {
        await tester.tap(fleche);
        await tester.pumpAndSettle();
        expect(
          coupsAffiches(tester),
          attendu,
          reason: 'la flèche a sauté un demi-coup',
        );
      }
    });

    testWidgets('un doigt qui rate n efface rien', (tester) async {
      await ouvrir(tester);
      final fleche = find.descendant(
        of: find.byType(MoveStrip),
        matching: find.text('<'),
      );
      await tester.tap(fleche);
      await tester.pumpAndSettle();

      // Cinq demi-coups joués : c'est aux NOIRS. On touche une pièce
      // BLANCHE, qui ne peut rien faire. Le geste ne doit rien produire —
      // et rien effacer.
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      Cell? mauvaise;
      for (var r = 1; r <= 8 && mauvaise == null; r++) {
        for (var c = 1; c <= 8 && mauvaise == null; c++) {
          final p = vue.board.at(c, r);
          if (p != null && p.camp == Camp.blanc) mauvaise = Cell(c, r);
        }
      }
      expect(mauvaise, isNotNull);
      vue.onTapCell(mauvaise!);
      await tester.pumpAndSettle();

      // On FORCE un redessin avant de regarder : le vice était silencieux —
      // la partie était coupée dans le contrôleur, mais l'écran continuait
      // d'afficher l'ancien bandeau. Lire le widget tel quel ne prouvait
      // rien.
      tester.widget<GameTopBar>(find.byType(GameTopBar)).onFlip();
      await tester.pumpAndSettle();

      final bandeau = tester.widget<MoveStrip>(find.byType(MoveStrip));
      expect(
        bandeau.moves,
        _coups,
        reason: 'une touche sans effet a coupé la suite de la partie',
      );
      expect(
        coupsAffiches(tester),
        _coups.length - 1,
        reason: 'on ne regarde plus la position qu on regardait',
      );
    });

    testWidgets('revenir sur le seul coup blanc, puis y jouer autre chose', (
      tester,
    ) async {
      await ouvrir(tester);
      // Le demi-coup 4 (indice 4) est un coup BLANC : c'est lui qu'on veut
      // revoir, sans toucher au coup noir qui le précède.
      tester.widget<MoveStrip>(find.byType(MoveStrip)).onSelect(4);
      await tester.pumpAndSettle();
      expect(coupsAffiches(tester), 5);

      // Les Noirs jouent ici : la variante ne doit remplacer QUE le coup noir.
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      vue.onTapCell(const Cell(2, 6));
      await tester.pump();
      vue.onTapCell(const Cell(2, 5));
      await tester.pump();
      vue.onTapCell(const Cell(2, 5));
      await tester.pumpAndSettle();

      final bandeau = tester.widget<MoveStrip>(find.byType(MoveStrip));
      expect(
        bandeau.moves.take(5).toList(),
        _coups.take(5).toList(),
        reason: 'le coup blanc a disparu avec le coup noir',
      );
    });
  });
}
