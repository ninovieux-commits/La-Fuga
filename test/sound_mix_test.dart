/// Le mixage d'un coup : c'est lui qui tient le tempo.
///
/// Les notes d'un coup ne sont pas déclenchées une par une — elles sont
/// mélangées dans un seul tampon, chaque retard devenant un décalage en
/// ÉCHANTILLONS. Deux coups identiques sonnent donc exactement pareil, quoi
/// que fasse l'interface au même moment. C'est ce contrat que ces tests
/// fixent : sans lui, une note se perdait puis tout repartait au coup suivant.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/pcm.dart';
import 'package:lafuga/game/sound_plan.dart';

void main() {
  const rate = 44100;

  /// Une banque dont chaque note est une impulsion unique : on retrouve donc
  /// exactement où chaque note a été posée.
  SoundBank impulses() {
    final notes = <String, Pcm>{};
    for (final note in kSoundNotes) {
      for (final octave in kSoundOctaves) {
        notes['$note$octave'] = Pcm(Int16List.fromList([32767]), rate);
      }
    }
    return SoundBank('test', notes, rate);
  }

  /// Positions des impulsions dans le tampon mixé.
  List<int> hits(Int16List mixed) => [
    for (var i = 0; i < mixed.length; i++)
      if (mixed[i] != 0) i,
  ];

  test('chaque note tombe à son échantillon exact', () {
    final cues = [
      const SoundCue('do2', Duration.zero),
      const SoundCue('re2', Duration(milliseconds: 250)),
      const SoundCue('mi2', Duration(milliseconds: 350)),
    ];
    final mixed = mixCues(cues, impulses(), 1)!;

    expect(hits(mixed), [0, 250 * rate ~/ 1000, 350 * rate ~/ 1000]);
  });

  test('le même coup donne toujours exactement le même tampon', () {
    final bank = impulses();
    final once = mixCues(planForNotation('Do1-Do2>'), bank, 1)!;
    final twice = mixCues(planForNotation('Do1-Do2>'), bank, 1)!;
    expect(once.length, twice.length);
    expect(hits(once), hits(twice));
  });

  test('un coup fait deux sons : le départ, puis l arrivée', () {
    // La poussée déclenchait un glissando de quatre notes à partir de
    // 250 ms. Trois d'entre elles ne correspondaient à aucune case, et
    // Nino les a supprimées : « les notes doivent correspondre aux notes
    // des cases ».
    final mixed = mixCues(planForNotation('Do1-Do2>'), impulses(), 1)!;
    final at = hits(mixed);
    expect(at, hasLength(2));
    expect(at.first, 0, reason: 'le départ, tout de suite');
    expect(at.last, 250 * rate ~/ 1000, reason: 'l arrivée, 250 ms après');
  });

  test('rien à jouer ne fabrique pas de tampon', () {
    expect(mixCues(const [], impulses(), 1), isNull);
    expect(mixCues(planForNotation(''), impulses(), 1), isNull);
  });

  test('une note inconnue est ignorée sans tout perdre', () {
    final cues = [
      const SoundCue('do2', Duration.zero),
      const SoundCue('trombone', Duration(milliseconds: 100)),
    ];
    expect(hits(mixCues(cues, impulses(), 1)!), [0]);
  });

  test('le mélange ne sature jamais', () {
    // Huit notes au même instant, au volume plein : le tampon doit rester
    // dans les bornes du 16 bits.
    final cues = [
      for (final note in kSoundNotes) SoundCue('${note}2', Duration.zero),
    ];
    final mixed = mixCues(cues, impulses(), 1)!;
    for (final v in mixed) {
      expect(v, lessThanOrEqualTo(32767));
      expect(v, greaterThanOrEqualTo(-32768));
    }
  });

  test('un WAV écrit se relit à l identique', () {
    final samples = Int16List.fromList([0, 1000, -1000, 32767, -32768]);
    final bytes = writeWav(samples, rate);
    final back = readWav(ByteData.sublistView(bytes))!;
    expect(back.rate, rate);
    expect(back.samples, samples);
  });

  test('un fichier qui n est pas un WAV ne fait pas tomber le jeu', () {
    expect(readWav(ByteData.sublistView(Uint8List(10))), isNull);
    expect(readWav(ByteData.sublistView(Uint8List(200))), isNull);
  });
}
