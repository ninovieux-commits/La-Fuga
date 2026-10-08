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
          r.pulsationsParMesure,
          r.tempsParMesure * r.pulsationsParTemps,
          reason: '${r.nom} : la mesure tombe juste en temps entiers',
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

  group('Les notes : une durée ET une force', () {
    test('la VALSE joue TROIS notes, la première tenue et appuyée', () {
      // « Fais les deux : trois notes, la première plus forte et tenue. »
      // Un temps et quart, puis trois quarts, puis un — et la mesure se
      // referme juste sur trois temps.
      final v = Rythmique.valse;
      expect(v.coupsParMesure, 3, reason: 'trois notes, pas deux');
      expect(v.ecarts, [
        5,
        3,
        4,
      ], reason: 'en double croches : 1,25 / 0,75 / 1');
      expect(v.forces.first, 1.0, reason: 'la première à pleine voix');
      expect(
        v.forces.sublist(1),
        everyElement(lessThan(1.0)),
        reason: 'les deux autres retenues : c est ça, l accent',
      );
      expect(
        v.ecarts.first,
        greaterThan(v.ecarts[1]),
        reason: 'la première est TENUE, plus longue que la deuxième',
      );
    });

    test('et la mesure de valse ne laisse AUCUN trou au bout', () {
      final v = Rythmique.valse;
      expect(v.pulsationsParMesure, 12, reason: 'trois temps de quatre');
      expect(v.tempsParMesure, 3);
      // À la microseconde près : douze pulsations arrondies ne font pas
      // exactement trois temps arrondis (1 058 820 µs contre 1 058 823). Trois
      // microsecondes sur une seconde, personne ne les entend — mais mieux
      // vaut l'écrire que de faire semblant que le compte tombe rond.
      expect(
        (v.parMesure - v.parTemps * 3).inMicroseconds.abs(),
        lessThan(1000),
      );
    });

    test('aucune danse ne laisse de trou, et chacune a sa pleine voix', () {
      for (final r in Rythmique.values) {
        expect(
          r.ecarts.fold<int>(0, (a, b) => a + b),
          r.pulsationsParMesure,
          reason: '${r.nom} : les durées d une mesure font la mesure',
        );
        expect(
          r.pulsationsParMesure % r.pulsationsParTemps,
          0,
          reason: '${r.nom} : la mesure doit tomber juste en temps entiers',
        );
        expect(
          r.forces,
          contains(1.0),
          reason: '${r.nom} : une note au moins doit sonner à pleine voix',
        );
      }
    });

    test('toutes accentuent leur premier temps, SAUF la sarabande', () {
      // C'est l'exception qui fait la danse : la sarabande appuie le DEUXIÈME.
      for (final r in Rythmique.values) {
        if (r == Rythmique.sarabande) continue;
        expect(r.forces.first, 1.0, reason: r.nom);
      }
      expect(Rythmique.sarabande.forces.first, lessThan(1.0));
      expect(Rythmique.sarabande.forces[1], 1.0);
    });

    test('aucune force ne dépasse 1 : le mélangeur y plafonne', () {
      // Monter au-dessus n'aurait aucun effet (`pcm.dart` borne à 1), et
      // laisserait croire à un accent qu'on n'entendrait pas.
      for (final r in Rythmique.values) {
        for (final f in r.forces) {
          expect(f, inInclusiveRange(0.0, 1.0), reason: r.nom);
        }
      }
    });

    test('chaque danse a un temps faible VRAIMENT plus faible', () {
      // Sans quoi l'accent ne s'entendrait pas : des notes toutes à 1 sonnent
      // comme un métronome, quelle que soit leur durée.
      for (final r in Rythmique.values) {
        expect(
          r.forces.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(0.9),
          reason: '${r.nom} : il faut un creux pour entendre la bosse',
        );
      }
    });

    test('la sarabande appuie et allonge son DEUXIÈME temps', () {
      // L'inverse de la valse : court et doux, puis long et fort.
      final s = Rythmique.sarabande;
      expect(s.ecarts, [1, 2]);
      expect(s.forces, [0.80, 1.0]);
    });

    test('la GIGUE galope sur ses croches', () {
      final g = Rythmique.gigue;
      expect(g.pulsationsParTemps, 3);
      expect(g.tempsParMesure, 2);
      expect(g.pulsationsParMesure, 6);
      expect(g.ecarts, [2, 1, 2, 1], reason: 'deux croches, une croche');
      expect(Rythmique.sicilienne.ecarts, [2, 1, 2, 1]);
    });

    test('les danses égales le sont en DURÉE, pas en force', () {
      // Le menuet, la marche et la gavotte avancent d un pas régulier : c est
      // l accent, et lui seul, qui les fait danser.
      for (final r in [Rythmique.menuet, Rythmique.marche, Rythmique.gavotte]) {
        expect(r.ecarts.toSet(), {1}, reason: '${r.nom} : des notes égales');
        expect(
          r.forces.toSet().length,
          greaterThan(1),
          reason: '${r.nom} : mais pas toutes au même volume',
        );
      }
    });

    test('en mesure simple sans subdivision, la pulsation EST le temps', () {
      for (final r in Rythmique.values) {
        if (r.pulsationsParTemps != 1) continue;
        expect(r.parPulsation, r.parTemps, reason: r.nom);
      }
    });

    test('le dessin se lit comme une partition', () {
      // `>` est le signe de l accent, et les durées sont en temps.
      expect(Rythmique.valse.motifEcrit, '>1,25  0,75  1');
      // Les chiffres sont des DURÉES en temps, pas des volumes : la première
      // note de la sarabande dure un temps, et c'est la seconde qui porte le
      // `>`.
      expect(Rythmique.sarabande.motifEcrit, '1  >2');
      // Trois notes d'un temps chacune : c'est le `>` seul qui dit laquelle
      // est appuyée.
      expect(Rythmique.menuet.motifEcrit, '>1  1  1');
      expect(Rythmique.gigue.motifEcrit, '>0,67  0,33  0,67  0,33');
    });

    test('le détail dit le tempo et le dessin', () {
      expect(Rythmique.valse.detail, contains('170/min'));
      expect(Rythmique.valse.detail, contains('>1,25'));
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

    test('la valse tient sa première note, puis presse les deux autres', () {
      const t = TempoLecture.danse(Rythmique.valse);
      expect(
        t.estLibre,
        isFalse,
        reason: 'on ne règle plus la vitesse quand une rythmique est choisie',
      );
      final pul = Rythmique.valse.parPulsation;
      expect(t.ecartAvant(0), pul * 5, reason: 'la note tenue : 1,25 temps');
      expect(t.ecartAvant(1), pul * 3, reason: '0,75 temps');
      expect(t.ecartAvant(2), pul * 4, reason: 'un temps');
      expect(t.ecartAvant(3), pul * 5, reason: 'la mesure suivante enchaîne');
      // Trois coups par mesure, et pas de trou.
      expect(
        t.ecartAvant(0) + t.ecartAvant(1) + t.ecartAvant(2),
        Rythmique.valse.parMesure,
      );
    });

    test('et elle appuie la première, en retenant les deux autres', () {
      const t = TempoLecture.danse(Rythmique.valse);
      expect(t.forceDe(0), 1.0);
      expect(t.forceDe(1), lessThan(1.0));
      expect(t.forceDe(2), lessThan(1.0));
      expect(t.forceDe(3), 1.0, reason: 'la mesure suivante réaccentue');
    });

    test('à la main, aucun coup n est plus fort qu un autre', () {
      const t = TempoLecture.libre(1.0);
      for (var n = 0; n < 5; n++) {
        expect(t.forceDe(n), 1.0);
      }
    });

    test('la gigue galope : deux croches, une croche', () {
      const t = TempoLecture.danse(Rythmique.gigue);
      final croche = Rythmique.gigue.parPulsation;
      expect(t.ecartAvant(0), croche * 2);
      expect(t.ecartAvant(1), croche);
      expect(t.ecartAvant(2), croche * 2);
      expect(t.ecartAvant(3), croche);
      expect(t.forceDe(0), 1.0, reason: 'le premier temps du galop');
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
