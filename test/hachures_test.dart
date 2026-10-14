/// Une touche hors service est HACHURÉE — partout dans l'application.
///
/// Nino : « j'aimerai aussi que les boutons "½" et ">" et "<" soient plutôt
/// hachurés quand inutilisables. En fait si tu pouvais appliquer ce réglage
/// partout dans l'app ça serait l'idéal. »
///
/// Chaque touche se débrouillait à sa façon : l'une pâlissait, l'autre se
/// fondait à moitié dans son panneau, la troisième gardait sa couleur. Le
/// réglage est maintenant UN seul, posé dans les trois touches de base, et
/// aucun appelant n'a à y penser.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/hachures.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  Future<void> montre(WidgetTester tester, Widget enfant) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: enfant)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Une touche ordinaire', () {
    testWidgets('sans geste, elle est hachurée', (tester) async {
      await montre(tester, const FugaButton(text: 'Défier', onPressed: null));
      expect(find.byKey(kHachuresKey), findsOneWidget);
    });

    testWidgets('avec un geste, aucune hachure', (tester) async {
      await montre(tester, FugaButton(text: 'Défier', onPressed: () {}));
      expect(find.byKey(kHachuresKey), findsNothing);
    });

    testWidgets('et les hachures ne mangent pas le toucher', (tester) async {
      // Elles sont par-dessus la touche : sans filtre, elles avaleraient le
      // doigt. Ici la touche est éteinte, donc rien ne doit se passer — mais
      // rien ne doit planter non plus.
      await montre(tester, const FugaButton(text: 'Défier', onPressed: null));
      await tester.tap(find.byType(FugaButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Le ½ du bandeau de joueur', () {
    Future<void> panneau(WidgetTester tester, {required bool actif}) => montre(
      tester,
      SizedBox(
        height: 120,
        width: 393,
        child: PlayerPanel(
          name: 'nino',
          clock: '∞',
          palette: paletteOf('original'),
          isWhite: true,
          isTurn: true,
          captures: const [],
          drawEnabled: actif,
          onDraw: () {},
        ),
      ),
    );

    testWidgets('éteint, il est hachuré', (tester) async {
      // Nino : « les boutons ½ […] plutôt hachurés quand inutilisables ».
      await panneau(tester, actif: false);
      expect(find.text('½'), findsOneWidget);
      expect(find.byKey(kHachuresKey), findsOneWidget);
    });

    testWidgets('allumé, il ne l est pas', (tester) async {
      await panneau(tester, actif: true);
      expect(find.byKey(kHachuresKey), findsNothing);
    });

    testWidgets('et il reste touchable, pour dire ce qui manque', (
      tester,
    ) async {
      // Éteint, le ½ répond quand même — par `onDrawBlocked`, qui explique.
      var explique = 0;
      await montre(
        tester,
        SizedBox(
          height: 120,
          width: 393,
          child: PlayerPanel(
            name: 'nino',
            clock: '∞',
            palette: paletteOf('original'),
            isWhite: true,
            isTurn: true,
            captures: const [],
            drawEnabled: false,
            onDraw: () {},
            onDrawBlocked: () => explique++,
          ),
        ),
      );
      await tester.tap(find.text('½'));
      await tester.pumpAndSettle();
      expect(explique, 1);
    });
  });

  group('Les flèches du bandeau des coups', () {
    Future<void> bandeau(
      WidgetTester tester, {
      required List<String> coups,
      required int? actif,
    }) => montre(
      tester,
      SizedBox(
        height: 60,
        width: 393,
        child: MoveStrip(
          moves: coups,
          activeIndex: actif,
          color: paletteOf('original').clair,
          palette: paletteOf('original'),
          onSelect: (_) {},
        ),
      ),
    );

    testWidgets('sans coup joué, les DEUX sont hachurées', (tester) async {
      await bandeau(tester, coups: const [], actif: null);
      expect(find.text('<'), findsOneWidget);
      expect(find.text('>'), findsOneWidget);
      expect(find.byKey(kHachuresKey), findsNWidgets(2));
    });

    testWidgets('au présent, seule la droite est hachurée', (tester) async {
      // On peut reculer, on ne peut pas avancer : `activeIndex` nul dit
      // qu'on est au dernier coup.
      await bandeau(tester, coups: const ['Do2-Do3', 'Do7-Do6'], actif: null);
      final droite = find.ancestor(
        of: find.text('>'),
        matching: find.byType(HorsService),
      );
      expect(tester.widget<HorsService>(droite).actif, isFalse);
      final gauche = find.ancestor(
        of: find.text('<'),
        matching: find.byType(HorsService),
      );
      expect(tester.widget<HorsService>(gauche).actif, isTrue);
      expect(find.byKey(kHachuresKey), findsOneWidget);
    });

    testWidgets('en revoyant un coup, les deux servent', (tester) async {
      await bandeau(tester, coups: const ['Do2-Do3', 'Do7-Do6'], actif: 1);
      expect(find.byKey(kHachuresKey), findsNothing);
    });
  });
}
