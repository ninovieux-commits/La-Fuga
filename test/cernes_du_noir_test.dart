/// Ce qui prend la couleur noire prend les contours blancs.
///
/// Nino : « pense que la couleur noire doit prendre les contours blancs »,
/// puis « les écritures aussi. À chaque fois que quelque chose prend la
/// couleur noire, il doit prendre les contours blancs. »
///
/// Un contour existe pour détacher un dessin de son fond. Peint de la
/// couleur du dessin, il ne détache plus rien : c'est ce qui arrivait au
/// thème Deep Grey le jour où sa couleur 2 est devenue le noir.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/auto_play_bar.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/picto_touche.dart';
import 'package:lafuga/ui/widgets/unread_dot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Key _cadre = Key('cadre');

/// Combien de pixels franchement PLUS CLAIRS que le gris de fond, et
/// combien franchement plus sombres.
///
/// Pas « blancs » et « noirs » au sens strict : la couronne ne fait qu'un
/// demi-point de large à l'échelle d'un essai, et ses pixels sortent mêlés
/// au gris. Ce qui se mesure, c'est qu'il y a bien du clair là où il n'y
/// avait que du noir.
Future<({int blancs, int noirs})> _compte(
  WidgetTester tester,
  Widget enfant, {
  String? asset,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _cadre,
            child: ColoredBox(
              // Le gris des touches : ni blanc ni noir, pour que les deux
              // se comptent sans ambiguïté.
              color: kGrisTouche,
              child: SizedBox(width: 160, height: 60, child: enfant),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Un `Image.asset` se décode HORS de la frame : sans cette attente, le
  // dessin sort vide et le test ne compte rien.
  if (asset != null) {
    await tester.runAsync(
      () => precacheImage(
        AssetImage(asset),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pumpAndSettle();
  }

  late ByteData pixels;
  await tester.runAsync(() async {
    final limite =
        tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
    final rendu = await limite.toImage();
    pixels = (await rendu.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });

  var blancs = 0;
  var noirs = 0;
  for (var i = 0; i < pixels.lengthInBytes; i += 4) {
    final somme =
        pixels.getUint8(i) + pixels.getUint8(i + 1) + pixels.getUint8(i + 2);
    if (somme > 560) blancs++;
    if (somme < 200) noirs++;
  }
  return (blancs: blancs, noirs: noirs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  test('le noir se cerne de blanc, tout le reste de noir', () {
    expect(contourDe(const Color(0xFF000000)), const Color(0xFFFFFFFF));
    expect(contourDe(const Color(0xFFFFFFFF)), const Color(0xFF000000));
    expect(contourDe(kGrisTouche), const Color(0xFF000000));
    // Un noir ADOUCI bascule lui aussi : le seuil ne tient pas au zéro.
    expect(contourDe(const Color(0xFF191919)), const Color(0xFFFFFFFF));
  });

  test('aucun thème ne bascule, sauf la couleur 2 de Deep Grey', () {
    // La règle se lit sur la couleur et non sur le nom du thème : ce test
    // dit exactement qui elle touche, pour qu'une palette retouchée ne
    // change pas en douce l'allure d'un autre thème.
    final bascules = <String>[];
    for (final nom in kThemeOrder) {
      final p = paletteOf(nom);
      if (estNoire(p.clair)) bascules.add('$nom.clair');
      if (estNoire(p.fonce)) bascules.add('$nom.fonce');
    }
    expect(bascules, ['deepgrey.fonce']);
  });

  test('Deep Grey s allume en blanc et en noir', () {
    final p = paletteOf('deepgrey');
    expect(p.clair, const Color(0xFFFFFFFF));
    expect(p.fonce, const Color(0xFF000000));
    // Le voyant du menu et des correspondances s'allume donc en blanc sans
    // avoir besoin du repli de [couleurAllumee].
    expect(couleurAllumee(p), const Color(0xFFFFFFFF));
  });

  testWidgets('un mot noir est cerné de blanc', (tester) async {
    final noir = await _compte(
      tester,
      Center(
        child: MotTouche(
          texte: 'La Fuga',
          couleur: const Color(0xFF000000),
          style: TextStyle(fontSize: SF(16), fontWeight: FontWeight.bold),
        ),
      ),
    );
    expect(noir.noirs, greaterThan(100), reason: 'les lettres sont noires');
    expect(noir.blancs, greaterThan(50), reason: 'le contour est blanc');

    // Et le mot blanc, lui, n'a pas changé : cerné de noir, comme partout.
    final blanc = await _compte(
      tester,
      Center(
        child: MotTouche(
          texte: 'La Fuga',
          couleur: const Color(0xFFFFFFFF),
          style: TextStyle(fontSize: SF(16), fontWeight: FontWeight.bold),
        ),
      ),
    );
    expect(blanc.blancs, greaterThan(100), reason: 'les lettres sont blanches');
    expect(blanc.noirs, greaterThan(50), reason: 'le contour est noir');
  });

  testWidgets('un symbole noir est cerné de blanc', (tester) async {
    final noir = await _compte(
      tester,
      const PictoTouche(
        asset: 'assets/images/podium.webp',
        couleur: Color(0xFF000000),
      ),
      asset: 'assets/images/podium.webp',
    );
    expect(noir.noirs, greaterThan(100), reason: 'le dessin est noir');
    // La couronne ne fait qu'un point de large : à cette taille, peu de
    // pixels en sortent PLEINEMENT blancs, et c'est déjà la preuve.
    expect(noir.blancs, greaterThan(20), reason: 'sa couronne est blanche');

    // Le témoin : la même couronne, autour d'un dessin qui n'est pas noir,
    // ne pose pas un seul point blanc.
    final gris = await _compte(
      tester,
      const PictoTouche(
        asset: 'assets/images/podium.webp',
        couleur: kGrisTouche,
      ),
      asset: 'assets/images/podium.webp',
    );
    expect(gris.blancs, lessThan(5), reason: 'sa couronne reste noire');
  });

  testWidgets('les signes DESSINÉS se cernent eux aussi', (tester) async {
    // Nino, montrant le retour au début du mode lecture sous Deep Grey :
    // « pourquoi ce bouton ne prend pas le contour blanc ? » Les trois
    // signes de la lecture sont tracés à la main, hors de [PictoTouche] :
    // leur couronne était restée noire en dur.
    for (final (nom, signe) in [
      ('début', const GlypheDebut(taille: 40, couleur: Color(0xFF000000))),
      ('pause', const GlyphePause(taille: 40, couleur: Color(0xFF000000))),
      ('lecture', const GlyphePlay(taille: 40, couleur: Color(0xFF000000))),
    ]) {
      final vu = await _compte(tester, Center(child: signe));
      expect(vu.noirs, greaterThan(100), reason: 'le signe $nom est noir');
      expect(vu.blancs, greaterThan(20), reason: 'sa couronne est blanche');
    }
  });

  testWidgets('une pastille noire se cerne de blanc', (tester) async {
    final noire = await _compte(
      tester,
      const Center(child: PastilleNonLue(cote: 40, couleur: Color(0xFF000000))),
    );
    expect(noire.blancs, greaterThan(20), reason: 'son trait est blanc');

    final claire = await _compte(
      tester,
      const Center(child: PastilleNonLue(cote: 40, couleur: Color(0xFFFFFFFF))),
    );
    expect(claire.noirs, greaterThan(20), reason: 'son trait reste noir');
  });

  testWidgets('sur une touche noire, le mot s écrit en noir', (tester) async {
    // Nino : « noir sur noir avec les contours blancs pour la couleur 2. »
    // Sur la couleur 1 de Deep Grey — le blanc — rien ne change : le mot
    // était déjà blanc.
    expect(encreSurTouche(const Color(0xFF000000)), const Color(0xFF000000));
    expect(encreSurTouche(const Color(0xFFFFFFFF)), const Color(0xFFFFFFFF));
    expect(encreSurTouche(kGrisTouche), const Color(0xFFFFFFFF));
    expect(
      encreSurTouche(paletteOf('medieval').fonce),
      const Color(0xFFFFFFFF),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FugaButton(
            text: '15 min',
            color: paletteOf('deepgrey').fonce,
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mot = tester.widget<MotTouche>(find.byType(MotTouche));
    expect(mot.couleur, const Color(0xFF000000));
  });
}
