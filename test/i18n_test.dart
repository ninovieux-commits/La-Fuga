/// Internationalisation : complétude des fichiers de langue et comportement
/// de repli. Le français est la clé, jamais une valeur.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final files = Directory('assets/i18n')
      .listSync()
      .whereType<File>()
      .where(
        (f) =>
            f.path.endsWith('.json') &&
            !f.path.endsWith('story.json') &&
            !f.path.endsWith('languages.json'),
      )
      .toList();

  Map<String, String> read(File f) =>
      (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );

  group('Fichiers de langue', () {
    test('il y en a un par langue traduite', () {
      // 10 langues proposées, moins le français qui est la langue source.
      expect(files.length, kLanguageLabels.length - 1);
    });

    test('aucun fichier pour le français : ses clés SONT ses valeurs', () {
      expect(File('assets/i18n/fr.json').existsSync(), isFalse);
    });

    test('toutes les langues couvrent les mêmes clés', () {
      final reference = read(files.first).keys.toSet();
      expect(reference.length, 416);
      for (final f in files) {
        final keys = read(f).keys.toSet();
        expect(
          keys.length,
          reference.length,
          reason: '${f.path} n a pas le même nombre de clés',
        );
        expect(
          keys.difference(reference),
          isEmpty,
          reason: '${f.path} a des clés en trop',
        );
        expect(
          reference.difference(keys),
          isEmpty,
          reason: '${f.path} a des clés manquantes',
        );
      }
    });

    test('aucune traduction vide', () {
      for (final f in files) {
        read(f).forEach((key, value) {
          expect(
            value.trim(),
            isNotEmpty,
            reason: '${f.path} : « $key » est vide',
          );
        });
      }
    });

    test("l'histoire du jeu existe dans chaque langue traduite", () {
      final story =
          jsonDecode(File('assets/i18n/story.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final lang in kLanguageLabels.keys) {
        if (lang == kSourceLanguage) continue;
        expect(
          story[lang],
          isA<String>(),
          reason: 'histoire manquante : $lang',
        );
        expect((story[lang] as String).length, greaterThan(100), reason: lang);
      }
    });
  });

  group('T()', () {
    test('le français renvoie la chaîne telle quelle', () async {
      await Translations.load('fr');
      expect(T('Se connecter'), 'Se connecter');
      expect(T('Chaîne jamais traduite'), 'Chaîne jamais traduite');
    });

    test('une langue chargée traduit', () async {
      final en = await Translations.load('en');
      expect(en.language, 'en');
      expect(en.length, 416);
      expect(
        T('Se connecter'),
        isNot('Se connecter'),
        reason: 'la chaîne doit être traduite',
      );
    });

    test('une clé inconnue retombe sur le français', () async {
      await Translations.load('en');
      const inedit = 'Texte qui n existe pas dans le dictionnaire';
      expect(
        T(inedit),
        inedit,
        reason: 'un texte non traduit s affiche, il ne disparaît jamais',
      );
    });

    test('une langue inconnue retombe sur le français', () async {
      final t = await Translations.load('xx');
      expect(t.language, 'fr');
      expect(T('Se connecter'), 'Se connecter');
    });

    test("l'histoire suit la langue", () async {
      final fr = await Translations.load('fr');
      final en = await Translations.load('en');
      expect(fr.story, startsWith('Deux frères'));
      expect(en.story, isNot(startsWith('Deux frères')));
      expect(en.story, isNotEmpty);
    });
  });
}
