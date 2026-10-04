/// Les fichiers de son : tous là, au bon format, et dans les bonnes bornes.
///
/// Les quatre instruments sont synthétisés par `tool/gen_sounds.py`. Ce test
/// est le garde-fou de cette fabrication : une note manquante rendrait un coup
/// muet, et une durée qui change déréglerait les arpèges.
library;

import 'dart:io';
import 'dart:math' as math;
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
  /// PLAFOND de durée, en secondes, par instrument.
  ///
  /// Ce n'est plus une durée fixe : chaque note est taillée sur sa propre
  /// extinction (`tool/gen_sounds.py`). Une note ne doit jamais dépasser le
  /// plafond de son instrument, et jamais non plus être si courte qu'elle
  /// aurait été tranchée.
  ///
  /// L'orgue est court exprès : chaque note est un coup joué, pas une touche
  /// qu'on tient. Une note qui dure empilerait un accord pendant un
  /// glissando. La cloche, à l'inverse, a besoin de temps — coupée à une
  /// seconde elle faisait « cling » au lieu de sonner.
  const plafondSecondes = {
    'piano': 1.70,
    'guitare': 1.70,
    'orgue': 0.42,
    'cloche': 2.40,
    'clavecin': 1.70,
    'xylophone': 0.80,
    'harpe': 1.70,
    'trompette': 0.50,
  };

  /// En dessous, le son serait tronqué plutôt que relâché.
  const plancherSecondes = {
    'piano': 1.00,
    'guitare': 1.00,
    'orgue': 0.25,
    'cloche': 1.50,
    'clavecin': 1.00,
    // Le xylophone meurt de lui-même en moins d'une seconde : sa note est
    // courte parce que l'instrument l'est, pas parce qu'on l'a tranchée.
    'xylophone': 0.50,
    'harpe': 1.00,
    'trompette': 0.30,
  };

  test('chaque instrument a ses 28 notes, et rien d autre', () {
    for (final instrument in kInstruments) {
      for (final note in kSoundNotes) {
        for (final octave in kSoundOctaves) {
          final path = 'assets/sounds/$instrument/$note$octave.wav';
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
      // Les arpèges d'éjection, de fugue et de mat ne servaient plus : Kivy
      // les chargeait sans jamais les jouer pour deux d'entre eux.
      final files = Directory(
        'assets/sounds/$instrument',
      ).listSync().where((f) => f.path.endsWith('.wav'));
      expect(files.length, kSoundNotes.length * kSoundOctaves.length);
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

  test('chaque note tient dans les bornes de son instrument', () {
    plafondSecondes.forEach((instrument, plafond) {
      final plancher = plancherSecondes[instrument]!;
      for (final note in kSoundNotes) {
        for (final octave in kSoundOctaves) {
          final path = 'assets/sounds/$instrument/$note$octave.wav';
          final secondes = readWav(path).frames / 44100;
          expect(
            secondes,
            lessThanOrEqualTo(plafond + 0.01),
            reason: '$path dépasse le plafond de son instrument',
          );
          expect(
            secondes,
            greaterThanOrEqualTo(plancher),
            reason: '$path est trop court : la note serait tranchée',
          );
        }
      }
    });
  });

  test('aucune note ne s arrête pendant qu elle sonne encore', () {
    // Le défaut le plus reconnaissable d'un faux instrument : le fichier
    // s'arrête alors que le son est encore fort, et on entend une porte se
    // fermer. On regarde l'énergie des dernières 40 ms par rapport au plus
    // fort de la note : en dessous de -22 dB, c'est une touche relâchée.
    for (final instrument in kInstruments) {
      for (final note in kSoundNotes) {
        for (final octave in kSoundOctaves) {
          final path = 'assets/sounds/$instrument/$note$octave.wav';
          final db = niveauDeFin(path);
          expect(
            db,
            lessThan(-22),
            reason:
                '$path s arrête à ${db.toStringAsFixed(0)} dB de son '
                'maximum : ça claque',
          );
        }
      }
    }
  });
}

/// Énergie des dernières 40 ms, en dB sous le maximum de la note.
double niveauDeFin(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  // L'en-tête WAV de ces fichiers fait 44 octets : on lit les échantillons
  // qui suivent, en 16 bits signés.
  final samples = <double>[];
  for (var i = 44; i + 1 < bytes.length; i += 2) {
    samples.add(data.getInt16(i, Endian.little) / 32768.0);
  }
  if (samples.length < 4410) return -120;
  double rms(int debut, int fin) {
    var somme = 0.0;
    for (var i = debut; i < fin; i++) {
      somme += samples[i] * samples[i];
    }
    return math.sqrt(somme / (fin - debut));
  }

  const bloc = 441; // 10 ms
  var maxi = 0.0;
  for (var i = 0; i + bloc <= samples.length; i += bloc) {
    final v = rms(i, i + bloc);
    if (v > maxi) maxi = v;
  }
  final fin = rms(samples.length - 4 * bloc, samples.length);
  if (maxi <= 0 || fin <= 0) return -120;
  return 20 * (math.log(fin / maxi) / math.ln10);
}
