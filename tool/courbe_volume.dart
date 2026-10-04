// La courbe d'atténuation, note par note, et le plus grand saut entre deux
// notes voisines. Un glissando les parcourt à la suite : une marche s'entend.
import 'dart:io';
import 'dart:math' as math;

import 'package:lafuga/game/sound_plan.dart';

void main() {
  var pireSaut = 0.0;
  String ou = '';
  double? precedent;
  for (var i = 0; i < 28; i++) {
    final nom = '${kSoundNotes[i % 7]}${2 + i ~/ 7}';
    final g = volumeFactorFor(nom);
    final db = 20 * (math.log(g) / math.ln10);
    if (precedent != null) {
      final saut = (db - precedent).abs();
      if (saut > pireSaut) {
        pireSaut = saut;
        ou = nom;
      }
    }
    precedent = db;
    stdout.writeln(
      '${nom.padRight(5)} ${g.toStringAsFixed(3)}  '
      '${db.toStringAsFixed(2)} dB',
    );
  }
  stdout.writeln(
    '\nplus grand écart entre deux notes voisines : '
    '${pireSaut.toStringAsFixed(2)} dB (avant $ou)',
  );
}
