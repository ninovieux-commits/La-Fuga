/// Quelles notes jouer pour un coup, et quand — portage de `_play_move_sound`,
/// `play_glissando` et `_row_to_octave` (main.py).
///
/// Dart pur : la décision musicale est testable sans jamais ouvrir le son.
/// La lecture proprement dite vit dans `sound_player.dart`.
///
/// Chaque colonne du plateau porte une note (do…si) et chaque rangée une
/// octave : un coup se donc *entend*, et deux coups différents ne sonnent pas
/// pareil.
library;

import 'dart:math' as math;

import '../engine/board.dart';
import '../engine/notation.dart';

/// Noms de fichiers des notes, dans l'ordre des colonnes.
/// Attention : `re` sans accent, contrairement à la notation affichée `Ré`.
const List<String> kSoundNotes = ['do', 're', 'mi', 'fa', 'sol', 'la', 'si'];

/// Instruments disponibles, dans l'ordre du menu Kivy.
const List<String> kInstruments = ['piano', 'orgue', 'guitare', 'cloche'];

/// Les quatre octaves des fichiers de notes.
const List<int> kSoundOctaves = [2, 3, 4, 5];

/// Octave associée à une rangée.
///
/// Les rangées du fond sonnent aigu, celles du milieu grave : le mouvement
/// vers l'adversaire s'entend.
int octaveForRow(int row) {
  final line = row + 1; // rangées 1 à 8
  return switch (line) {
    1 || 8 => 5,
    2 || 7 => 4,
    3 || 6 => 3,
    4 || 5 => 5,
    _ => 3,
  };
}

/// Nom du fichier de note pour une case, par exemple `fa5`.
String? noteForCell(int col, int row) {
  if (col < 0 || col >= kCols) return null;
  return '${kSoundNotes[col]}${octaveForRow(row)}';
}

/// Les quatre repères d'atténuation, un par octave : do2, do3, do4, do5.
///
/// Ce sont les valeurs réglées à l'oreille, et elles ne bougent pas. Ce qui
/// change, c'est ce qui se passe ENTRE elles.
const List<double> kVolumeOctaves = [1.0, 0.80, 0.55, 0.40];

/// Atténuation d'une note, continue sur toute la gamme.
///
/// Les graves servent de référence et les aigus sont baissés : sans cela, une
/// note aiguë écrase tout le reste.
///
/// Elle se lisait sur le seul CHIFFRE de l'octave, donc par marches : les
/// sept notes de l'octave 3 sortaient toutes à 0,80, puis do4 tombait d'un
/// coup à 0,55. Un glissando est une course de notes consécutives dans la
/// gamme ; dès qu'il franchissait une frontière d'octave — `la3 si3 do4 re4` —
/// le volume décrochait de presque 3 dB en plein milieu, et les quatre notes
/// n'avaient plus le même son.
///
/// L'atténuation suit maintenant le NUMÉRO de la note dans la gamme, par
/// interpolation en décibels entre les quatre repères. Les do tombent
/// exactement sur les valeurs d'avant, et il n'y a plus une seule marche.
/// Au-delà de do5, la dernière pente continue.
double volumeFactorFor(String name) {
  final index = noteIndexOf(name);
  if (index == null) return 1;
  // En décibels, pour que la progression s'entende régulière : l'oreille
  // suit le logarithme, pas l'amplitude.
  final position = index / 7.0;
  final i = position.floor().clamp(0, kVolumeOctaves.length - 2);
  final t = position - i;
  final a = _db(kVolumeOctaves[i]);
  final b = _db(kVolumeOctaves[i + 1]);
  return _amp(a + (b - a) * t);
}

double _db(double amp) => 20 * (math.log(amp) / math.ln10);

double _amp(double db) => math.pow(10, db / 20).toDouble();

/// Numéro d'une note dans la gamme complète, de `do2` (0) à `si5` (27).
///
/// `null` pour tout ce qui n'est pas une note — `ejection`, `fugue`…
int? noteIndexOf(String name) {
  if (name.length < 3) return null;
  final octave = int.tryParse(name.substring(name.length - 1));
  if (octave == null) return null;
  final col = kSoundNotes.indexOf(name.substring(0, name.length - 1));
  if (col < 0) return null;
  if (!kSoundOctaves.contains(octave)) return null;
  return _noteIndex(col, octave);
}

/// Un son à jouer, avec son retard depuis le début du coup.
final class SoundCue {
  const SoundCue(this.name, this.delay);

  /// Nom du fichier sans extension : `fa5`, `ejection`, `fugue`…
  final String name;

  /// Retard avant lecture.
  final Duration delay;

  /// Volume relatif, avant application du volume général.
  double get volumeFactor => volumeFactorFor(name);

  @override
  bool operator ==(Object other) =>
      other is SoundCue && other.name == name && other.delay == delay;

  @override
  int get hashCode => Object.hash(name, delay);

  @override
  String toString() => '$name@${delay.inMilliseconds}ms';
}

/// Index d'une note dans la gamme complète : 4 octaves × 7 notes = 28.
int _noteIndex(int col, int octave) => (octave - 2) * 7 + col;

/// Notes d'un glissando arrivant **sur** la case cible.
///
/// [direction] vaut `+1` pour monter vers la cible, `-1` pour descendre.
/// La dernière note est toujours celle de la case cible.
List<String> glissandoNotes(
  int targetCol,
  int targetRow,
  int count,
  int direction,
) {
  if (count < 1) count = 1;
  final targetIndex = _noteIndex(targetCol, octaveForRow(targetRow));
  final notes = <String>[];
  for (var k = count - 1; k >= 0; k--) {
    final idx = (targetIndex - direction * k).clamp(0, 27);
    final octave = 2 + idx ~/ 7;
    final col = idx % 7;
    notes.add('${kSoundNotes[col]}$octave');
  }
  return notes;
}

const Duration _glissandoStep = Duration(milliseconds: 100);
const Duration _arrivalDelay = Duration(milliseconds: 250);

/// Traduit une notation `.nmc` en suite de sons.
///
/// Renvoie une liste vide si la notation n'est pas exploitable — on préfère
/// le silence à un son faux.
List<SoundCue> planForNotation(String? notation) {
  if (notation == null) return const [];
  var n = notation.trim();
  if (n.isEmpty) return const [];

  final cues = <SoundCue>[];
  // La marque de mat ne fait pas partie du coup : elle ne s'entend pas.
  if (n.endsWith('#')) n = n.substring(0, n.length - 1);

  // ── Manœuvre : note de la maîtresse, puis glissando descendant ──
  if (n.startsWith('(')) {
    final match = RegExp(r'^\((.*)\)-(.+)$').firstMatch(n);
    if (match != null) {
      final cells = parseCellsConcat(match.group(1)!);
      if (cells != null && cells.isNotEmpty) {
        final note = noteForCell(cells.first.col, cells.first.row);
        if (note != null) cues.add(SoundCue(note, Duration.zero));
      }
      final dest = notationToCell(match.group(2)!);
      if (dest != null) {
        _addGlissando(cues, dest, 4, -1, _arrivalDelay);
      }
    }
    return cues;
  }

  // ── Fugue sur case non nommable : « Départ* » ──
  if (n.contains('*') && !n.contains('-')) {
    final start = notationToCell(n.replaceAll('*', '').trim());
    if (start != null) {
      final note = noteForCell(start.col, start.row);
      if (note != null) cues.add(SoundCue(note, Duration.zero));
    }
    return cues;
  }

  // ── Déplacement, saut ou poussée ──
  final hasPush = n.contains('>');
  var movePart = hasPush ? n.split('>').first : n;
  if (movePart.endsWith('*')) {
    movePart = movePart.substring(0, movePart.length - 1);
  }

  final parts = movePart.split('-');
  final start = notationToCell(parts.first);
  final end = parts.length > 1 ? notationToCell(parts[1]) : null;

  if (start != null) {
    final note = noteForCell(start.col, start.row);
    if (note != null) cues.add(SoundCue(note, Duration.zero));
  }

  if (end != null) {
    if (hasPush) {
      // Une poussée monte vers la note d'arrivée : on entend la ligne partir.
      _addGlissando(cues, end, 4, 1, _arrivalDelay);
    } else {
      final note = noteForCell(end.col, end.row);
      if (note != null) cues.add(SoundCue(note, _arrivalDelay));
    }
  }

  return cues;
}

void _addGlissando(
  List<SoundCue> cues,
  Cell target,
  int count,
  int direction,
  Duration initialDelay,
) {
  final notes = glissandoNotes(target.col, target.row, count, direction);
  for (var i = 0; i < notes.length; i++) {
    cues.add(SoundCue(notes[i], initialDelay + _glissandoStep * i));
  }
}
