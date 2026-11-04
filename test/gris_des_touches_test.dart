/// UN SEUL GRIS POUR TOUTES LES TOUCHES, et c'est celui du plateau.
///
/// Nino : « absolument toutes les touches grises de l'App doivent être en
/// gris pile entre noir et blanc, comme les touches autour du plateau de
/// jeu. »
///
/// Le vérifier à l'écran demanderait de rendre chaque écran de l'appli, dans
/// chaque état, et de compter les pixels. On lit donc le CODE : l'ancien
/// gris, plus sombre, ne doit plus servir qu'aux fonds de popup — un
/// panneau n'est pas une touche, et les touches qu'il porte doivent s'en
/// détacher.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';

/// Ce qui a le droit de nommer encore l'ancien gris.
///
/// Un fond de boîte de dialogue (`backgroundColor:`), le panneau d'un volet
/// du menu, et la déclaration de la constante elle-même.
bool _aLeDroit(String fichier, String ligne) {
  if (fichier.endsWith('fuga_button.dart') && ligne.contains('const Color')) {
    return true;
  }
  if (ligne.contains('backgroundColor:')) return true;
  if (fichier.endsWith('volet_menu.dart')) return true;
  return false;
}

void main() {
  test('le gris des touches est PILE entre le noir et le blanc', () {
    expect(kGrisTouche, const Color(0xFF808080));
    expect(
      ((kGrisTouche.r + kGrisTouche.g + kGrisTouche.b) / 3 * 255).round(),
      128,
      reason: 'ni plus clair ni plus sombre que la moitié',
    );
  });

  test('plus aucune touche ne porte l ancien gris', () {
    final coupables = <String>[];
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in sources) {
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final ligne = lignes[i];
        if (!ligne.contains('kFugaGrey')) continue;
        // Une ligne de commentaire parle du gris, elle ne le pose pas.
        if (ligne.trimLeft().startsWith('//')) continue;
        if (ligne.trimLeft().startsWith('///')) continue;
        if (_aLeDroit(f.path, ligne)) continue;
        coupables.add('${f.path}:${i + 1} : ${ligne.trim()}');
      }
    }
    expect(
      coupables,
      isEmpty,
      reason:
          'ces endroits posent encore le gris sombre là où une touche '
          'attend le gris médian :\n${coupables.join("\n")}',
    );
  });
}
