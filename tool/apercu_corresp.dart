/// Aperçu des aperçus de correspondance : le cadre qui s'allume, désormais
/// épais comme la barre de séparation, et blanc en système deepgrey.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_corresp.dart` écrit des PNG dans `tool/apercus/`.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey _cadre = GlobalKey();

CorrGame _partie({required bool aMoi, required String adversaire}) =>
    CorrGame.fromJson({
      'id': adversaire,
      'statut': 'en_cours',
      'ma_couleur': 'Blanc',
      'adversaire': adversaire,
      'adversaire_melo': 1500,
      'mon_score': 28,
      'score_adverse': 4,
      'turn': aMoi ? 'Blanc' : 'Noir',
      'moves_text': '1.Do2-Do3/Do7-Do6 2.Ré2-Ré4/La7-Fa5',
      'my_turn': aMoi,
    });

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (nom, theme) in [
    ('corresp', 'original'),
    ('corresp_deepgrey', 'deepgrey'),
  ]) {
    testWidgets('aperçu des $nom', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
        'theme': theme,
      });
      await Settings.load();
      await Translations.load('fr');
      resetScale();
      setScaleSize(const Size(393, 851));
      tester.view.physicalSize = const Size(393, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        final police = FontLoader('NotoSansCJK')
          ..addFont(
            File(
              'assets/fonts/NotoSansCJKsc-Regular.otf',
            ).readAsBytes().then((o) => ByteData.view(o.buffer)),
          );
        await police.load();
      });

      final palette = paletteOf(theme);
      final axes = Settings.instance.themeAxes;

      Widget case_(CorrGame? g) => CorrSlot(
        game: g,
        palette: palette,
        boardTheme: axes.board,
        pieceTheme: axes.pieces,
        onTap: () {},
        onAccept: (_) {},
        onRefuse: (_) {},
        onCancel: (_) {},
        onRematch: (_) {},
        onClose: (_) {},
        onShow: (_) {},
        onShowChallenge: (_) {},
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansCJK'),
          home: ColoredBox(
            color: paletteOf(axes.menu).menu,
            child: RepaintBoundary(
              key: _cadre,
              child: Padding(
                padding: EdgeInsets.all(S(10)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // La barre de séparation, allumée : c'est elle qui donne
                    // son épaisseur au cadre des plateaux.
                    FractionallySizedBox(
                      widthFactor: 0.62,
                      child: Container(
                        height: S(kEpaisseurDuVoyant),
                        decoration: BoxDecoration(
                          color: couleurAllumee(palette),
                          borderRadius: BorderRadius.circular(
                            S(kEpaisseurDuVoyant / 2),
                          ),
                          border: const Border.fromBorderSide(kTraitDeTouche),
                        ),
                      ),
                    ),
                    SizedBox(height: S(14)),
                    Row(
                      children: [
                        Expanded(
                          child: case_(
                            _partie(aMoi: true, adversaire: 'mesange'),
                          ),
                        ),
                        SizedBox(width: S(14)),
                        Expanded(
                          child: case_(
                            _partie(aMoi: false, adversaire: 'celia'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      Directory('tool/apercus').createSync(recursive: true);
      final limite =
          _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final octets = await tester.runAsync(() async {
        final image = await limite.toImage(pixelRatio: 3);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(
        'tool/apercus/$nom.png',
      ).writeAsBytesSync(Uint8List.view(octets!.buffer));
    });
  }
}
