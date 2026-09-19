/// Recherche de coup de Deep Grey — portage de `dg_choose_move`,
/// `_dg_score_move` et `dg_choose_move_topn` (main.py). Dart pur : conçu pour
/// tourner dans un `Isolate`, afin que le chrono ne gèle jamais.
library;

import 'dart:math';

import '../board.dart';
import '../move.dart';
import '../move_generator.dart';
import '../piece.dart';
import 'evaluation.dart';
import 'weights.dart';

/// Contexte partagé d'une réflexion : poids appris, cache, compteurs de
/// répétition et générateur aléatoire (injectable pour les tests).
final class SearchContext {
  SearchContext({
    DeepGreyWeights? weights,
    EvalCache? cache,
    this.seenPositions = const {},
    Random? random,
  })  : weights = weights ?? DeepGreyWeights(),
        cache = cache ?? EvalCache(),
        random = random ?? Random();

  final DeepGreyWeights weights;
  final EvalCache cache;

  /// Combien de fois chaque configuration de NOS pièces a déjà été vue.
  final Map<String, int> seenPositions;

  final Random random;

  double eval(Board b, Camp camp) =>
      evaluate(b, camp, weights: weights, cache: cache);
}

/// Pénalité anti allers-retours.
///
/// On ne pénalise qu'à partir de la 3ᵉ occurrence d'une configuration de nos
/// pièces, et la pénalité grandit ensuite : −150 à la 3ᵉ, −600 à la 4ᵉ,
/// −1350 à la 5ᵉ… pour ne jamais tourner en rond.
double repetitionPenalty(Board after, Camp camp, Map<String, int> seen) {
  if (seen.isEmpty) return 0;
  final count = seen[after.ownPiecesKey(camp)] ?? 0;
  if (count + 1 < 3) return 0;
  final extra = (count + 1) - 2;
  return -150.0 * extra * extra;
}

/// Un coup gagne-t-il immédiatement ?
bool _winsNow(Move mv, Camp camp) =>
    mv.fugue || mv.fugueBy == camp || mv.matOn == camp.opposite;

/// Coup interdit : donner la fugue à l'adversaire, ou éjecter une de nos
/// propres pièces sans gagner dans le même coup (« règle d'or »).
bool _isForbidden(Move mv, Camp camp) {
  if (mv.fugueBy == camp.opposite) return true;
  if (mv.ejAlly > 0 && !_winsNow(mv, camp)) return true;
  return false;
}

/// Déduplique les coups menant à la même position résultante.
List<Move> _dedupe(List<Move> moves) {
  final seen = <String>{};
  final out = <Move>[];
  for (final mv in moves) {
    if (seen.add(mv.board.key)) out.add(mv);
  }
  return out;
}

/// Priorité de tri : les coups à fort potentiel d'abord, pour élaguer tôt.
int _movePriority(Move mv, Camp camp) {
  if (mv.fugue || mv.fugueBy == camp) return 0;
  if (mv.fugueBy == camp.opposite) return 100; // à ne jamais jouer : en dernier
  if (mv.matOn == camp.opposite) return 1;
  if (mv.ejected > 0) return 2;
  return 3;
}

/// Priorité des réponses adverses : les plus dangereuses pour nous d'abord.
int _oppPriority(Move omv, Camp camp, Camp opp) {
  if (omv.fugue || omv.fugueBy == opp) return 0;
  if (omv.matOn == camp) return 1;
  if (omv.ejected > 0) return 2;
  return 3;
}

/// Score d'un coup à la profondeur donnée. Portage de `_dg_score_move`.
double scoreMove(
  Move mv,
  Board board,
  Camp camp,
  int depth,
  SearchContext ctx,
) {
  final opp = camp.opposite;

  // Coups décisifs immédiats.
  if (mv.fugue || mv.fugueBy == camp) return 200000;
  if (mv.matOn == opp) return 100000;
  if (mv.fugueBy == opp) return -200000;

  final nb = mv.board;
  final bonus = moveBonus(mv, camp);
  final repPenalty = repetitionPenalty(nb, camp, ctx.seenPositions);

  if (depth <= 1) return ctx.eval(nb, camp) + bonus + repPenalty;

  final oppMoves = generateMoves(nb, opp);
  if (oppMoves.isEmpty) return ctx.eval(nb, camp) + bonus + repPenalty;

  double? worst;
  for (final omv in oppMoves) {
    final s = _scoreOppReply(omv, nb, camp, opp, depth, ctx);
    if (worst == null || s < worst) worst = s;
  }
  return worst! + bonus + repPenalty;
}

/// Score de la position après une réponse adverse.
double _scoreOppReply(
  Move omv,
  Board nb,
  Camp camp,
  Camp opp,
  int depth,
  SearchContext ctx,
) {
  if (omv.fugue || omv.fugueBy == opp) return -100000;
  if (omv.matOn == camp) return -50000;

  final nb2 = omv.board;
  if (depth < 3) return ctx.eval(nb2, camp);

  // Un niveau de plus : notre meilleure contre-réponse.
  final my2 = generateMoves(nb2, camp);
  if (my2.isEmpty) return ctx.eval(nb2, camp);

  double? best2;
  for (final m2 in my2) {
    if (_isForbidden(m2, camp)) continue;
    final double s2;
    if (m2.fugue || m2.fugueBy == camp) {
      s2 = 100000;
    } else if (m2.matOn == opp) {
      s2 = 50000;
    } else {
      s2 = ctx.eval(m2.board, camp) + moveBonus(m2, camp);
    }
    if (best2 == null || s2 > best2) best2 = s2;
  }
  return best2 ?? ctx.eval(nb2, camp);
}

/// Choisit le meilleur coup à la profondeur `depth`, avec élagage alpha-bêta.
///
/// Pendant les 5 premiers coups (`moveNumber <= 5`), l'élagage est désactivé et
/// le coup est tiré au sort parmi les 3 meilleurs, pour varier les ouvertures.
Move? chooseMove(
  Board board,
  Camp camp, {
  int depth = 2,
  int? moveNumber,
  SearchContext? context,
}) {
  final ctx = context ?? SearchContext();
  final opp = camp.opposite;

  var myMoves = generateMoves(board, camp);
  if (myMoves.isEmpty) return null;
  myMoves = _dedupe(myMoves);
  myMoves.sort((a, b) => _movePriority(a, camp) - _movePriority(b, camp));

  Move? bestMove;
  double? bestScore;
  var alpha = double.negativeInfinity;
  final openingPhase = moveNumber != null && moveNumber <= 5;
  final scoredMoves = <(double, Move)>[];

  for (final mv in myMoves) {
    if (_isForbidden(mv, camp)) continue;
    // Coup gagnant immédiat : on le prend sans réfléchir plus loin.
    if (_winsNow(mv, camp)) return mv;

    final nb = mv.board;
    final bonus = moveBonus(mv, camp);
    final repPenalty = repetitionPenalty(nb, camp, ctx.seenPositions);

    final double sc;
    if (depth <= 1) {
      sc = ctx.eval(nb, camp) + bonus + repPenalty;
    } else {
      final oppMoves = generateMoves(nb, opp);
      if (oppMoves.isEmpty) {
        sc = ctx.eval(nb, camp) + bonus + repPenalty;
      } else {
        oppMoves.sort(
            (a, b) => _oppPriority(a, camp, opp) - _oppPriority(b, camp, opp));
        double? worst;
        for (final omv in oppMoves) {
          final s = _scoreOppReply(omv, nb, camp, opp, depth, ctx);
          if (worst == null || s < worst) {
            worst = s;
            // Élagage désactivé en ouverture, pour obtenir des scores complets
            // et donc un vrai top 3.
            if (!openingPhase && worst + bonus + repPenalty <= alpha) break;
          }
        }
        sc = worst! + bonus + repPenalty;
      }
    }

    if (openingPhase) scoredMoves.add((sc, mv));
    if (bestScore == null || sc > bestScore) {
      bestScore = sc;
      bestMove = mv;
      alpha = max(alpha, sc);
    }
  }

  // Ouverture : tirer au sort parmi les 3 meilleurs.
  if (openingPhase && scoredMoves.isNotEmpty) {
    scoredMoves.sort((a, b) => b.$1.compareTo(a.$1));
    final top = scoredMoves.take(3).toList();
    return top[ctx.random.nextInt(top.length)].$2;
  }

  // Aucun coup non catastrophique : prendre le moins pire.
  if (bestMove == null) {
    for (final mv in myMoves) {
      var sc = ctx.eval(mv.board, camp) - 100000;
      if (mv.ejAlly > 0) sc -= 5000 * mv.ejAlly;
      if (bestScore == null || sc > bestScore) {
        bestScore = sc;
        bestMove = mv;
      }
    }
  }

  return bestMove;
}

/// Mode profond : recherche en deux temps.
///
/// 1. tous les coups évalués à profondeur 2 (rapide) ;
/// 2. les `topN` meilleurs ré-évalués à profondeur 3 (cher, mais sur peu de
///    coups).
///
/// Donne la force d'une profondeur 3 sans en payer le coût partout, et ne peut
/// pas rater le meilleur coup s'il figure dans le top N de la profondeur 2.
Move? chooseMoveTopN(
  Board board,
  Camp camp, {
  int topN = 5,
  int? moveNumber,
  SearchContext? context,
}) {
  final ctx = context ?? SearchContext();
  final opp = camp.opposite;

  var myMoves = generateMoves(board, camp);
  if (myMoves.isEmpty) return null;
  myMoves = _dedupe(myMoves);

  // Coup gagnant immédiat.
  for (final mv in myMoves) {
    if (mv.fugue || mv.fugueBy == camp || mv.matOn == opp) return mv;
  }

  final candidates = myMoves.where((mv) => !_isForbidden(mv, camp)).toList();
  if (candidates.isEmpty) {
    return chooseMove(board, camp,
        depth: 2, moveNumber: moveNumber, context: ctx);
  }

  // Passe 1 : profondeur 2 sur tous les candidats.
  final scored = <(double, Move)>[
    for (final mv in candidates) (scoreMove(mv, board, camp, 2, ctx), mv),
  ]..sort((a, b) => b.$1.compareTo(a.$1));

  // Ouverture : varier parmi les 3 meilleurs de la profondeur 2.
  if (moveNumber != null && moveNumber <= 5) {
    final top3 = scored.take(3).toList();
    return top3[ctx.random.nextInt(top3.length)].$2;
  }

  // Passe 2 : profondeur 3 sur les topN meilleurs.
  Move? bestMove;
  double? bestScore;
  for (final (_, mv) in scored.take(topN)) {
    final sc3 = scoreMove(mv, board, camp, 3, ctx);
    if (bestScore == null || sc3 > bestScore) {
      bestScore = sc3;
      bestMove = mv;
    }
  }
  return bestMove;
}
