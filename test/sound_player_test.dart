/// Le son suit les réglages — `SoundManager` chez Kivy lit l'instrument et le
/// volume choisis. Le lecteur partait toujours sur le piano à plein volume :
/// changer d'instrument dans les réglages n'avait aucun effet en partie.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/sound_plan.dart';
import 'package:lafuga/game/sound_player.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le lecteur reprend l instrument et le volume des réglages', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Settings.instance.setInstrument(kInstruments.last);
    await Settings.instance.setVolume(0.4);

    final player = SoundPlayer();
    expect(player.instrument, kInstruments.first, reason: 'avant lecture');

    player.applySettings();
    expect(player.instrument, kInstruments.last);
    expect(player.volume, closeTo(0.4, 1e-9));
  });

  test('un instrument inconnu ne casse rien', () {
    final player = SoundPlayer();
    player.setInstrument('trombone');
    expect(player.instrument, kInstruments.first);
  });
}
