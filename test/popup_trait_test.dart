/// Le trait noir fait le tour de CHAQUE popup.
///
/// Nino : « pour chaque popup je veux le trait noir qui fait le tour du popup
/// stp. » Il est posé dans le thème de l'application, et non sur les
/// vingt-neuf boîtes de dialogue une par une : celles qu'on écrira demain
/// l'auront aussi, et aucune ne peut l'oublier. Ce test tient cette promesse
/// — il ouvre une boîte ORDINAIRE, sans rien lui demander de particulier.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/fuga_popup.dart';
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
  });

  /// Le côté du cadre que porte la forme d'un popup.
  BorderSide? traitDe(ShapeBorder? forme) =>
      forme is RoundedRectangleBorder ? forme.side : null;

  testWidgets('une boîte ordinaire le porte, sans rien demander', (
    tester,
  ) async {
    await tester.pumpWidget(const FugaApp());
    await tester.pumpAndSettle();

    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(Scaffold).first),
        builder: (context) => const AlertDialog(
          backgroundColor: kFugaGrey,
          title: Text('Pause'),
          content: Text('Une boîte de dialogue ordinaire.'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boite = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final theme = Theme.of(tester.element(find.byType(AlertDialog)));
    final forme = boite.shape ?? theme.dialogTheme.shape;
    expect(
      traitDe(forme)?.color,
      const Color(0xFF000000),
      reason: 'le popup n a pas le trait noir',
    );
    expect(traitDe(forme)?.width, kTraitDeTouche.width);
  });

  testWidgets('le popup maison aussi, qui impose sa forme', (tester) async {
    // `FugaPopup` fixe sa propre forme : il ne la prend donc pas du thème, et
    // c'est pour ça qu'il faut l'y remettre à la main.
    await tester.pumpWidget(const FugaApp());
    await tester.pumpAndSettle();

    unawaited(
      showFugaPopup<void>(
        tester.element(find.byType(Scaffold).first),
        widthFactor: 0.8,
        heightFactor: 0.4,
        rows: const [],
        title: 'Plus',
      ),
    );
    await tester.pumpAndSettle();

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(traitDe(dialog.shape)?.color, const Color(0xFF000000));
    expect(traitDe(dialog.shape)?.width, kTraitDeTouche.width);
  });
}
