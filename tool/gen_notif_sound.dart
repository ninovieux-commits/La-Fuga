// Fabrique le son des notifications — lancé à la main :
//
//     dart run tool/gen_notif_sound.dart
//
// Android ne sait pas synthétiser un son au moment d'afficher une
// notification : il lui faut un fichier, posé dans `res/raw` et embarqué dans
// l'APK. On le fabrique donc ici, À PARTIR DES VRAIES NOTES DU JEU et avec
// SES PROPRES RÈGLES — `glissandoNotes` pour le choix des notes,
// `volumeFactorFor` pour l'équilibre, et le mixage de `mixCues`. Le son de la
// notification EST un son du jeu, pas une imitation.
//
// Le glissando choisi monte jusqu'au MILIEU de la tessiture : quatre octaves
// vont de do2 à si5, et il arrive sur do4, la note exactement médiane. Ni
// trop aigu ni trop grave.
//
// PIANO POUR TOUT LE MONDE, quel que soit l'instrument choisi pour les
// parties. Un son par instrument voulait dire un salon de notification par
// instrument — Android fige le son d'un salon à sa création — donc quatre
// lignes dans les réglages du téléphone et quatre fichiers dans l'APK. Pour
// un son de trois secondes par jour, ça ne valait pas son prix.
import 'dart:io';
import 'dart:typed_data';

import 'package:lafuga/game/pcm.dart';
import 'package:lafuga/game/sound_plan.dart';

/// Rangée dont l'octave est 4 : celle du milieu de la tessiture.
int _rangeeOctave4() {
  for (var row = 0; row < 8; row++) {
    if (octaveForRow(row) == 4) return row;
  }
  throw StateError('aucune rangée ne sonne en octave 4');
}

Pcm _lireWav(File f) {
  final o = f.readAsBytesSync();
  final d = ByteData.sublistView(o);
  // En-tête RIFF minimal : on cherche « fmt » puis « data ».
  var i = 12;
  var rate = 44100;
  var bits = 16;
  var canaux = 1;
  Int16List? samples;
  while (i + 8 <= o.length) {
    final id = String.fromCharCodes(o.sublist(i, i + 4));
    final taille = d.getUint32(i + 4, Endian.little);
    final corps = i + 8;
    if (id == 'fmt ') {
      canaux = d.getUint16(corps + 2, Endian.little);
      rate = d.getUint32(corps + 4, Endian.little);
      bits = d.getUint16(corps + 14, Endian.little);
    } else if (id == 'data') {
      if (bits != 16 || canaux != 1) {
        throw StateError(
          '${f.path} : attendu 16 bits mono, reçu $bits bits '
          '$canaux canal(aux)',
        );
      }
      samples = Int16List(taille ~/ 2);
      for (var k = 0; k < samples.length; k++) {
        samples[k] = d.getInt16(corps + k * 2, Endian.little);
      }
    }
    i = corps + taille + (taille.isOdd ? 1 : 0);
  }
  if (samples == null) throw StateError('${f.path} : pas de bloc « data »');
  return Pcm(samples, rate);
}

void _ecrireWav(File f, Int16List samples, int rate) {
  final octets = BytesBuilder();
  void chaine(String s) => octets.add(s.codeUnits);
  void u32(int v) => octets.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void u16(int v) => octets.add(
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
  );

  final donnees = samples.length * 2;
  chaine('RIFF');
  u32(36 + donnees);
  chaine('WAVE');
  chaine('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(rate);
  u32(rate * 2); // octets par seconde
  u16(2); // alignement
  u16(16); // bits
  chaine('data');
  u32(donnees);
  final corps = ByteData(donnees);
  for (var k = 0; k < samples.length; k++) {
    corps.setInt16(k * 2, samples[k], Endian.little);
  }
  octets.add(corps.buffer.asUint8List());
  f.writeAsBytesSync(octets.toBytes());
}

/// Volume du mixage. Voir le commentaire du mixage : il tient la saturation.
const double _marge = 0.8;

void main() {
  // Le même glissando que dans une partie : quatre notes, cent millisecondes
  // d'écart, montant jusqu'à la case visée.
  final notes = glissandoNotes(0, _rangeeOctave4(), 4, 1);
  stdout.writeln('glissando : ${notes.join(" → ")}');

  final sortie = Directory('android/app/src/main/res/raw');
  sortie.createSync(recursive: true);

  for (final instrument in const ['piano']) {
    final banque = <String, Pcm>{};
    var rate = 44100;
    for (final note in notes) {
      final f = File('assets/sounds/$instrument/$note.wav');
      if (!f.existsSync()) throw StateError('manquant : ${f.path}');
      final pcm = _lireWav(f);
      banque[note] = pcm;
      rate = pcm.rate;
    }

    final cues = <SoundCue>[
      for (var i = 0; i < notes.length; i++)
        SoundCue(notes[i], Duration(milliseconds: 100 * i)),
    ];
    // Un peu de marge : à plein volume l'orgue touche la butée du 16 bits et
    // se met à grésiller. En partie il ne sature pas, parce que le réglage de
    // volume du joueur est rarement à fond ; ici le fichier est figé, donc la
    // marge doit être dedans.
    final mixe = mixCues(cues, SoundBank(instrument, banque, rate), _marge);
    if (mixe == null) throw StateError('$instrument : mixage vide');

    final cible = File('${sortie.path}/notif_$instrument.wav');
    _ecrireWav(cible, mixe, rate);
    stdout.writeln(
      '${cible.path} — ${(mixe.length / rate).toStringAsFixed(2)} s'
      ', ${(cible.lengthSync() / 1024).round()} Ko',
    );
  }
}
