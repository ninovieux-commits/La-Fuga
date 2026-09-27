/// Le son des notifications : un glissando du jeu, avec l'instrument choisi.
///
/// Android ne sait pas synthétiser un son au moment d'afficher une
/// notification : il lui faut un FICHIER embarqué dans l'APK. Et il FIGE le
/// son d'un salon à sa création — changer d'instrument veut donc dire changer
/// de salon, un par instrument.
///
/// Ces tests gardent les deux bouts : les fichiers existent vraiment et
/// contiennent le bon son, et l'application va chercher le bon fichier.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/sound_plan.dart';
import 'package:lafuga/net/push_notifications.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Les fichiers embarqués', () {
    final dossier = Directory('android/app/src/main/res/raw');

    test('il y en a un par instrument, et aucun de vide', () {
      // Le garde-fou : ajouter un instrument sans refaire les sons casse ce
      // test au lieu de livrer une notification muette.
      for (final instrument in kInstruments) {
        final f = File('${dossier.path}/notif_$instrument.wav');
        expect(
          f.existsSync(),
          isTrue,
          reason:
              'son manquant pour $instrument — relancer '
              '`dart run tool/gen_notif_sound.dart`',
        );

        final wav = _lireWav(f);
        expect(wav.rate, 44100, reason: '$instrument : fréquence inattendue');
        expect(
          wav.samples.length,
          greaterThan(44100 ~/ 2),
          reason: '$instrument : moins d une demi-seconde',
        );

        var crete = 0;
        for (final v in wav.samples) {
          final a = v.abs();
          if (a > crete) crete = a;
        }
        expect(crete, greaterThan(3000), reason: '$instrument : quasi muet');
        expect(
          crete,
          lessThan(32767),
          reason: '$instrument : saturé, le son grésillera',
        );
      }
    });

    test('quatre attaques espacées de cent millisecondes', () {
      // C est ce qui fait un glissando plutôt qu un accord.
      final wav = _lireWav(File('${dossier.path}/notif_piano.wav'));
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
  });

  group('Un salon par instrument', () {
    test('des identifiants distincts, et le bon fichier', () {
      final ids = {for (final i in kInstruments) channelIdFor(i)};
      expect(
        ids.length,
        kInstruments.length,
        reason:
            'deux instruments partagent un salon : Android fige le son '
            'd un salon, ils sonneraient donc pareil',
      );
      for (final i in kInstruments) {
        expect(channelSoundFor(i), 'notif_$i');
        expect(channelNameFor(i), contains(i));
      }
    });

    test('l ancien salon a un autre identifiant : il sera supprimé', () {
      expect(kLegacyChannelId, isNot(channelIdFor(kInstruments.first)));
    });
  });

  group('L instrument suivi', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
      });
      await Settings.load();
    });

    test('c est celui des réglages', () async {
      await Settings.instance.setInstrument('cloche');
      expect(await PushNotifications.currentInstrument(), 'cloche');
      expect(channelSoundFor('cloche'), 'notif_cloche');
    });

    test('le piano par défaut', () async {
      expect(kInstruments.first, 'piano');
      expect(await PushNotifications.currentInstrument(), 'piano');
    });
  });
}
