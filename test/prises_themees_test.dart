/// Les pièces MANGÉES portent le dessin du plateau, quel que soit le thème.
///
/// Nino : « les pièces mangées doivent toujours avoir le même design que sur
/// le plateau. Peu importe le thème. »
///
/// `CapturesStrip` ne recevait qu'une palette : pas d'images, pas de nom de
/// thème. Sous un thème à images — médiéval, fleurs, dragon — la même pièce
/// était donc une illustration sur le plateau et un dessin géométrique dans
/// le bandeau des prises. Le test compare les pixels, parce que l'arbre des
/// widgets ne dit rien du dessin.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/piece_painter.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:lafuga/ui/widgets/theme_image_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La bande d'essai : un seul pion, dans une boîte de taille connue.
const Size _boite = Size(100, 40);
const Piece _pion = Piece.blancSoldat;

/// Ce que le plateau fait d'une pièce : le MÊME appel, aux mêmes arguments
/// de thème. La géométrie de la bande est reprise ici à la main — c'est le
/// DESSIN qu'on mesure, pas la place.
class _CommeSurLePlateau extends CustomPainter {
  const _CommeSurLePlateau(this.palette, this.images, this.theme);

  final ThemePalette palette;
  final LoadedThemeImages? images;
  final String? theme;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(math.min(size.height - S(2), size.width), S(36));
    final top = (size.height - side) / 2;
    paintPiece(
      canvas,
      Rect.fromLTWH(0, top, side, side),
      _pion,
      palette,
      outlineWidth: S(1),
      images: images,
      theme: theme,
      rainbowFraction: rainbowFractionOf(0, 0),
    );
  }

  @override
  bool shouldRepaint(_CommeSurLePlateau old) => true;
}

/// Rend un widget dans une boîte de [_boite] et renvoie ses pixels.
Future<ByteData> _pixels(WidgetTester tester, Widget enfant) async {
  final cle = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: cle,
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: SizedBox(
                width: _boite.width,
                height: _boite.height,
                child: enfant,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  late ByteData octets;
  await tester.runAsync(() async {
    final limite =
        cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rendu = await limite.toImage();
    octets = (await rendu.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return octets;
}

/// Combien d'octets diffèrent entre deux rendus de même taille.
int _ecarts(ByteData a, ByteData b) {
  expect(a.lengthInBytes, b.lengthInBytes);
  var compte = 0;
  for (var i = 0; i < a.lengthInBytes; i++) {
    if (a.getUint8(i) != b.getUint8(i)) compte++;
  }
  return compte;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    setScaleSize(const Size(393, 851));
  });
  tearDown(() {
    resetScale();
    ThemeImageCache.clear();
  });

  testWidgets('une prise se dessine comme sur le plateau, thème à images', (
    tester,
  ) async {
    const theme = 'medieval';
    // Les images se décodent en tâche de fond : sans cette attente, la bande
    // montre son rendu de secours et le test ne mesure pas ce qu'il croit.
    await tester.runAsync(() => ThemeImageCache.load(theme));
    final images = ThemeImageCache.ready(theme);
    expect(images?.pieceFor(_pion), isNotNull, reason: 'le thème a des images');

    final palette = paletteOf(theme);
    final bande = await _pixels(
      tester,
      CapturesStrip(pieces: const [_pion], palette: palette, theme: theme),
    );
    final plateau = await _pixels(
      tester,
      CustomPaint(
        size: Size.infinite,
        painter: _CommeSurLePlateau(palette, images, theme),
      ),
    );
    expect(
      _ecarts(bande, plateau),
      0,
      reason: 'la prise doit être le dessin du plateau, pixel pour pixel',
    );

    // Et le défaut d'origine : sans le thème, ce n'était PAS le même dessin.
    final sansTheme = await _pixels(
      tester,
      CapturesStrip(pieces: const [_pion], palette: palette),
    );
    expect(
      _ecarts(bande, sansTheme),
      greaterThan(0),
      reason: 'le rendu géométrique diffère de l image du thème',
    );
  });

  testWidgets('une prise prend les couleurs de l arc-en-ciel', (tester) async {
    // L'arc-en-ciel n'a pas d'images : il colore l'accent de chaque pièce.
    // Une pièce prise n'a plus de case — son rang dans la bande en tient le
    // rôle — mais les couleurs restent celles du plateau.
    const theme = 'arcenciel';
    final palette = paletteOf(theme);
    final bande = await _pixels(
      tester,
      CapturesStrip(pieces: const [_pion], palette: palette, theme: theme),
    );
    final attendue = rainbowColor(rainbowFractionOf(0, 0));
    var trouvee = 0;
    for (var i = 0; i < bande.lengthInBytes; i += 4) {
      if (bande.getUint8(i) == (attendue.r * 255).round() &&
          bande.getUint8(i + 1) == (attendue.g * 255).round() &&
          bande.getUint8(i + 2) == (attendue.b * 255).round()) {
        trouvee++;
      }
    }
    expect(
      trouvee,
      greaterThan(20),
      reason: 'la couleur d accent doit être là',
    );
  });

  test('toute bande de prises reçoit un thème', () {
    // Trois écrans portent des prises, et il en viendra d'autres : une bande
    // qu'on oublierait de thémer retomberait en silence sur le rendu
    // géométrique — exactement le défaut qu'on vient de corriger.
    final fautes = <String>[];
    for (final fichier
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = fichier.readAsStringSync();
      for (final appel in ['CapturesStrip(', 'BandeauPrises(']) {
        var depuis = 0;
        while (true) {
          final i = source.indexOf(appel, depuis);
          if (i < 0) break;
          depuis = i + appel.length;
          // `CapturesStrip({` est la DÉCLARATION du widget, pas un appel.
          if (source.startsWith('({', depuis - 1)) continue;
          final fin = source.indexOf(');', depuis);
          final args = fin < 0 ? '' : source.substring(depuis, fin);
          if (!args.contains('theme:')) {
            fautes.add('${fichier.path} : $appel sans theme:');
          }
        }
      }
    }
    expect(fautes, isEmpty, reason: fautes.join('\n'));
  });
}
