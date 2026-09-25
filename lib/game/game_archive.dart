/// Archivage d'une partie terminée — portage de `_save_game` et
/// `_make_game_uid` (main.py).
///
/// Règle de destination, inchangée : **connecté**, toutes les parties (en
/// ligne comme locales) partent au serveur, pour être synchronisées entre
/// appareils ; **non connecté**, la partie va dans un `.nmc` sur l'appareil.
library;

import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../engine/piece.dart';
import '../net/online_service.dart';
import '../state/local_games.dart';
import 'nmc.dart';

/// Points marqués selon la façon dont la partie s'est finie.
///
/// Mat et papatte valent 1 point ; fugue, temps écoulé et abandon en valent 2 ;
/// une nulle n'en donne aucun.
int pointsForMethod(String method) => switch (method) {
  'nulle' => 0,
  'mat' || 'papatte' => 1,
  _ => 2,
};

/// Ramène les fins de nulle (`nulle_pat`, `nulle_accord`, `repetition`) au seul
/// mot que connaît le format `.nmc`.
String nmcMethod(String method) =>
    method.startsWith('nulle') || method == 'repetition' ? 'nulle' : method;

/// Marque le dernier coup du mode de fin : `#` pour un mat, `*` pour un temps
/// écoulé ou un abandon.
///
/// Une fugue se termine déjà par `*` ; on n'ajoute donc rien.
List<String> withEndSuffix(List<String> history, String method) {
  if (history.isEmpty) return history;
  final last = history.last;
  // Les conditions sont celles de `_end_game_by_color`, au caractère près :
  // un mat ne double pas son dièse, et un temps ou un abandon ne marque ni un
  // coup déjà fugué (`Mi7*`) ni un coup déjà mat (`Do1-Do2#`).
  final suffix = switch (method) {
    'mat' when !last.endsWith('#') => '#',
    'temps' || 'abandon' when !last.endsWith('*') && !last.endsWith('#') => '*',
    _ => null,
  };
  if (suffix == null) return history;
  return [...history.take(history.length - 1), last + suffix];
}

/// Une partie prête à être rangée : son en-tête, ses coups et son identifiant.
final class ArchivedGame {
  const ArchivedGame({
    required this.meta,
    required this.moves,
    required this.uid,
  });

  final NmcMeta meta;
  final List<String> moves;

  /// Identifiant de la partie côté serveur. Préfixé `online_` pour une partie
  /// jouée en ligne ou par correspondance — les deux joueurs enregistrent
  /// alors le **même** identifiant, et c'est bien une seule partie des deux
  /// côtés — et `local_` sinon.
  final String uid;

  String get nmc => buildNmc(meta, moves);
}

/// Deux chiffres, pour composer les dates à la main.
String _pad(int n) => n.toString().padLeft(2, '0');

/// Date de l'en-tête, au format de Kivy : `2026-09-19 14:03`.
String _stampMinute(DateTime t) =>
    '${t.year}-${_pad(t.month)}-${_pad(t.day)} ${_pad(t.hour)}:${_pad(t.minute)}';

/// Compose l'archive d'une partie terminée.
///
/// [winner] est le nom du vainqueur, ou `null` pour une nulle. [player1] et
/// [player2] donnent l'ordre d'affichage ; [blanc] dit qui tenait les Blancs,
/// ce dont la relecture a besoin pour orienter le plateau.
ArchivedGame buildArchive({
  required String player1,
  required String player2,
  required String blanc,
  required String? winner,
  required String method,
  required List<String> history,
  String objectif = 'partie',
  String cadence = 'zen',
  String? randomCode,
  String? onlineGameId,
  String? corrGameId,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final endMethod = nmcMethod(method);
  final moves = withEndSuffix(history, endMethod);
  final result = winner == null ? '½-½' : (winner == player1 ? '1-0' : '0-1');

  final meta = NmcMeta(
    date: _stampMinute(at),
    player1: player1,
    player2: player2,
    blanc: blanc,
    objectif: objectif,
    cadence: cadence,
    result: result,
    method: endMethod,
    points: '${pointsForMethod(endMethod)}',
    random: randomCode,
  );

  final content = buildNmc(meta, moves);
  final uid = switch ((onlineGameId, corrGameId)) {
    (final String id, _) => 'online_$id',
    (_, final String id) => 'online_corr$id',
    _ =>
      'local_${sha1.convert(utf8.encode(meta.date + content.substring(0, content.length < 200 ? content.length : 200))).toString().substring(0, 16)}',
  };

  return ArchivedGame(meta: meta, moves: moves, uid: uid);
}

/// Compose l'archive d'une partie jouée contre un adversaire — en direct ou
/// par correspondance.
///
/// L'ordre des joueurs est celui de Kivy : le Blanc d'abord, le Noir ensuite
/// (`scores = {blanc_name: …, noir_name: …}`), et `1-0` veut donc dire que
/// les Blancs ont gagné. Les deux joueurs enregistrent le MÊME identifiant :
/// c'est bien une seule partie des deux côtés de l'historique.
ArchivedGame buildOpponentArchive({
  required String myPseudo,
  required String opponent,
  required Camp myCamp,
  required Camp? winner,
  required String method,
  required List<String> history,
  String objectif = 'partie',
  String cadence = 'zen',
  String? randomCode,
  String? onlineGameId,
  String? corrGameId,
  DateTime? now,
}) {
  final blanc = myCamp == Camp.blanc ? myPseudo : opponent;
  final noir = myCamp == Camp.blanc ? opponent : myPseudo;
  return buildArchive(
    player1: blanc,
    player2: noir,
    blanc: blanc,
    winner: switch (winner) {
      null => null,
      Camp.blanc => blanc,
      Camp.noir => noir,
    },
    method: method,
    history: history,
    objectif: objectif,
    cadence: cadence,
    randomCode: (randomCode == null || randomCode.isEmpty) ? null : randomCode,
    onlineGameId: onlineGameId,
    corrGameId: corrGameId,
    now: now,
  );
}

/// Ce dont l'archivage a besoin du compte en ligne.
///
/// Réduit à ces deux gestes, l'archivage se teste sans serveur — et sans même
/// construire la couche réseau.
abstract interface class AccountGames {
  bool get isLoggedIn;

  Future<void> saveGame(Map<String, dynamic> data);
}

/// Le compte réel de l'application.
final class OnlineAccountGames implements AccountGames {
  const OnlineAccountGames();

  @override
  bool get isLoggedIn => OnlineService.instance.isLoggedIn;

  @override
  Future<void> saveGame(Map<String, dynamic> data) =>
      OnlineService.instance.client.saveGame(data);
}

/// Range une partie terminée, au bon endroit.
class GameArchive {
  GameArchive({AccountGames? account, LocalGamesStore? local})
    : _online = account ?? const OnlineAccountGames(),
      _local = local ?? LocalGamesStore();

  final AccountGames _online;
  final LocalGamesStore _local;

  /// Enregistre la partie. Ne lève jamais : rater l'archivage ne doit pas
  /// gâcher la fin d'une partie.
  Future<void> store(ArchivedGame game) async {
    try {
      if (_online.isLoggedIn) {
        await _online.saveGame({
          'game_uid': game.uid,
          'nmc_text': game.nmc,
          'joueur1': game.meta.player1,
          'joueur2': game.meta.player2,
          'resultat': game.meta.result,
          'methode': game.meta.method,
          'cadence': game.meta.cadence,
          'objectif': game.meta.objectif,
        });
      } else {
        await _local.save(game.meta, game.moves);
      }
    } catch (_) {
      // Une partie qu'on n'arrive pas à ranger reste affichée à l'écran ;
      // mieux vaut cela qu'un plantage au moment du verdict.
    }
  }
}
