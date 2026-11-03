/// LA DATE DU TAMPON, dans le sens de chaque langue.
///
/// Nino : « lorsqu'un joueur a l'app réglée en anglais, ça doit mettre la
/// date dans le sens anglais, idem pour les autres langues où le sens est
/// différent », et « pour la date ça doit laisser les // et remplir seul au
/// bon endroit, qu'on ait qu'à appuyer sur les chiffres voulus ».
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/date_locale.dart';

void main() {
  final jour = DateTime(2026, 11, 3);

  group("L'ordre", () {
    test('le français, et ceux qui le suivent : jour, mois, année', () {
      for (final langue in ['fr', 'es', 'it', 'pt']) {
        expect(dateEcriteSelon(jour, langue), '03/11/2026', reason: langue);
      }
    });

    test("l'anglais met le mois d'abord", () {
      expect(dateEcriteSelon(jour, 'en'), '11/03/2026');
    });

    test("l'allemand et le russe comptent en points", () {
      expect(dateEcriteSelon(jour, 'de'), '03.11.2026');
      expect(dateEcriteSelon(jour, 'ru'), '03.11.2026');
    });

    test("l'asie commence par l'année", () {
      for (final langue in ['zh', 'ja', 'ko']) {
        expect(dateEcriteSelon(jour, langue), '2026/11/03', reason: langue);
      }
    });

    test('une langue inconnue garde le sens du français', () {
      expect(dateEcriteSelon(jour, 'xx'), '03/11/2026');
    });
  });

  group('Le masque', () {
    test('les barres se posent toutes seules, au fil des chiffres', () {
      expect(masqueLaDate('0', 'fr'), '0');
      expect(masqueLaDate('03', 'fr'), '03');
      expect(masqueLaDate('031', 'fr'), '03/1');
      expect(masqueLaDate('0311', 'fr'), '03/11');
      expect(masqueLaDate('03112026', 'fr'), '03/11/2026');
    });

    test('et dans le sens de la langue', () {
      expect(masqueLaDate('20261103', 'ja'), '2026/11/03');
      expect(masqueLaDate('03112026', 'de'), '03.11.2026');
    });

    test('ce qui n est pas un chiffre ne compte pas', () {
      expect(masqueLaDate('03/11/2026', 'fr'), '03/11/2026');
      expect(masqueLaDate('a0b3c1d1', 'fr'), '03/11');
    });
  });

  group('La relecture', () {
    test('on retrouve la date qu on a écrite', () {
      for (final langue in ['fr', 'en', 'de', 'ja', 'ru']) {
        final ecrite = dateEcriteSelon(jour, langue);
        expect(dateDuTexte(ecrite, langue), jour, reason: langue);
      }
    });

    test(
      'le même texte ne dit pas la même chose en français et en anglais',
      () {
        expect(dateDuTexte('03/11/2026', 'fr'), DateTime(2026, 11, 3));
        expect(dateDuTexte('03/11/2026', 'en'), DateTime(2026, 3, 11));
      },
    );

    test('ce qui n est pas une date est refusé, jamais deviné', () {
      expect(dateDuTexte('03/11', 'fr'), isNull);
      expect(dateDuTexte('', 'fr'), isNull);
      // Le 31 février : `DateTime` le décalerait au 3 mars, on refuse.
      expect(dateDuTexte('31/02/2026', 'fr'), isNull);
      expect(dateDuTexte('00/11/2026', 'fr'), isNull);
      expect(dateDuTexte('03/13/2026', 'fr'), isNull);
    });
  });
}
