/// Le son des notifications : un glissando du jeu, au piano.
///
/// Android ne sait pas synthétiser un son au moment d'afficher une
/// notification : il lui faut un FICHIER embarqué dans l'APK. Et il FIGE le
/// son d'un salon à sa création — le faire suivre l'instrument choisi
/// demanderait un salon par instrument, donc quatre lignes dans les réglages
/// du téléphone. C'est le piano pour tout le monde.
///
/// Ces tests gardent les deux bouts : le fichier existe vraiment et contient
/// le bon son, et l'application va chercher ce fichier-là.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/sound_plan.dart';
import 'package:lafuga/net/push_notifications.dart';

/// Un WAV lu à la main : fréquence, et échantillons.
({int rate, Int16List samples}) _lireWav(File f) {
  final o = f.readAsBytesSync();
  final d = ByteData.sublistView(o);
  var i = 12;
  var rate = 0;
  Int16List? samples;
  while (i + 8 <= o.length) {
    final id = String.fromCharCodes(o.sublist(i, i + 4));
    final taille = d.getUint32(i + 4, Endian.little);
    if (id == 'fmt ') rate = d.getUint32(i + 12, Endian.little);
    if (id == 'data') {
      samples = Int16List(taille ~/ 2);
      for (var k = 0; k < samples.length; k++) {
        samples[k] = d.getInt16(i + 8 + k * 2, Endian.little);
      }
    }
    i += 8 + taille + (taille.isOdd ? 1 : 0);
  }
  return (rate: rate, samples: samples ?? Int16List(0));
}

void main() {
  group('Le glissando choisi', () {
    test('arrive au MILIEU de la tessiture', () {
      // Quatre octaves de sept notes : vingt-huit en tout, do2 à si5. Le
      // milieu est l'indice 14, c'est-à-dire do4.
      final rangee = List.generate(
        8,
        (r) => r,
      ).firstWhere((r) => octaveForRow(r) == 4);
      final notes = glissandoNotes(0, rangee, 4, 1);

      expect(notes, ['sol3', 'la3', 'si3', 'do4']);
      expect(
        notes.last,
        'do4',
        reason: 'ni trop aigu ni trop grave : la note médiane des 28',
      );
      // Et c'est bien la médiane : 14 notes en dessous, 13 au-dessus.
      const indiceDo4 = (4 - 2) * 7 + 0;
      expect(indiceDo4, 14);
      expect(kSoundOctaves.length * kSoundNotes.length, 28);
    });

    test('il monte, et finit sur sa cible', () {
      final notes = glissandoNotes(0, 3, 4, 1);
      expect(notes.length, 4);
      expect(notes.toSet().length, 4, reason: 'quatre notes différentes');
    });
  });

  group('Le fichier embarqué', () {
    final dossier = Directory('android/app/src/main/res/raw');
    final fichier = File('${dossier.path}/$kChannelSound.wav');

    test('il existe, et il n est ni muet ni saturé', () {
      // Le garde-fou : renommer le son sans refaire le fichier casse ce test
      // au lieu de livrer une notification muette.
      expect(
        fichier.existsSync(),
        isTrue,
        reason:
            'son manquant : relancer '
            '`dart run tool/gen_notif_sound.dart`',
      );

      final wav = _lireWav(fichier);
      expect(wav.rate, 44100, reason: 'fréquence inattendue');
      expect(
        wav.samples.length,
        greaterThan(44100 ~/ 2),
        reason: 'moins d une demi-seconde',
      );

      var crete = 0;
      for (final v in wav.samples) {
        final a = v.abs();
        if (a > crete) crete = a;
      }
      expect(crete, greaterThan(3000), reason: 'quasi muet');
      expect(crete, lessThan(32767), reason: 'saturé, le son grésillera');
    });

    test('quatre attaques espacées de cent millisecondes', () {
      // C est ce qui fait un glissando plutôt qu un accord.
      final wav = _lireWav(fichier);
      int creteAutourDe(double seconde) {
        final debut = (wav.rate * seconde).round();
        var c = 0;
        for (var i = debut; i < debut + 1200 && i < wav.samples.length; i++) {
          final a = wav.samples[i].abs();
          if (a > c) c = a;
        }
        return c;
      }

      for (final t in [0.0, 0.1, 0.2, 0.3]) {
        expect(
          creteAutourDe(t),
          greaterThan(2000),
          reason: 'aucune attaque à ${(t * 1000).round()} ms',
        );
      }
    });

    test('c est le seul : pas de fichier par instrument qui traîne', () {
      // La version intermédiaire en posait quatre. Les laisser gonflerait
      // l APK de 300 Ko pour rien.
      final sons = dossier
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('notif_') && n.endsWith('.wav'))
          .toList();
      expect(sons, ['$kChannelSound.wav']);
    });
  });

  group('Le salon unique', () {
    test('son identifiant n est aucun des anciens', () {
      // Sinon Android garderait le salon déjà créé — avec son ancien son,
      // qu on ne peut plus changer — ou le supprimerait aussitôt créé.
      expect(
        kLegacyChannelIds,
        isNot(contains(kChannelId)),
        reason: 'le salon courant serait supprimé au démarrage',
      );
    });

    test('les anciens salons sont tous listés, pour être effacés', () {
      // Le muet d avant, et les quatre de la version par instrument.
      expect(
        kLegacyChannelIds,
        containsAll(<String>[
          'lafuga_default',
          for (final i in kInstruments) 'lafuga_$i',
        ]),
        reason:
            'un salon oublié reste une ligne morte dans les réglages '
            'Android du téléphone',
      );
    });

    test('le salon PRÉCÉDENT est effacé : il pourrait être muet', () {
      // Android fige le son d'un salon à sa création et le garde après les
      // mises à jour. Un salon créé une fois sans le bon son reste muet pour
      // toujours : la seule issue est d'en changer le nom ET d'effacer
      // l'ancien, sinon il traîne dans les réglages du téléphone.
      expect(
        kChannelId,
        'lafuga_notif_2',
        reason: 'le nom du salon a changé sans que l ancien soit listé',
      );
      expect(
        kLegacyChannelIds,
        contains('lafuga_notif'),
        reason: 'le salon d avant survit, peut-être muet',
      );
    });

    test('son nom ne nomme aucun instrument : il n y en a qu un', () {
      expect(kChannelName, 'La Fuga');
      for (final i in kInstruments) {
        expect(kChannelName.toLowerCase(), isNot(contains(i)));
      }
    });
  });
}
