/// Les rythmiques de la lecture automatique.
///
/// Nino : « quand on choisit une rythmique, ça ne doit jouer un coup que
/// lorsque le temps est joué. Il doit donc y avoir les pauses. Valse 3/4 doit
/// se jouer comme une vraie valse 3 temps. »
///
/// Tout est là : une danse n'est pas un métronome. Ce qui la fait entendre, ce
/// sont les temps qu'elle NE joue pas.
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

    test('le motif compte autant de temps que la mesure en annonce', () {
      // Six croches, mais DEUX temps en 6/8 : le temps y est la noire pointée.
      // Une gigue qui jouerait six coups par mesure ne serait pas une gigue.
      for (final r in [Rythmique.gigue, Rythmique.sicilienne]) {
        expect(r.tempsParMesure, 2, reason: r.nom);
      }
      expect(Rythmique.valse.tempsParMesure, 3);
      expect(Rythmique.marche.tempsParMesure, 2);
      expect(Rythmique.gavotte.tempsParMesure, 4);
      for (final r in Rythmique.values) {
        expect(r.motif.length, r.tempsParMesure, reason: r.nom);
      }
    });

    test('chaque danse a son tempo, et il diffère de celui du voisin', () {
      // Deux 3/4 qui iraient à la même vitesse seraient la même chose.
      expect(
        Rythmique.valse.parTemps,
        lessThan(Rythmique.menuet.parTemps),
        reason: 'une valse va plus vite qu un menuet',
      );
      expect(
        Rythmique.menuet.parTemps,
        lessThan(Rythmique.passacaille.parTemps),
      );
      expect(
        Rythmique.passacaille.parTemps,
        lessThan(Rythmique.sarabande.parTemps),
        reason: 'la sarabande est la plus lente des trois temps',
      );
      expect(
        Rythmique.gigue.parTemps,
        lessThan(Rythmique.sicilienne.parTemps),
        reason: 'même mesure, mais la sicilienne se balance lentement',
      );
    });

    test('la durée d un temps suit le tempo', () {
      // 60 à la minute : une seconde pile.
      expect(Rythmique.sarabande.tempsParMin, 60);
      expect(Rythmique.sarabande.parTemps, const Duration(seconds: 1));
      // 120 : une demi-seconde.
      expect(Rythmique.gigue.parTemps, const Duration(milliseconds: 500));
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

  group('Les pauses : une danse n est pas un métronome', () {
    test('la valse joue SON PREMIER temps, et se tait sur les deux autres', () {
      expect(Rythmique.valse.motif, [true, false, false]);
      expect(
        Rythmique.valse.coupsParMesure,
        1,
        reason: 'une valse qui jouerait ses trois temps serait un métronome',
      );
      // Et le coup suivant tombe une MESURE plus loin, pas un temps.
      expect(Rythmique.valse.ecarts, [3]);
    });

    test('toutes partent du premier temps, et aucune ne reste muette', () {
      final avecPause = Rythmique.values.where(
        (r) => r.motif.any((joue) => !joue),
      );
      expect(avecPause, isNotEmpty, reason: 'sans pause, pas de danse');
      for (final r in Rythmique.values) {
        expect(
          r.coupsParMesure,
          greaterThan(0),
          reason: '${r.nom} ne joue aucun coup : la lecture n avancerait pas',
        );
        expect(
          r.motif.first,
          isTrue,
          reason: '${r.nom} doit jouer son premier temps',
        );
      }
    });

    test('la sarabande BOITE : un temps, puis deux', () {
      // Elle appuie son deuxième temps. C'est ce qui la rend reconnaissable, et
      // c'est le seul endroit où les écarts ne sont pas tous égaux.
      expect(Rythmique.sarabande.motif, [true, true, false]);
      expect(Rythmique.sarabande.ecarts, [1, 2]);
    });

    test('les écarts bouclent avec la mesure', () {
      for (final r in Rythmique.values) {
        expect(
          r.ecarts.length,
          r.coupsParMesure,
          reason: '${r.nom} : un écart par coup joué',
        );
        expect(
          r.ecarts.fold<int>(0, (a, b) => a + b),
          r.tempsParMesure,
          reason: '${r.nom} : les écarts d une mesure font la mesure',
        );
      }
    });

    test('la gavotte marque un et trois', () {
      expect(Rythmique.gavotte.motif, [true, false, true, false]);
      expect(Rythmique.gavotte.ecarts, [2, 2]);
    });

    test('la marche marque ses deux temps : le pas gauche-droite', () {
      expect(Rythmique.marche.motif, [true, true]);
      expect(Rythmique.marche.ecarts, [1, 1]);
    });

    test('le motif s écrit avec ses pauses', () {
      expect(Rythmique.valse.motifEcrit, '1 · ·');
      expect(Rythmique.sarabande.motifEcrit, '1 2 ·');
      expect(Rythmique.gavotte.motifEcrit, '1 · 3 ·');
      expect(Rythmique.marche.motifEcrit, '1 2');
    });

    test('le détail dit le tempo, le motif et les coups par mesure', () {
      expect(Rythmique.valse.detail, contains('170/min'));
      expect(Rythmique.valse.detail, contains('1 · ·'));
      expect(Rythmique.valse.detail, contains('1 coup par mesure'));
      expect(Rythmique.marche.detail, contains('2 coups par mesure'));
    });
  });

  group('Le réglage : une danse OU une durée', () {
    test('à la main, la durée est celle du curseur, à chaque coup', () {
      const t = TempoLecture.libre(2.5);
      expect(t.estLibre, isTrue);
      for (var n = 0; n < 5; n++) {
        expect(t.ecartAvant(n), const Duration(milliseconds: 2500));
      }
      expect(t.etiquette, '2.5 s');
    });

    test('une valse attend une MESURE entière entre deux coups', () {
      const t = TempoLecture.danse(Rythmique.valse);
      expect(
        t.estLibre,
        isFalse,
        reason: 'on ne règle plus la vitesse quand une rythmique est choisie',
      );
      for (var n = 0; n < 4; n++) {
        expect(
          t.ecartAvant(n),
          Rythmique.valse.parMesure,
          reason: 'coup $n : trois temps, dont deux de pause',
        );
      }
    });

    test('la sarabande alterne un temps et deux, indéfiniment', () {
      const t = TempoLecture.danse(Rythmique.sarabande);
      const temps = Duration(seconds: 1); // 60 à la minute
      expect(t.ecartAvant(0), temps);
      expect(t.ecartAvant(1), temps * 2);
      expect(t.ecartAvant(2), temps, reason: 'la mesure suivante recommence');
      expect(t.ecartAvant(3), temps * 2);
    });

    test('l étiquette d une danse la nomme', () {
      expect(
        const TempoLecture.danse(Rythmique.marche).etiquette,
        'Marche 2/4',
      );
    });

    test('le défaut est une seconde, à la main', () {
      expect(TempoLecture.defaut.estLibre, isTrue);
      expect(TempoLecture.defaut.ecartAvant(0), const Duration(seconds: 1));
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
          reason: '$v n est pas un multiple de $kVitessePas',
        );
        expect(v, lessThanOrEqualTo(kVitesseMax));
      }
    });
  });
}
