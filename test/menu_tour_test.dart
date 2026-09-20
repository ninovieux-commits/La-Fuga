/// Visite guidée du menu : la dernière étape du tuto.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/tuto.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/screens/tuto_screen.dart';
import 'package:lafuga/ui/widgets/menu_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Ouvre le menu et lance sa visite guidée, comme le fait la dernière
  /// touche du tuto.
  Future<void> startTour(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
    await tester.pumpAndSettle();
    // On ne l'attend pas : la visite fait défiler le menu, et cette
    // animation n'avance que si le test pompe des images.
    unawaited(
      tester.state<MenuScreenState>(find.byType(MenuScreen)).startMenuTour(),
    );
    await tester.pumpAndSettle();
  }

  group('Étapes', () {
    test('les neuf étapes de Kivy sont là, dans l ordre', () {
      final stops = loadMenuTour();

      expect(stops, hasLength(9));
      expect(stops.first.targets, ['cad']);
      expect(stops.first.text, contains('CADENCE'));
      expect(stops[1].targets, ['local', 'online']);
      expect(stops.last.targets, isEmpty, reason: 'le mot de la fin');
      expect(stops.last.text, contains('Bonne fugue'));
    });

    test('chaque cible est un élément connu du menu', () {
      const known = {
        'cad',
        'local',
        'online',
        'ai',
        'search',
        'fav',
        'corr',
        'compte',
        'random',
        'plus',
      };
      for (final stop in loadMenuTour()) {
        for (final target in stop.targets) {
          expect(known, contains(target), reason: target);
        }
      }
    });
  });

  testWidgets('la visite commence par la cadence, par-dessus le menu', (
    tester,
  ) async {
    await startTour(tester);

    expect(find.byType(MenuScreen), findsOneWidget, reason: 'le vrai menu');
    expect(find.byType(MenuTourOverlay), findsOneWidget);
    expect(find.textContaining('CADENCE'), findsOneWidget);
    expect(find.text('Continuer >'), findsOneWidget);
  });

  testWidgets('on avance d étape en étape, et la dernière referme', (
    tester,
  ) async {
    await startTour(tester);

    for (var i = 0; i < 8; i++) {
      await tapVisible(tester, find.text('Continuer >'));
    }
    expect(find.textContaining('Bonne fugue'), findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);

    await tapVisible(tester, find.text('Fermer'));

    expect(find.byType(MenuTourOverlay), findsNothing);
    expect(find.byType(MenuScreen), findsOneWidget);
  });

  testWidgets('reculer depuis la première étape rouvre le tuto', (
    tester,
  ) async {
    await startTour(tester);

    await tapVisible(tester, find.text('< Précédent'));

    expect(find.byType(TutoScreen), findsOneWidget);
    expect(find.byType(MenuTourOverlay), findsNothing);
  });

  testWidgets('la dernière touche du tuto demande la visite', (tester) async {
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => TutoScreen(
                    // Directement à la dernière étape.
                    controller: TutoController()..goTo(21),
                  ),
                ),
              );
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );

    await tapVisible(tester, find.text('ouvrir'));
    expect(find.text('Le menu >'), findsOneWidget);

    await tapVisible(tester, find.text('Le menu >'));

    expect(result, isTrue, reason: 'le menu saura qu il doit se faire visiter');
  });
}
