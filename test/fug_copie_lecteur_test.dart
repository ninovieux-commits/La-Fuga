/// Copier une position, et la relire.
///
/// Nino : « Quand on est en mode analyse ou dans l'historique, on doit pouvoir
/// copier la position affichée sous forme de texte fug, et on doit ajouter une
/// touche "lecteur fug" en dessous de la touche "lecteur nmc" dans la page de
/// sélection d'historique personnel. Le lecteur doit proposer la même chose
/// que le lecteur nmc (continuer contre deepgrey etc). »
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/fug.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/fug_reader_screen.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/screens/parties_menu_screen.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Ce que l'application a mis dans le presse-papier.
  late List<String> presse;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    presse = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            presse.add((call.arguments as Map)['text'] as String);
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': presse.isEmpty ? '' : presse.last};
          }
          return null;
        });
  });
  tearDown(resetScale);

  Future<void> appuyer(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('Copier la position affichée', () {
    testWidgets('en analyse, la touche « Position » la met au presse-papier', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            cadence: Cadence.zen,
            aiCamp: null,
            initialBoard: Board.initial(),
            initialTurn: Camp.blanc,
            analysis: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final barre = tester.widget<GameTopBar>(find.byType(GameTopBar));
      expect(
        barre.onCopyFug,
        isNotNull,
        reason: 'on doit pouvoir copier la position en analyse',
      );

      // On joue un coup AVANT de copier : à la position de départ, « la
      // position affichée » et « celle du départ » sont la même chose, et le
      // test ne prouverait rien.
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      vue.onTapCell(const Cell(2, 1));
      await tester.pump();
      vue.onTapCell(const Cell(2, 2));
      await tester.pump();
      vue.onTapCell(const Cell(2, 2));
      await tester.pumpAndSettle();
      final affichee = tester
          .widget<GameBoardView>(find.byType(GameBoardView))
          .board;
      expect(
        affichee.positionKey(Camp.blanc),
        isNot(Board.initial().positionKey(Camp.blanc)),
        reason: 'le coup n a pas été joué : le test ne distinguerait rien',
      );

      await appuyer(tester, find.text('Position'));

      expect(presse.length, 1);
      final lu = fugLire(presse.single);
      expect(lu.erreur, isNull, reason: 'la copie doit être relisible');
      expect(
        lu.position!.board.positionKey(Camp.blanc),
        affichee.positionKey(Camp.blanc),
        reason: 'ce n est pas la position AFFICHÉE qui a été copiée',
      );
      expect(
        lu.position!.turn,
        Camp.noir,
        reason: 'le trait aussi est celui de la position affichée',
      );
    });

    testWidgets('hors analyse, la touche n est pas là', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GameScreen(cadence: Cadence.zen, aiCamp: Camp.noir),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<GameTopBar>(find.byType(GameTopBar)).onCopyFug,
        isNull,
        reason: 'en pleine partie, rien à copier',
      );
    });

    testWidgets('dans l historique, « Copier » propose la partie ET la '
        'position', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReplayScreen(
            nmc: '[Date "2026-09-27"]\n[Blanc "nino"]\n\n1.Do2-Do3/Do7-Do6',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await appuyer(tester, find.text('Copier'));

      expect(find.text('La partie (.nmc)'), findsOneWidget);
      expect(find.text('La position (.fug)'), findsOneWidget);
      await appuyer(tester, find.text('La position (.fug)'));

      expect(presse.length, 1);
      final lu = fugLire(presse.single);
      expect(lu.erreur, isNull, reason: 'la copie doit être relisible');
      expect(
        lu.position!.board.positionKey(Camp.blanc),
        tester
            .widget<GameBoardView>(find.byType(GameBoardView))
            .board
            .positionKey(Camp.blanc),
        reason: 'ce n est pas la position affichée qui a été copiée',
      );
    });
  });

  group('Le lecteur fug', () {
    testWidgets('sa touche est sous celle du lecteur nmc', (tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: FugaScale(child: PartiesMenuScreen(online: OnlineService())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lecteur nmc'), findsOneWidget);
      expect(find.text('Lecteur fug'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Lecteur fug')).dy,
        greaterThan(tester.getCenter(find.text('Lecteur nmc')).dy),
        reason: 'EN DESSOUS de la touche du lecteur nmc',
      );
    });

    testWidgets('une position lisible s ouvre en analyse', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FugReaderScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        fugEcrire(Board.initial(), Camp.noir),
      );
      await appuyer(tester, find.text('Lire'));

      final ecran = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(ecran.analysis, isTrue);
      expect(ecran.initialTurn, Camp.noir);
      expect(
        ecran.initialBoard!.positionKey(Camp.blanc),
        Board.initial().positionKey(Camp.blanc),
      );
      // « La même chose que le lecteur nmc » : on peut y reprendre la
      // position contre Deep Grey.
      expect(
        tester.widget<GameTopBar>(find.byType(GameTopBar)).onDeepGrey,
        isNotNull,
        reason: 'le lecteur doit mener quelque part, comme celui des parties',
      );
    });

    testWidgets('un texte abîmé dit QUOI et OÙ, sans ouvrir', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FugReaderScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'B\n-------\n--x----\n-------\n-------\n-------\n-------\n-------\n-------',
      );
      await appuyer(tester, find.text('Lire'));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Lettres acceptées'), findsOneWidget);
      expect(
        find.textContaining('Ligne 3'),
        findsOneWidget,
        reason: 'huit lignes de sept caractères : il faut dire laquelle',
      );
      expect(find.byType(GameScreen), findsNothing);
    });

    testWidgets('un collage vient du presse-papier', (tester) async {
      presse.add(fugEcrire(Board.initial(), Camp.blanc));
      await tester.pumpWidget(const MaterialApp(home: FugReaderScreen()));
      await tester.pumpAndSettle();
      await appuyer(tester, find.text('Coller'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        presse.last,
      );
    });
  });
}
