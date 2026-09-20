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
import 'package:lafuga/ui/widgets/fuga_button.dart';
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
    expect(find.text('1 / 22'), findsOneWidget);
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

  testWidgets('la bannière remplace le plateau', (tester) async {
    final steps = loadTutoSteps();
    final i = steps.indexWhere((s) => s.banner != null);
    await open(tester, step: i);

    expect(find.byType(GameBoardView), findsNothing);
    expect(find.textContaining('FIN DE PARTIE'), findsOneWidget);
  });

  testWidgets('la dernière étape renvoie au menu', (tester) async {
    await open(tester, step: 21);
    expect(find.text('Le menu >'), findsOneWidget);
  });
}
