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
      expect(reference.length, 549);
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

  /// Un littéral de chaîne Dart simple, lu à partir du guillemet en `i`.
  ///
  /// Renvoie le texte TEL QU'IL SERA à l'exécution — échappements résolus —
  /// et l'indice juste après. `null` pour tout ce qui n'est pas une chaîne
  /// fixe : triple guillemet, interpolation, `\u....`.
  (String, int)? litteral(String s, int i) {
    const echappes = {
      'n': '\n',
      't': '\t',
      'r': '\r',
      "'": "'",
      '"': '"',
      '\\': '\\',
      r'$': r'$',
    };
    final q = s[i];
    if (i + 3 <= s.length && s.substring(i, i + 3) == q * 3) return null;
    final out = StringBuffer();
    var j = i + 1;
    while (j < s.length) {
      final c = s[j];
      if (c == '\\') {
        final n = s[j + 1];
        if (n == 'u') return null;
        out.write(echappes[n] ?? n);
        j += 2;
        continue;
      }
      if (c == q) return (out.toString(), j + 1);
      if (c == '\n' || c == r'$') return null;
      out.write(c);
      j++;
    }
    return null;
  }

  /// Toutes les chaînes ÉCRITES dans un `T(...)` de `lib/`.
  ///
  /// On lit le code source, parce qu'une liste tenue à la main dérive : c'est
  /// exactement ce qui est arrivé — quatre-vingt-seize textes neufs ne
  /// vivaient qu'en français, et aucun test ne le voyait.
  ///
  /// Les `T(variable)` échappent à ce balayage : seules les chaînes écrites
  /// là sont vérifiées. C'est déjà l'essentiel, et c'est vérifiable.
  Set<String> textesDuCode() {
    final debut = RegExp(r'(?<![A-Za-z0-9_])T\(');
    final trouves = <String>{};
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in sources) {
      final src = f.readAsStringSync();
      for (final m in debut.allMatches(src)) {
        var i = m.end;
        while (i < src.length && ' \t\n'.contains(src[i])) {
          i++;
        }
        final morceaux = <String>[];
        while (i < src.length && (src[i] == "'" || src[i] == '"')) {
          final lu = litteral(src, i);
          if (lu == null) {
            morceaux.clear();
            break;
          }
          morceaux.add(lu.$1);
          i = lu.$2;
          while (i < src.length && ' \t\n'.contains(src[i])) {
            i++;
          }
        }
        if (morceaux.isNotEmpty) trouves.add(morceaux.join());
      }
    }
    return trouves;
  }

  group('Couverture du code', () {
    test('le balayage trouve bien les textes de l application', () {
      // Un garde-fou sur le garde-fou : si le balayage se mettait à ne rien
      // trouver, le test suivant passerait pour de mauvaises raisons.
      final textes = textesDuCode();
      expect(textes.length, greaterThan(250));
      expect(textes, contains('Revenir au menu'));
      expect(textes, contains('Pas de partie en cours'));
    });

    test(
      'chaque texte écrit dans un T() est traduit, dans TOUTES les langues',
      () {
        final textes = textesDuCode();
        for (final f in files) {
          final manquants = textes.difference(read(f).keys.toSet()).toList()
            ..sort();
          expect(
            manquants,
            isEmpty,
            reason:
                '${f.path} : ${manquants.length} texte(s) sans traduction\n'
                '${manquants.take(10).join("\n")}',
          );
        }
      },
    );
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
      expect(en.length, 549);
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
