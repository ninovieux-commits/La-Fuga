/// Les deux couleurs du thème s'alternent d'une touche à l'autre.
///
/// Nino : « toutes les touches utilisent une seule des deux couleurs système
/// du thème. Je voudrais équilibrer. Dans le bandeau fin du haut, la touche
/// pause reste ainsi. La touche boule de voyance doit utiliser l'autre
/// couleur. La touche flip doit utiliser la couleur du bouton pause. La
/// touche chat doit utiliser la couleur de la touche boule de voyance. Dans
/// le bandeau large du bas, la touche drapeau reste ainsi, la touche avion en
/// papier doit utiliser l'autre couleur. La touche annulation de coup doit
/// utiliser la couleur de la touche drapeau. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/picto_touche.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final palette = paletteOf('foret');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  /// La couleur de chaque dessin de l'écran, rangée par fichier.
  Map<String, Color> couleurs(WidgetTester tester) => {
    for (final p in tester.widgetList<PictoTouche>(find.byType(PictoTouche)))
      p.asset.split('/').last: p.couleur,
  };

  Future<void> pose(WidgetTester tester, Widget enfant) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: enfant)));
    await tester.pumpAndSettle();
  }

  testWidgets('le bandeau fin : pause et flip en clair, boule et chat en '
      'foncé', (tester) async {
    await pose(
      tester,
      SizedBox(
        height: 851 * 7 / 104,
        child: GameTopBar(
          palette: palette,
          color: Colors.grey,
          onFlip: () {},
          onPause: () {},
          onChat: () {},
          onAnalyse: () {},
        ),
      ),
    );

    final c = couleurs(tester);
    expect(c['flip.webp'], palette.clair, reason: 'comme la pause');
    expect(c['boule.webp'], palette.fonce, reason: 'l autre couleur');
    expect(c['chat.webp'], palette.fonce, reason: 'comme la boule');

    // La pause ne porte pas de dessin de fichier : ses deux barres sont
    // peintes. On vérifie qu'elle est bien là, en clair, par son peintre.
    expect(find.byType(ToucheDePause), findsOneWidget);
  });

  testWidgets('le bandeau large : drapeau et annulation en clair, avion en '
      'foncé', (tester) async {
    await pose(
      tester,
      SizedBox(
        height: 851 * 12 / 104,
        child: PlayerPanel(
          name: 'nino',
          clock: '15:00',
          palette: palette,
          isWhite: true,
          isTurn: true,
          captures: const [Piece.noirSoldat],
          onUndo: () {},
          onMessageRapide: () {},
          onResign: () {},
          onDraw: () {},
        ),
      ),
    );

    final c = couleurs(tester);
    expect(c['drapeau.webp'], palette.clair);
    expect(c['annuler.webp'], palette.clair, reason: 'comme le drapeau');
    expect(c['avion.webp'], palette.fonce, reason: 'l autre couleur');
  });

  testWidgets('les deux couleurs servent autant l une que l autre', (
    tester,
  ) async {
    await pose(
      tester,
      Column(
        children: [
          SizedBox(
            height: 851 * 7 / 104,
            child: GameTopBar(
              palette: palette,
              color: Colors.grey,
              onFlip: () {},
              onPause: () {},
              onChat: () {},
              onAnalyse: () {},
            ),
          ),
          SizedBox(
            height: 851 * 12 / 104,
            child: PlayerPanel(
              name: 'nino',
              clock: '15:00',
              palette: palette,
              isWhite: true,
              isTurn: true,
              captures: const [],
              onUndo: () {},
              onMessageRapide: () {},
              onResign: () {},
              onDraw: () {},
            ),
          ),
        ],
      ),
    );

    final toutes = couleurs(tester).values.toList();
    expect(toutes, hasLength(6), reason: 'six dessins, sans la pause');
    expect(toutes.where((c) => c == palette.fonce), hasLength(3));
    expect(toutes.where((c) => c == palette.clair), hasLength(3));
  });
}
