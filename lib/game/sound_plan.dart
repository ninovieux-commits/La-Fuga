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

/// Atténuation par octave.
///
/// Les graves servent de référence et les aigus sont nettement baissés :
/// sans cela, une note aiguë écrase tout le reste.
double volumeFactorFor(String name) {
  if (name.isEmpty) return 1;
  final last = name.codeUnitAt(name.length - 1);
  if (last < 0x30 || last > 0x39) return 1;
  return switch (name[name.length - 1]) {
    '5' => 0.40,
    '4' => 0.55,
    '3' => 0.80,
    _ => 1.0,
  };
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
