/// Sons : chaque coup doit s'entendre correctement, sans jamais ouvrir de
/// fichier audio. Seule la décision musicale est testée ici.
library;

import 'dart:math' as math;

import 'package:lafuga/game/sound_plan.dart';
import 'package:test/test.dart';

void main() {
  group('Correspondance case → note', () {
    test('les colonnes portent les sept notes', () {
      expect(noteForCell(0, 2), startsWith('do'));
      expect(noteForCell(1, 2), startsWith('re'), reason: 'sans accent');
      expect(noteForCell(2, 2), startsWith('mi'));
      expect(noteForCell(3, 2), startsWith('fa'));
      expect(noteForCell(4, 2), startsWith('sol'));
      expect(noteForCell(5, 2), startsWith('la'));
      expect(noteForCell(6, 2), startsWith('si'));
    });

    test('les rangées donnent les octaves', () {
      expect(octaveForRow(0), 5, reason: 'rangée 1');
      expect(octaveForRow(7), 5, reason: 'rangée 8');
      expect(octaveForRow(1), 4);
      expect(octaveForRow(6), 4);
      expect(octaveForRow(2), 3);
      expect(octaveForRow(5), 3);
      expect(octaveForRow(3), 5, reason: 'rangée 4');
      expect(octaveForRow(4), 5, reason: 'rangée 5');
    });

    test('la correspondance est symétrique entre les deux camps', () {
      for (var row = 0; row < 4; row++) {
        expect(
          octaveForRow(row),
          octaveForRow(7 - row),
          reason: 'rangées $row et ${7 - row}',
        );
      }
    });

    test('une colonne hors plateau ne donne pas de note', () {
      expect(noteForCell(7, 0), isNull);
      expect(noteForCell(-1, 0), isNull);
    });
  });

  group('Volume par octave', () {
    test('les aigus sont atténués, les graves servent de référence', () {
      // `closeTo` : l'atténuation est désormais CALCULÉE entre les repères,
      // et non plus lue dans une table. Le résultat tombe sur les mêmes
      // valeurs, au bruit de calcul près.
      expect(volumeFactorFor('do2'), closeTo(1.0, 1e-9));
      expect(volumeFactorFor('do3'), closeTo(0.80, 1e-9));
      expect(volumeFactorFor('do4'), closeTo(0.55, 1e-9));
      expect(volumeFactorFor('do5'), closeTo(0.40, 1e-9));
    });

    test('un nom sans octave garde le volume plein', () {
      expect(volumeFactorFor('do'), 1.0);
      expect(volumeFactorFor(''), 1.0);
      expect(volumeFactorFor('ejection'), 1.0);
      expect(volumeFactorFor('xx9'), 1.0);
    });
  });

  group('Un glissando garde le même son d un bout à l autre', () {
    // Nino : « pense aux glissandos qui doivent avoir le même son ».
    //
    // L'atténuation se lisait sur le seul CHIFFRE de l'octave : les sept
    // notes de l'octave 3 sortaient toutes à 0,80, puis do4 tombait d'un coup
    // à 0,55. Un glissando parcourt des notes CONSÉCUTIVES ; dès qu'il
    // franchissait une frontière d'octave, il décrochait de 3,25 dB en plein
    // milieu.

    double db(String note) =>
        20 * (math.log(volumeFactorFor(note)) / math.ln10);

    List<String> toute() => [
      for (var i = 0; i < 28; i++) '${kSoundNotes[i % 7]}${2 + i ~/ 7}',
    ];

    test('aucune marche : deux notes voisines ne sautent jamais', () {
      final notes = toute();
      var pire = 0.0;
      var ou = '';
      for (var i = 1; i < notes.length; i++) {
        final saut = (db(notes[i]) - db(notes[i - 1])).abs();
        if (saut > pire) {
          pire = saut;
          ou = '${notes[i - 1]} → ${notes[i]}';
        }
      }
      expect(
        pire,
        lessThan(0.5),
        reason: 'marche de ${pire.toStringAsFixed(2)} dB entre $ou',
      );
    });

    test('et la course descend sans jamais remonter', () {
      final notes = toute();
      for (var i = 1; i < notes.length; i++) {
        expect(
          volumeFactorFor(notes[i]),
          lessThan(volumeFactorFor(notes[i - 1])),
          reason: '${notes[i]} ne descend pas sous ${notes[i - 1]}',
        );
      }
    });

    test('celui qui franchit une octave est aussi régulier que les autres', () {
      // la3 si3 do4 re4 : c'est le cas qui décrochait.
      final atravers = ['la3', 'si3', 'do4', 're4'];
      final dedans = ['do3', 're3', 'mi3', 'fa3'];
      double amplitude(List<String> notes) =>
          (db(notes.last) - db(notes.first)).abs();
      expect(
        (amplitude(atravers) - amplitude(dedans)).abs(),
        lessThan(0.3),
        reason:
            'le glissando à cheval sur deux octaves doit sonner comme '
            'les autres, pas décrocher au passage',
      );
    });

    test('les quatre repères réglés à l oreille sont intacts', () {
      // La continuité ne devait rien changer là où Nino avait réglé.
      expect(volumeFactorFor('do2'), closeTo(1.0, 1e-9));
      expect(volumeFactorFor('do3'), closeTo(0.80, 1e-9));
      expect(volumeFactorFor('do4'), closeTo(0.55, 1e-9));
      expect(volumeFactorFor('do5'), closeTo(0.40, 1e-9));
    });

    test('et tout glissando produit tient dans la gamme', () {
      for (var col = 0; col < 7; col++) {
        for (var row = 0; row < 8; row++) {
          for (final sens in [1, -1]) {
            for (final note in glissandoNotes(col, row, 4, sens)) {
              expect(
                noteIndexOf(note),
                isNotNull,
                reason: '« $note » n est pas une note de la banque',
              );
            }
          }
        }
      }
    });
  });

  group('Glissando', () {
    test('la dernière note est celle de la case cible', () {
      final notes = glissandoNotes(3, 4, 4, 1);
      expect(notes.length, 4);
      expect(notes.last, noteForCell(3, 4));
    });

    test('montant et descendant encadrent la cible', () {
      final up = glissandoNotes(3, 4, 4, 1);
      final down = glissandoNotes(3, 4, 4, -1);
      expect(up.last, down.last, reason: 'même arrivée');
      expect(up.first, isNot(down.first), reason: 'départs opposés');
    });

    test('on reste dans la gamme même au bord du plateau', () {
      for (final direction in [1, -1]) {
        for (final (col, row) in [(0, 0), (6, 7), (0, 7), (6, 0)]) {
          final notes = glissandoNotes(col, row, 4, direction);
          expect(notes.length, 4);
          for (final n in notes) {
            expect(kSoundNotes.any(n.startsWith), isTrue, reason: n);
          }
        }
      }
    });
  });

  group('Plan sonore d un coup', () {
    test('déplacement simple : départ puis arrivée', () {
      final cues = planForNotation('Fa2-Fa3');
      expect(cues.length, 2);
      expect(cues[0].name, noteForCell(3, 1));
      expect(cues[0].delay, Duration.zero);
      expect(cues[1].name, noteForCell(3, 2));
      expect(cues[1].delay, const Duration(milliseconds: 250));
    });

    test('poussée : glissando montant vers l arrivée', () {
      final cues = planForNotation('Do1-Do2>');
      expect(cues.first.delay, Duration.zero, reason: 'note de départ');
      // Une note de départ plus quatre notes de glissando.
      expect(cues.length, 5);
      expect(cues.last.name, noteForCell(0, 1), reason: 'arrive sur la cible');
    });

    test('manœuvre : note de la maîtresse puis glissando descendant', () {
      final cues = planForNotation('(Do1Ré1)-Do2');
      expect(cues.first.name, noteForCell(0, 0));
      expect(cues.length, 5);
      expect(cues.last.name, noteForCell(0, 1));
    });

    test('fugue : la seule note de la case de départ', () {
      // Les arpèges d'éjection, de fugue et de mat ne sonnent plus : c'était
      // du code mort dans l'application Kivy.
      final cues = planForNotation('Fa7*');
      expect(cues.length, 1);
      expect(cues.single.name, noteForCell(3, 6));
    });

    test('aucun son ne s ajoute pour une éjection ou un mat', () {
      final simple = planForNotation('Do1-Do2');
      expect(planForNotation('Do1-Do2#'), hasLength(simple.length));
      expect(
        planForNotation('Do1-Do2#').first.name,
        noteForCell(0, 0),
        reason: 'le coup lui-même reste audible',
      );
    });

    test('tous les sons d un coup sont des notes du plateau', () {
      for (final n in ['Do1-Do2', 'Do1-Do2>', '(Do1Ré1)-Do2', 'Fa7*']) {
        for (final cue in planForNotation(n)) {
          expect(
            kSoundNotes.any(cue.name.startsWith),
            isTrue,
            reason: '$n -> ${cue.name}',
          );
        }
      }
    });

    test('aucun son pour une notation vide ou absente', () {
      expect(planForNotation(null), isEmpty);
      expect(planForNotation(''), isEmpty);
      expect(planForNotation('   '), isEmpty);
    });

    test(
      'une notation incompréhensible reste silencieuse plutôt que fausse',
      () {
        expect(planForNotation('n importe quoi'), isEmpty);
      },
    );

    test('les sons sont ordonnés dans le temps', () {
      for (final notation in [
        'Fa2-Fa3',
        'Do1-Do2>',
        '(Do1Ré1)-Do2',
        'Fa7*',
        'Do1-Do2#',
      ]) {
        final cues = planForNotation(notation);
        for (var i = 1; i < cues.length; i++) {
          expect(
            cues[i].delay,
            greaterThanOrEqualTo(cues[i - 1].delay),
            reason: '$notation : le son $i arrive avant le précédent',
          );
        }
      }
    });
  });

  test('les quatre instruments sont déclarés', () {
    expect(kInstruments, ['piano', 'orgue', 'guitare', 'cloche']);
  });
}
