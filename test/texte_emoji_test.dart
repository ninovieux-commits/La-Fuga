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
        grossissementDe(compteEmojisSeuls('🇫🇷')),
        kEmojiGrossi,
        reason: 'un drapeau seul est gros',
      );
    });
  });

  // Nino : « je veux pas que ça rétrécisse quand il y en a plusieurs, je
  // trouve ça naze. »
  group('Le grossissement', () {
    test('un dessin seul est gros', () {
      expect(grossissementDe(1), kEmojiGrossi);
      expect(kEmojiGrossi, greaterThan(1.0));
    });

    test('et une rangée ne rapetisse pas', () {
      for (final n in [2, 3, 4, 10, 30]) {
        expect(
          grossissementDe(n),
          kEmojiGrossi,
          reason: '$n dessins font la même taille qu un seul',
        );
      }
    });

    test('du texte ne grossit jamais', () {
      expect(grossissementDe(compteEmojisSeuls('salut')), 1);
      expect(grossissementDe(compteEmojisSeuls('salut 😀')), 1);
      expect(grossissementDe(compteEmojisSeuls('')), 1);
    });
  });
}
