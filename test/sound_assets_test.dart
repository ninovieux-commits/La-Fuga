/// Les fichiers de son : tous là, au bon format, et de la bonne durée.
///
/// Les quatre instruments sont synthétisés par `tool/gen_sounds.py`. Ce test
/// est le garde-fou de cette fabrication : une note manquante rendrait un coup
/// muet, et une durée qui change déréglerait les arpèges.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/sound_plan.dart';

/// En-tête lu dans un fichier WAV.
typedef WavInfo = ({int rate, int channels, int bits, int frames});

WavInfo readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF', reason: path);
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE', reason: path);

  var offset = 12;
  int rate = 0, channels = 0, bits = 0, dataSize = 0;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'fmt ') {
      channels = data.getUint16(offset + 10, Endian.little);
      rate = data.getUint32(offset + 12, Endian.little);
      bits = data.getUint16(offset + 22, Endian.little);
    } else if (id == 'data') {
      dataSize = size;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  final bytesPerFrame = channels * (bits ~/ 8);
  return (
    rate: rate,
    channels: channels,
    bits: bits,
    frames: bytesPerFrame == 0 ? 0 : dataSize ~/ bytesPerFrame,
  );
}

void main() {
  /// Durée d'une note, en échantillons, par instrument. Elle fait le caractère
  /// de chacun : l'orgue est court parce qu'il ne meurt pas, la guitare tient
  /// plus longtemps.
  const noteFrames = {
    'piano': 44100,
    'guitare': 52920,
    'orgue': 35280,
    'cloche': 44100,
  };

  const octaves = [2, 3, 4, 5];
  const effects = [kSoundEjection, kSoundFugue, kSoundMat];

  test('chaque instrument a ses 28 notes et ses 3 effets', () {
    for (final instrument in kInstruments) {
      for (final note in kSoundNotes) {
        for (final octave in octaves) {
          final path = 'assets/sounds/$instrument/$note$octave.wav';
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
      for (final effect in effects) {
        final path = 'assets/sounds/$instrument/$effect.wav';
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    }
  });

  test('tout est en 44,1 kHz, mono, 16 bits', () {
    for (final instrument in kInstruments) {
      for (final file in Directory('assets/sounds/$instrument').listSync()) {
        if (!file.path.endsWith('.wav')) continue;
        final info = readWav(file.path);
        expect(info.rate, 44100, reason: file.path);
        expect(info.channels, 1, reason: file.path);
        expect(info.bits, 16, reason: file.path);
        expect(info.frames, greaterThan(1000), reason: file.path);
      }
    }
  });

  test('les notes gardent la durée de leur instrument', () {
    noteFrames.forEach((instrument, frames) {
      for (final note in kSoundNotes) {
        for (final octave in octaves) {
          final path = 'assets/sounds/$instrument/$note$octave.wav';
          expect(readWav(path).frames, frames, reason: path);
        }
      }
    });
  });

  test('un effet a la place de son arpège de quatre notes', () {
    // Quatre notes espacées de 0,12 s : la dernière commence à 0,36 s et doit
    // pouvoir sonner un peu. On exige au moins une demi-seconde.
    for (final instrument in kInstruments) {
      for (final effect in effects) {
        final path = 'assets/sounds/$instrument/$effect.wav';
        expect(readWav(path).frames, greaterThan(22050), reason: path);
      }
    }
  });
}
