/// Machine à états de l'interaction — portage de `handle_cell`, `_no_sel`,
/// `_with_sel`, `_try_maneuver` et `do_push` (GameScreen, main.py).
///
/// Dart pur, aucun import Flutter : la logique de jeu est testable sans
/// interface, et c'est elle qui décide — jamais l'animation.
///
/// L'interaction est **incrémentale**, comme en Kivy : on ne choisit pas un
/// coup dans une liste. On touche une pièce, on la déplace, puis on pousse
/// direction par direction ou on compose un groupe, et on **valide en
/// retouchant la pièce**. C'est ce qui permet de choisir *quelles* poussées
/// appliquer parmi celles que le déplacement active.
library;

import '../engine/board.dart';
import '../engine/move.dart';
import '../engine/move_generator.dart';
import '../engine/notation.dart';
import 'captures.dart';
import '../engine/piece.dart';

/// Ce que le contrôleur demande à l'interface après un geste.
enum ControllerEffect {
  /// Rien de visible n'a changé (geste ignoré).
  none,

  /// La sélection a changé : redessiner.
  selectionChanged,

  /// Des pièces ont bougé : redessiner, éventuellement animer.
  boardChanged,

  /// Le coup est validé : notation disponible, c'est au camp suivant.
  turnEnded,

  /// La partie est terminée.
  gameOver,
}

/// Résultat d'un geste.
final class ControllerResult {
  const ControllerResult(
    this.effect, {
    this.notation,
    this.slides = const [],
    this.hadEjection = false,
    this.endReason,
    this.loser,
    this.camp,
    this.pushTargets = const [],
    this.jumpPath = const [],
  });

  final ControllerEffect effect;

  /// Notation `.nmc` du coup validé, quand [effect] vaut `turnEnded`.
  final String? notation;

  /// Glissements à animer : (pièce, départ, arrivée). Une arrivée hors
  /// plateau est une éjection.
  final List<(Piece, Cell, Cell)> slides;

  /// Vrai si le coup a éjecté au moins une pièce (son d'éjection).
  final bool hadEjection;

  /// Méthode de fin : `fugue`, `mat`, `papatte`, `nulle_pat`, `repetition`…
  final String? endReason;

  /// Camp perdant ; nul pour une partie nulle.
  final Camp? loser;

  /// Camp qui vient de jouer. Sert à colorer la mise en évidence du coup.
  final Camp? camp;

  /// Cases effectivement poussées, pour marquer les directions de poussée.
  final List<Cell> pushTargets;

  /// Atterrissages intermédiaires d'un multisaut.
  final List<Cell> jumpPath;
}

/// État courant de la construction d'un coup.
final class MoveTracking {
  Cell? start;
  bool isPush = false;
  bool isManeuver = false;
  List<Cell> maneuverPieces = [];
  List<Cell> pushTargets = [];
  List<Cell> pushableDirs = [];
  bool hadEjection = false;

  /// Ronde sautée au saut précédent : on ne peut pas la re-sauter
  /// immédiatement (mais on pourra plus tard).
  Cell? lastJumpedRound;

  /// Atterrissages d'un multisaut, sans l'arrivée finale : ce sont les petits
  /// carrés que Kivy dessine sur le chemin du dernier coup.
  List<Cell> jumpPath = [];

  void reset() {
    start = null;
    isPush = false;
    isManeuver = false;
    maneuverPieces = [];
    pushTargets = [];
    pushableDirs = [];
    hadEjection = false;
    lastJumpedRound = null;
    jumpPath = [];
  }
}

/// Contrôleur d'une partie en cours.
class MoveController {
  MoveController({
    Board? board,
    this.turn = Camp.blanc,
    this.countRepetitions = true,
    Map<Camp, List<Piece>>? captured,
    Set<Camp> fugued = const {},
  }) : board = board ?? Board.initial(),
       fuguedHeirs = {...fugued},
       captured = {
         for (final camp in Camp.values) camp: [...?captured?[camp]],
       } {
    _turnStartBoard = this.board.clone();
    _turnStartCaptured = _capturedCounts();
  }

  /// Compter les répétitions de position (nulle à la quatrième).
  ///
  /// Désactivé en analyse : on y explore librement, revenir sur ses pas ne
  /// doit pas clore la partie — portage de la garde `not self.analysis_mode`
  /// de Kivy.
  final bool countRepetitions;

  Board board;
  Camp turn;

  /// Pièce sélectionnée.
  Cell? selected;

  /// Autres pièces du groupe retenu pour une manœuvre.
  Set<Cell> groupSelection = {};

  /// La pièce a déjà bougé : le coup est en cours de construction.
  bool moved = false;

  /// Le déplacement a activé la poussée : les clics suivants poussent.
  bool pushOn = false;

  /// On est en train d'enchaîner des sauts.
  bool jumping = false;

  final MoveTracking tracking = MoveTracking();

  /// Pièces éjectées, par camp.
  /// Pièces sorties du plateau, rangées au camp qui les a PERDUES.
  ///
  /// Une partie reprise en cours de route — la correspondance, une analyse
  /// qui repart d'une position passée — les reçoit à la construction : les
  /// recompter après coup laisserait le repère d'annulation à zéro, et le
  /// premier coup annulé effacerait tout le tableau.
  final Map<Camp, List<Piece>> captured;

  /// Camps dont l'Héritier a fugué, à afficher en permanence dans son
  /// ralliement.
  ///
  /// Le camp suffit : la case d'affichage est toujours le milieu du
  /// ralliement ([rallyDisplayCell]), et un camp n'a qu'un Héritier. Une
  /// partie reprise en route — correspondance, reconnexion, analyse — la
  /// reçoit à la construction, sinon l'Héritier manquerait à l'écran alors
  /// qu'il manque au plateau.
  final Set<Camp> fuguedHeirs;

  /// Notations jouées, dans l'ordre.
  final List<String> history = [];

  /// Combien de fois chaque position (plateau + trait) est survenue.
  final Map<String, int> positionCounts = {};

  bool gameOver = false;

  /// Plateau au début du tour, pour annuler un coup en cours.
  late Board _turnStartBoard;

  // ── Geste principal ───────────────────────────────────────────────────────

  /// Traite un appui sur une case.
  ControllerResult tapCell(Cell cell) {
    if (gameOver) return const ControllerResult(ControllerEffect.none);
    return selected == null
        ? _tapWithoutSelection(cell)
        : _tapWithSelection(cell);
  }

  ControllerResult _tapWithoutSelection(Cell cell) {
    if (!cell.onBoard) return const ControllerResult(ControllerEffect.none);
    final p = board.atCell(cell);
    if (p == null || p.camp != turn) {
      return const ControllerResult(ControllerEffect.none);
    }
    // Une pièce immobilisée ne se sélectionne pas : c'est la même condition
    // que le contour rouge à l'écran.
    if (board.isImmobilised(cell.col, cell.row)) {
      return const ControllerResult(ControllerEffect.none);
    }

    selected = cell;
    groupSelection = {};
    moved = false;
    pushOn = false;
    jumping = false;
    tracking.reset();
    tracking.start = cell;
    return const ControllerResult(ControllerEffect.selectionChanged);
  }

  ControllerResult _tapWithSelection(Cell cell) {
    final from = selected!;
    final piece = board.atCell(from);
    if (piece == null) return const ControllerResult(ControllerEffect.none);
    final dc = cell.col - from.col;
    final dr = cell.row - from.row;

    // Retoucher la pièce : valide le coup, ou annule la sélection.
    if (dc == 0 && dr == 0) {
      if (moved) return endTurn();
      selected = null;
      groupSelection = {};
      return const ControllerResult(ControllerEffect.selectionChanged);
    }

    // Composer un groupe de carrées, avant tout déplacement.
    if (piece.isSquare && !moved) {
      final target = cell.onBoard ? board.atCell(cell) : null;
      if (target != null && target.isSquare && target.camp == turn) {
        // Un NOUVEL ensemble à chaque fois : le peintre compare ce qu'on lui
        // donne à ce qu'il avait. Muter celui-ci en place lui ferait croire
        // que rien n'a changé, et le cadre rose n'apparaîtrait jamais.
        if (groupSelection.contains(cell)) {
          groupSelection = {...groupSelection}..remove(cell);
        } else if (board.groupOf(from.col, from.row).contains(cell)) {
          groupSelection = {...groupSelection, cell};
        }
        return const ControllerResult(ControllerEffect.selectionChanged);
      }
    }

    // Poussée : après un déplacement qui l'a activée, chaque clic pousse une
    // direction. On peut en pousser plusieurs avant de valider.
    if (moved && pushOn) {
      if (pushValid(piece.type, dc, dr) &&
          cell.onBoard &&
          board.atCell(cell) != null) {
        return _applyPush(cell, dc, dr);
      }
      return const ControllerResult(ControllerEffect.none);
    }

    // Manœuvre de groupe.
    if (piece.isSquare && groupSelection.isNotEmpty && !moved) {
      if (dc.abs() <= 1 && dr.abs() <= 1) {
        return _tryManeuver(dc, dr);
      }
      return const ControllerResult(ControllerEffect.none);
    }

    // Saut, simple ou enchaîné.
    if (piece.isRound && groupSelection.isEmpty && (!moved || jumping)) {
      final jumpShape =
          (dc.abs() == 0 || dc.abs() == 2) &&
          (dr.abs() == 0 || dr.abs() == 2) &&
          (dc.abs() + dr.abs()) > 0;
      if (jumpShape) {
        final result = _tryJump(from, cell, dc, dr, piece);
        if (result != null) return result;
      }
    }

    // Déplacement simple d'une case.
    if (dc.abs() <= 1 && dr.abs() <= 1 && !moved && groupSelection.isEmpty) {
      final result = _trySimpleMove(from, cell, dc, dr, piece);
      if (result != null) return result;
    }

    // Geste sans effet : on désélectionne tant que rien n'a bougé.
    if (!moved) {
      selected = null;
      groupSelection = {};
      return const ControllerResult(ControllerEffect.selectionChanged);
    }
    return const ControllerResult(ControllerEffect.none);
  }

  // ── Coups élémentaires ────────────────────────────────────────────────────

  ControllerResult? _trySimpleMove(
    Cell from,
    Cell cell,
    int dc,
    int dr,
    Piece piece,
  ) {
    final isRally = Board.isFugueDest(cell.col, cell.row, piece);
    if (!cell.onBoard && !isRally) return null;
    if (cell.onBoard && board.atCell(cell) != null) return null;
    if (piece.isRound && !board.hasRoundNeighbour(from.col, from.row)) {
      return null;
    }

    board.setCell(from, null);
    final slides = [(piece, from, cell)];

    if (!cell.onBoard) {
      // L'Héritier atteint son ralliement : fugue.
      moved = true;
      return _fugue(piece.camp, slides);
    }

    board.setCell(cell, piece);
    selected = cell;
    moved = true;
    jumping = false;
    pushOn = pushActivated(piece.type, dc, dr);
    if (pushOn) {
      tracking.pushableDirs = _pushableCells(cell, piece.type);
    }
    return ControllerResult(ControllerEffect.boardChanged, slides: slides);
  }

  ControllerResult? _tryJump(
    Cell from,
    Cell cell,
    int dc,
    int dr,
    Piece piece,
  ) {
    final middle = Cell(from.col + dc ~/ 2, from.row + dr ~/ 2);
    if (!middle.onBoard) return null;
    final jumped = board.atCell(middle);
    if (jumped == null || !jumped.isRound) return null;

    final isRally = Board.isFugueDest(cell.col, cell.row, piece);
    if (!cell.onBoard && !isRally) return null;
    if (cell.onBoard && board.atCell(cell) != null) return null;

    // Anti-aller-retour : interdit de re-sauter immédiatement la même ronde.
    if (tracking.lastJumpedRound == middle) return null;

    board.setCell(from, null);
    final slides = [(piece, from, cell)];

    if (!cell.onBoard) {
      moved = true;
      return _fugue(piece.camp, slides);
    }

    board.setCell(cell, piece);
    // L'atterrissage PRÉCÉDENT devient une étape du chemin : seule la case
    // finale n'en fait pas partie, et on ne la connaît qu'à la validation.
    if (jumping) tracking.jumpPath.add(from);
    selected = cell;
    moved = true;
    jumping = true;
    pushOn = false;
    tracking.lastJumpedRound = middle;
    return ControllerResult(ControllerEffect.boardChanged, slides: slides);
  }

  ControllerResult _tryManeuver(int dc, int dr) {
    final from = selected!;
    final all = {from, ...groupSelection};

    for (final c in all) {
      final t = Cell(c.col + dc, c.row + dr);
      if (!t.onBoard) return const ControllerResult(ControllerEffect.none);
      final occ = board.atCell(t);
      if (occ != null && !all.contains(t)) {
        return const ControllerResult(ControllerEffect.none);
      }
    }

    // Maîtresse en tête, reste trié : c'est l'ordre que lit la notation.
    final others = groupSelection.toList()
      ..sort((a, b) => a.col != b.col ? a.col - b.col : a.row - b.row);
    tracking.isManeuver = true;
    tracking.maneuverPieces = [from, ...others];
    tracking.start = from;

    final pieces = {for (final c in all) c: board.atCell(c)!};
    final slides = [
      for (final c in all) (pieces[c]!, c, Cell(c.col + dc, c.row + dr)),
    ];
    for (final c in all) {
      board.setCell(c, null);
    }
    pieces.forEach((c, p) => board.set(c.col + dc, c.row + dr, p));

    selected = Cell(from.col + dc, from.row + dr);
    groupSelection = {
      for (final c in groupSelection) Cell(c.col + dc, c.row + dr),
    };
    moved = true;
    pushOn = false;
    jumping = false;
    return ControllerResult(ControllerEffect.boardChanged, slides: slides);
  }

  /// Applique une poussée depuis la case cliquée, dans la direction du clic.
  ///
  /// Toute la ligne contiguë avance d'une case. **Un Chevalier dans la ligne
  /// annule entièrement la poussée** : il ne bouge pas et rien ne bouge
  /// derrière lui.
  ControllerResult _applyPush(Cell cell, int dc, int dr) {
    final line = <(Cell, Piece)>[];
    var cc = cell.col, rr = cell.row;
    while (Board.onBoard(cc, rr)) {
      final p = board.at(cc, rr);
      if (p == null) break;
      if (p.isKnight) {
        // Mur : la poussée n'a pas lieu du tout.
        return const ControllerResult(ControllerEffect.none);
      }
      line.add((Cell(cc, rr), p));
      cc += dc;
      rr += dr;
    }
    if (line.isEmpty) return const ControllerResult(ControllerEffect.none);

    tracking.isPush = true;
    tracking.pushTargets.add(cell);

    final slides = <(Piece, Cell, Cell)>[
      for (final (c, p) in line) (p, c, Cell(c.col + dc, c.row + dr)),
    ];

    Camp? fugueBy;
    Camp? matOn;

    for (final (c, p) in line.reversed) {
      final dest = Cell(c.col + dc, c.row + dr);
      board.setCell(c, null);
      if (dest.onBoard) {
        board.setCell(dest, p);
        continue;
      }
      // Sortie du plateau.
      final ownRally = kRally.contains(dest.col) && dest.row == p.camp.rallyRow;
      if (p.isHeir && ownRally) {
        fugueBy = p.camp;
      } else {
        captured[p.camp]!.add(p);
        tracking.hadEjection = true;
        if (p.isHeir) matOn = p.camp;
      }
    }

    if (fugueBy != null) {
      return _fugue(fugueBy, slides);
    }
    if (matOn != null) {
      // Le coup de mat doit être ENREGISTRÉ avant la fin de partie, sinon il
      // manque dans l'historique et dans le replay.
      final result = endTurn(matPending: matOn);
      return ControllerResult(
        result.effect,
        notation: result.notation,
        slides: slides,
        hadEjection: true,
        endReason: result.endReason,
        loser: result.loser,
      );
    }
    return ControllerResult(
      ControllerEffect.boardChanged,
      slides: slides,
      hadEjection: true,
    );
  }

  /// Cases adjacentes occupées, dans les directions de poussée du type.
  List<Cell> _pushableCells(Cell at, PieceType type) {
    final out = <Cell>[];
    for (final (dc, dr) in pushDirsFor(type)) {
      final c = Cell(at.col + dc, at.row + dr);
      if (c.onBoard && board.atCell(c) != null) out.add(c);
    }
    return out;
  }

  // ── Fin de tour et fins de partie ─────────────────────────────────────────

  /// Valide le coup en cours et passe la main.
  ControllerResult endTurn({Camp? matPending}) {
    if (tracking.start == null) {
      return const ControllerResult(ControllerEffect.none);
    }

    final notation = buildMoveNotation(
      start: tracking.start!,
      end: selected,
      isManeuver: tracking.isManeuver,
      maneuverPieces: tracking.maneuverPieces,
      isPush: tracking.isPush,
      pushTargets: tracking.pushTargets,
      pushableDirs: tracking.pushableDirs,
    );
    final hadEjection = tracking.hadEjection;
    // Retenu AVANT de vider la sélection : ce qui décrit le coup qu'on vient
    // de jouer sert ensuite à le mettre en évidence.
    final played = turn;
    final pushed = List<Cell>.of(tracking.pushTargets);
    final jumped = List<Cell>.of(tracking.jumpPath);

    _clearSelection();
    turn = turn.opposite;
    _record(notation);

    // Mat détecté pendant la poussée : le coup est enregistré, on termine.
    if (matPending != null) {
      return _finish(
        notation,
        hadEjection,
        'mat',
        matPending,
        camp: played,
        pushTargets: pushed,
        jumpPath: jumped,
      );
    }

    // Nulle par répétition : la même position quatre fois.
    if ((positionCounts[board.positionKey(turn)] ?? 0) >= 4) {
      return _finish(
        notation,
        hadEjection,
        'repetition',
        null,
        camp: played,
        pushTargets: pushed,
        jumpPath: jumped,
      );
    }
    // Trêve : plus aucune carrée ne peut bouger, aucun camp ne peut gagner.
    if (!anySquareCanMove(board)) {
      return _finish(
        notation,
        hadEjection,
        'nulle_pat',
        null,
        camp: played,
        pushTargets: pushed,
        jumpPath: jumped,
      );
    }
    // Papatte : le joueur au trait n'a aucun coup légal, il perd.
    if (!playerHasAnyMove(board, turn)) {
      return _finish(
        notation,
        hadEjection,
        'papatte',
        turn,
        camp: played,
        pushTargets: pushed,
        jumpPath: jumped,
      );
    }

    _turnStartBoard = board.clone();
    _turnStartCaptured = _capturedCounts();
    return ControllerResult(
      ControllerEffect.turnEnded,
      notation: notation,
      hadEjection: hadEjection,
      camp: played,
      pushTargets: pushed,
      jumpPath: jumped,
    );
  }

  /// L'Héritier de `camp` atteint son ralliement.
  ///
  /// Règle auto : on ne donne pas de tour de rattrapage. Si le camp qui vient
  /// de jouer a fait fuguer SON Héritier, on regarde tout de suite si
  /// l'adversaire peut fuguer en un coup — oui : nulle, non : victoire. Si un
  /// camp a poussé l'Héritier ADVERSE dans le ralliement adverse, l'adversaire
  /// gagne immédiatement.
  // La case d'arrivée exacte ne sert plus : l'Héritier s'affiche au milieu du
  // ralliement, toujours, pour que la même partie donne la même image relue
  // depuis son `.nmc`, qui ne dit pas par où il est sorti.
  ControllerResult _fugue(Camp camp, List<(Piece, Cell, Cell)> slidesBruts) {
    final mover = turn;
    fuguedHeirs.add(camp);

    // La glissée de l'Héritier finit là où il s'affichera — au milieu. Sans
    // ce recalage, elle le posait sur sa colonne de sortie et il sautait
    // d'une case au moment de se poser. La zone de ralliement est dessinée
    // d'une seule bande de trois cases : glisser vers son centre se voit
    // moins qu'un saut à l'atterrissage.
    final slides = [
      for (final (piece, from, to) in slidesBruts)
        if (piece.isHeir && !to.onBoard && to.row == camp.rallyRow)
          (piece, from, rallyDisplayCell(camp))
        else
          (piece, from, to),
    ];

    final notation = buildMoveNotation(
      start: tracking.start!,
      end: null, // fugue : « Départ* »
      isPush: tracking.isPush,
      pushTargets: tracking.pushTargets,
      pushableDirs: tracking.pushableDirs,
    );
    final hadEjection = tracking.hadEjection;

    _clearSelection();

    if (camp != mover) {
      // On a poussé l'Héritier adverse jusqu'à SON ralliement : il gagne.
      turn = mover;
      _record(notation);
      final r = _finish(notation, hadEjection, 'fugue', mover);
      return ControllerResult(
        r.effect,
        notation: notation,
        slides: slides,
        hadEjection: hadEjection,
        endReason: r.endReason,
        loser: r.loser,
      );
    }

    turn = mover.opposite;
    final opponentCanFugue = campCanFugue(board, mover.opposite);
    _record(notation);
    final r = opponentCanFugue
        ? _finish(notation, hadEjection, 'nulle', null)
        : _finish(notation, hadEjection, 'fugue', mover.opposite);
    return ControllerResult(
      r.effect,
      notation: notation,
      slides: slides,
      hadEjection: hadEjection,
      endReason: r.endReason,
      loser: r.loser,
    );
  }

  ControllerResult _finish(
    String notation,
    bool hadEjection,
    String reason,
    Camp? loser, {
    Camp? camp,
    List<Cell> pushTargets = const [],
    List<Cell> jumpPath = const [],
  }) {
    gameOver = true;
    return ControllerResult(
      ControllerEffect.gameOver,
      notation: notation,
      hadEjection: hadEjection,
      endReason: reason,
      loser: loser,
      camp: camp,
      pushTargets: pushTargets,
      jumpPath: jumpPath,
    );
  }

  void _record(String notation) {
    history.add(notation);
    if (countRepetitions) {
      final key = board.positionKey(turn);
      positionCounts[key] = (positionCounts[key] ?? 0) + 1;
    }
    tracking.reset();
  }

  void _clearSelection() {
    selected = null;
    groupSelection = {};
    moved = false;
    pushOn = false;
    jumping = false;
  }

  /// Annule le coup en cours de construction et restaure le plateau au début
  /// du tour. Sans effet si rien n'a été commencé.
  bool cancelCurrentMove() {
    if (gameOver) return false;
    if (!moved && selected == null && groupSelection.isEmpty) return false;
    board = _turnStartBoard.clone();
    // Les pièces poussées dehors pendant ce coup reviennent avec lui : sans
    // cela, elles restaient au tableau des prises alors qu'elles étaient de
    // nouveau sur le plateau — et s'y ajoutaient une seconde fois si le coup
    // était rejoué.
    _restoreCaptured();
    _clearSelection();
    tracking.reset();
    return true;
  }

  /// Nombre de prises de chaque camp au début du tour.
  ///
  /// Posé au constructeur, pas à la première lecture : un `late` initialisé
  /// paresseusement se serait créé AU MOMENT de l'annulation, donc après la
  /// poussée, et n'aurait rien eu à restaurer.
  late Map<Camp, int> _turnStartCaptured;

  Map<Camp, int> _capturedCounts() => {
    for (final camp in Camp.values) camp: captured[camp]!.length,
  };

  void _restoreCaptured() {
    for (final camp in Camp.values) {
      final kept = _turnStartCaptured[camp] ?? 0;
      final list = captured[camp]!;
      if (list.length > kept) list.removeRange(kept, list.length);
    }
  }

  /// Applique un coup venu d'ailleurs : l'IA, le réseau, ou un replay.
  ///
  /// Contrairement à [tapCell], le coup arrive déjà construit. On réutilise
  /// néanmoins les mêmes contrôles de fin de partie, pour qu'un coup de l'IA
  /// et un coup joué à la main soient jugés exactement de la même façon.
  ControllerResult applyGeneratedMove(
    Move move, {
    List<Cell> pushTargets = const [],
  }) {
    if (gameOver) return const ControllerResult(ControllerEffect.none);

    final mover = turn;
    final before = board;
    var slides = _slidesBetween(board, move.board);
    final notation = notationOn(board, move);
    final hadEjection = move.ejected > 0;

    board = move.board;
    // Les prises se lisent sur la différence entre les deux positions : un
    // coup construit ailleurs n'est pas passé par `_applyPush`, et sans cela
    // les pièces que Deep Grey ou l'adversaire éjectaient n'apparaissaient
    // jamais dans les panneaux.
    for (final piece in ejectedBetween(before, board, notation)) {
      captured[piece.camp]!.add(piece);
    }
    _clearSelection();

    // Fugue : l'Héritier a rejoint un ralliement.
    final fugueCamp = move.fugue ? mover : move.fugueBy;
    if (fugueCamp != null) {
      fuguedHeirs.add(fugueCamp);

      // Et il GLISSE jusqu'à son ralliement. `_slidesBetween` ne compare que
      // les rangées jouables : une pièce qui quitte le plateau y a un départ
      // sans arrivée, donc aucune glissée. Le coup gagnant de Deep Grey, celui
      // de l'adversaire en ligne et celui d'une correspondance faisaient donc
      // disparaître l'Héritier d'un coup sec, là où le même coup joué au doigt
      // le faisait glisser. C'est le coup le plus important d'une partie : il
      // se voit partir.
      slides = [...slides, ..._fugueSlide(before, move.board, fugueCamp)];

      if (fugueCamp != mover) {
        // On a poussé l'Héritier adverse dans SON ralliement : il gagne.
        _record(notation);
        final r = _finish(notation, hadEjection, 'fugue', mover);
        return ControllerResult(
          r.effect,
          notation: notation,
          slides: slides,
          hadEjection: hadEjection,
          endReason: r.endReason,
          loser: r.loser,
        );
      }
      turn = mover.opposite;
      final opponentCanFugue = campCanFugue(board, mover.opposite);
      _record(notation);
      final r = opponentCanFugue
          ? _finish(notation, hadEjection, 'nulle', null)
          : _finish(notation, hadEjection, 'fugue', mover.opposite);
      return ControllerResult(
        r.effect,
        notation: notation,
        slides: slides,
        hadEjection: hadEjection,
        endReason: r.endReason,
        loser: r.loser,
      );
    }

    turn = mover.opposite;
    _record(notation);

    if (move.matOn != null) {
      final r = _finish(notation, hadEjection, 'mat', move.matOn);
      return ControllerResult(
        r.effect,
        notation: notation,
        slides: slides,
        hadEjection: hadEjection,
        endReason: r.endReason,
        loser: r.loser,
      );
    }
    if ((positionCounts[board.positionKey(turn)] ?? 0) >= 4) {
      final r = _finish(notation, hadEjection, 'repetition', null);
      return ControllerResult(
        r.effect,
        notation: notation,
        slides: slides,
        endReason: r.endReason,
      );
    }
    if (!anySquareCanMove(board)) {
      final r = _finish(notation, hadEjection, 'nulle_pat', null);
      return ControllerResult(
        r.effect,
        notation: notation,
        slides: slides,
        endReason: r.endReason,
      );
    }
    if (!playerHasAnyMove(board, turn)) {
      final r = _finish(notation, hadEjection, 'papatte', turn);
      return ControllerResult(
        r.effect,
        notation: notation,
        slides: slides,
        endReason: r.endReason,
        loser: r.loser,
      );
    }

    _turnStartBoard = board.clone();
    _turnStartCaptured = _capturedCounts();
    return ControllerResult(
      ControllerEffect.turnEnded,
      notation: notation,
      slides: slides,
      hadEjection: hadEjection,
    );
  }

  /// Glissements entre deux états de plateau, en appariant chaque départ à
  /// l'arrivée la plus proche de même type et de même camp.
  ///
  /// Portage de `_build_slides_from_diff` : sert à animer un coup dont on ne
  /// connaît que le plateau résultant.
  /// La glissée de sortie de l'Héritier de [camp] : de la case qu'il occupait
  /// à celle où il s'affiche, au milieu de son ralliement.
  ///
  /// Sa case de départ est le seul endroit où il était avant le coup et où il
  /// n'est plus après. On la cherche plutôt que de la déduire du coup, parce
  /// que l'Héritier peut aussi bien avoir marché que s'être fait pousser.
  static List<(Piece, Cell, Cell)> _fugueSlide(
    Board before,
    Board after,
    Camp camp,
  ) {
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        final p = before.at(c, r);
        if (p == null || !p.isHeir || p.camp != camp) continue;
        if (after.at(c, r) == p) continue;
        return [(p, Cell(c, r), rallyDisplayCell(camp))];
      }
    }
    return const [];
  }

  static List<(Piece, Cell, Cell)> _slidesBetween(Board before, Board after) {
    final departures = <(Piece, Cell)>[];
    final arrivals = <(Piece, Cell)>[];
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        final b = before.at(c, r);
        final a = after.at(c, r);
        if (b == a) continue;
        if (b != null) departures.add((b, Cell(c, r)));
        if (a != null) arrivals.add((a, Cell(c, r)));
      }
    }

    final slides = <(Piece, Cell, Cell)>[];
    final used = <int>{};
    for (final (piece, from) in departures) {
      var bestIndex = -1;
      var bestDistance = 1 << 30;
      for (var i = 0; i < arrivals.length; i++) {
        if (used.contains(i)) continue;
        final (other, to) = arrivals[i];
        if (other.type != piece.type || other.camp != piece.camp) continue;
        final d = (to.col - from.col).abs() + (to.row - from.row).abs();
        if (d < bestDistance) {
          bestDistance = d;
          bestIndex = i;
        }
      }
      if (bestIndex >= 0) {
        used.add(bestIndex);
        slides.add((piece, from, arrivals[bestIndex].$2));
      }
    }
    return slides;
  }

  /// Cases à mettre en évidence pendant la construction du coup : les
  /// directions de poussée encore disponibles.
  List<Cell> get availablePushCells {
    if (!moved || !pushOn) return const [];
    return [
      for (final c in tracking.pushableDirs)
        if (!tracking.pushTargets.contains(c)) c,
    ];
  }

  /// Vrai si le coup en cours peut être validé en retouchant la pièce.
  bool get canValidate => moved;
}
