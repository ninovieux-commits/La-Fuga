/// Chronomètre : décompte, drapeau, affichage.
library;

import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:test/test.dart';

void main() {
  group('Affichage', () {
    test('format mm:ss', () {
      expect(GameClock.format(0), '00:00');
      expect(GameClock.format(59), '00:59');
      expect(GameClock.format(60), '01:00');
      expect(GameClock.format(180), '03:00');
      expect(GameClock.format(1800), '30:00');
      expect(GameClock.format(3599), '59:59');
    });

    test('sans chrono, on affiche le symbole infini', () {
      expect(GameClock.format(null), '∞');
    });

    test('un temps négatif est ramené à zéro', () {
      expect(GameClock.format(-5), '00:00');
    });
  });

  group('Décompte', () {
    test('seul le camp au trait perd du temps', () {
      final c = GameClock(Cadence.cinq);
      c.tick(Camp.blanc);
      c.tick(Camp.blanc);
      expect(c.remainingFor(Camp.blanc), 298);
      expect(c.remainingFor(Camp.noir), 300, reason: 'intact');
    });

    test('le camp qui atteint zéro est signalé une fois', () {
      final c = GameClock(const Cadence(3, 'test'));
      expect(c.tick(Camp.blanc), isNull);
      expect(c.tick(Camp.blanc), isNull);
      expect(c.tick(Camp.blanc), Camp.blanc, reason: 'le temps est écoulé');
      expect(c.remainingFor(Camp.blanc), 0);
    });

    test('le temps ne descend jamais sous zéro', () {
      final c = GameClock(const Cadence(1, 'test'));
      c.tick(Camp.blanc);
      c.tick(Camp.blanc);
      c.tick(Camp.blanc);
      expect(c.remainingFor(Camp.blanc), 0);
    });

    test('sans chrono, rien ne s écoule', () {
      final c = GameClock(Cadence.zen);
      expect(c.isUnlimited, isTrue);
      expect(c.tick(Camp.blanc), isNull);
      expect(c.remainingFor(Camp.blanc), isNull);
      expect(c.displayFor(Camp.blanc), '∞');
    });
  });

  group('Synchronisation et remise à zéro', () {
    test('on peut forcer le temps restant (synchro en ligne)', () {
      final c = GameClock(Cadence.quinze);
      c.setRemaining(Camp.noir, 123);
      expect(c.remainingFor(Camp.noir), 123);
      expect(c.displayFor(Camp.noir), '02:03');
    });

    test('une valeur nulle venue du réseau est ignorée', () {
      // Le serveur relaie `clock_adverse: null` quand il n'a rien reçu : on ne
      // doit pas écraser un chrono correct avec du vide.
      final c = GameClock(Cadence.quinze);
      c.setRemaining(Camp.noir, null);
      expect(c.remainingFor(Camp.noir), 900);
    });

    test('reset rend leur temps aux deux camps', () {
      final c = GameClock(Cadence.cinq);
      c.tick(Camp.blanc);
      c.tick(Camp.noir);
      c.reset();
      expect(c.remainingFor(Camp.blanc), 300);
      expect(c.remainingFor(Camp.noir), 300);
    });
  });

  test('les cadences sont celles de Kivy, valeurs transmises comprises', () {
    // Ce qui part au serveur doit être « 5 », « 15 », « 30 » ou « zen » :
    // un autre mot et le matchmaking n apparierait jamais deux joueurs.
    expect(Cadence.toutes.map((c) => c.wire), ['5', '15', '30']);
    expect(Cadence.toutes.map((c) => c.seconds), [300, 900, 1800]);
    expect(Cadence.zen.wire, 'zen');
    expect(Cadence.zen.seconds, isNull);
    expect(Cadence.parDefaut, Cadence.quinze);
    expect(Cadence.fromWire('30'), Cadence.trente);
    expect(Cadence.fromWire('zen'), Cadence.zen);
    expect(Cadence.fromWire('nawak'), Cadence.zen, reason: 'repli sans chrono');
    expect(Cadence.quinze.label, '15 min');
  });
}
