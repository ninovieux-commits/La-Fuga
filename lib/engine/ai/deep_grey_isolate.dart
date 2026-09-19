/// Deep Grey sur un fil séparé.
///
/// En Kivy, l'IA calculait sur le thread de l'interface : pendant sa réflexion
/// l'application ne repeignait plus et **le chrono gelait**. C'est précisément
/// ce que ce fichier corrige.
///
/// Un isolate unique est démarré une fois puis réutilisé : `Isolate.spawn`
/// coûte quelques dizaines de millisecondes, ce qu'on ne veut pas payer à
/// chaque coup. Tout `lib/engine/` est du Dart pur, sans import Flutter,
/// précisément pour pouvoir s'exécuter ici.
library;

import 'dart:async';
import 'dart:isolate';

import '../board.dart';
import '../move.dart';
import '../notation.dart';
import '../piece.dart';
import 'evaluation.dart';
import 'search.dart';
import 'weights.dart';

/// Demande de réflexion envoyée à l'isolate.
final class ThinkRequest {
  const ThinkRequest({
    required this.id,
    required this.board,
    required this.camp,
    required this.deepMode,
    this.moveNumber,
    this.seenPositions = const {},
    this.weights = const {},
  });

  /// Identifiant de la demande : permet d'ignorer une réponse périmée.
  final int id;

  final List<List<Map<String, String>?>> board;
  final String camp;

  /// Mode profond (top 5 à profondeur 2, puis profondeur 3) ou normal
  /// (profondeur 2).
  final bool deepMode;

  final int? moveNumber;
  final Map<String, int> seenPositions;
  final Map<String, double> weights;
}

/// Coup choisi par l'isolate.
final class ThinkResult {
  const ThinkResult({
    required this.id,
    required this.notation,
    required this.board,
    required this.kind,
    required this.fugue,
    required this.fugueBy,
    required this.matOn,
    required this.ejAlly,
    required this.ejOpp,
    required this.from,
    required this.movedCells,
    required this.pushTargets,
    required this.elapsedMicros,
  });

  final int id;

  /// Notation `.nmc` du coup, ou `null` si aucun coup n'est possible.
  final String? notation;

  final List<List<Map<String, String>?>>? board;
  final String? kind;
  final bool fugue;
  final String? fugueBy;
  final String? matOn;
  final int ejAlly;
  final int ejOpp;
  final List<List<int>> from;
  final List<List<int>> movedCells;
  final List<List<int>> pushTargets;

  /// Temps de réflexion, utile pour régler la temporisation d'affichage.
  final int elapsedMicros;

  bool get hasMove => notation != null;
}

/// Pilote l'isolate de Deep Grey depuis le thread de l'interface.
///
/// Usage :
/// ```dart
/// final engine = DeepGreyEngine();
/// await engine.start();
/// final result = await engine.think(board: b, camp: Camp.noir, deepMode: false);
/// engine.dispose();
/// ```
final class DeepGreyEngine {
  Isolate? _isolate;
  SendPort? _toIsolate;
  ReceivePort? _fromIsolate;
  StreamSubscription<dynamic>? _sub;

  var _nextId = 1;
  final Map<int, Completer<ThinkResult>> _pending = {};

  bool get isRunning => _toIsolate != null;

  /// Démarre l'isolate. Idempotent.
  Future<void> start() async {
    if (_isolate != null) return;

    final ready = Completer<SendPort>();
    _fromIsolate = ReceivePort();
    _sub = _fromIsolate!.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (message is ThinkResult) {
        // Une demande annulée n'a plus de completer : on ignore sa réponse.
        _pending.remove(message.id)?.complete(message);
      }
    });

    _isolate = await Isolate.spawn(
      _deepGreyMain,
      _fromIsolate!.sendPort,
      debugName: 'deep-grey',
      errorsAreFatal: false,
    );
    _toIsolate = await ready.future;
  }

  /// Demande un coup. La réflexion n'occupe jamais le thread de l'interface.
  ///
  /// [seenPositions] alimente la pénalité anti allers-retours ; [weights] sont
  /// les poids appris (`dg_weights.json`).
  Future<ThinkResult> think({
    required Board board,
    required Camp camp,
    required bool deepMode,
    int? moveNumber,
    Map<String, int> seenPositions = const {},
    DeepGreyWeights? weights,
  }) async {
    if (!isRunning) await start();
    final id = _nextId++;
    final completer = Completer<ThinkResult>();
    _pending[id] = completer;
    _toIsolate!.send(
      ThinkRequest(
        id: id,
        board: board.toJson(),
        camp: camp.wire,
        deepMode: deepMode,
        moveNumber: moveNumber,
        seenPositions: seenPositions,
        weights: weights?.values ?? const {},
      ),
    );
    return completer.future;
  }

  /// Abandonne l'attente d'une demande (partie terminée, retour au menu…).
  ///
  /// L'isolate finit son calcul — on ne peut pas l'interrompre au milieu d'une
  /// recherche — mais sa réponse sera ignorée.
  void cancel(int id) => _pending.remove(id);

  /// Abandonne toutes les demandes en attente.
  void cancelAll() => _pending.clear();

  /// Arrête l'isolate et libère les ports.
  void dispose() {
    _pending.clear();
    _sub?.cancel();
    _fromIsolate?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toIsolate = null;
    _fromIsolate = null;
    _sub = null;
  }
}

/// Point d'entrée de l'isolate.
void _deepGreyMain(SendPort toMain) {
  final fromMain = ReceivePort();
  toMain.send(fromMain.sendPort);

  // Le cache d'évaluation vit le temps de l'isolate, mais il est vidé avant
  // chaque réflexion : une position doit être réévaluée avec les poids et le
  // contexte du coup en cours.
  final cache = EvalCache();

  fromMain.listen((message) {
    if (message is! ThinkRequest) return;
    toMain.send(_think(message, cache));
  });
}

ThinkResult _think(ThinkRequest req, EvalCache cache) {
  final stopwatch = Stopwatch()..start();
  cache.clear();

  final board = Board.fromJson(req.board);
  final camp = Camp.fromWire(req.camp);
  final ctx = SearchContext(
    weights: DeepGreyWeights(req.weights),
    cache: cache,
    seenPositions: req.seenPositions,
  );

  final move = req.deepMode
      ? chooseMoveTopN(board, camp, moveNumber: req.moveNumber, context: ctx)
      : chooseMove(
          board,
          camp,
          depth: 2,
          moveNumber: req.moveNumber,
          context: ctx,
        );

  stopwatch.stop();

  if (move == null) {
    return ThinkResult(
      id: req.id,
      notation: null,
      board: null,
      kind: null,
      fugue: false,
      fugueBy: null,
      matOn: null,
      ejAlly: 0,
      ejOpp: 0,
      from: const [],
      movedCells: const [],
      pushTargets: const [],
      elapsedMicros: stopwatch.elapsedMicroseconds,
    );
  }

  final pushTargets = _pushTargets(board, move);
  return ThinkResult(
    id: req.id,
    notation: notationOfMove(move, pushTargets: pushTargets),
    board: move.board.toJson(),
    kind: move.kind.name,
    fugue: move.fugue,
    fugueBy: move.fugueBy?.wire,
    matOn: move.matOn?.wire,
    ejAlly: move.ejAlly,
    ejOpp: move.ejOpp,
    from: [
      [move.from.col, move.from.row],
    ],
    movedCells: [
      for (final c in move.movedCells) [c.col, c.row],
    ],
    pushTargets: [
      for (final c in pushTargets) [c.col, c.row],
    ],
    elapsedMicros: stopwatch.elapsedMicroseconds,
  );
}

/// Cases effectivement poussées par un coup, pour reconstruire la notation.
///
/// Portage de `_ai_compute_push_targets` : la case poussée est la première
/// case occupée dans chaque direction retenue, vue depuis l'arrivée.
List<Cell> _pushTargets(Board before, Move move) {
  if (move.pushDirsUsed.isEmpty) return const [];
  final dest = move.to;
  // Plateau après le seul déplacement, avant les poussées.
  final moved = before.clone();
  moved.set(dest.col, dest.row, moved.atCell(move.from));
  moved.setCell(move.from, null);

  final targets = <Cell>[];
  for (final (dc, dr) in move.pushDirsUsed) {
    final tc = dest.col + dc, tr = dest.row + dr;
    if (Board.onBoard(tc, tr) && moved.at(tc, tr) != null) {
      targets.add(Cell(tc, tr));
    }
  }
  return targets;
}
