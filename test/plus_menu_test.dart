/// Le volet « Plus » et le menu de l'historique, tels que Kivy les propose.
///
/// Kivy n'y met que cinq entrées : ni le lecteur `.nmc` (il est au bout de
/// l'historique) ni le composeur de thèmes (il est dans les réglages). Ce
/// test fige la liste, pour qu'aucune entrée ne s'y glisse à nouveau.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/parties_menu_screen.dart';
import 'package:lafuga/ui/screens/reader_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/volet_menu.dart';
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

  Future<void> openPlus(WidgetTester tester) async {
    await tester.pumpWidget(const FugaApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Autres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autres'));
    await tester.pumpAndSettle();
  }

  testWidgets('« Plus » propose les cinq entrées de Kivy, et rien d autre', (
    tester,
  ) async {
    await openPlus(tester);

    for (final label in const [
      'Tuto',
      'Historique',
      'Analyse',
      'Réglages',
      'Soutenir les devs',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Cinq entrées, plus le « Fermer » du volet : le menu « Autres » ne
    // s'ouvre plus en route par-dessus l'écran mais en volet posé sur le
    // menu, pour que les deux touches du bandeau restent accessibles.
    expect(
      find.descendant(
        of: find.byType(PanneauDuVolet),
        matching: find.byType(FugaButton),
      ),
      findsNWidgets(6),
    );
    expect(find.text('Lecteur nmc'), findsNothing);
    expect(find.text('Composer le thème'), findsNothing);
  });

  testWidgets("l historique mène aux deux listes et au lecteur", (
    tester,
  ) async {
    await openPlus(tester);
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();

    expect(find.byType(PartiesMenuScreen), findsOneWidget);
    expect(find.text('Historique en ligne'), findsOneWidget);
    expect(find.text('Historique en local'), findsOneWidget);
    expect(find.text('Lecteur nmc'), findsOneWidget);

    await tester.tap(find.text('Lecteur nmc'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets("sans compte, l historique en ligne invite à se connecter", (
    tester,
  ) async {
    await openPlus(tester);
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Historique en ligne'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connectez-vous à un compte'), findsOneWidget);
  });
}
