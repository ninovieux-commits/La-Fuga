/// Les bandeaux de joueur vont d'un bord à l'autre, sans coins arrondis.
///
/// Nino : « en partie, les angles des bandeaux ne doivent plus être
/// arrondis, ils doivent aller jusqu'aux bords de l'écran comme les bandeaux
/// fins le font. » Les quatre coins laissaient voir le fond, et le bandeau
/// flottait au-dessus de la page au lieu de la barrer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const largeur = 393.0;
  final palette = paletteOf('foret');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
  });

  Future<void> pose(WidgetTester tester) async {
    tester.view.physicalSize = const Size(largeur, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setScaleSize(const Size(largeur, 851));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // L'épaisseur que `GameLayout` lui donne : 12 parts sur 104.
            height: 851 * 12 / 104,
            child: PlayerPanel(
              name: 'nino',
              clock: '15:00',
              palette: palette,
              isWhite: true,
              isTurn: true,
              captures: const [Piece.noirSoldat],
              onMessageRapide: () {},
              onResign: () {},
              onDraw: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Le fond du bandeau : le seul à porter la couleur de menu du thème.
  Finder leFond() => find.byWidgetPredicate(
    (w) =>
        w is Container &&
        (w.color == palette.menu ||
            (w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color == palette.menu)),
  );

  testWidgets('aucun coin arrondi', (tester) async {
    await pose(tester);
    expect(leFond(), findsOneWidget);

    final fond = tester.widget<Container>(leFond());
    final decor = fond.decoration;
    if (decor is BoxDecoration) {
      expect(
        decor.borderRadius,
        isNull,
        reason: 'le bandeau se coupe net, comme les bandeaux fins',
      );
    }
  });

  testWidgets('il va d un bord à l autre', (tester) async {
    await pose(tester);
    final place = tester.getRect(leFond());

    expect(place.left, 0);
    expect(place.right, largeur);
  });
}
