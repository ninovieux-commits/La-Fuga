/// Chronomètre de partie — portage de `_tick` et `_fmt` (GameScreen, main.py).
///
/// Dart pur : la logique est testable sans horloge réelle, en injectant les
/// tics à la main.
library;

import '../engine/piece.dart';

/// Cadence d'une partie, en secondes par camp. `null` = sans chrono.
///
/// Les valeurs sont **celles de Kivy**, et c'est important : `wire` est ce qui
/// part au serveur (`chercher_partie`, `defier`) et ce qui s'écrit dans le
/// `.nmc`. Un autre mot, et le matchmaking n'apparierait jamais un joueur
/// Flutter avec un joueur Kivy.
final class Cadence {
  const Cadence(this.seconds, this.wire);

  /// Secondes allouées à chaque camp, ou `null` pour une partie sans chrono.
  final int? seconds;

  /// Valeur transmise au serveur : `5`, `15`, `30` ou `zen`.
  final String wire;

  /// Sans chrono. Les parties contre Deep Grey, l'analyse et la
  /// correspondance sont toujours en Zen.
  static const Cadence zen = Cadence(null, 'zen');

  static const Cadence cinq = Cadence(300, '5');
  static const Cadence quinze = Cadence(900, '15');
  static const Cadence trente = Cadence(1800, '30');

  /// Les trois cadences proposées au menu, comme en Kivy.
  static const List<Cadence> toutes = [cinq, quinze, trente];

  /// Cadence par défaut du menu.
  static const Cadence parDefaut = quinze;

  /// Libellé affiché : « 15 min », ou « Zen ».
  String get label => this == zen ? 'Zen' : '$wire min';

  /// Retrouve une cadence à partir de ce que dit le serveur.
  static Cadence fromWire(String? value) => switch (value) {
    '5' => cinq,
    '15' => quinze,
    '30' => trente,
    _ => zen,
  };
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
