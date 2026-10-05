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
    test('il DESCEND, et part des notes les plus graves', () {
      // Il montait jusqu'au milieu de la tessiture, du temps où tous les
      // glissandos du jeu montaient. Depuis, le sens dit quelque chose :
      // une poussée descend, un déplacement de groupe monte. Une
      // notification qui monte aurait annoncé un déplacement de groupe.
      expect(kNotesNotification, ['mi2', 're2', 'do2']);

      final indices = [for (final n in kNotesNotification) noteIndexOf(n)];
      expect(indices, [2, 1, 0], reason: 'les trois plus graves des 28');
      for (var i = 1; i < indices.length; i++) {
        expect(
          indices[i]!,
          lessThan(indices[i - 1]!),
          reason: 'ça doit descendre',
        );
      }
    });

    test('ses notes ne viennent pas d une case, et c est voulu', () {
      // Le plateau ne tient plus que sur deux octaves : aucune rangée ne
      // descend jusqu'à l'octave 2. La notification n'est pas un coup, elle
      // n'a pas de case — ses notes sont nommées directement.
      final duPlateau = {
        for (var c = 0; c < 7; c++)
          for (var r = 0; r < 8; r++) noteForCell(c, r),
      };
      for (final n in kNotesNotification) {
        expect(
          duPlateau,
          isNot(contains(n)),
          reason: '« $n » est pourtant la note d une case',
        );
      }
    });

    test('et les trois notes sont bien dans la banque', () {
      for (final n in kNotesNotification) {
        expect(noteIndexOf(n), isNotNull, reason: n);
        expect(
          File('assets/sounds/piano/$n.wav').existsSync(),
          isTrue,
          reason: n,
        );
      }
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
      // Cette liste est un fait HISTORIQUE, pas une dérivée de
      // `kInstruments` : ce sont les salons qui ont réellement existé sur
      // les téléphones. Elle était construite à partir des instruments, et
      // en ajouter quatre lui a fait réclamer la suppression de
      // « lafuga_clavecin » — un salon que personne n'a jamais eu.
      //
      // Elle ne grandira que si une version PUBLIÉE crée un nouveau salon.
      expect(
        kLegacyChannelIds,
        containsAll(<String>[
          'lafuga_default', // le muet du tout début
          'lafuga_piano', // les quatre de la version par instrument
          'lafuga_orgue',
          'lafuga_guitare',
          'lafuga_cloche',
          'lafuga_notif', // le premier salon unique
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
      // La règle, et non la valeur du jour : TOUT salon abandonné doit être
      // dans la liste à effacer. Le son a changé deux fois, le salon aussi.
      expect(
        kChannelId,
        'lafuga_notif_3',
        reason: 'le nom du salon a changé sans que l ancien soit listé',
      );
      for (final abandonne in ['lafuga_notif', 'lafuga_notif_2']) {
        expect(
          kLegacyChannelIds,
          contains(abandonne),
          reason: '« $abandonne » survit, peut-être muet',
        );
      }
    });

    test('son nom ne nomme aucun instrument : il n y en a qu un', () {
      expect(kChannelName, 'La Fuga');
      for (final i in kInstruments) {
        expect(kChannelName.toLowerCase(), isNot(contains(i)));
      }
    });
  });
}
