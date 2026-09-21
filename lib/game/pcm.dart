/// Lecture d'un fichier WAV et fabrication d'un autre — Dart pur.
///
/// Le jeu mixe lui-même les notes d'un coup en un seul son (voir
/// `sound_player.dart`) : il lui faut donc savoir lire les échantillons d'un
/// `.wav` et en réécrire un.
library;

import 'dart:typed_data';

/// Échantillons d'un son : PCM 16 bits, mono, et sa fréquence.
final class Pcm {
  const Pcm(this.samples, this.rate);

  final Int16List samples;
  final int rate;

  int get length => samples.length;

  static final Pcm empty = Pcm(Int16List(0), 44100);
}

/// Lit un WAV PCM 16 bits. `null` si ce n'en est pas un.
///
/// Tolérant : un fichier qu'on ne sait pas lire rend `null` plutôt que de
/// faire tomber le jeu. Le son est un agrément, jamais une raison de planter.
Pcm? readWav(ByteData data) {
  try {
    if (data.lengthInBytes < 44) return null;
    if (_tag(data, 0) != 'RIFF' || _tag(data, 8) != 'WAVE') return null;

    var offset = 12;
    var channels = 1;
    var rate = 44100;
    var bits = 16;
    while (offset + 8 <= data.lengthInBytes) {
      final id = _tag(data, offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'fmt ' && body + 16 <= data.lengthInBytes) {
        channels = data.getUint16(body + 2, Endian.little);
        rate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        if (bits != 16 || channels < 1) return null;
        final count = (size ~/ 2).clamp(0, (data.lengthInBytes - body) ~/ 2);
        final all = Int16List(count);
        for (var i = 0; i < count; i++) {
          all[i] = data.getInt16(body + i * 2, Endian.little);
        }
        if (channels == 1) return Pcm(all, rate);
        // Plusieurs canaux : on ne garde que le premier, le jeu est mono.
        final mono = Int16List(count ~/ channels);
        for (var i = 0; i < mono.length; i++) {
          mono[i] = all[i * channels];
        }
        return Pcm(mono, rate);
      }
      offset = body + size + (size.isOdd ? 1 : 0);
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Emballe des échantillons dans un fichier WAV mono 16 bits.
Uint8List writeWav(Int16List samples, int rate) {
  const headerSize = 44;
  final dataSize = samples.length * 2;
  final out = ByteData(headerSize + dataSize);

  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + dataSize, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // taille du bloc fmt
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, rate, Endian.little);
  out.setUint32(28, rate * 2, Endian.little); // octets par seconde
  out.setUint16(32, 2, Endian.little); // octets par bloc
  out.setUint16(34, 16, Endian.little); // bits
  tag(36, 'data');
  out.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(headerSize + i * 2, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

String _tag(ByteData d, int at) => String.fromCharCodes([
  d.getUint8(at),
  d.getUint8(at + 1),
  d.getUint8(at + 2),
  d.getUint8(at + 3),
]);
