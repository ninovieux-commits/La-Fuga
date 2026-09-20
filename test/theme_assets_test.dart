/// Images de thème : la table générée doit désigner des fichiers qui existent
/// vraiment et être déclarée dans le pubspec.
///
/// C'est le genre d'erreur qui ne se voit qu'à l'exécution, sur le téléphone.
library;

import 'dart:io';

import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/theme/theme_assets.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
import 'package:test/test.dart';

void main() {
  group('Table des images', () {
    test('les cinq thèmes à images sont déclarés', () {
      expect(kThemeImages.keys.toSet(), {
        'medieval',
        'fleur',
        'insectes',
        'dragon',
        'deepgrey',
      });
    });

    test('chaque thème déclaré existe dans la liste des thèmes', () {
      for (final name in kThemeImages.keys) {
        expect(
          kThemes.containsKey(name),
          isTrue,
          reason: '« $name » n est pas un thème connu',
        );
      }
    });

    test('les logos et la photo de Deep Grey existent aussi', () {
      // Ces chemins-là sont écrits à la main, pas générés : rien ne les
      // rattrape si une image est renommée ou convertie.
      for (final theme in kThemes.keys) {
        final path = logoAssetOf(theme);
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'logo manquant pour « $theme » : $path',
        );
      }
      expect(File('assets/images/deepgrey.webp').existsSync(), isTrue);
    });

    test('aucune image du jeu n est restée en PNG', () {
      // Tout est en WebP sans perte : un PNG oublié pèserait pour rien.
      for (final folder in ['assets/themes', 'assets/logos', 'assets/images']) {
        final leftovers = Directory(folder)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.png'))
            .toList();
        expect(leftovers, isEmpty, reason: 'PNG restants dans $folder');
      }
    });

    test('tous les fichiers référencés existent', () {
      for (final entry in kThemeImages.entries) {
        final images = entry.value;
        for (final path in [
          if (images.background != null) images.background!,
          if (images.board != null) images.board!,
          ...images.pieces.values,
        ]) {
          expect(
            File(path).existsSync(),
            isTrue,
            reason: '${entry.key} : fichier manquant $path',
          );
        }
      }
    });

    test('les quatre thèmes à pièces couvrent les dix combinaisons', () {
      for (final name in ['medieval', 'fleur', 'insectes', 'dragon']) {
        final images = kThemeImages[name]!;
        expect(images.hasPieceImages, isTrue, reason: name);
        for (final type in PieceType.values) {
          for (final camp in Camp.values) {
            expect(
              images.pieces[(type, camp)],
              isNotNull,
              reason: '$name : ${type.wire} ${camp.wire} manquant',
            );
          }
        }
      }
    });

    test('deepgrey n a que des fonds, ses pièces restent dessinées', () {
      final images = kThemeImages['deepgrey']!;
      expect(images.hasPieceImages, isFalse);
      expect(images.hasBackgrounds, isTrue);
      expect(images.board, isNotNull);
    });

    test('insectes partage une image entre Soldat et Garde', () {
      final images = kThemeImages['insectes']!;
      for (final camp in Camp.values) {
        expect(
          images.pieces[(PieceType.soldat, camp)],
          images.pieces[(PieceType.garde, camp)],
          reason: 'les deux carrées ont la même image dans ce thème',
        );
        expect(images.pieces[(PieceType.soldat, camp)], contains('carree'));
      }
    });

    test('medieval arrondit ses coins pour masquer le filigrane', () {
      expect(kThemeImages['medieval']!.cornerRadius, greaterThan(0));
      expect(kThemeImages['fleur']!.cornerRadius, 0);
    });

    test('un thème sans images n est pas dans la table', () {
      expect(imagesFor('original'), isNull);
      expect(imagesFor('ocean'), isNull);
      expect(imagesFor('inexistant'), isNull);
    });
  });

  test('tous les dossiers d images sont déclarés dans le pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final folders = <String>{};
    for (final images in kThemeImages.values) {
      for (final path in [
        if (images.background != null) images.background!,
        if (images.board != null) images.board!,
        ...images.pieces.values,
      ]) {
        folders.add('${path.substring(0, path.lastIndexOf('/'))}/');
      }
    }
    for (final folder in folders) {
      expect(
        pubspec,
        contains(folder),
        reason: 'dossier non déclaré dans pubspec.yaml : $folder',
      );
    }
  });
}
