// Banc d'essai du mixage d'un coup — lancé à la main.
import 'dart:typed_data';
import 'package:lafuga/game/pcm.dart';
import 'package:lafuga/game/sound_plan.dart';

void main() {
  const rate = 44100;
  final notes = <String, Pcm>{};
  for (final n in kSoundNotes) {
    for (final o in kSoundOctaves) {
      // Une note de guitare : la plus longue (1,2 s).
      notes['$n$o'] = Pcm(Int16List(rate * 12 ~/ 10), rate);
    }
  }
  final bank = SoundBank('bench', notes, rate);
  final cues = planForNotation('Do1-Do2>'); // 5 notes, le pire des cas

  for (var i = 0; i < 50; i++) {
    final m = mixCues(cues, bank, 1.0)!;
    writeWav(m, rate);
  }
  final times = <int>[];
  for (var run = 0; run < 7; run++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      final m = mixCues(cues, bank, 1.0)!;
      writeWav(m, rate);
    }
    times.add(sw.elapsedMicroseconds ~/ 50);
  }
  times.sort();
  print('mixage + écriture d un coup : ${times[3]} µs (médiane)  $times');
}
