/// Les rythmiques de la lecture automatique.
///
/// Nino : « quand on joue une valse en trois temps, on ne joue des notes que
/// sur les trois premiers temps puis on attend sur un temps […] C'est bien ça
/// ou c'est plutôt une note longue qui dure deux temps ? J'aimerai que la
/// lecture imite la valse simplement. »
///
/// C'est la note longue. Trois notes puis une attente feraient QUATRE temps —
/// une mesure à 4/4 avec un silence au bout, pas une valse. Ce qui fait
/// entendre une danse, c'est la longueur INÉGALE de ses notes : long, court,
/// long, court pour la valse ; court, long pour la sarabande ; le galop de la
/// gigue sur ses croches.
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

    test('la mesure compte le bon nombre de temps', () {
      // Six croches, mais DEUX temps en 6/8 : le temps y est la noire pointée.
      for (final r in [Rythmique.gigue, Rythmique.sicilienne]) {
        expect(r.tempsParMesure, 2, reason: r.nom);
      }
      expect(Rythmique.valse.tempsParMesure, 3);
      expect(Rythmique.marche.tempsParMesure, 2);
      expect(Rythmique.gavotte.tempsParMesure, 4);
      for (final r in Rythmique.values) {
        expect(
          r.motif.length,
          r.tempsParMesure * r.pulsationsParTemps,
          reason: r.nom,
        );
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
      // La gigue : 80 noires pointées à la minute, donc 0,75 s par temps, et
      // le tiers par croche.
      expect(Rythmique.gigue.parTemps, const Duration(milliseconds: 750));
      expect(Rythmique.gigue.parPulsation, const Duration(milliseconds: 250));
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

  group('Les notes longues et les courtes : la danse', () {
    test('la VALSE tient son premier temps deux temps durant', () {
      // La réponse à la question de Nino. Une note tenue deux temps, puis une
      // sur le troisième : ONE—— deux-trois. Pas trois notes puis une attente,
      // qui ferait quatre temps.
      expect(Rythmique.valse.motif, [true, false, true]);
      expect(Rythmique.valse.ecarts, [2, 1], reason: 'long, court');
      expect(Rythmique.valse.coupsParMesure, 2);
    });

    test('et la mesure de valse ne laisse AUCUN trou au bout', () {
      // Le piège : un écart de plus que la mesure ne contient de temps, c est
      // le silence qui ferait d elle une mesure à quatre temps.
      final r = Rythmique.valse;
      expect(
        r.ecarts.fold<int>(0, (a, b) => a + b),
        r.pulsationsParMesure,
        reason: 'la mesure suivante enchaîne sans attendre',
      );
      expect(r.parMesure, r.parTemps * 3);
    });

    test('aucune danse ne laisse de trou au bout de sa mesure', () {
      for (final r in Rythmique.values) {
        expect(
          r.ecarts.fold<int>(0, (a, b) => a + b),
          r.pulsationsParMesure,
          reason: '${r.nom} : les écarts d une mesure font la mesure',
        );
        expect(
          r.ecarts.length,
          r.coupsParMesure,
          reason: '${r.nom} : un écart par note frappée',
        );
        expect(
          r.motif.first,
          isTrue,
          reason: '${r.nom} doit frapper son premier temps',
        );
      }
    });

    test('la sarabande est l INVERSE de la valse : court, puis long', () {
      // Elle appuie et allonge son DEUXIÈME temps.
      expect(Rythmique.sarabande.motif, [true, true, false]);
      expect(Rythmique.sarabande.ecarts, [1, 2]);
    });

    test('la GIGUE galope sur ses croches', () {
      // En 6/8 le temps est la noire pointée — deux par mesure — mais la gigue
      // s écrit en croches : une note de deux croches, une d une. Sans cette
      // division, elle ne serait qu un pouls à deux.
      expect(Rythmique.gigue.pulsationsParTemps, 3);
      expect(Rythmique.gigue.tempsParMesure, 2);
      expect(Rythmique.gigue.pulsationsParMesure, 6);
      expect(Rythmique.gigue.motif, [true, false, true, true, false, true]);
      expect(Rythmique.gigue.ecarts, [2, 1, 2, 1], reason: 'le galop');
      expect(Rythmique.sicilienne.ecarts, [2, 1, 2, 1]);
    });

    test('les danses égales le sont vraiment', () {
      // Toutes ne boitent pas : le menuet, la marche et la gavotte avancent
      // d un pas régulier, et c est leur caractère.
      expect(Rythmique.menuet.ecarts, [1, 1, 1]);
      expect(Rythmique.marche.ecarts, [1, 1]);
      expect(Rythmique.gavotte.ecarts, [1, 1, 1, 1]);
    });

    test('mais la moitié des danses boitent, sinon ce serait un métronome', () {
      final boiteuses = Rythmique.values.where(
        (r) => r.ecarts.toSet().length > 1,
      );
      expect(
        boiteuses.length,
        greaterThanOrEqualTo(4),
        reason: 'valse, sarabande, passacaille, gigue, sicilienne',
      );
    });

    test('en mesure simple, la pulsation EST le temps', () {
      for (final r in Rythmique.values) {
        if (r.mesure.endsWith('/8')) continue;
        expect(r.pulsationsParTemps, 1, reason: r.nom);
        expect(r.parPulsation, r.parTemps, reason: r.nom);
      }
    });

    test('le motif s écrit avec ses prolongements', () {
      expect(Rythmique.valse.motifEcrit, '1 · 3');
      expect(Rythmique.sarabande.motifEcrit, '1 2 ·');
      expect(Rythmique.menuet.motifEcrit, '1 2 3');
      expect(Rythmique.gigue.motifEcrit, '1 · 3 4 · 6');
    });

    test('le détail dit le tempo et le motif', () {
      expect(Rythmique.valse.detail, contains('170/min'));
      expect(Rythmique.valse.detail, contains('1 · 3'));
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

    test('la valse alterne un temps long et un court, indéfiniment', () {
      const t = TempoLecture.danse(Rythmique.valse);
      expect(
        t.estLibre,
        isFalse,
        reason: 'on ne règle plus la vitesse quand une rythmique est choisie',
      );
      final temps = Rythmique.valse.parTemps;
      expect(t.ecartAvant(0), temps * 2, reason: 'la note tenue');
      expect(t.ecartAvant(1), temps, reason: 'le troisième temps');
      expect(t.ecartAvant(2), temps * 2, reason: 'la mesure suivante enchaîne');
      expect(t.ecartAvant(3), temps);
      // Deux coups par mesure, et pas de trou : deux écarts font la mesure.
      expect(t.ecartAvant(0) + t.ecartAvant(1), Rythmique.valse.parMesure);
    });

    test('la gigue galope : deux croches, une croche', () {
      const t = TempoLecture.danse(Rythmique.gigue);
      final croche = Rythmique.gigue.parPulsation;
      expect(t.ecartAvant(0), croche * 2);
      expect(t.ecartAvant(1), croche);
      expect(t.ecartAvant(2), croche * 2);
      expect(t.ecartAvant(3), croche);
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
