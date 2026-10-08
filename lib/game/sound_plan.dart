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

/// Instruments disponibles, dans l'ordre du sélecteur des réglages.
///
/// Les quatre derniers ont été choisis sur la MESURE de leur attaque : une
/// note doit parler en moins d'une centaine de millisecondes, sinon elle
/// arrive après le doigt. La banque en compte 128, mais un violon met 465 ms
/// à parler et un violoncelle 1184 — ils sont inutilisables ici.
const List<String> kInstruments = [
  'piano',
  'orgue',
  'guitare',
  'cloche',
  'xylophone',
  'harpe',
  'choeur',
];

/// Les quatre octaves des fichiers de notes.
const List<int> kSoundOctaves = [2, 3, 4, 5];

/// Les deux octaves du plateau : une par moitié.
///
/// Tout le jeu tient sur deux octaves. Il en utilisait quatre, réparties par
/// rangée selon une table où les rangées 1, 4, 5 et 8 sonnaient toutes à
/// l'octave 5 : un coup d'une rangée à l'autre pouvait sauter de deux
/// octaves, et l'oreille n'y entendait aucune géographie.
///
/// Maintenant, chaque moitié de plateau a son octave. Avancer vers
/// l'adversaire monte d'une octave, une seule fois, au milieu — et ce
/// franchissement s'entend pour ce qu'il est.
const int kOctaveProche = 3;
const int kOctaveLointaine = 4;

/// Octave associée à une rangée : la moitié d'où vient la case.
int octaveForRow(int row) => row + 1 <= 4 ? kOctaveProche : kOctaveLointaine;

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
  const SoundCue(this.name, this.delay, {this.gain = 1});

  /// Nom du fichier sans extension : `fa5`, `ejection`, `fugue`…
  final String name;

  /// Retard avant lecture.
  final Duration delay;

  /// Volume relatif, avant application du volume général.
  double get volumeFactor => volumeFactorFor(name);

  /// Volume voulu par l'APPELANT, en plus de celui du son lui-même.
  ///
  /// C'est par là que passe l'accent d'une danse : dans une mesure mixée d'un
  /// seul tenant, chaque note porte le sien. Vaut 1 partout ailleurs.
  final double gain;

  /// Le même son, à un autre instant et à un autre volume.
  SoundCue decale(Duration de, {double? gain}) =>
      SoundCue(name, delay + de, gain: gain ?? this.gain);

  @override
  bool operator ==(Object other) =>
      other is SoundCue &&
      other.name == name &&
      other.delay == delay &&
      other.gain == gain;

  @override
  int get hashCode => Object.hash(name, delay, gain);

  @override
  String toString() => '$name@${delay.inMilliseconds}ms';
}

/// Index d'une note dans la gamme complète : 4 octaves × 7 notes = 28.
int _noteIndex(int col, int octave) => (octave - 2) * 7 + col;

/// Notes d'un glissando arrivant **sur** la case cible.
///
/// Plus utilisée en partie : un coup se dit en DEUX sons, celui de la case
/// d'où l'on vient et celui de la case où l'on arrive, et rien d'autre. Les
/// notes intermédiaires d'un glissando ne correspondaient à aucune case.
///
/// Elle survit pour le son de NOTIFICATION (`tool/gen_notif_sound.dart`),
/// qui est un petit motif de quatre notes montantes et n'a rien à voir avec
/// la géographie du plateau.
///
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

/// Notes d'un glissando PARTANT de la case d'arrivée.
///
/// [direction] vaut `+1` pour monter, `-1` pour descendre. La première note
/// est toujours celle de la case où la pièce arrive.
///
/// À ne pas confondre avec [glissandoNotes], qui ARRIVE sur sa cible et ne
/// sert plus qu'au son de notification.
///
/// Les notes débordent au besoin sur les octaves voisines : descendre de
/// trois notes depuis le bas du plateau n'a pas d'autre issue, et répéter
/// trois fois la même note ne serait pas un glissando. Le plateau, lui,
/// tient bien sur ses deux octaves.
List<String> glissandoDepuis(
  int startCol,
  int startRow,
  int count,
  int direction,
) {
  if (count < 1) count = 1;
  final depart = _noteIndex(startCol, octaveForRow(startRow));
  final notes = <String>[];
  for (var k = 0; k < count; k++) {
    final idx = (depart + direction * k).clamp(0, 27);
    notes.add('${kSoundNotes[idx % 7]}${2 + idx ~/ 7}');
  }
  return notes;
}

/// Trois notes : assez pour s'entendre comme un mouvement, assez peu pour
/// ne pas déborder sur le coup suivant.
const int kGlissandoCount = 3;

/// Les trois notes du son de NOTIFICATION : la descente la plus grave.
///
/// Choisies à l'oreille par Nino parmi dix concurrents — sept instruments,
/// deux tempos, deux registres. Le son montait jusqu'au milieu de la
/// tessiture, du temps où tous les glissandos du jeu montaient ; depuis, le
/// sens dit quelque chose — une poussée descend, un groupe monte — et une
/// notification qui monte aurait annoncé un déplacement de groupe.
///
/// Elles ne viennent PAS d'une case, et c'est voulu : le plateau ne tient
/// que sur deux octaves et aucune de ses rangées ne descend jusqu'à
/// l'octave 2. Une notification n'est pas un coup, elle n'a pas de case.
const List<String> kNotesNotification = ['mi2', 're2', 'do2'];

/// L'écart entre deux notes de la notification.
///
/// Le jeu en met cent ; vingt de plus ici, parce qu'une notification n'est
/// pas un coup joué — elle a le droit de respirer.
const int kPasNotification = 120;

const Duration _glissandoStep = Duration(milliseconds: 100);

/// Traduit une notation `.nmc` en suite de sons.
///
/// On entend la case d'ARRIVÉE, et elle seule — pas celle de départ.
///
/// Et le glissando dit combien de pièces ont bougé :
///
///   une seule pièce        une note, celle de l'arrivée ;
///   une poussée            trois notes qui DESCENDENT depuis l'arrivée —
///                          la pièce entraîne la ligne derrière elle ;
///   un déplacement de      trois notes qui MONTENT depuis l'arrivée —
///   groupe                 plusieurs carrés avancent de concert.
///
/// Le glissando part donc toujours de la case où la pièce arrive.
///
/// La fugue fait exception, et elle n'a pas le choix : sa case d'arrivée est
/// hors du plateau et n'a pas de nom. Un seul son, celui du départ.
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

  // ── Manœuvre : plusieurs carrés avancent ensemble, donc ça MONTE ──
  if (n.startsWith('(')) {
    final match = RegExp(r'^\((.*)\)-(.+)$').firstMatch(n);
    if (match != null) {
      final dest = notationToCell(match.group(2)!);
      if (dest != null) _ajouteGlissando(cues, dest, 1);
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

  if (end == null) {
    // Pas de case d'arrivée nommée : il ne reste que le départ. C'est le cas
    // d'une notation qu'on ne sait pas lire entièrement — mieux vaut un son
    // juste qu'un silence.
    if (start != null) {
      final note = noteForCell(start.col, start.row);
      if (note != null) cues.add(SoundCue(note, Duration.zero));
    }
    return cues;
  }

  // Une poussée déplace la pièce ET la ligne qu'elle pousse : ça DESCEND.
  // Un déplacement ordinaire ne bouge qu'une pièce : une seule note.
  if (hasPush) {
    _ajouteGlissando(cues, end, -1);
  } else {
    final note = noteForCell(end.col, end.row);
    if (note != null) cues.add(SoundCue(note, Duration.zero));
  }

  return cues;
}

/// Le glissando d'un coup où PLUSIEURS pièces bougent, depuis l'arrivée.
void _ajouteGlissando(List<SoundCue> cues, Cell depart, int direction) {
  final notes = glissandoDepuis(
    depart.col,
    depart.row,
    kGlissandoCount,
    direction,
  );
  for (var i = 0; i < notes.length; i++) {
    cues.add(SoundCue(notes[i], _glissandoStep * i));
  }
}
