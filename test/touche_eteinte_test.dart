/// Une touche HORS SERVICE se voit — et de la même façon partout.
///
/// Elle s'est hachurée le temps d'un essai. Nino, les hachures vues sur son
/// téléphone : « on vire tout, on remet comme c'était avant, partout. Là
/// c'est moche de fou », puis « effet pâlissant comme les autres touches ».
///
/// Le signe est donc la PÂLEUR, à une seule valeur — `kOpaciteEteinte` —,
/// posée dans la touche elle-même pour qu'aucun appelant n'ait à y penser.
/// Le ½ du bandeau de joueur garde son signe à lui, plus ancien : il se fond
/// à moitié dans son panneau, parce qu'il doit rester touchable pour dire ce
/// qui manque.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
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

  /// L'opacité appliquée autour de [quoi] — 1 si rien ne la pâlit.
  double paleurAutourDe(WidgetTester tester, Finder quoi) {
    final voiles = tester.widgetList<Opacity>(
      find.ancestor(of: quoi, matching: find.byType(Opacity)),
    );
    return voiles.isEmpty
        ? 1
        : voiles.map((o) => o.opacity).reduce((a, b) => a < b ? a : b);
  }

  group('Une touche ordinaire', () {
    testWidgets('sans geste, elle PÂLIT', (tester) async {
      await montre(tester, const FugaButton(text: 'Défier', onPressed: null));
      expect(
        paleurAutourDe(tester, find.text('Défier')),
        kOpaciteEteinte,
        reason: 'une touche éteinte doit se voir',
      );
    });

    testWidgets('avec un geste, elle est pleine', (tester) async {
      await montre(tester, FugaButton(text: 'Défier', onPressed: () {}));
      expect(paleurAutourDe(tester, find.text('Défier')), 1);
    });

    testWidgets('et la pâleur ne mange pas le toucher', (tester) async {
      // Éteinte, rien ne doit se passer — mais rien ne doit planter non plus.
      await montre(tester, const FugaButton(text: 'Défier', onPressed: null));
      await tester.tap(find.byType(FugaButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
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

    testWidgets('sans coup joué, les DEUX pâlissent', (tester) async {
      await bandeau(tester, coups: const [], actif: null);
      expect(paleurAutourDe(tester, find.text('<')), kOpaciteEteinte);
      expect(paleurAutourDe(tester, find.text('>')), kOpaciteEteinte);
    });

    testWidgets('au présent, seule la droite pâlit', (tester) async {
      // On peut reculer, on ne peut pas avancer : `activeIndex` nul dit
      // qu'on est au dernier coup.
      await bandeau(tester, coups: const ['Do2-Do3', 'Do7-Do6'], actif: null);
      expect(paleurAutourDe(tester, find.text('>')), kOpaciteEteinte);
      expect(paleurAutourDe(tester, find.text('<')), 1);
    });

    testWidgets('en revoyant un coup, les deux sont pleines', (tester) async {
      await bandeau(tester, coups: const ['Do2-Do3', 'Do7-Do6'], actif: 1);
      expect(paleurAutourDe(tester, find.text('<')), 1);
      expect(paleurAutourDe(tester, find.text('>')), 1);
    });

    testWidgets('et c est la MÊME pâleur que celle des touches', (
      tester,
    ) async {
      // Deux valeurs voisines se verraient côte à côte à l'écran. Il n'y en
      // a qu'une, et les deux endroits la lisent au même endroit.
      await bandeau(tester, coups: const [], actif: null);
      await montre(tester, const FugaButton(text: 'Défier', onPressed: null));
      expect(paleurAutourDe(tester, find.text('Défier')), kOpaciteEteinte);
    });
  });

  group('Le drapeau du bandeau de joueur', () {
    // Le ½ et le X ont quitté le bandeau : un seul drapeau les remplace, et
    // c'est son popup qui porte les deux gestes. Nino : « le bouton
    // abandonner et le bouton match nul doivent disparaître. »
    Future<void> panneau(
      WidgetTester tester, {
      required bool nulleActive,
      String? raison,
      VoidCallback? onDraw,
      VoidCallback? onResign,
    }) => montre(
      tester,
      SizedBox(
        height: 120,
        width: 393,
        child: PlayerPanel(
          name: 'nino',
          clock: '',
          palette: paletteOf('original'),
          isWhite: true,
          isTurn: true,
          captures: const [],
          drawEnabled: nulleActive,
          raisonNulle: raison,
          onDraw: onDraw ?? () {},
          onResign: onResign ?? () {},
        ),
      ),
    );

    testWidgets('le bandeau ne porte plus ni ½ ni X', (tester) async {
      await panneau(tester, nulleActive: true);
      expect(find.text('½'), findsNothing);
      expect(find.text('X'), findsNothing);
      expect(find.byType(Image), findsWidgets, reason: 'le drapeau est là');
    });

    testWidgets('il ouvre les deux gestes, et dit ce qui manque', (
      tester,
    ) async {
      await panneau(
        tester,
        nulleActive: false,
        raison: 'Jouez votre coup pour pouvoir proposer la nulle',
      );
      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();

      expect(find.text('Proposer nulle'), findsOneWidget);
      expect(find.text('Abandonner'), findsOneWidget);
      expect(
        find.text('Jouez votre coup pour pouvoir proposer la nulle'),
        findsOneWidget,
        reason: 'la raison se LIT, au lieu de se gagner en touchant un ½ mort',
      );
    });

    testWidgets('la nulle ne part qu après un oui', (tester) async {
      var propose = 0;
      await panneau(tester, nulleActive: true, onDraw: () => propose++);
      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, 'Proposer nulle'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmer la demande de nulle ?'), findsOneWidget);
      expect(propose, 0, reason: 'rien ne part avant la confirmation');
      await tester.tap(find.widgetWithText(FugaButton, 'Non'));
      await tester.pumpAndSettle();
      expect(propose, 0);

      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, 'Proposer nulle'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, 'Oui'));
      await tester.pumpAndSettle();
      expect(propose, 1);
    });

    testWidgets('l abandon non plus', (tester) async {
      var abandonne = 0;
      await panneau(tester, nulleActive: true, onResign: () => abandonne++);
      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, 'Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmer l\'abandon ?'), findsOneWidget);
      expect(abandonne, 0);
      await tester.tap(find.widgetWithText(FugaButton, 'Oui'));
      await tester.pumpAndSettle();
      expect(abandonne, 1);
    });

    testWidgets('coup non joué : la nulle est pâle et ne mène nulle part', (
      tester,
    ) async {
      var propose = 0;
      await panneau(tester, nulleActive: false, onDraw: () => propose++);
      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();
      expect(
        paleurAutourDe(tester, find.text('Proposer nulle')),
        kOpaciteEteinte,
      );
      await tester.tap(find.widgetWithText(FugaButton, 'Proposer nulle'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmer la demande de nulle ?'), findsNothing);
      expect(propose, 0);
    });
  });
}
