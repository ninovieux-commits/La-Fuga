/// Tutoriel — portage de `TutoScreen` (main.py).
///
/// Dart pur : les 22 étapes et leur machine à phases se testent sans écran.
/// Le principe de Kivy est conservé : une étape interactive rejoue le **vrai**
/// mécanisme du jeu (sélectionner, déplacer, valider), mais seul le coup prévu
/// est possible, et le texte change à chaque phase.
library;

import 'dart:convert';

import '../engine/board.dart';
import '../engine/piece.dart';
import '../ui/tuto/tuto_data.g.dart';

/// Les sept colonnes, nommées comme les notes.
const List<String> kTutoNotes = ['do', 'ré', 'mi', 'fa', 'sol', 'la', 'si'];

/// Phases d'une étape.
enum TutoPhase {
  /// Cliquer la pièce.
  select,

  /// La déplacer.
  move,

  /// Ajouter les membres du groupe (manœuvre).
  group,

  /// Déplacer le groupe.
  groupMove,

  /// Choisir la direction de poussée.
  push,

  /// Recliquer la pièce pour valider.
  validate,

  /// Étape réussie.
  done,
}

/// Un lien dessiné entre des cases (illustration des groupes).
final class TutoLink {
  const TutoLink(this.pairs, this.color);

  final List<(Cell, Cell)> pairs;

  /// Couleur, en composantes 0..1 comme en Kivy.
  final (double, double, double) color;
}

/// Un faux élément d'interface, dessiné par-dessus le plateau pour illustrer
/// une fin de partie (bouton d'abandon, chrono à zéro…).
final class TutoMockElement {
  const TutoMockElement({
    required this.text,
    required this.fx,
    required this.fy,
    required this.fw,
    required this.fh,
    required this.color,
    this.circled = false,
  });

  final String text;

  /// Position et taille, en fractions de la zone du plateau.
  final double fx;
  final double fy;
  final double fw;
  final double fh;

  final (double, double, double) color;
  final bool circled;
}

/// Ce qu'il faut dessiner par-dessus le plateau à un instant donné.
final class TutoAnnotations {
  const TutoAnnotations({
    this.framed = const [],
    this.framedOk = const [],
    this.framedBlue = const [],
    this.framedSelected = const [],
    this.arrows = const [],
    this.links = const [],
  });

  /// Cases encadrées en rouge (à remarquer, ou bloquées).
  final List<Cell> framed;

  /// Cases encadrées en vert (ce qui marche).
  final List<Cell> framedOk;

  final List<Cell> framedBlue;

  /// Case de la pièce à cliquer.
  final List<Cell> framedSelected;

  final List<(Cell, Cell)> arrows;
  final List<TutoLink> links;
}

/// Une étape du tuto.
final class TutoStep {
  TutoStep(this.raw);

  final Map<String, dynamic> raw;

  String get title => '${raw['title'] ?? ''}';

  bool get interactive => raw['interactive'] == true;
  bool get isManeuver => raw['maneuver'] == true;
  bool get isPush => raw['push'] == true;

  /// Grand texte de transition, à la place du plateau.
  String? get banner => raw['banner'] as String?;

  String get text => '${raw['text'] ?? ''}';
  String get textSelect => '${raw['text_select'] ?? ''}';
  String get textMove => '${raw['text_move'] ?? ''}';
  String get textGroup => '${raw['text_group'] ?? ''}';
  String get textPush => '${raw['text_push'] ?? ''}';
  String get textValidate => '${raw['text_validate'] ?? ''}';
  String get textDone => '${raw['text_done'] ?? ''}';

  Cell? get move => _cellOrNull(raw['move']);
  Cell? get leader => _cellOrNull(raw['leader']);
  Cell? get moveTo => _cellOrNull(raw['move_to']);
  Cell? get pushTo => _cellOrNull(raw['push_to']);
  Cell? get doneFrame => _cellOrNull(raw['done_frame']);

  List<Cell> get dests => _cells(raw['dests']);
  List<Cell> get groupAdd => _cells(raw['group_add']);

  /// Sauts guidés : chaque étape a sa case et son texte.
  List<({Cell dest, String text})> get sequence => [
    for (final s in raw['sequence'] as List? ?? const [])
      (dest: _cell((s as Map)['dest']), text: '${s['text'] ?? ''}'),
  ];

  /// Poussées successives, pour l'étape à plusieurs directions.
  List<({Cell pushTo, String text})> get pushes => [
    for (final p in raw['pushes'] as List? ?? const [])
      (pushTo: _cell((p as Map)['push_to']), text: '${p['text'] ?? ''}'),
  ];

  List<Cell> get framed => _cells(raw['framed']);
  List<Cell> get framedOk => _cells(raw['framed_ok']);
  List<Cell> get framedBlue => _cells(raw['framed_blue']);

  List<(Cell, Cell)> get arrows => [
    for (final a in raw['arrows'] as List? ?? const [])
      (_cell((a as List)[0]), _cell(a[1])),
  ];

  List<TutoLink> get links => [
    for (final l in raw['links'] as List? ?? const [])
      TutoLink([
        for (final p in (l as Map)['pairs'] as List? ?? const [])
          (_cell((p as List)[0]), _cell(p[1])),
      ], _color(l['color'])),
  ];

  List<TutoMockElement> get mockUi => [
    for (final m in raw['mock_ui'] as List? ?? const [])
      TutoMockElement(
        text: '${(m as Map)['text'] ?? ''}',
        fx: _double(m['fx']),
        fy: _double(m['fy']),
        fw: _double(m['fw']),
        fh: _double(m['fh']),
        color: _color(m['bg']),
        circled: m['circle'] == true,
      ),
  ];

  /// Plateau de départ de l'étape.
  Board board() {
    final b = Board.empty();
    for (final p in raw['pieces'] as List? ?? const []) {
      final row = (p as List)[1] as int;
      b.set(
        kTutoNotes.indexOf('${p[0]}'),
        row - 1,
        Piece(PieceType.fromWire('${p[2]}'), Camp.fromWire('${p[3]}')),
      );
    }
    return b;
  }
}

/// Lit une case du tuto : `["fa", 4]`, ou `["fa", "out"]` pour le ralliement
/// du joueur, qui est hors plateau.
///
/// Les données comptent les lignes de 1 à 8, le plateau de 0 à 7.
Cell _cell(Object? raw) {
  final list = raw as List;
  final row = list[1];
  return Cell(
    kTutoNotes.indexOf('${list[0]}'),
    row == 'out' ? kRows : (row as int) - 1,
  );
}

Cell? _cellOrNull(Object? raw) => raw == null ? null : _cell(raw);

List<Cell> _cells(Object? raw) => [
  for (final c in raw as List? ?? const []) _cell(c),
];

double _double(Object? v) => (v as num?)?.toDouble() ?? 0;

(double, double, double) _color(Object? raw) {
  final l = raw as List? ?? const [0.4, 0.4, 0.4];
  return (_double(l[0]), _double(l[1]), _double(l[2]));
}

/// Les 22 étapes, lues une fois.
List<TutoStep> loadTutoSteps([String json = kTutoStepsJson]) => [
  for (final s in jsonDecode(json) as List)
    TutoStep(Map<String, dynamic>.from(s as Map)),
];

/// Déroulement du tuto : navigation entre les étapes, et machine à phases des
/// étapes interactives.
class TutoController {
  TutoController({List<TutoStep>? steps}) : steps = steps ?? loadTutoSteps() {
    _enter();
  }

  final List<TutoStep> steps;

  int _index = 0;
  late Board _board;
  TutoPhase _phase = TutoPhase.select;
  bool _stepDone = false;

  Cell? _selected;
  final Set<Cell> _groupSelected = {};
  Cell? _movedTo;
  int _seqIndex = 0;
  int _groupIndex = 0;
  int _pushIndex = 0;

  /// Héritiers dessinés dans leur zone de ralliement, après une fugue.
  final List<({Cell cell, Camp camp})> _fugued = [];

  int get index => _index;
  int get stepCount => steps.length;
  TutoStep get step => steps[_index];
  Board get board => _board;
  TutoPhase get phase => _phase;
  bool get stepDone => _stepDone;

  Cell? get selected => _selected;
  Set<Cell> get groupSelected => Set.unmodifiable(_groupSelected);
  List<({Cell cell, Camp camp})> get fugued => List.unmodifiable(_fugued);

  bool get atFirst => _index == 0;
  bool get atLast => _index == steps.length - 1;

  /// Une étape interactive verrouille « Suivant » tant que le coup n'est pas
  /// joué : le tuto se fait, il ne se survole pas.
  bool get canGoNext => !step.interactive || _stepDone;

  /// (Re)prépare l'étape courante.
  void _enter() {
    _board = step.board();
    _phase = TutoPhase.select;
    _stepDone = false;
    _selected = null;
    _groupSelected.clear();
    _movedTo = null;
    _seqIndex = 0;
    _groupIndex = 0;
    _pushIndex = 0;
    _fugued.clear();
  }

  bool goTo(int index) {
    if (index < 0 || index >= steps.length || index == _index) return false;
    _index = index;
    _enter();
    return true;
  }

  bool previous() => goTo(_index - 1);

  bool next() => canGoNext && goTo(_index + 1);

  /// Le joueur touche une case. Renvoie vrai si quelque chose a changé.
  bool tap(Cell cell) {
    if (!step.interactive || _stepDone) return false;
    if (step.isManeuver) return _tapManeuver(cell);
    if (step.isPush) return _tapPush(cell);
    return _tapMove(cell);
  }

  // ── Déplacement simple et multisaut ──

  bool _tapMove(Cell cell) {
    final from = _selected ?? step.move!;
    final sequence = step.sequence;

    switch (_phase) {
      case TutoPhase.select:
        if (cell != step.move) return false;
        _selected = cell;
        _phase = TutoPhase.move;
        _seqIndex = 0;
        return true;

      case TutoPhase.move:
        if (sequence.isNotEmpty) {
          if (cell == sequence[_seqIndex].dest) return _applyMove(from, cell);
          // Recliquer la pièce avant le premier saut la désélectionne.
          if (cell == from && _seqIndex == 0) return _deselect();
          return false;
        }
        if (step.dests.contains(cell)) return _applyMove(from, cell);
        if (cell == from) return _deselect();
        return false;

      case TutoPhase.validate:
        if (cell != _movedTo) return false;
        return _finishStep();

      default:
        return false;
    }
  }

  bool _deselect() {
    _selected = null;
    _phase = TutoPhase.select;
    return true;
  }

  /// Joue un déplacement ou un saut. Sortir du plateau est une fugue, qui
  /// termine l'étape aussitôt.
  bool _applyMove(Cell from, Cell to) {
    final piece = _board.at(from.col, from.row);
    if (piece == null) return false;

    _board.set(from.col, from.row, null);

    if (!to.onBoard) {
      _fugued.add((cell: to, camp: piece.camp));
      _selected = null;
      _movedTo = null;
      return _finishStep();
    }

    _board.set(to.col, to.row, piece);
    _selected = to;
    _movedTo = to;

    final sequence = step.sequence;
    if (sequence.isNotEmpty) {
      _seqIndex++;
      _phase = _seqIndex < sequence.length
          ? TutoPhase.move
          : TutoPhase.validate;
    } else {
      _phase = TutoPhase.validate;
    }
    return true;
  }

  // ── Manœuvre de groupe ──

  bool _tapManeuver(Cell cell) {
    final group = step.groupAdd;

    switch (_phase) {
      case TutoPhase.select:
        if (cell != (_selected ?? step.leader)) return false;
        _selected = cell;
        _groupIndex = 0;
        _phase = group.isEmpty ? TutoPhase.groupMove : TutoPhase.group;
        return true;

      case TutoPhase.group:
        if (_groupIndex >= group.length || cell != group[_groupIndex]) {
          return false;
        }
        _groupSelected.add(cell);
        _groupIndex++;
        _phase = _groupIndex < group.length
            ? TutoPhase.group
            : TutoPhase.groupMove;
        return true;

      case TutoPhase.groupMove:
        if (cell != step.moveTo) return false;
        return _applyManeuver(_selected!, cell);

      case TutoPhase.validate:
        if (cell != _movedTo) return false;
        _groupSelected.clear();
        return _finishStep();

      default:
        return false;
    }
  }

  /// Décale en bloc la meneuse et les membres choisis. Les autres pièces ne
  /// bougent pas.
  bool _applyManeuver(Cell leader, Cell moveTo) {
    final dc = moveTo.col - leader.col;
    final dr = moveTo.row - leader.row;
    final cells = [leader, ..._groupSelected];
    final pieces = {for (final c in cells) c: _board.at(c.col, c.row)};

    for (final c in cells) {
      _board.set(c.col, c.row, null);
    }
    for (final e in pieces.entries) {
      _board.set(e.key.col + dc, e.key.row + dr, e.value);
    }

    _selected = Cell(leader.col + dc, leader.row + dr);
    final moved = {
      for (final c in _groupSelected) Cell(c.col + dc, c.row + dr),
    };
    _groupSelected
      ..clear()
      ..addAll(moved);
    _movedTo = _selected;
    _phase = TutoPhase.validate;
    return true;
  }

  // ── Poussée ──

  bool _tapPush(Cell cell) {
    switch (_phase) {
      case TutoPhase.select:
        if (cell != (_selected ?? step.leader)) return false;
        _selected = cell;
        _phase = TutoPhase.move;
        return true;

      case TutoPhase.move:
        if (cell != step.moveTo) return false;
        final from = _selected!;
        final piece = _board.at(from.col, from.row);
        if (piece == null) return false;
        _board.set(from.col, from.row, null);
        _board.set(cell.col, cell.row, piece);
        _selected = cell;
        _phase = TutoPhase.push;
        return true;

      case TutoPhase.push:
        final pushes = step.pushes;
        final target = pushes.isNotEmpty
            ? pushes[_pushIndex].pushTo
            : step.pushTo;
        if (cell != target) return false;
        return _applyPush(_selected!, cell, multi: pushes.isNotEmpty);

      case TutoPhase.validate:
        if (cell != _movedTo) return false;
        return _finishStep();

      default:
        return false;
    }
  }

  /// Pousse toute la ligne d'une case. Une pièce sortie est éliminée ; un
  /// Héritier sorti est maté, sauf s'il rejoint son ralliement : c'est alors
  /// une fugue. Un Chevalier bloque toute la poussée.
  bool _applyPush(Cell pusher, Cell pushTo, {required bool multi}) {
    final dc = pushTo.col - pusher.col;
    final dr = pushTo.row - pusher.row;

    final line = <Cell>[];
    var c = pusher.col + dc;
    var r = pusher.row + dr;
    while (Board.onBoard(c, r)) {
      final p = _board.at(c, r);
      if (p == null) break;
      if (p.type == PieceType.chevalier) {
        line.clear();
        break;
      }
      line.add(Cell(c, r));
      c += dc;
      r += dr;
    }

    var won = false;
    for (final cell in line.reversed) {
      final piece = _board.at(cell.col, cell.row)!;
      final to = Cell(cell.col + dc, cell.row + dr);
      _board.set(cell.col, cell.row, null);

      if (to.onBoard) {
        _board.set(to.col, to.row, piece);
        continue;
      }
      // Sortie du plateau.
      if (piece.type != PieceType.heritier) continue;
      won = true;
      final rallied =
          kRally.contains(to.col) &&
          ((piece.camp == Camp.blanc && to.row >= kRows) ||
              (piece.camp == Camp.noir && to.row < 0));
      if (rallied) _fugued.add((cell: to, camp: piece.camp));
    }

    _movedTo = pusher;
    if (won) return _finishStep();

    if (multi) {
      _pushIndex++;
      _phase = _pushIndex < step.pushes.length
          ? TutoPhase.push
          : TutoPhase.validate;
    } else {
      _phase = TutoPhase.validate;
    }
    return true;
  }

  bool _finishStep() {
    _selected = null;
    _phase = TutoPhase.done;
    _stepDone = true;
    return true;
  }

  /// Le texte à afficher, selon l'étape et la phase.
  String get text {
    if (!step.interactive) return step.text;
    return switch (_phase) {
      TutoPhase.select => step.textSelect,
      TutoPhase.group => step.textGroup,
      TutoPhase.move => _moveText,
      TutoPhase.groupMove => step.textMove,
      TutoPhase.push => _pushText,
      TutoPhase.validate => step.textValidate,
      TutoPhase.done => step.textDone,
    };
  }

  String get _moveText {
    final sequence = step.sequence;
    if (sequence.isEmpty) return step.textMove;
    final t = sequence[_seqIndex].text;
    return t.isEmpty ? step.textMove : t;
  }

  String get _pushText {
    final pushes = step.pushes;
    if (pushes.isEmpty) return step.textPush;
    final t = pushes[_pushIndex].text;
    return t.isEmpty ? step.textPush : t;
  }

  /// Ce qu'il faut dessiner par-dessus le plateau.
  TutoAnnotations get annotations {
    if (!step.interactive) {
      return TutoAnnotations(
        framed: step.framed,
        framedOk: step.framedOk,
        framedBlue: step.framedBlue,
        arrows: step.arrows,
        links: step.links,
      );
    }

    return switch (_phase) {
      // À la sélection, on montre aussi l'illustration de l'étape (groupes,
      // liens) : c'est le moment où le joueur regarde le plateau.
      TutoPhase.select => TutoAnnotations(
        framedSelected: [step.move ?? step.leader!],
        framedOk: step.framedOk,
        framedBlue: step.framedBlue,
        links: step.links,
      ),
      TutoPhase.group => TutoAnnotations(
        framedSelected: [step.groupAdd[_groupIndex]],
      ),
      TutoPhase.move => _moveAnnotations,
      TutoPhase.groupMove => TutoAnnotations(
        arrows: [(_selected!, step.moveTo!)],
      ),
      TutoPhase.push => TutoAnnotations(
        arrows: [
          (
            _selected!,
            step.pushes.isNotEmpty
                ? step.pushes[_pushIndex].pushTo
                : step.pushTo!,
          ),
        ],
      ),
      TutoPhase.validate => TutoAnnotations(framedSelected: [_movedTo!]),
      TutoPhase.done => TutoAnnotations(
        framed: [if (step.doneFrame != null) step.doneFrame!],
      ),
    };
  }

  TutoAnnotations get _moveAnnotations {
    final sequence = step.sequence;
    if (sequence.isEmpty) return TutoAnnotations(arrows: step.arrows);
    // Multisaut : seule la flèche du saut courant, depuis la pièce.
    return TutoAnnotations(arrows: [(_selected!, sequence[_seqIndex].dest)]);
  }
}
