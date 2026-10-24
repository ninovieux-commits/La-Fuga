/// Un seul écran de réglages, le même depuis le menu et depuis une partie.
///
/// Nino : « j'aimerais que le popup réglages ingame soit le même que celui du
/// menu (avec l'accès au composeur de thème, sans perdre la partie en cours
/// quand on revient en arrière). Il n'y aurait donc plus deux popups de
/// réglages différents dans l'app mais qu'un seul. »
///
/// Kivy réduisait l'écran dès qu'on venait d'une partie : la langue et le
/// composeur en disparaissaient, parce qu'en changer aurait reconstruit
/// l'écran sous les pieds du joueur. Le portage n'a plus ce défaut —
/// `SuitLesReglages` repeint les écrans de la pile, y compris ceux du
/// dessous, sans les reconstruire.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/ai_memory.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/screens/settings_screen.dart';
import 'package:lafuga/ui/screens/theme_composer_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    tmp = Directory.systemTemp.createTempSync('lafuga_reglages');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> partie(WidgetTester tester) async {
    // Un téléphone, et pas la surface d'essai : à 800 de large les polices
    // valent le double et les popups débordent.
    setScaleSize(const Size(393, 851));
    addTearDown(resetScale);
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          // Quinze minutes : un chrono court expirerait pendant qu'on
          // promène les popups, et le verdict tomberait par-dessus.
          cadence: const Cadence(15, '15'),
          objectif: 'partie',
          archive: GameArchive(local: LocalGamesStore(directory: tmp)),
          memory: AiMemory(directory: tmp),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> appuyer(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  /// La pause, puis les réglages : le chemin du joueur en partie.
  Future<void> ouvrirLesReglages(WidgetTester tester) async {
    await appuyer(tester, find.byTooltip(T('Pause')));
    await appuyer(tester, find.widgetWithText(FugaButton, T('Réglages')));
  }

  testWidgets('depuis une partie, les réglages sont ceux du menu', (
    tester,
  ) async {
    await partie(tester);
    await ouvrirLesReglages(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      find.text(T('Langue')),
      findsOneWidget,
      reason: 'la langue était cachée en partie : il n y a plus deux écrans',
    );
    expect(
      find.widgetWithText(FugaButton, T('Composer le thème')),
      findsOneWidget,
      reason: 'Nino : « avec l accès au composeur de thème »',
    );
    expect(
      find.widgetWithText(FugaButton, T('Valider la langue')),
      findsOneWidget,
    );
  });

  testWidgets('on va composer un thème, et la partie est toujours là', (
    tester,
  ) async {
    await partie(tester);
    final avant = tester.state<State<GameScreen>>(find.byType(GameScreen));

    await ouvrirLesReglages(tester);
    await appuyer(
      tester,
      find.widgetWithText(FugaButton, T('Composer le thème')),
    );
    expect(find.byType(ThemeComposerScreen), findsOneWidget);

    // On revient : composeur, puis réglages.
    Navigator.of(tester.element(find.byType(ThemeComposerScreen))).pop();
    await tester.pumpAndSettle();
    await appuyer(tester, find.widgetWithText(FugaButton, T('Fermer')));

    expect(find.byType(GameScreen), findsOneWidget);
    expect(
      tester.state<State<GameScreen>>(find.byType(GameScreen)),
      same(avant),
      reason:
          'la partie a été reconstruite : son état, donc ses coups, sont '
          'perdus',
    );
  });
}
