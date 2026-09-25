/// Correspondance : parties asynchrones, un coup à la fois.
///
/// Contrairement au temps réel, tout passe par HTTP : on lit la liste de ses
/// parties, on joue un coup, on referme. Le serveur garde l'état.
library;

import '../engine/board.dart';
import '../engine/move_generator.dart';
import '../engine/piece.dart';
import '../engine/literal_replay.dart';
import '../engine/random_fuga.dart';
import '../game/captures.dart';
import '../game/last_move.dart';
import '../game/nmc.dart';
import '../net/online_client.dart';

/// Où en est une partie de correspondance.
enum CorrStatus {
  /// Défi lancé, en attente de réponse.
  defi,

  /// Partie en cours.
  enCours,

  /// Partie terminée, pas encore refermée par ce joueur.
  termine;

  static CorrStatus fromWire(String s) => switch (s) {
    'defi' => CorrStatus.defi,
    'termine' => CorrStatus.termine,
    _ => CorrStatus.enCours,
  };
}

/// Une partie de correspondance, vue du joueur connecté.
///
/// Reprend champ pour champ ce que renvoie `_corr_game_dict` côté serveur.
final class CorrGame {
  const CorrGame({
    required this.id,
    required this.status,
    required this.myCamp,
    required this.opponent,
    required this.opponentMelo,
    required this.myScore,
    required this.opponentScore,
    required this.objectif,
    required this.turn,
    required this.movesText,
    required this.myTurn,
    required this.isChallenger,
    required this.result,
    required this.method,
    required this.won,
    required this.unreadChat,
    required this.drawToAnswer,
    required this.drawProposer,
    required this.drawOfferedByMe,
    required this.randomCode,
    required this.updatedAt,
  });

  final String id;
  final CorrStatus status;

  /// Camp que je joue dans cette partie.
  final Camp myCamp;

  final String opponent;
  final int opponentMelo;

  /// Score direct entre nous deux.
  final int myScore;
  final int opponentScore;

  final String objectif;

  /// Camp au trait.
  final Camp turn;

  /// Coups joués, au format `.nmc`.
  final String movesText;

  final bool myTurn;

  /// Vrai si c'est moi qui ai lancé le défi.
  final bool isChallenger;

  /// `1-0`, `0-1` ou `nulle`, quand la partie est terminée.
  final String result;

  final String method;

  /// Ai-je gagné ? `null` pour une nulle ou une partie en cours.
  final bool? won;

  final int unreadChat;

  /// Une nulle m'est proposée et j'ai à répondre.
  final bool drawToAnswer;
  final String drawProposer;

  /// J'ai proposé une nulle, en attente.
  final bool drawOfferedByMe;

  /// Code Random Fuga, vide si la partie part de la position standard.
  final String randomCode;

  final String updatedAt;

  Camp get opponentCamp => myCamp.opposite;

  /// Plateau de départ de cette partie.
  Board get initialBoard => randomCode.isEmpty
      ? Board.initial()
      : (buildRandomFugaBoard(randomCode) ?? Board.initial());

  /// Coups joués, un par entrée.
  List<String> get moves => parseMoves(movesText);

  static CorrGame fromJson(Map<String, dynamic> j) => CorrGame(
    id: (j['id'] ?? '').toString(),
    status: CorrStatus.fromWire((j['statut'] ?? 'en_cours').toString()),
    myCamp: Camp.fromWire((j['ma_couleur'] ?? 'Blanc').toString()),
    opponent: (j['adversaire'] ?? '').toString(),
    opponentMelo: (j['adversaire_melo'] as num?)?.toInt() ?? 1500,
    myScore: (j['mon_score'] as num?)?.toInt() ?? 0,
    opponentScore: (j['score_adverse'] as num?)?.toInt() ?? 0,
    objectif: (j['objectif'] ?? 'partie').toString(),
    turn: Camp.fromWire((j['turn'] ?? 'Blanc').toString()),
    movesText: (j['moves_text'] ?? '').toString(),
    myTurn: j['my_turn'] == true,
    isChallenger: j['is_defieur'] == true,
    result: (j['resultat'] ?? '').toString(),
    method: (j['methode'] ?? '').toString(),
    won: j['gagne'] as bool?,
    unreadChat: (j['chat_non_lus'] as num?)?.toInt() ?? 0,
    drawToAnswer: j['nulle_a_repondre'] == true,
    drawProposer: (j['nulle_proposeur'] ?? '').toString(),
    drawOfferedByMe: j['nulle_proposee_par_moi'] == true,
    randomCode: (j['random_code'] ?? '').toString(),
    updatedAt: (j['updated_at'] ?? '').toString(),
  );
}

/// Rejeux déjà faits, par (code Random Fuga, texte des coups).
///
/// Rejouer une partie demande d'appliquer chaque notation ; l'aperçu du menu,
/// lui, se reconstruit à chaque défilement. Le texte des coups est la clé :
/// dès qu'il change, le rejeu est refait.
final Map<String, ({Board board, LastMove? lastMove, Captures captured})>
_replayCache = {};

/// Pièces sorties du plateau, par camp d'appartenance.
typedef Captures = Map<Camp, List<Piece>>;

/// Au-delà, on oublie les plus anciens : une poignée de parties suffit.
const int _replayCacheMax = 48;

/// Oublie les rejeux mémorisés — pour les tests.
void clearReplayCache() => _replayCache.clear();

/// Découpe le `moves_text` du serveur : une notation par ligne.
///
/// C'est exactement ce que fait Kivy (`moves_text.split("\n")`), et ce n'est
/// PAS le découpage d'un fichier `.nmc`, qui groupe les coups par tour.
List<String> corrMoveLines(String movesText) => [
  for (final line in movesText.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

/// Rejoue les coups d'une partie de correspondance sur un plateau.
///
/// **À la lettre, jamais par les règles.** Kivy reconstruit une partie de
/// correspondance en appliquant chaque notation telle qu'elle est écrite
/// (`_apply_notation`), aussi bien pour l'aperçu du menu que pour l'ouverture
/// de la partie. Chercher le coup légal qui correspond à la notation donnerait
/// parfois une autre position — et une partie « illisible » là où Kivy en
/// affiche une. Une notation qu'on ne sait pas appliquer est sautée, comme le
/// `try/except` de Kivy ; le trait, lui, vient du serveur.
///
/// Le plateau rendu est une copie : l'appelant peut jouer dessus sans abîmer
/// ce qui est mémorisé.
({Board board, Camp turn, LastMove? lastMove, Captures captured}) replay(
  CorrGame game,
) {
  final key = '${game.randomCode}|${game.movesText}';
  final hit = _replayCache[key] ?? _replayNow(game);
  if (_replayCache.length >= _replayCacheMax) {
    _replayCache.remove(_replayCache.keys.first);
  }
  _replayCache[key] = hit;
  return (
    board: hit.board.clone(),
    turn: game.turn,
    lastMove: hit.lastMove,
    // Copie : l'appelant y ajoutera ses propres prises en jouant.
    captured: {
      for (final e in hit.captured.entries) e.key: List<Piece>.of(e.value),
    },
  );
}

({Board board, LastMove? lastMove, Captures captured}) _replayNow(
  CorrGame game,
) {
  var board = game.initialBoard;
  // Les prises se recomptent en chemin : la position finale seule ne dit pas
  // ce qui est sorti, et les panneaux restaient vides toute la partie.
  final captured = <Camp, List<Piece>>{Camp.blanc: [], Camp.noir: []};

  // Ce que Kivy lit dans son historique pour encadrer le dernier coup :
  // le snapshot de l'avant-dernier coup réussi, ou la position de départ.
  Board? beforeLast;
  Board? lastSnapshot;
  String? lastNotation;

  for (final notation in corrMoveLines(game.movesText)) {
    final before = board;
    final applied = applyNotationLiterally(board, notation);
    board = applied.board;
    if (!applied.ok) continue;
    for (final piece in ejectedBetween(before, board, notation)) {
      captured[piece.camp]!.add(piece);
    }
    beforeLast = lastSnapshot;
    lastSnapshot = board;
    lastNotation = notation;
  }

  final last = lastNotation == null
      ? null
      : lastMoveFromNotation(
          lastNotation,
          beforeLast ?? game.initialBoard,
          board,
        );
  return (board: board, lastMove: last, captured: captured);
}

/// Méthode de fin à transmettre avec un coup qui clôt la partie.
///
/// En correspondance, `corr_jouer` enregistre le coup **et** clôt la partie en
/// une seule requête. C'est volontairement atomique : deux appels séparés
/// ouvriraient la porte aux doubles envois et aux courses.
String? closingMethodFor({
  required Board boardAfter,
  required Camp nextTurn,
  required bool fugue,
  required bool mat,
}) {
  if (fugue) return 'fugue';
  if (mat) return 'mat';
  if (!anySquareCanMove(boardAfter)) return 'nulle';
  if (!playerHasAnyMove(boardAfter, nextTurn)) return 'papatte';
  return null;
}

/// Accès aux parties de correspondance.
class CorrespondenceService {
  CorrespondenceService(this._client);

  final OnlineClient _client;

  /// Parties à afficher : défis, parties en cours, et parties terminées que
  /// je n'ai pas encore refermées.
  Future<List<CorrGame>?> list() async {
    final r = await _client.corrList();
    if (!r.isOk) return null;
    final games = r.get<List<dynamic>>('games') ?? const [];
    return [
      for (final g in games)
        CorrGame.fromJson(Map<String, dynamic>.from(g as Map)),
    ];
  }

  /// Défie un joueur par correspondance.
  Future<String?> challenge(
    String pseudo,
    String objectif, {
    bool random = false,
  }) async {
    final r = await _client.corrDefier(pseudo, objectif, random: random);
    return r.isOk ? null : (r.serverError ?? r.error ?? 'Échec du défi.');
  }

  Future<bool> answerChallenge(String gameId, bool accept) async {
    final r = await _client.corrRepondre(gameId, accept);
    return r.isOk;
  }

  /// Joue un coup. [method] n'est fourni que si ce coup termine la partie.
  Future<bool> play(String gameId, String notation, {String? method}) async {
    final r = await _client.corrJouer(gameId, notation, methode: method);
    return r.isOk;
  }

  Future<bool> resign(String gameId) async =>
      (await _client.corrAbandon(gameId)).isOk;

  /// Masque une partie terminée sur mon écran.
  Future<bool> close(String gameId) async =>
      (await _client.corrClose(gameId)).isOk;

  Future<bool> offerDraw(String gameId) async =>
      (await _client.corrProposerNulle(gameId)).isOk;

  /// Répond à une proposition de nulle. Renvoie vrai si la partie est nulle.
  Future<bool> answerDraw(String gameId, bool accept) async {
    final r = await _client.corrRepondreNulle(gameId, accept);
    return r.isOk && r.get<bool>('nulle') == true;
  }

  /// Chat de correspondance.
  ///
  /// Ces deux routes existent côté serveur mais n'étaient utilisées nulle part
  /// dans l'app Kivy.
  Future<bool> sendChat(String gameId, String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    return (await _client.corrChatSend(gameId, t)).isOk;
  }

  Future<List<Map<String, dynamic>>?> chat(String gameId) async {
    final r = await _client.corrChatList(gameId);
    if (!r.isOk) return null;
    final messages =
        r.get<List<dynamic>>('messages') ??
        r.get<List<dynamic>>('chat') ??
        const [];
    return [for (final m in messages) Map<String, dynamic>.from(m as Map)];
  }
}
