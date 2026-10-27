/// Une touche posée sur un popup se VOIT.
///
/// Nino : « comment ça les touches secondaires du popup sont gris sur gris ? »
/// Puis, la cause expliquée : « corrige ça en utilisant le gris foncé des
/// touches du bandeau fin du haut en partie. »
///
/// Le fond d'un popup est `kFugaGrey`, et c'était aussi la couleur par défaut
/// d'une touche. Une touche n'ayant ni contour ni ombre, elle n'existe à
/// l'œil que par son rectangle de couleur : peint dans la couleur du fond, il
/// ne restait que les lettres blanches, et le popup paraissait n'avoir qu'une
/// seule touche — celle qui, elle, nomme sa couleur.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/fuga_popup.dart';
import 'package:lafuga/ui/widgets/pause_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final palette = paletteOf('foret');

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

  /// Ouvre un popup et rend les couleurs de ses touches, par libellé.
  Future<Map<String, Color>> couleursDesTouches(
    WidgetTester tester,
    void Function(BuildContext context) ouvrir,
  ) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ouvrir(context),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(find.byType(FugaPopup), findsOneWidget);
    return {
      for (final b in tester.widgetList<FugaButton>(
        find.descendant(
          of: find.byType(FugaPopup),
          matching: find.byType(FugaButton),
        ),
      ))
        b.text: b.color,
    };
  }

  test('le gris des popups se distingue de leur fond', () {
    // Il valait celui des touches du bandeau du haut, et c'était la même
    // constante. Les touches des bandeaux sont passées au gris médian —
    // Nino : « utilise un gris qui est pile à mi-chemin entre le noir et le
    // blanc pour toutes les touches » — et les popups, eux, ont gardé le
    // gris foncé : c'est celui qu'on a vu à l'écran et retenu. Les deux ne
    // sont donc plus la même valeur, et ce test dit ce qui compte vraiment :
    // une touche de popup ne se confond pas avec le fond du popup.
    expect(kGrisTouche, isNot(kFugaGrey));
    expect(kGrisTouche, isNot(kFugaGrey));
  });

  testWidgets('la confirmation : « Non » se voit autant que « Oui »', (
    tester,
  ) async {
    final couleurs = await couleursDesTouches(
      tester,
      (context) =>
          confirmerFuga(context, palette: palette, titre: 'Abandonner ?'),
    );

    expect(couleurs.keys, containsAll([T('Non'), T('Oui')]));
    for (final e in couleurs.entries) {
      expect(
        e.value,
        isNot(kFugaGrey),
        reason: 'la touche « ${e.key} » serait de la couleur du fond',
      );
    }
    expect(couleurs[T('Non')], kGrisTouche);
  });

  testWidgets('la pause : aucune de ses touches ne disparaît', (tester) async {
    final couleurs = await couleursDesTouches(
      tester,
      (context) => showPauseDialog(context, palette: palette),
    );

    expect(couleurs, isNotEmpty);
    for (final e in couleurs.entries) {
      expect(
        e.value,
        isNot(kFugaGrey),
        reason: 'la touche « ${e.key} » serait de la couleur du fond',
      );
    }
    expect(couleurs[T('Continuer')] ?? kGrisTouche, kGrisTouche);
    expect(couleurs[T('Réglages')], kGrisTouche);
  });
}
