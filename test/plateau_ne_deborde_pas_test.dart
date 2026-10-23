/// Le plateau ne peint plus par-dessus les bandeaux.
///
/// Nino : « rétrécis très légèrement les bandeaux pour que le plateau ne
/// déborde plus dessus. »
///
/// Un plateau dessine DIX rangées de haut — les huit jouables et les deux
/// zones de ralliement — pour sept de large : sa hauteur vaut 10/7 de la
/// largeur, et il est centré dans la place qu'on lui réserve. Quand cette
/// place est plus courte, il dépasse des deux côtés et vient peindre sur les
/// bandeaux. Les parts fixes (12 + 66 + 12) ne peuvent pas convenir à toutes
/// les formes d'écran : plus un téléphone est étroit, plus son plateau est
/// haut.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/game_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Monte la mise en page sur un écran donné et rend la HAUTEUR réservée
  /// au plateau.
  Future<double> hauteurPlateau(WidgetTester tester, Size ecran) async {
    setScaleSize(ecran);
    addTearDown(resetScale);
    tester.view.physicalSize = ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GameLayout(
            topBar: SizedBox.shrink(),
            topPanel: ColoredBox(color: Colors.red),
            board: SizedBox.expand(key: Key('plateau')),
            bottomPanel: ColoredBox(color: Colors.blue),
            moveStrip: SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byKey(const Key('plateau'))).height;
  }

  testWidgets('sur un téléphone, le plateau tient dans sa place', (
    tester,
  ) async {
    const largeur = 393.0;
    final h = await hauteurPlateau(tester, const Size(largeur, 851));
    expect(
      h,
      greaterThanOrEqualTo(largeur * kExtRows / kCols - 0.5),
      reason: 'ce qui manque au plateau, les bandeaux le cèdent',
    );
  });

  testWidgets('les bandeaux ne cèdent QUE ce qu il faut', (tester) async {
    // Un écran très haut n'a aucun débordement : les bandeaux gardent leurs
    // douze parts, et le plateau ne prend pas la place pour autant.
    final h = await hauteurPlateau(tester, const Size(393, 1400));
    const bandeau = 1400 * kPartsBandeauJoueur / kPartsEcran;
    const barre = 1400 * 7 / kPartsEcran;
    expect(
      h,
      closeTo(1400 - 2 * barre - 2 * bandeau, 0.5),
      reason: 'rien à céder, rien de cédé',
    );
  });

  testWidgets('sur une tablette, les bandeaux gardent leur hauteur', (
    tester,
  ) async {
    // Là, le plateau dépasse de bien plus que ce que les bandeaux peuvent
    // donner. Les rétrécir quand même ne réglerait rien et couperait leur
    // contenu — le « ∞ » du chrono n'y tenait plus.
    final h = await hauteurPlateau(tester, const Size(1024, 768));
    const bandeau = 768 * kPartsBandeauJoueur / kPartsEcran;
    const barre = 768 * 7 / kPartsEcran;
    expect(h, closeTo(768 - 2 * barre - 2 * bandeau, 0.5));
  });
}
