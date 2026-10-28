/// Un message qui n'est que des émojis s'affiche en gros.
///
/// Nino : « quand on envoie un smiley seul il apparaît en plus gros. »
library;

import 'package:lafuga/ui/texte_emoji.dart';
import 'package:test/test.dart';

void main() {
  group('Compter les émojis d un message', () {
    test('un émoji seul en vaut un', () {
      expect(compteEmojisSeuls('😀'), 1);
      expect(
        compteEmojisSeuls('  😀  '),
        1,
        reason: 'les blancs ne comptent pas',
      );
      expect(compteEmojisSeuls('🎉'), 1);
      expect(compteEmojisSeuls('❤'), 1);
    });

    test('un émoji TEINTÉ en vaut toujours UN', () {
      // « 👍🏽 » fait deux points de code : le pouce et la teinte. Les compter
      // tous les deux donnerait deux émojis là où l œil en voit un.
      expect(compteEmojisSeuls('👍🏽'), 1);
      expect(compteEmojisSeuls('🙋🏿‍♀️'), 1);
    });

    test('une famille cousue de liants en vaut UN', () {
      // « 👩‍👩‍👧 » : trois personnages et deux liants invisibles, cinq points
      // de code pour un seul dessin.
      expect(compteEmojisSeuls('👩‍👩‍👧'), 1);
      expect(compteEmojisSeuls('👨‍👩‍👧‍👦'), 1);
    });

    test('un cœur avec son sélecteur de variante en vaut un', () {
      expect(compteEmojisSeuls('❤️'), 1);
      expect(compteEmojisSeuls('☺️'), 1);
    });

    test('plusieurs émojis se comptent', () {
      expect(compteEmojisSeuls('😀😀'), 2);
      expect(compteEmojisSeuls('😀 😀 😀'), 3);
      expect(compteEmojisSeuls('🎉🎊🥳🎈'), 4);
    });

    test('du texte, même avec un émoji, ne compte pas', () {
      expect(compteEmojisSeuls('salut 😀'), 0);
      expect(compteEmojisSeuls('😀 !'), 0);
      expect(compteEmojisSeuls('bravo'), 0);
      expect(compteEmojisSeuls(''), 0);
      expect(compteEmojisSeuls('   '), 0);
      expect(compteEmojisSeuls('3'), 0, reason: 'un chiffre reste un chiffre');
    });

    test('un drapeau en vaut UN, pas deux', () {
      // Deux indicateurs régionaux, un seul dessin.
      expect(compteEmojisSeuls('🇫🇷'), 1);
      expect(compteEmojisSeuls('🇫🇷🇮🇹'), 2, reason: 'deux drapeaux');
      expect(
        grossissementEmoji('🇫🇷'),
        3.0,
        reason: 'un drapeau seul est gros',
      );
    });
  });

  group('Le grossissement', () {
    test('un seul est le plus gros', () {
      expect(grossissementEmoji('😀'), 3.0);
    });

    test('deux puis trois décroissent', () {
      final deux = grossissementEmoji('😀😀')!;
      final trois = grossissementEmoji('😀😀😀')!;
      expect(deux, lessThan(3.0));
      expect(trois, lessThan(deux));
      expect(trois, greaterThan(1.0), reason: 'trois restent plus gros');
    });

    test('au-delà de trois, ça rapetisse mais ça reste gros', () {
      // Nino : « quand on envoie que des smileys […] ça doit aussi le mettre
      // en plus gros ». Quatre ne redeviennent donc pas du texte.
      final trois = grossissementEmoji('😀😀😀')!;
      final quatre = grossissementEmoji('😀😀😀😀')!;
      expect(quatre, lessThan(trois));
      expect(quatre, greaterThan(1.0));
    });

    test('le plancher arrête la décroissance', () {
      final dix = grossissementEmoji('😀' * 10)!;
      final trente = grossissementEmoji('😀' * 30)!;
      expect(dix, kEmojiGrossiMin);
      expect(trente, kEmojiGrossiMin);
      expect(kEmojiGrossiMin, greaterThan(1.0), reason: 'jamais du texte');
    });

    test('l\'escalier d\'avant est intact', () {
      // La formule REMPLACE trois valeurs écrites à la main : elle doit
      // rendre exactement les mêmes.
      expect(grossissementDe(1), 3.0);
      expect(grossissementDe(2), 2.4);
      expect(grossissementDe(3), 2.0);
    });

    test('du texte ne grossit jamais', () {
      expect(grossissementEmoji('salut'), isNull);
      expect(grossissementEmoji('salut 😀'), isNull);
      expect(grossissementEmoji(''), isNull);
    });
  });
}
