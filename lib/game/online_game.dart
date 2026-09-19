/// Partie en ligne : relie les événements Socket.IO au contrôleur de jeu.
///
/// Pas d'import Flutter : la logique d'une partie en ligne se teste sans
/// interface, en lui envoyant des événements à la main.
///
/// Règle constante : **ce qui arrive du réseau passe par les mêmes contrôles
/// que ce qui est joué à la main**. Un coup adverse est résolu en coup légal,
/// puis appliqué par le contrôleur, qui juge les fins de partie exactement
/// comme pour un coup local.
library;

import 'dart:async';

import '../engine/board.dart';
import '../engine/move_generator.dart';
import '../engine/piece.dart';
import '../engine/random_fuga.dart';
import '../net/socket_client.dart';
import 'clock.dart';
import 'move_controller.dart';

/// Informations d'ouverture d'une partie, telles que `partie_trouvee` les
/// donne.
final class OnlineGameInfo {
  const OnlineGameInfo({
    required this.gameId,
    required this.myCamp,
    required this.opponent,
    required this.opponentMelo,
    required this.objectif,
    required this.cadence,
    this.randomCode,
  });

  final String gameId;

  /// Camp que je joue.
  final Camp myCamp;

  final String opponent;
  final int opponentMelo;

  /// `partie` pour une partie unique, sinon un nombre de points.
  final String objectif;

  final String cadence;

  /// Code Random Fuga, quand la partie part d'une position tirée au sort.
  final String? randomCode;

  /// Lit un payload `partie_trouvee`.
  factory OnlineGameInfo.fromEvent(Map<String, dynamic> d) => OnlineGameInfo(
    gameId: (d['game_id'] ?? '').toString(),
    myCamp: Camp.fromWire((d['couleur'] ?? 'Blanc').toString()),
    opponent: (d['adversaire'] ?? '').toString(),
    opponentMelo: (d['adversaire_melo'] as num?)?.toInt() ?? 1500,
    objectif: (d['objectif'] ?? 'partie').toString(),
    cadence: (d['cadence'] ?? '').toString(),
    randomCode: d['random_code'] as String?,
  );
}

/// Ce qui peut changer et que l'interface doit refléter.
enum OnlineEvent {
  /// Le plateau a bougé (coup local ou adverse).
  boardChanged,

  /// La partie est terminée.
  gameOver,

  /// L'adversaire a proposé la nulle.
  drawOffered,

  /// L'adversaire s'est déconnecté, ou est revenu.
  opponentPresence,

  /// Nouveau message dans le chat de partie.
  chat,

  /// Le mélo a été mis à jour en fin de partie.
  meloUpdated,

  /// Le match continue, ou se termine.
  matchProgress,
}

/// Une partie jouée en ligne.
class OnlineGame {
  OnlineGame({
    required this.socket,
    required this.info,
    required Cadence cadence,
    void Function(OnlineEvent event)? onChanged,
  }) : clock = GameClock(cadence),
       _onChanged = onChanged,
       game = MoveController(
         board: info.randomCode == null
             ? Board.initial()
             : (buildRandomFugaBoard(info.randomCode!) ?? Board.initial()),
       ) {
    _bind();
    _startTicking();
  }

  final GameSocket socket;
  final OnlineGameInfo info;
  final MoveController game;
  final GameClock clock;

  final void Function(OnlineEvent event)? _onChanged;

  Timer? _ticker;

  /// Messages du chat de partie, dans l'ordre.
  final List<({String author, String text})> chat = [];

  /// Verdict de fin de partie, quand il y en a un.
  String? endReason;
  Camp? loser;

  /// Mélo après la partie, quand le serveur l'a renvoyé.
  int? newMelo;
  int? meloDelta;

  /// Score du match en cours.
  int scoreBlanc = 0;
  int scoreNoir = 0;

  /// Vrai quand le match continue après cette partie.
  bool matchContinues = false;

  /// L'adversaire a-t-il proposé la nulle ?
  bool drawOffered = false;

  /// L'adversaire est-il présent ?
  bool opponentConnected = true;

  /// Délai de grâce annoncé par le serveur, en secondes.
  int? disconnectGrace;

  Camp get myCamp => info.myCamp;
  Camp get opponentCamp => info.myCamp.opposite;

  /// Est-ce à moi de jouer ?
  bool get isMyTurn => !game.gameOver && game.turn == myCamp;

  // ── Réception ─────────────────────────────────────────────────────────────

  void _bind() {
    socket
      ..on(FugaEvents.coupAdverse, _onOpponentMove)
      ..on(FugaEvents.partieTerminee, _onRemoteEnd)
      ..on(FugaEvents.nulleProposee, _onDrawOffered)
      ..on(FugaEvents.adversaireDeconnecte, _onOpponentGone)
      ..on(FugaEvents.adversaireRevenu, _onOpponentBack)
      ..on(FugaEvents.chatRecu, _onChat)
      ..on(FugaEvents.meloMaj, _onMelo)
      ..on(FugaEvents.matchContinue, _onMatchContinue)
      ..on(FugaEvents.matchOver, _onMatchOver);
  }

  /// Applique un coup reçu de l'adversaire.
  ///
  /// La notation est résolue en coup légal : si elle ne correspond à rien, on
  /// l'ignore. Rejouer approximativement un coup adverse désynchroniserait les
  /// deux plateaux sans que personne ne s'en aperçoive.
  void _onOpponentMove(Map<String, dynamic> d) {
    if (game.gameOver) return;
    final notation = (d['notation'] ?? '').toString();
    final move = resolveNotation(game.board, game.turn, notation);
    if (move == null) return;

    final result = game.applyGeneratedMove(move);

    // Le serveur relaie le temps restant de l'adversaire.
    final clockAdverse = (d['clock_adverse'] as num?)?.toInt();
    clock.setRemaining(opponentCamp, clockAdverse);

    if (result.effect == ControllerEffect.gameOver) {
      _finish(result.endReason, result.loser, notifyServer: false);
    } else {
      _notify(OnlineEvent.boardChanged);
    }
  }

  void _onRemoteEnd(Map<String, dynamic> d) {
    if (game.gameOver) return;
    final method = (d['methode'] ?? '').toString();
    final loserColor = d['loser_color'] as String?;
    _finish(
      method,
      loserColor == null ? null : Camp.fromWire(loserColor),
      notifyServer: false,
    );
  }

  void _onDrawOffered(Map<String, dynamic> d) {
    drawOffered = true;
    _notify(OnlineEvent.drawOffered);
  }

  void _onOpponentGone(Map<String, dynamic> d) {
    opponentConnected = false;
    disconnectGrace = (d['delai'] as num?)?.toInt();
    _notify(OnlineEvent.opponentPresence);
  }

  void _onOpponentBack(Map<String, dynamic> d) {
    opponentConnected = true;
    disconnectGrace = null;
    _notify(OnlineEvent.opponentPresence);
  }

  void _onChat(Map<String, dynamic> d) {
    chat.add((author: info.opponent, text: (d['texte'] ?? '').toString()));
    _notify(OnlineEvent.chat);
  }

  void _onMelo(Map<String, dynamic> d) {
    newMelo = (d['mon_melo'] as num?)?.toInt();
    meloDelta = (d['delta'] as num?)?.toInt();
    _notify(OnlineEvent.meloUpdated);
  }

  void _onMatchContinue(Map<String, dynamic> d) {
    _readScore(d);
    matchContinues = true;
    _notify(OnlineEvent.matchProgress);
  }

  void _onMatchOver(Map<String, dynamic> d) {
    _readScore(d);
    matchContinues = false;
    _notify(OnlineEvent.matchProgress);
  }

  void _readScore(Map<String, dynamic> d) {
    scoreBlanc = (d['score_blanc'] as num?)?.toInt() ?? scoreBlanc;
    scoreNoir = (d['score_noir'] as num?)?.toInt() ?? scoreNoir;
  }

  // ── Émission ──────────────────────────────────────────────────────────────

  /// Traite un appui du joueur local et transmet le coup s'il est validé.
  ControllerResult tapCell(Cell cell) {
    if (!isMyTurn) return const ControllerResult(ControllerEffect.none);
    final result = game.tapCell(cell);

    if (result.notation != null) _sendMove(result.notation!);
    if (result.effect == ControllerEffect.gameOver) {
      _finish(result.endReason, result.loser, notifyServer: true);
    }
    return result;
  }

  void _sendMove(String notation) {
    socket.jouerCoup(
      gameId: info.gameId,
      notation: notation,
      clockBlanc: clock.remainingFor(Camp.blanc),
      clockNoir: clock.remainingFor(Camp.noir),
      // Le serveur lit « clock_me » : sans cette clé, il relaie null et la
      // synchronisation d'horloge ne marche pas du tout.
      clockMe: clock.remainingFor(myCamp),
    );
  }

  /// Propose la nulle à l'adversaire.
  void offerDraw() => socket.proposerNulle(info.gameId);

  /// Accepte la nulle proposée.
  void acceptDraw() {
    drawOffered = false;
    _finish('nulle', null, notifyServer: true);
  }

  void declineDraw() {
    drawOffered = false;
    _notify(OnlineEvent.drawOffered);
  }

  /// Abandonne la partie en cours.
  void resign() => _finish('abandon', myCamp, notifyServer: true);

  /// Abandonne tout le match.
  void resignMatch() {
    socket.abandonnerMatch(info.gameId);
    _finish('abandon', myCamp, notifyServer: false);
  }

  void sendChat(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    socket.chat(info.gameId, t);
    chat.add((author: 'moi', text: t));
    _notify(OnlineEvent.chat);
  }

  /// Signale au serveur qu'on est prêt pour la partie suivante du match.
  void readyForNext() => socket.pretPartieSuivante(info.gameId);

  // ── Chrono ────────────────────────────────────────────────────────────────

  void _startTicking() {
    if (clock.isUnlimited) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (game.gameOver) return;
      final flagged = clock.tick(game.turn);
      if (flagged == null) {
        _notify(OnlineEvent.boardChanged);
        return;
      }
      // Je ne déclare la perte au temps que pour MON horloge : pour celle de
      // l'adversaire, sa machine fait foi et j'attends son signal.
      if (flagged != myCamp) {
        _notify(OnlineEvent.boardChanged);
        return;
      }
      _finish('temps', myCamp, notifyServer: true);
    });
  }

  // ── Fin de partie ─────────────────────────────────────────────────────────

  void _finish(String? reason, Camp? loserCamp, {required bool notifyServer}) {
    if (endReason != null) return; // une seule fin
    game.gameOver = true;
    endReason = reason;
    loser = loserCamp;
    _ticker?.cancel();

    // On ne renvoie rien au serveur quand la fin découle d'un signal qu'on
    // vient de recevoir : l'adversaire le sait déjà.
    if (notifyServer) {
      socket.finPartie(
        gameId: info.gameId,
        methode: reason ?? 'abandon',
        loserColor: loserCamp?.wire,
      );
    }
    _notify(OnlineEvent.gameOver);
  }

  void _notify(OnlineEvent event) => _onChanged?.call(event);

  void dispose() {
    _ticker?.cancel();
    for (final e in [
      FugaEvents.coupAdverse,
      FugaEvents.partieTerminee,
      FugaEvents.nulleProposee,
      FugaEvents.adversaireDeconnecte,
      FugaEvents.adversaireRevenu,
      FugaEvents.chatRecu,
      FugaEvents.meloMaj,
      FugaEvents.matchContinue,
      FugaEvents.matchOver,
    ]) {
      socket.off(e);
    }
  }
}
