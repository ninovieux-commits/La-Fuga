/// Tutoriel : les 21 étapes, et la machine à phases des étapes interactives.
library;

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/tuto.dart';
import 'package:test/test.dart';

/// Case du tuto, écrite comme dans les données : note + ligne 1..8.
Cell at(String note, int row) => Cell(kTutoNotes.indexOf(note), row - 1);

/// Première étape répondant à un critère.
int indexWhere(TutoController t, bool Function(TutoStep) test) =>
    t.steps.indexWhere(test);

void main() {
  group('Chargement', () {
    test('les 21 étapes sont là, dans l ordre', () {
      final steps = loadTutoSteps();

      expect(steps, hasLength(21));
      expect(steps.first.title, 'Le but du jeu');
      expect(steps[1].title, 'Le déplacement');
      expect(steps.last.title, 'Fin : la répétition');
    });

    test('ce qui coule de source n est plus enseigné', () {
      final steps = loadTutoSteps();

      expect(
        steps.map((s) => s.title),
        isNot(contains('Fin : abandon, temps, déco')),
        reason: 'abandon, temps et déco se devinent',
      );
      expect(
        steps.expand((s) => s.mockUi).map((m) => m.text),
        isNot(contains('½')),
        reason: 'la touche nulle n existe plus dans l app',
      );
      expect(
        steps.map((s) => s.text).join(' '),
        isNot(contains('proposer la nulle')),
      );
    });

    test('chaque étape a un texte à afficher', () {
      for (final s in loadTutoSteps()) {
        final hasText = s.interactive
            ? s.textSelect.isNotEmpty
            : s.text.isNotEmpty || (s.banner ?? '').isNotEmpty;
        expect(hasText, isTrue, reason: 'étape « ${s.title} »');
      }
    });

    test('la première étape pose la position de départ complète', () {
      final board = loadTutoSteps().first.board();

      var count = 0;
      for (var c = 0; c < kCols; c++) {
        for (var r = 0; r < kRows; r++) {
          if (board.at(c, r) != null) count++;
        }
      }
      expect(count, 30, reason: '14 pièces par camp + les deux Chevaliers');
      expect(
        board.at(at('fa', 1).col, at('fa', 1).row)!.type,
        PieceType.heritier,
      );
    });
  });

  group('Navigation', () {
    test('on avance et on recule', () {
      final t = TutoController();

      expect(t.atFirst, isTrue);
      expect(t.next(), isTrue);
      expect(t.index, 1);
      expect(t.previous(), isTrue);
      expect(t.index, 0);
      expect(t.previous(), isFalse, reason: 'déjà au début');
    });

    test(
      'une étape interactive bloque Suivant tant qu elle n est pas faite',
      () {
        final t = TutoController()..goTo(1);

        expect(t.step.interactive, isTrue);
        expect(t.canGoNext, isFalse);
        expect(t.next(), isFalse);

        t.tap(at('fa', 4));
        t.tap(at('fa', 3));
        t.tap(at('fa', 3));

        expect(t.stepDone, isTrue);
        expect(t.canGoNext, isTrue);
        expect(t.next(), isTrue);
      },
    );

    test('revenir sur une étape la recommence', () {
      final t = TutoController()..goTo(1);
      t.tap(at('fa', 4));
      expect(t.phase, TutoPhase.move);

      t.previous();
      t.next();

      expect(t.phase, TutoPhase.select);
      expect(t.selected, isNull);
      expect(t.board.at(at('fa', 4).col, at('fa', 4).row), isNotNull);
    });
  });

  group('Déplacement (étape 2)', () {
    late TutoController t;

    setUp(() => t = TutoController()..goTo(1));

    test('les trois temps du vrai jeu', () {
      expect(t.phase, TutoPhase.select);
      expect(t.text, contains('sélectionner'));

      expect(t.tap(at('fa', 4)), isTrue);
      expect(t.phase, TutoPhase.move);

      expect(t.tap(at('sol', 5)), isTrue);
      expect(t.phase, TutoPhase.validate);
      expect(t.board.at(at('fa', 4).col, at('fa', 4).row), isNull);
      expect(t.board.at(at('sol', 5).col, at('sol', 5).row), isNotNull);

      expect(t.tap(at('sol', 5)), isTrue);
      expect(t.phase, TutoPhase.done);
      expect(t.text, contains('Suivant'));
    });

    test('seul le coup prévu est possible', () {
      expect(t.tap(at('do', 1)), isFalse, reason: 'pas la bonne pièce');
      t.tap(at('fa', 4));
      expect(t.tap(at('do', 8)), isFalse, reason: 'pas une case voisine');
      expect(t.phase, TutoPhase.move);
    });

    test('recliquer la pièce avant de bouger la désélectionne', () {
      t.tap(at('fa', 4));
      expect(t.tap(at('fa', 4)), isTrue);
      expect(t.phase, TutoPhase.select);
      expect(t.selected, isNull);
    });
  });

  group('Multisaut (étape 4)', () {
    test('les sauts s enchaînent dans l ordre, et seulement dans l ordre', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.title == 'Le multisaut'));

      final sequence = t.step.sequence;
      expect(sequence.length, greaterThan(1));

      t.tap(t.step.move!);
      expect(t.phase, TutoPhase.move);

      // Sauter directement à la deuxième case ne marche pas.
      expect(t.tap(sequence[1].dest), isFalse);

      for (final s in sequence) {
        expect(t.tap(s.dest), isTrue);
      }
      expect(t.phase, TutoPhase.validate);

      t.tap(sequence.last.dest);
      expect(t.stepDone, isTrue);
    });
  });

  group('Fugue', () {
    test('sortir du plateau termine l étape tout de suite', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.title == 'Fuguer en sautant'));

      t.tap(t.step.move!);
      for (final s in t.step.sequence) {
        t.tap(s.dest);
      }

      expect(t.stepDone, isTrue, reason: 'pas de validation après une fugue');
      expect(t.fugued, hasLength(1));
      expect(t.fugued.single.cell.onBoard, isFalse);
    });
  });

  group('Manœuvre de groupe', () {
    test('meneuse, membres, puis déplacement en bloc', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.isManeuver));

      final leader = t.step.leader!;
      final group = t.step.groupAdd;
      final moveTo = t.step.moveTo!;
      final dc = moveTo.col - leader.col;
      final dr = moveTo.row - leader.row;

      expect(t.tap(leader), isTrue);
      expect(t.phase, TutoPhase.group);

      // Les membres s'ajoutent dans l'ordre prévu.
      if (group.length > 1) {
        expect(t.tap(group[1]), isFalse);
      }
      for (final g in group) {
        expect(t.tap(g), isTrue);
      }
      expect(t.phase, TutoPhase.groupMove);

      expect(t.tap(moveTo), isTrue);
      expect(t.phase, TutoPhase.validate);
      for (final g in group) {
        expect(
          t.board.at(g.col + dc, g.row + dr),
          isNotNull,
          reason: 'tout le groupe a suivi',
        );
      }

      t.tap(moveTo);
      expect(t.stepDone, isTrue);
    });
  });

  group('Poussée', () {
    test('sélectionner, avancer, pousser, valider', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.isPush && s.pushes.isEmpty));

      final leader = t.step.leader!;
      final moveTo = t.step.moveTo!;
      final pushTo = t.step.pushTo!;
      final pushed = t.board.at(pushTo.col, pushTo.row);

      t.tap(leader);
      expect(t.tap(moveTo), isTrue);
      expect(t.phase, TutoPhase.push);

      expect(t.tap(pushTo), isTrue);
      expect(t.phase, TutoPhase.validate);
      if (pushed != null) {
        final dc = pushTo.col - moveTo.col;
        final dr = pushTo.row - moveTo.row;
        expect(
          t.board.at(pushTo.col + dc, pushTo.row + dr),
          isNotNull,
          reason: 'la pièce poussée a reculé d une case',
        );
      }

      t.tap(moveTo);
      expect(t.stepDone, isTrue);
    });

    test('les poussées multiples s enchaînent', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.pushes.isNotEmpty));

      t.tap(t.step.leader!);
      t.tap(t.step.moveTo!);
      for (final p in t.step.pushes) {
        expect(t.tap(p.pushTo), isTrue, reason: 'poussée ${p.pushTo}');
      }
      expect(t.phase, TutoPhase.validate);
    });
  });

  group('Glissées', () {
    test('un déplacement dit quelle pièce va où', () {
      final t = TutoController();
      t.goTo(1);

      final depart = t.step.move!;
      final piece = t.board.at(depart.col, depart.row)!;
      final arrivee = t.step.dests.first;

      // Sélectionner ne déplace rien.
      t.tap(depart);
      expect(t.glissees, isEmpty);

      t.tap(arrivee);
      expect(t.glissees, hasLength(1));
      final (bougee, de, vers) = t.glissees.single;
      expect(bougee.type, piece.type);
      expect(bougee.camp, piece.camp);
      expect(de, depart);
      expect(vers, arrivee);

      // Valider ne rebouge rien : le plateau ne doit pas rejouer le coup.
      t.tap(arrivee);
      expect(t.glissees, isEmpty);
    });

    test('un saut glisse case par case', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.sequence.length > 1));

      t.tap(t.step.move!);
      var depart = t.step.move!;
      for (final saut in t.step.sequence) {
        t.tap(saut.dest);
        expect(t.glissees.map((g) => (g.$2, g.$3)), [
          (depart, saut.dest),
        ], reason: 'le saut vers ${saut.dest}');
        depart = saut.dest;
      }
    });

    test('la manœuvre fait glisser tout le groupe', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.isManeuver));

      final leader = t.step.leader!;
      final group = t.step.groupAdd;
      final moveTo = t.step.moveTo!;
      final dc = moveTo.col - leader.col;
      final dr = moveTo.row - leader.row;

      t.tap(leader);
      for (final g in group) {
        t.tap(g);
      }
      t.tap(moveTo);

      expect(t.glissees, hasLength(group.length + 1));
      for (final depart in [leader, ...group]) {
        expect(
          t.glissees.any(
            (g) =>
                g.$2 == depart &&
                g.$3 == Cell(depart.col + dc, depart.row + dr),
          ),
          isTrue,
          reason: 'la pièce de $depart a suivi le groupe',
        );
      }
    });

    test('la poussée glisse le pousseur puis la ligne', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.isPush && s.pushes.isEmpty));

      final leader = t.step.leader!;
      final moveTo = t.step.moveTo!;
      final pushTo = t.step.pushTo!;

      t.tap(leader);
      t.tap(moveTo);
      expect(t.glissees.map((g) => (g.$2, g.$3)), [(leader, moveTo)]);

      // La poussée est un second geste : le pousseur reste où il est, et
      // seule la ligne recule. Chaque tap n'anime que ce qu'il a fait.
      final dc = pushTo.col - moveTo.col;
      final dr = pushTo.row - moveTo.row;
      t.tap(pushTo);
      expect(
        t.glissees.map((g) => (g.$2, g.$3)),
        contains((pushTo, Cell(pushTo.col + dc, pushTo.row + dr))),
        reason: 'la pièce poussée recule d une case',
      );
      expect(
        t.glissees.every((g) => g.$2 != moveTo),
        isTrue,
        reason: 'le pousseur a déjà glissé au tap précédent',
      );
      for (final (_, de, vers) in t.glissees) {
        expect(
          (vers.col - de.col, vers.row - de.row),
          (dc, dr),
          reason: 'toute la ligne recule du même pas',
        );
      }
    });

    test('la fugue marchée glisse jusqu au ralliement', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.title == 'Fuguer en sautant'));

      t.tap(t.step.move!);
      for (final s in t.step.sequence) {
        t.tap(s.dest);
      }

      final sortie = t.fugued.single.cell;
      expect(t.glissees, hasLength(1));
      expect(t.glissees.single.$1.type, PieceType.heritier);
      expect(t.glissees.single.$3, sortie, reason: 'elle finit dans la zone');
    });

    test('changer d étape oublie la glissée précédente', () {
      final t = TutoController();
      t.goTo(1);
      t.tap(t.step.move!);
      t.tap(t.step.dests.first);
      expect(t.glissees, isNotEmpty);

      t.goTo(2);
      expect(t.glissees, isEmpty);
    });
  });

  group('Annotations', () {
    test('une étape d illustration montre ses encadrés', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.title == 'La règle de contact'));

      final ann = t.annotations;
      expect(ann.framedOk, isNotEmpty, reason: 'les pièces qui peuvent bouger');
      expect(ann.framed, isNotEmpty, reason: 'les pièces bloquées');
    });

    test('une étape interactive encadre la pièce à cliquer', () {
      final t = TutoController()..goTo(1);
      expect(t.annotations.framedSelected, [t.step.move]);
    });

    test('la flèche suit le saut courant', () {
      final t = TutoController();
      t.goTo(indexWhere(t, (s) => s.sequence.length > 1));
      t.tap(t.step.move!);

      expect(t.annotations.arrows.single.$2, t.step.sequence.first.dest);
      t.tap(t.step.sequence.first.dest);
      expect(t.annotations.arrows.single.$2, t.step.sequence[1].dest);
    });

    test('la bannière de transition existe', () {
      final t = TutoController();
      final i = indexWhere(t, (s) => s.banner != null);
      expect(i, isNot(-1));
      expect(t.steps[i].banner, contains('FIN DE PARTIE'));
    });

    test('plus aucune étape ne dessine de faux bouton', () {
      // Les deux seules qui en montraient — la touche « ½ » et l'étape
      // abandon / temps / déco — ont été retirées : montrer une touche que
      // l'app n'a plus enseignait un geste impossible. Le mécanisme reste,
      // et doit rester valide le jour où une étape s'en resservira.
      for (final s in loadTutoSteps()) {
        expect(s.mockUi, isEmpty, reason: 'étape « ${s.title} »');
        for (final m in s.mockUi) {
          expect(m.fw, greaterThan(0));
          expect(m.text, isNotEmpty);
        }
      }
    });
  });

  group('La règle de contact', () {
    /// L'étape qui montre en vert ce qui peut bouger et en rouge ce qui est
    /// bloqué.
    TutoStep etape() => TutoController().steps.firstWhere(
      (e) => e.title == 'La règle de contact',
    );

    test('les deux Nurses se touchent EN DIAGONALE', () {
      // Nino : « mets la nurse noire en ré 7, qu on comprenne que ça marche
      // aussi quand elles se touchent en diagonale. » Côte à côte, l étape
      // ne montrait que le contact par un côté.
      final b = etape().board();
      final noire = b.at(1, 6);
      final blanche = b.at(2, 5);
      expect(noire?.type, PieceType.nurse);
      expect(noire?.camp, Camp.noir);
      expect(blanche?.type, PieceType.nurse);
      expect(blanche?.camp, Camp.blanc);
    });

    test('et l encadré vert suit la Nurse qui a bougé', () {
      final cadres = etape().framedOk;
      expect(
        cadres,
        contains(const Cell(1, 6)),
        reason: 'la Nurse noire est en ré7 : c est elle qu on encadre',
      );
      expect(cadres, isNot(contains(const Cell(2, 6))));
    });

    test('les bloquées restent bloquées', () {
      // Les deux de la colonne sol n ont toujours personne de leur forme à
      // côté : le rouge ne bouge pas.
      final cadres = etape().framed;
      expect(cadres, contains(const Cell(4, 3)));
      expect(cadres, contains(const Cell(4, 4)));
    });
  });
}
