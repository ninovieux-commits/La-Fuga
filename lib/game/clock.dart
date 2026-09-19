/// Chronomètre de partie — portage de `_tick` et `_fmt` (GameScreen, main.py).
///
/// Dart pur : la logique est testable sans horloge réelle, en injectant les
/// tics à la main.
library;

import '../engine/piece.dart';

/// Cadence d'une partie, en secondes par camp. `null` = illimité.
final class Cadence {
  const Cadence(this.seconds, this.label);

  /// Secondes allouées à chaque camp, ou `null` pour une partie sans chrono.
  final int? seconds;

  /// Libellé affiché, tel que le serveur l'attend (`cadence` du matchmaking).
  final String label;

  static const Cadence illimitee = Cadence(null, 'illimité');
  static const Cadence blitz3 = Cadence(180, '3min');
  static const Cadence blitz5 = Cadence(300, '5min');
  static const Cadence rapide10 = Cadence(600, '10min');
  static const Cadence longue30 = Cadence(1800, '30min');

  static const List<Cadence> toutes = [
    illimitee,
    blitz3,
    blitz5,
    rapide10,
    longue30,
  ];
}

/// Chronomètre à deux camps.
///
/// Le temps du camp au trait s'écoule **même quand la partie est en pause** :
/// c'est volontaire côté Kivy, pour qu'une mise en pause ne serve pas à
/// gagner du temps de réflexion.
class GameClock {
  GameClock(this.cadence)
    : _remaining = {Camp.blanc: cadence.seconds, Camp.noir: cadence.seconds};

  final Cadence cadence;
  final Map<Camp, int?> _remaining;

  /// Vrai quand la partie se joue sans chrono.
  bool get isUnlimited => cadence.seconds == null;

  int? remainingFor(Camp camp) => _remaining[camp];

  /// Retire une seconde au camp au trait.
  ///
  /// Renvoie le camp qui vient d'épuiser son temps, ou `null`. Sans chrono,
  /// ne fait rien.
  Camp? tick(Camp turn) {
    if (isUnlimited) return null;
    final left = (_remaining[turn] ?? 0) - 1;
    _remaining[turn] = left < 0 ? 0 : left;
    return left <= 0 ? turn : null;
  }

  /// Force le temps restant d'un camp (synchronisation en ligne).
  void setRemaining(Camp camp, int? seconds) {
    if (seconds == null) return;
    _remaining[camp] = seconds < 0 ? 0 : seconds;
  }

  void reset() {
    _remaining[Camp.blanc] = cadence.seconds;
    _remaining[Camp.noir] = cadence.seconds;
  }

  /// `mm:ss`, ou `∞` sans chrono.
  static String format(int? seconds) {
    if (seconds == null) return '∞';
    final s = seconds < 0 ? 0 : seconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  String displayFor(Camp camp) => format(_remaining[camp]);
}
