/// Écran du tuto : le plateau, le texte qui suit la phase, et le verrou de
/// « Suivant » sur les étapes interactives.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/game/tuto.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/tuto_screen.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
  });

  Future<TutoController> open(WidgetTester tester, {int step = 0}) async {
    final tuto = TutoController()..goTo(step);
    await tester.pumpWidget(MaterialApp(home: TutoScreen(controller: tuto)));
    await tester.pumpAndSettle();
    return tuto;
  }

  /// Touche une case sur le plateau affiché.
  Future<void> tapCell(WidgetTester tester, Cell cell) async {
    final view = tester.widget<GameBoardView>(find.byType(GameBoardView));
    view.onTapCell(cell);
    await tester.pumpAndSettle();
  }

  testWidgets('la première étape montre le plateau et son texte', (
    tester,
  ) async {
    await open(tester);

    expect(find.byType(GameBoardView), findsOneWidget);
    expect(find.text('1 / 21'), findsOneWidget);
    expect(find.textContaining('Bienvenue'), findsOneWidget);
    expect(find.text('Suivant >'), findsOneWidget);
  });

  testWidgets('Précédent est fermé sur la première étape', (tester) async {
    await open(tester);
    final prev = tester.widget<FugaButton>(
      find.ancestor(
        of: find.text('< Précédent'),
        matching: find.byType(FugaButton),
      ),
    );
    expect(prev.onPressed, isNull);
  });

  testWidgets('Suivant reste bloqué tant que le coup n est pas joué', (
    tester,
  ) async {
    final tuto = await open(tester, step: 1);

    FugaButton next() => tester.widget<FugaButton>(
      find.ancestor(
        of: find.text('Suivant >'),
        matching: find.byType(FugaButton),
      ),
    );
    expect(next().onPressed, isNull, reason: 'étape interactive non faite');

    await tapCell(tester, tuto.step.move!);
    await tapCell(tester, tuto.step.dests.first);
    await tapCell(tester, tuto.step.dests.first);

    expect(next().onPressed, isNotNull);
  });

  testWidgets('le texte suit la phase', (tester) async {
    final tuto = await open(tester, step: 1);

    expect(find.textContaining('sélectionner'), findsOneWidget);

    await tapCell(tester, tuto.step.move!);
    expect(find.textContaining("d'une case"), findsOneWidget);

    await tapCell(tester, tuto.step.dests.first);
    expect(find.textContaining('valider'), findsOneWidget);
  });

  testWidgets('la pause est LA MÊME touche qu en partie', (tester) async {
    // Nino : « dans le tuto, la touche pause doit être la même qu'en
    // partie. » C'était une large touche grise portant le mot « Pause ».
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setScaleSize(const Size(393, 851));

    await open(tester);
    expect(
      find.text(T('Pause')),
      findsNothing,
      reason: 'plus de touche écrite : c est le carré aux deux barres',
    );
    expect(find.byType(ToucheDePause), findsOneWidget);
    final auTuto = tester.getRect(find.byType(ToucheDePause));
    expect(
      auTuto.width,
      moreOrLessEquals(auTuto.height, epsilon: 0.5),
      reason: 'carrée, comme en partie',
    );

    // Et la même, à la même place, que sur un écran de jeu.
    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(aiCamp: null, initialFlipped: false)),
    );
    await tester.pumpAndSettle();
    final enPartie = tester.getRect(find.byType(ToucheDePause));

    expect(
      auTuto.size.width,
      moreOrLessEquals(enPartie.size.width, epsilon: 1),
    );
    expect(
      auTuto.size.height,
      moreOrLessEquals(enPartie.size.height, epsilon: 1),
    );
    expect(
      auTuto.center.dy,
      moreOrLessEquals(enPartie.center.dy, epsilon: 1),
      reason: 'sur la même ligne : la rangée a l épaisseur d un bandeau fin',
    );
  });

  testWidgets('la bannière remplace le plateau', (tester) async {
    final steps = loadTutoSteps();
    final i = steps.indexWhere((s) => s.banner != null);
    await open(tester, step: i);

    expect(find.byType(GameBoardView), findsNothing);
    expect(find.textContaining('FIN DE PARTIE'), findsOneWidget);
  });

  testWidgets('les pièces glissent, elles ne se téléportent pas', (
    tester,
  ) async {
    final tuto = await open(tester, step: 1);
    GameBoardView board() =>
        tester.widget<GameBoardView>(find.byType(GameBoardView));

    expect(board().slides, isEmpty, reason: 'rien n a encore bougé');
    final jetonDepart = board().slideToken;

    final depart = tuto.step.move!;
    await tapCell(tester, depart);
    expect(
      board().slideToken,
      jetonDepart,
      reason: 'une sélection ne fait rien glisser',
    );

    final arrivee = tuto.step.dests.first;
    await tapCell(tester, arrivee);
    expect(board().slideToken, greaterThan(jetonDepart));
    expect(board().slides.map((g) => (g.$2, g.$3)), [(depart, arrivee)]);
    expect(
      board().slideDuration,
      greaterThan(Duration.zero),
      reason: 'la durée vient des réglages, comme en partie',
    );
  });

  testWidgets('l Héritier qui fugue glisse jusqu à son ralliement', (
    tester,
  ) async {
    final steps = loadTutoSteps();
    final i = steps.indexWhere((s) => s.title == 'Fuguer en sautant');
    final tuto = await open(tester, step: i);
    GameBoardView board() =>
        tester.widget<GameBoardView>(find.byType(GameBoardView));

    await tapCell(tester, tuto.step.move!);
    for (final saut in tuto.step.sequence) {
      await tapCell(tester, saut.dest);
    }

    final sortie = tuto.fugued.single;
    expect(
      board().fuguedHeirs,
      {sortie.camp: sortie.cell},
      reason: 'c est le plateau qui le pose, avec les pièces du thème',
    );
    expect(board().slides.single.$3, sortie.cell);
  });

  testWidgets('la dernière étape renvoie au menu', (tester) async {
    await open(tester, step: loadTutoSteps().length - 1);
    expect(find.text('Le menu >'), findsOneWidget);
  });
}
