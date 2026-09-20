/// Match en plusieurs parties : score, alternance des couleurs, et la règle
/// de l'ultime partie.
library;

import 'package:lafuga/game/match_play.dart';
import 'package:test/test.dart';

FugaMatch matchOf({String target = '3', String? firstBlanc}) => FugaMatch(
  playerA: 'Nino',
  playerB: 'Ana',
  target: target,
  firstBlanc: firstBlanc,
);

void main() {
  group('Partie unique', () {
    test('rien ne s enchaîne', () {
      final m = matchOf(target: 'partie');
      final step = m.record(winner: 'Nino', points: 2);

      expect(step.outcome, MatchOutcome.singleGame);
      expect(m.isSingleGame, isTrue);
    });
  });

  group('Score', () {
    test('la fin de partie rapporte ses points', () {
      final m = matchOf();

      m.record(winner: 'Nino', points: 1); // mat
      m.record(winner: 'Nino', points: 2); // fugue

      expect(m.scores['Nino'], 3);
      expect(m.scores['Ana'], 0);
    });

    test('une nulle ne rapporte rien à personne', () {
      final m = matchOf();
      final step = m.record(points: 0);

      expect(m.scores['Nino'], 0);
      expect(m.scores['Ana'], 0);
      expect(step.outcome, MatchOutcome.next);
    });
  });

  group('Alternance des couleurs', () {
    test('les Blancs changent de main à chaque partie', () {
      final m = matchOf(firstBlanc: 'Nino');
      expect(m.playedBlanc['Nino'], 1);

      final step = m.record(winner: 'Nino', points: 1);
      expect(step.nextFirstBlanc, 'Ana');

      m.startNext(step.nextFirstBlanc!);
      expect(m.firstBlanc, 'Ana');
      expect(m.playedBlanc['Ana'], 1);
    });
  });

  group('Fin du match', () {
    test('atteindre la cible à égalité de Blancs termine le match', () {
      final m = matchOf(target: '2', firstBlanc: 'Nino');

      // Nino gagne la première, Ana prend les Blancs, Nino gagne encore :
      // chacun a tenu les Blancs une fois.
      var step = m.record(winner: 'Nino', points: 1);
      m.startNext(step.nextFirstBlanc!);
      step = m.record(winner: 'Nino', points: 1);

      expect(step.outcome, MatchOutcome.over);
      expect(step.winner, 'Nino');
    });

    test(
      'celui qui a eu moins souvent les Blancs a droit à une ultime partie',
      () {
        final m = matchOf(target: '1', firstBlanc: 'Nino');

        final step = m.record(winner: 'Nino', points: 2);

        // Nino a mené ET tenu les Blancs une fois de plus qu'Ana.
        expect(step.outcome, MatchOutcome.next);
        expect(step.lastChance, isTrue);
        expect(step.nextFirstBlanc, 'Ana', reason: 'Blancs au retardataire');
        expect(m.lastChance, isTrue);
      },
    );

    test('l ultime partie égalise : on rejoue, personne ne mène', () {
      // Comme en Kivy : la fin du match demande un joueur DEVANT l'autre. À
      // égalité, le match continue — l'ultime partie a servi à rattraper.
      final m = matchOf(target: '1', firstBlanc: 'Nino');
      var step = m.record(winner: 'Nino', points: 2);
      m.startNext(step.nextFirstBlanc!);

      step = m.record(winner: 'Ana', points: 2);

      expect(step.outcome, MatchOutcome.next);
      expect(m.scores['Nino'], m.scores['Ana']);
    });

    test('une fois l ultime partie passée, le premier devant l emporte', () {
      final m = matchOf(target: '1', firstBlanc: 'Nino');
      var step = m.record(winner: 'Nino', points: 2);
      m.startNext(step.nextFirstBlanc!);
      step = m.record(winner: 'Ana', points: 2); // 2-2, on rejoue
      m.startNext(step.nextFirstBlanc!);

      step = m.record(winner: 'Ana', points: 1);

      expect(step.outcome, MatchOutcome.over);
      expect(step.winner, 'Ana');
    });

    test('l ultime partie ne suffit pas : le meneur l emporte', () {
      final m = matchOf(target: '1', firstBlanc: 'Nino');
      var step = m.record(winner: 'Nino', points: 2);
      m.startNext(step.nextFirstBlanc!);

      step = m.record(winner: 'Ana', points: 1);

      expect(step.outcome, MatchOutcome.over);
      expect(step.winner, 'Nino');
    });

    test('tant que personne n atteint la cible, on continue', () {
      final m = matchOf(target: '5');

      for (var i = 0; i < 3; i++) {
        final step = m.record(winner: 'Nino', points: 1);
        expect(step.outcome, MatchOutcome.next);
        m.startNext(step.nextFirstBlanc!);
      }
      expect(m.scores['Nino'], 3);
    });
  });

  test('le score s affiche dans l ordre des joueurs', () {
    final m = matchOf();
    m.record(winner: 'Ana', points: 2);

    expect(m.scoreLine, 'Nino : 0    Ana : 2');
  });
}
