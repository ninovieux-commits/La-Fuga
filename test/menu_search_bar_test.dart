/// La barre de recherche du menu, mesurée EN PIXELS PEINTS.
///
/// Mesurer la boîte d'un `TextField` ne dit rien de ce qu'on voit : sur le
/// téléphone de Nino, la boîte faisait ses 52 px logiques et la barre grise
/// n'en peignait que 19, pendant que l'étoile juste à côté était correcte.
/// Un test qui interroge l'arbre de rendu passait donc pendant que l'écran
/// montrait le contraire.
///
/// Celui-ci rend l'application à la résolution exacte d'un téléphone, capture
/// l'image, et compte les pixels gris — la même mesure que sur une capture
/// d'écran. C'est la seule qui parle de ce que voit le joueur.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le gris des touches et de la barre — `kFugaGrey`, rgb(89, 89, 89).
bool _estGris(ByteData image, int largeur, int x, int y) {
  final i = (y * largeur + x) * 4;
  if (i + 3 >= image.lengthInBytes) return false;
  return (image.getUint8(i) - 89).abs() < 14 &&
      (image.getUint8(i + 1) - 89).abs() < 14 &&
      (image.getUint8(i + 2) - 89).abs() < 14;
}

/// Plus longue bande grise continue de la colonne `x`, cherchée UNIQUEMENT
/// entre `y0` et `y1`, en tolérant les trous que creusent les lettres.
///
/// Le bornage n'est pas un détail : sans lui, la plus longue bande de la
/// colonne pouvait être une tout autre touche, et le test passait alors même
/// que la barre était minuscule. C'est le piège dans lequel je suis tombé.
int _bandeGrise(ByteData image, int largeur, int x, int y0, int y1) {
  final lignes = <int>[];
  for (var y = y0; y < y1; y++) {
    if (_estGris(image, largeur, x, y)) lignes.add(y);
  }
  if (lignes.isEmpty) return 0;
  var meilleur = 1, debut = lignes.first, precedent = lignes.first;
  for (final y in lignes.skip(1)) {
    if (y - precedent > 14) debut = y;
    precedent = y;
    if (y - debut + 1 > meilleur) meilleur = y - debut + 1;
  }
  return meilleur;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    resetScale();
  });
  tearDown(resetScale);

  for (final (nom, taille, densite) in [
    ('un téléphone 1080×2400', const Size(1080, 2400), 2.75),
    ('un téléphone 1440×3200', const Size(1440, 3200), 3.5),
    ('un petit écran 720×1520', const Size(720, 1520), 2.0),
  ]) {
    testWidgets('sur $nom, la barre de recherche est aussi épaisse que '
        'l\'étoile', (tester) async {
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = densite;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const RepaintBoundary(key: Key('ecran'), child: FugaApp()),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Les colonnes à scruter, choisies HORS des lettres : le bout droit du
      // champ (vide) et le bord gauche de l'étoile (avant le dessin).
      // La BOÎTE PEINTE de la barre, pas celle du TextField qu'elle contient.
      final barre = tester.getRect(find.byKey(kBarreRechercheKey));
      Rect? etoile;
      for (final e in find.byType(FugaButton).evaluate()) {
        if ((e.widget as FugaButton).text == '★') {
          etoile = tester.getRect(find.byWidget(e.widget));
        }
      }
      expect(etoile, isNotNull, reason: 'étoile des favoris introuvable');

      late ByteData image;
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject(find.byKey(const Key('ecran')))
                as RenderRepaintBoundary;
        final rendu = await boundary.toImage(pixelRatio: densite);
        image = (await rendu.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });

      final largeur = taille.width.round();
      final xChamp = ((barre.right - 8) * densite).round();
      final xEtoile = ((etoile!.left + 5) * densite).round();
      // On ne regarde QUE la bande de la ligne de recherche, avec un peu de
      // marge : ailleurs dans la colonne il y a d'autres touches grises.
      final y0 = ((barre.top - 25) * densite).round().clamp(0, 99999);
      final y1 = ((barre.bottom + 25) * densite).round().clamp(
        0,
        taille.height.round(),
      );

      final attendu = touchHeight() * densite;
      final mesureChamp = _bandeGrise(image, largeur, xChamp, y0, y1);
      final mesureEtoile = _bandeGrise(image, largeur, xEtoile, y0, y1);

      expect(
        mesureEtoile.toDouble(),
        moreOrLessEquals(attendu, epsilon: 3),
        reason:
            'repère faussé : l\'étoile peint $mesureEtoile px au lieu de '
            '${attendu.toStringAsFixed(0)}',
      );
      expect(
        mesureChamp.toDouble(),
        moreOrLessEquals(attendu, epsilon: 3),
        reason:
            'la barre de recherche peint $mesureChamp px au lieu de '
            '${attendu.toStringAsFixed(0)} — soit '
            '${(100 * mesureChamp / attendu).toStringAsFixed(0)} % d\'une '
            'touche. C\'est ce que voit le joueur.',
      );
    });
  }
}
