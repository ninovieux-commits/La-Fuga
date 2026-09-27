/// Trois corrections d'après Nino.
///
///   — « les logos des thèmes spéciaux (qui sont des images) ne prennent
///     pas » ;
///   — « le thème insectes doit avoir des croix derrière les pièces carrées
///     pour qu'on les reconnaisse » ;
///   — « quand on déconnecte le compte ça ne doit pas garder le thème […]
///     les infos appartiennent au compte ».
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/theme_assets.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/piece_painter.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Les logos des thèmes', () {
    test('chaque thème pointe sur un fichier qui EXISTE', () {
      // Trois thèmes ont un logo dont le fichier ne porte pas leur nom. Le
      // chemin construit à la main tombait donc à côté, et l'image de repli
      // faisait passer la panne inaperçue.
      final manquants = <String>[];
      for (final theme in kThemeOrder) {
        if (!File(logoAssetOf(theme)).existsSync()) manquants.add(theme);
      }
      expect(manquants, isEmpty, reason: 'logos introuvables : $manquants');
    });

    test('les trois thèmes aux noms décalés sont bien redirigés', () {
      expect(logoAssetOf('medieval'), endsWith('logo_bataille.webp'));
      expect(logoAssetOf('fleur'), endsWith('logo_fleurs.webp'));
      // Faute de logo d'insectes, celui de la forêt fait l'intérim.
      expect(logoAssetOf('insectes'), endsWith('logo_foret.webp'));
    });

    test('et un thème ordinaire garde son propre nom', () {
      expect(logoAssetOf('volcan'), endsWith('logo_volcan.webp'));
      expect(logoAssetOf('original'), endsWith('logo_original.webp'));
    });

    test('tous les logos sont déclarés dans pubspec', () {
      // Un fichier présent sur le disque mais non déclaré n'est pas embarqué
      // dans l'APK : il manquerait sur le téléphone, et nulle part ailleurs.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains('assets/logos/'),
        isTrue,
        reason: 'le dossier des logos n est pas embarqué',
      );
    });
  });

  group('Le thème insectes', () {
    test('il donne bien la MÊME image au Soldat et au Garde', () {
      // C'est la raison d'être de la croix. Si un jour le thème gagne deux
      // images distinctes, ce test le dira et la croix deviendra inutile.
      final img = kThemeImages['insectes']!;
      expect(
        img.pieces[(PieceType.soldat, Camp.blanc)],
        img.pieces[(PieceType.garde, Camp.blanc)],
      );
      expect(kThemesSansFormeCarree, contains('insectes'));
    });

    test('les thèmes qui distinguent déjà n en reçoivent pas', () {
      for (final theme in ['medieval', 'fleur', 'dragon']) {
        final img = kThemeImages[theme]!;
        expect(
          img.pieces[(PieceType.soldat, Camp.blanc)],
          isNot(img.pieces[(PieceType.garde, Camp.blanc)]),
          reason: '$theme partage ses images : il lui faudrait la croix',
        );
        expect(kThemesSansFormeCarree, isNot(contains(theme)));
      }
    });

    test('le Soldat porte un « + », le Garde un « × »', () async {
      // On dessine les deux croix et on regarde le CENTRE des bords : le
      // « + » y passe, le « × » non.
      Future<ui.Image> dessiner(PieceType type) async {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 100, 100),
          Paint()..color = const Color(0xFF808080),
        );
        paintActivationCross(
          canvas,
          const Rect.fromLTWH(0, 0, 100, 100),
          type,
          Paint()
            ..color = const Color(0xFFFF0000)
            ..strokeWidth = 8
            ..style = PaintingStyle.stroke,
        );
        return rec.endRecording().toImage(100, 100);
      }

      Future<bool> rougeEn(ui.Image img, int x, int y) async {
        final data = await img.toByteData();
        final i = (y * 100 + x) * 4;
        return data!.getUint8(i) > 200 && data.getUint8(i + 1) < 100;
      }

      final plus = await dessiner(PieceType.soldat);
      final croix = await dessiner(PieceType.garde);

      // Milieu du bord gauche : le « + » y a sa barre horizontale.
      expect(
        await rougeEn(plus, 22, 50),
        isTrue,
        reason: 'le + n a pas sa barre',
      );
      expect(
        await rougeEn(croix, 22, 50),
        isFalse,
        reason: 'le × ne doit pas toucher le milieu du bord',
      );
      // Coin haut-gauche : le « × » y passe, le « + » non.
      expect(
        await rougeEn(croix, 22, 22),
        isTrue,
        reason: 'le × n a pas sa diagonale',
      );
      expect(await rougeEn(plus, 22, 22), isFalse);
    });
  });

  group('La déconnexion rend ce qui est au compte', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
      });
      await Settings.load();
    });

    test('le thème repart à zéro', () async {
      await Settings.instance.setTheme('insectes|insectes|insectes');
      expect(Settings.instance.theme, isNot(kDefaultTheme));

      await Settings.instance.clearOnlineSession();
      expect(
        Settings.instance.theme,
        kDefaultTheme,
        reason: 'le compte suivant héritait du thème du précédent',
      );
    });

    test('mais les réglages de l APPAREIL restent', () async {
      await Settings.instance.setVolume(0.42);
      await Settings.instance.setInstrument('cloche');
      await Settings.instance.setSlideSpeed(0.5);

      await Settings.instance.clearOnlineSession();

      expect(Settings.instance.volume, closeTo(0.42, 0.001));
      expect(Settings.instance.instrument, 'cloche');
      expect(
        Settings.instance.slideSpeed,
        closeTo(0.5, 0.001),
        reason: 'ces réglages-là sont ceux du téléphone, pas du compte',
      );
    });

    test('les portraits des adversaires sont oubliés', () async {
      AvatarPhotos.remember('celia', 'insectes|Heritier');
      expect(AvatarPhotos.known('celia'), isNotEmpty);

      await OnlineService.instance.logout();
      expect(
        AvatarPhotos.known('celia'),
        isEmpty,
        reason: 'le compte suivant voyait les portraits du précédent',
      );
    });
  });
}
