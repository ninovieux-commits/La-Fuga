/// Les dessins des quatre grosses touches, mesurés dans leur fichier.
///
/// Nino : « il faut que le symbole + et le symbole silhouette de Deep Grey
/// soient à la même hauteur. »
///
/// Deux dessins posés dans la même case font la même hauteur à l'écran si,
/// et seulement si, leur ENCRE occupe la même hauteur dans leur carré de
/// 192 : c'est ce carré que `BoxFit.contain` met à l'échelle, pas l'encre.
/// On le vérifie donc sur les fichiers eux-mêmes — une retouche du
/// générateur qui recadrerait l'un sans l'autre se verrait ici, et nulle
/// part ailleurs avant l'écran de Nino.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';

/// Les bords de l'encre : les premières et dernières lignes non vides.
Future<({int cote, int hauteurDeLEncre, int largeurDeLEncre, int videDessous})>
mesure(String chemin) async {
  final octets = await File(chemin).readAsBytes();
  final codec = await ui.instantiateImageCodec(octets);
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final l = image.width;
  int? haut, bas, gauche, droite;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < l; x++) {
      if (data.getUint8((y * l + x) * 4 + 3) < 8) continue;
      haut ??= y;
      bas = y;
      if (gauche == null || x < gauche) gauche = x;
      if (droite == null || x > droite) droite = x;
    }
  }
  expect(haut, isNotNull, reason: '$chemin est vide');
  return (
    cote: image.width,
    hauteurDeLEncre: bas! - haut! + 1,
    largeurDeLEncre: droite! - gauche! + 1,
    videDessous: image.height - 1 - bas,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le + et la silhouette de Deep Grey ont la même hauteur', () async {
    final plus = await mesure('assets/images/plus.webp');
    final deepGrey = await mesure('assets/images/deepgrey_silhouette.webp');
    expect(plus.cote, deepGrey.cote, reason: 'le même carré');
    expect(
      plus.hauteurDeLEncre,
      deepGrey.hauteurDeLEncre,
      reason:
          'posés dans la même case, ils ne feront la même hauteur que si '
          'leur encre occupe la même hauteur de leur carré',
    );
  });

  test('les quatre dessins gardent la marge des neuf autres', () async {
    for (final nom in [
      'chat',
      'podium',
      'deepgrey_silhouette',
      'plus',
      // Deux voisins de longue date, pour que la règle soit bien LA règle.
      'enveloppe',
      'retour',
    ]) {
      final m = await mesure('assets/images/$nom.webp');
      expect(m.cote, 192, reason: nom);
      final plusGrand = m.hauteurDeLEncre > m.largeurDeLEncre
          ? m.hauteurDeLEncre
          : m.largeurDeLEncre;
      expect(
        plusGrand,
        inInclusiveRange(170, 174),
        reason: '$nom : l encre doit remplir les 172 du dedans',
      );
    }
  });

  test('la table du sol commun dit la vérité des fichiers', () async {
    // Le menu descend chaque dessin de ce qu'il laisse de vide sous lui,
    // pour que les quatre posent sur le même sol. Ces nombres sont écrits à
    // la main dans `menu_screen.dart` : ils doivent être une MESURE, et
    // c'est ici qu'on la refait.
    for (final e in kVideSousLeDessin.entries) {
      final m = await mesure(e.key);
      expect(
        m.videDessous.toDouble(),
        moreOrLessEquals(e.value, epsilon: 1),
        reason:
            '${e.key} laisse ${m.videDessous} de vide sous lui, la table '
            'en annonce ${e.value.toStringAsFixed(0)}',
      );
    }
  });
}
