/// Chaque instrument est COMPLET : ses sons, son dessin, son nom.
///
/// Un instrument ajouté sans son dossier de sons dans `pubspec.yaml` reste
/// muet dans l'APK, sans la moindre erreur — Flutter ne descend pas dans les
/// sous-dossiers d'une entrée d'assets, et quatre instruments sont partis
/// comme ça avec leurs 112 notes hors du paquet. Sur ma machine tout allait
/// bien : les fichiers sont là, c'est l'EMBARQUEMENT qui manquait.
///
/// Ce test regarde donc le pubspec, pas le disque.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/sound_plan.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/settings_screen.dart';
import 'package:lafuga/ui/widgets/instrument_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  group('Tout instrument est complet', () {
    test('ses sons sont déclarés dans le pubspec, donc embarqués', () {
      for (final nom in kInstruments) {
        expect(
          pubspec,
          contains('assets/sounds/$nom/'),
          reason:
              '« $nom » n est pas dans pubspec.yaml : ses notes resteraient '
              'hors de l APK, et il serait muet sans aucune erreur',
        );
      }
    });

    test('et ses 28 notes sont bien là', () {
      for (final nom in kInstruments) {
        final dossier = Directory('assets/sounds/$nom');
        expect(dossier.existsSync(), isTrue, reason: nom);
        final wav = dossier
            .listSync()
            .where((f) => f.path.endsWith('.wav'))
            .length;
        expect(wav, kSoundNotes.length * kSoundOctaves.length, reason: nom);
      }
    });

    test('il a son dessin, et le dossier est embarqué', () {
      expect(pubspec, contains('assets/instruments/'));
      for (final nom in kInstruments) {
        expect(
          File(instrumentAsset(nom)).existsSync(),
          isTrue,
          reason: 'pas de dessin pour « $nom »',
        );
      }
    });

    test('il a un nom affichable', () {
      for (final nom in kInstruments) {
        expect(kInstrumentLabels[nom], isNotNull, reason: nom);
      }
    });
  });

  group('Et rien ne traîne', () {
    test('aucun dossier de sons orphelin', () {
      // Un instrument retiré laisse sinon ses 28 fichiers dans l APK.
      final dossiers = Directory('assets/sounds')
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split('/').last)
          .toList();
      expect(dossiers..sort(), [...kInstruments]..sort());
    });

    test('aucun dessin orphelin', () {
      final dessins = Directory('assets/instruments')
          .listSync()
          .where((f) => f.path.endsWith('.png'))
          .map((f) => f.path.split('/').last.replaceAll('.png', ''))
          .toList();
      expect(dessins..sort(), [...kInstruments]..sort());
    });
  });

  group('L aperçu dans les réglages', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
      });
      await Settings.load();
      await Translations.load('fr');
    });

    Future<void> ouvre(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();
    }

    testWidgets('le dessin de l instrument choisi est montré', (tester) async {
      await ouvre(tester);
      final vus = tester
          .widgetList<InstrumentPreview>(find.byType(InstrumentPreview))
          .toList();
      expect(vus, hasLength(1));
      expect(vus.single.instrument, Settings.instance.instrument);
    });

    testWidgets('et il change quand on change d instrument', (tester) async {
      await ouvre(tester);
      String montre() => tester
          .widget<InstrumentPreview>(find.byType(InstrumentPreview))
          .instrument;
      final depart = montre();

      // La flèche « > » de CETTE ligne-là : on la cherche dans la rangée qui
      // porte l'aperçu, pas à l'aveugle sur l'écran — les réglages en ont
      // plusieurs, et elles se ressemblent toutes.
      final rangee = find.ancestor(
        of: find.byType(InstrumentPreview),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: rangee.first, matching: find.text('>')).first,
      );
      await tester.pumpAndSettle();

      expect(montre(), isNot(depart));
      expect(kInstruments, contains(montre()));
    });
  });
}
