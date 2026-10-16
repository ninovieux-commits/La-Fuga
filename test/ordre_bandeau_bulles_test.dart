/// Qui passe devant, du bandeau ou des bulles.
///
/// Nino : « la proposition de nulle doit passer devant la bulle de texte
/// ingame et pas l'inverse. »
///
/// Les deux occupent la MÊME bande — celle de l'adversaire — et ce fichier
/// mesure lequel reçoit le doigt, parce que dans une pile Flutter c'est le
/// dernier dessiné qui est devant, et que l'ordre d'une liste ne se relit pas
/// d'un coup d'œil.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/game_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => setScaleSize(const Size(393, 851)));
  tearDown(resetScale);

  /// Monte la bande avec deux calques qui prennent toute la place, et rend
  /// le nom de celui qui a reçu l'appui.
  Future<String> quiRecoitLAppui(
    WidgetTester tester, {
    required bool topPanelDevant,
  }) async {
    var touche = 'personne';
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget calque(String nom, Color couleur) => GestureDetector(
      key: ValueKey(nom),
      behavior: HitTestBehavior.opaque,
      onTap: () => touche = nom,
      child: ColoredBox(color: couleur),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameLayout(
            topBar: const SizedBox.shrink(),
            topPanel: calque('bandeau', Colors.blue),
            topOverlay: calque('bulles', Colors.orange),
            topPanelDevant: topPanelDevant,
            board: const SizedBox.shrink(),
            bottomPanel: const SizedBox.shrink(),
            moveStrip: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Au milieu de la bande : les deux calques occupent exactement la même
    // place, donc le même centre. C'est la pile qui décide lequel répond.
    final centre = tester.getCenter(find.byKey(const ValueKey('bandeau')));
    expect(
      centre,
      tester.getCenter(find.byKey(const ValueKey('bulles'))),
      reason: 'les deux calques doivent se superposer, sinon on ne mesure rien',
    );
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    return touche;
  }

  testWidgets('par défaut, les bulles sont devant le bandeau', (tester) async {
    expect(
      await quiRecoitLAppui(tester, topPanelDevant: false),
      'bulles',
      reason: 'un message doit se lire sans quitter le plateau des yeux',
    );
  });

  testWidgets('le bandeau passe devant quand on le demande', (tester) async {
    expect(
      await quiRecoitLAppui(tester, topPanelDevant: true),
      'bandeau',
      reason: 'une question à répondre ne se laisse pas recouvrir',
    );
  });
}
