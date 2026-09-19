/// Lecture des sons — portage de `SoundManager` (main.py).
///
/// La *décision* musicale (quelles notes, à quel moment) vit dans
/// `sound_plan.dart`, en Dart pur. Ce fichier ne fait que la jouer.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'sound_plan.dart';

/// Joue les notes du jeu, avec un instrument au choix.
///
/// Un échec de lecture n'est jamais remonté : le son est un agrément, il ne
/// doit sous aucun prétexte interrompre une partie.
class SoundPlayer {
  SoundPlayer({String instrument = 'piano', double volume = 1.0})
    : _instrument = instrument,
      _volume = volume.clamp(0.0, 1.0);

  String _instrument;
  double _volume;
  bool _enabled = true;

  /// Un lecteur par voix : les notes d'un glissando se chevauchent, un
  /// lecteur unique les couperait les unes après les autres.
  final List<AudioPlayer> _voices = [];
  int _nextVoice = 0;
  static const int _voiceCount = 6;

  final List<Timer> _pending = [];

  String get instrument => _instrument;
  double get volume => _volume;
  bool get enabled => _enabled && _volume > 0;

  set enabled(bool value) => _enabled = value;

  void setVolume(double value) => _volume = value.clamp(0.0, 1.0);

  /// Change d'instrument : `piano`, `orgue`, `guitare` ou `cloche`.
  void setInstrument(String name) {
    if (kInstruments.contains(name)) _instrument = name;
  }

  Future<void> init() async {
    for (var i = 0; i < _voiceCount; i++) {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      _voices.add(p);
    }
  }

  /// Joue les sons d'un coup.
  void playNotation(String? notation, {bool hadEjection = false}) {
    play(planForNotation(notation, hadEjection: hadEjection));
  }

  /// Joue un plan de sons déjà calculé.
  void play(List<SoundCue> cues) {
    if (!enabled || _voices.isEmpty) return;
    for (final cue in cues) {
      if (cue.delay == Duration.zero) {
        _playCue(cue);
      } else {
        final timer = Timer(cue.delay, () => _playCue(cue));
        _pending.add(timer);
      }
    }
  }

  void _playCue(SoundCue cue) {
    if (!enabled) return;
    final player = _voices[_nextVoice];
    _nextVoice = (_nextVoice + 1) % _voices.length;
    final level = (_volume * cue.volumeFactor).clamp(0.0, 1.0);
    // Aucun await : une note qui ne part pas ne doit pas retarder les
    // suivantes, et surtout pas bloquer l'interface.
    unawaited(() async {
      try {
        await player.stop();
        await player.setVolume(level);
        await player.play(AssetSource('sounds/$_instrument/${cue.name}.wav'));
      } catch (_) {
        // Fichier absent ou lecteur occupé : on laisse passer en silence.
      }
    }());
  }

  /// Coupe tout ce qui est en attente (fin de partie, retour au menu).
  void stopAll() {
    for (final t in _pending) {
      t.cancel();
    }
    _pending.clear();
    for (final p in _voices) {
      unawaited(p.stop().catchError((_) {}));
    }
  }

  Future<void> dispose() async {
    stopAll();
    for (final p in _voices) {
      await p.dispose();
    }
    _voices.clear();
  }
}
