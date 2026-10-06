/// Les rythmiques de la lecture automatique.
///
/// Nino : « un bouton (choisir une rythmique) qui donnerait le choix entre
/// valse 3/4, menuet 3/4, sarabande 3/2, passacaille 3/4, marche 2/4, gavotte
/// 4/4, gigue 6/8, sicilienne 6/8. On ne peut plus régler la vitesse si l'on a
/// choisi une rythmique ; les vitesses sont prédéfinies par rapport à la
/// rythmique en question. Le lecteur doit lire un coup (et donc une note) à
/// chaque temps marqué. »
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/rythmique.dart';

void main() {
  group('Les huit danses', () {
    test('elles sont là, avec la bonne mesure', () {
      expect(
        {for (final r in Rythmique.values) r.nom: r.mesure},
        {
          'Valse': '3/4',
          'Menuet': '3/4',
          'Sarabande': '3/2',
          'Passacaille': '3/4',
          'Marche': '2/4',
          'Gavotte': '4/4',
          'Gigue': '6/8',
          'Sicilienne': '6/8',
        },
      );
    });

    test('en 6/8 le temps est la noire pointée : DEUX par mesure', () {
      // Six croches, mais deux temps. Une gigue qui jouerait six coups par
      // mesure ne serait pas une gigue.
      for (final r in [Rythmique.gigue, Rythmique.sicilienne]) {
        expect(r.tempsParMesure, 2, reason: r.nom);
      }
      expect(Rythmique.valse.tempsParMesure, 3);
      expect(Rythmique.marche.tempsParMesure, 2);
      expect(Rythmique.gavotte.tempsParMesure, 4);
    });

    test('chaque danse a son tempo, et ils sont tous différents du voisin', () {
      // Deux 3/4 qui iraient à la même vitesse seraient la même chose.
      expect(
        Rythmique.valse.parCoup,
        lessThan(Rythmique.menuet.parCoup),
        reason: 'une valse va plus vite qu un menuet',
      );
      expect(Rythmique.menuet.parCoup, lessThan(Rythmique.passacaille.parCoup));
      expect(
        Rythmique.passacaille.parCoup,
        lessThan(Rythmique.sarabande.parCoup),
        reason: 'la sarabande est la plus lente des trois temps',
      );
      expect(
        Rythmique.gigue.parCoup,
        lessThan(Rythmique.sicilienne.parCoup),
        reason: 'même mesure, mais la sicilienne se balance lentement',
      );
    });

    test('la durée d un temps suit le tempo', () {
      // 60 à la minute : une seconde pile.
      expect(Rythmique.sarabande.tempsParMin, 60);
      expect(Rythmique.sarabande.parCoup, const Duration(seconds: 1));
      // 120 : une demi-seconde.
      expect(Rythmique.gigue.parCoup, const Duration(milliseconds: 500));
    });

    test('l étiquette porte le nom et la mesure', () {
      expect(Rythmique.gavotte.etiquette, 'Gavotte 4/4');
    });

    test('elles voyagent en texte, et un nom inconnu ne fait pas tomber', () {
      for (final r in Rythmique.values) {
        expect(Rythmique.fromWire(r.name), r);
      }
      expect(Rythmique.fromWire('tango'), isNull);
      expect(Rythmique.fromWire(null), isNull);
    });
  });

  group('Le réglage : une danse OU une durée', () {
    test('à la main, la durée est celle du curseur', () {
      const t = TempoLecture.libre(2.5);
      expect(t.estLibre, isTrue);
      expect(t.parCoup, const Duration(milliseconds: 2500));
      expect(t.etiquette, '2.5 s');
    });

    test('une danse choisie impose sa vitesse', () {
      const t = TempoLecture.danse(Rythmique.marche);
      expect(
        t.estLibre,
        isFalse,
        reason: 'on ne règle plus la vitesse quand une rythmique est choisie',
      );
      expect(t.parCoup, Rythmique.marche.parCoup);
      expect(t.etiquette, contains('Marche 2/4'));
    });

    test('le défaut est une seconde, à la main', () {
      expect(TempoLecture.defaut.estLibre, isTrue);
      expect(TempoLecture.defaut.parCoup, const Duration(seconds: 1));
    });
  });

  group('Le curseur', () {
    test('il va de 0,5 à 5 secondes, par demi-secondes', () {
      expect(kVitesseMin, 0.5);
      expect(kVitesseMax, 5.0);
      expect(kVitessePas, 0.5);
      expect(kVitesseCrans, 10, reason: '0,5 à 5,0 fait dix crans');
    });

    test('chaque cran tombe sur une demi-seconde ronde', () {
      for (var i = 0; i < kVitesseCrans; i++) {
        final v = kVitesseMin + i * kVitessePas;
        expect(
          (v * 2) % 1,
          0,
          reason: '$v n est pas un multiple de ${kVitessePas}',
        );
        expect(v, lessThanOrEqualTo(kVitesseMax));
      }
    });
  });
}
