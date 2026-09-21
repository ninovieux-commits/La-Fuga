/// Lecture des sons — portage de `SoundManager` (main.py).
///
/// La *décision* musicale (quelles notes, à quel moment) vit dans
/// `sound_plan.dart`, en Dart pur. Ce fichier ne fait que la jouer.
///
/// **Un coup = un seul son.** Les notes d'un coup ne sont pas déclenchées une
/// par une : elles sont MIXÉES en Dart dans un unique tampon, à l'échantillon
/// près, puis jouées d'un bloc. C'est ce qui donne un tempo rigoureusement
/// identique d'un coup à l'autre et dans tous les modes de jeu — un minuteur
/// Dart, lui, dérive dès que l'interface a du travail, et chaque envoi vers la
/// plateforme coûte quelques millisecondes imprévisibles.
///
/// Un échec de lecture n'est jamais remonté : le son est un agrément, il ne
/// doit sous aucun prétexte interrompre une partie.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../state/settings.dart';
import 'pcm.dart';
import 'sound_plan.dart';

/// Charge les 28 notes d'un instrument depuis les assets.
Future<SoundBank> loadSoundBank(String instrument) async {
  final notes = <String, Pcm>{};
  var rate = 44100;
  for (final note in kSoundNotes) {
    for (final octave in kSoundOctaves) {
      final name = '$note$octave';
      try {
        final data = await rootBundle.load(
          'assets/sounds/$instrument/$name.wav',
        );
        final pcm = readWav(data);
        if (pcm != null && pcm.length > 0) {
          notes[name] = pcm;
          rate = pcm.rate;
        }
      } catch (_) {
        // Fichier absent ou illisible : cette note restera muette.
      }
    }
  }
  return SoundBank(instrument, notes, rate);
}

/// Joue les notes du jeu, avec un instrument au choix.
class SoundPlayer {
  SoundPlayer({String instrument = 'piano', double volume = 1.0})
    : _instrument = instrument,
      _volume = volume.clamp(0.0, 1.0);

  String _instrument;
  double _volume;
  bool _enabled = true;

  SoundBank? _bank;
  Future<SoundBank>? _loading;

  /// Quelques lecteurs en rotation : un coup joué pendant que le précédent
  /// résonne encore ne doit pas le couper.
  final List<AudioPlayer> _voices = [];
  int _nextVoice = 0;
  static const int _voiceCount = 3;

  String get instrument => _instrument;
  double get volume => _volume;
  bool get enabled => _enabled && _volume > 0;

  /// Vrai quand les notes sont décodées et prêtes à sonner.
  bool get isReady => _bank != null && !_bank!.isEmpty;

  set enabled(bool value) => _enabled = value;

  void setVolume(double value) => _volume = value.clamp(0.0, 1.0);

  /// Change d'instrument : `piano`, `orgue`, `guitare` ou `cloche`.
  void setInstrument(String name) {
    if (!kInstruments.contains(name) || name == _instrument) return;
    _instrument = name;
    _bank = null;
    _loading = null;
    unawaited(_ensureBank());
  }

  /// Reprend l'instrument et le volume des réglages.
  ///
  /// À rappeler en revenant des réglages : ils s'ouvrent depuis la pause, en
  /// pleine partie, et le changement doit s'entendre au coup suivant.
  void applySettings() {
    setInstrument(Settings.instance.instrument);
    setVolume(Settings.instance.volume);
  }

  Future<void> init() async {
    applySettings();
    for (var i = 0; i < _voiceCount; i++) {
      try {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        _voices.add(p);
      } catch (_) {
        // Un lecteur en moins : on jouera avec ceux qui restent.
      }
    }
    await _ensureBank();
  }

  Future<SoundBank> _ensureBank() async {
    final ready = _bank;
    if (ready != null && ready.instrument == _instrument) return ready;
    final wanted = _instrument;
    final pending = _loading ??= loadSoundBank(wanted);
    final bank = await pending;
    // L'instrument a pu changer pendant le chargement.
    if (bank.instrument == _instrument) {
      _bank = bank;
      _loading = null;
    }
    return bank;
  }

  /// Joue les sons d'un coup.
  void playNotation(String? notation) => play(planForNotation(notation));

  /// Joue un plan de sons déjà calculé.
  ///
  /// Rien n'est attendu : le mixage prend quelques dixièmes de milliseconde et
  /// l'envoi vers la plateforme part sans bloquer le doigt du joueur.
  void play(List<SoundCue> cues) {
    if (!enabled || cues.isEmpty || _voices.isEmpty) return;
    final bank = _bank;
    if (bank == null || bank.isEmpty) {
      // Les notes ne sont pas encore décodées : on ne fait pas la queue, ce
      // coup-ci restera muet plutôt que d'arriver en retard.
      unawaited(_ensureBank());
      return;
    }
    final mixed = mixCues(cues, bank, _volume);
    if (mixed == null) return;
    _send(mixed, bank.rate);
  }

  void _send(Int16List samples, int rate) {
    final player = _voices[_nextVoice];
    _nextVoice = (_nextVoice + 1) % _voices.length;
    final bytes = writeWav(samples, rate);
    unawaited(_start(player, bytes));
  }

  Future<void> _start(AudioPlayer player, Uint8List bytes) async {
    try {
      await player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (_) {
      // Lecteur occupé, mémoire, pilote audio : on laisse passer en silence.
    }
  }

  /// Coupe tout (fin de partie, retour au menu).
  void stopAll() {
    for (final p in _voices) {
      unawaited(p.stop().catchError((_) {}));
    }
  }

  Future<void> dispose() async {
    stopAll();
    for (final p in _voices) {
      try {
        await p.dispose();
      } catch (_) {
        // Rien à faire : on s'en va.
      }
    }
    _voices.clear();
  }
}
