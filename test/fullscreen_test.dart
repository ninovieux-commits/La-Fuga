/// Plein écran immersif — portage d'`_enable_immersive_mode` (main.py).
///
/// C'est de la hauteur d'écran : sans lui, la barre d'état et celle de
/// navigation mangent les deux bandes de ralliement.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  /// Ce que l'application demande à Android.
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    SharedPreferences.setMockInitialValues(const {
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
  });

  test('le plein écran immersif est demandé au démarrage', () async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final mode = calls.singleWhere(
      (c) => c.method == 'SystemChrome.setEnabledSystemUIMode',
    );
    expect(mode.arguments, 'SystemUiMode.immersiveSticky');
  });

  testWidgets('il est redemandé au retour au premier plan', (tester) async {
    await tester.pumpWidget(const FugaApp());
    await tester.pumpAndSettle();
    calls.clear();

    // L'application revient d'ailleurs : Android a pu réafficher ses barres.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      calls.where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode'),
      isNotEmpty,
    );
  });
}
