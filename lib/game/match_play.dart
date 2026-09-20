/// Match en plusieurs parties — portage de `_decide_next` et du suivi de
/// score du jeu local (main.py).
///
/// Un objectif en points enchaîne les parties jusqu'à ce qu'un joueur
/// atteigne la cible. Les couleurs alternent, et la **règle de l'ultime
/// partie** protège l'équité : si celui qui mène a tenu les Blancs plus
/// souvent que l'autre, l'autre a droit à une dernière partie, Blancs en
/// main.
///
/// Dart pur : tout se teste sans écran.
library;

/// Ce qu'il faut faire après une partie.
enum MatchOutcome {
  /// Objectif « partie » : il n'y a rien à enchaîner.
  singleGame,

  /// Le match continue : une partie de plus.
  next,

  /// Le match est joué : quelqu'un l'emporte.
  over,
}

/// Résultat de l'enregistrement d'une partie.
final class MatchStep {
  const MatchStep({
    required this.outcome,
    this.nextFirstBlanc,
    this.winner,
    this.lastChance = false,
  });

  final MatchOutcome outcome;

  /// Qui tiendra les Blancs à la partie suivante.
  final String? nextFirstBlanc;

  /// Vainqueur du match, quand il est joué.
  final String? winner;

  /// La partie suivante est l'ultime partie accordée au retardataire.
  final bool lastChance;
}

/// Suivi d'un match entre deux joueurs.
class FugaMatch {
  FugaMatch({
    required this.playerA,
    required this.playerB,
    this.target = 'partie',
    String? firstBlanc,
  }) : firstBlanc = firstBlanc ?? playerA {
    scores = {playerA: 0, playerB: 0};
    playedBlanc = {playerA: 0, playerB: 0};
    playedBlanc[this.firstBlanc] = 1;
  }

  final String playerA;
  final String playerB;

  /// `partie` pour une partie unique, sinon le nombre de points à atteindre.
  final String target;

  /// Qui tient les Blancs dans la partie en cours.
  String firstBlanc;

  late final Map<String, int> scores;

  /// Combien de fois chacun a tenu les Blancs.
  late final Map<String, int> playedBlanc;

  /// L'ultime partie est en cours.
  bool lastChance = false;

  bool get isSingleGame => target == 'partie';

  int? get targetPoints => int.tryParse(target);

  String other(String player) => player == playerA ? playerB : playerA;

  /// Enregistre le résultat d'une partie et dit ce qui suit.
  ///
  /// [winner] est `null` pour une nulle ; [points] est ce que la fin de partie
  /// rapporte (mat et papatte 1, fugue, temps et abandon 2).
  MatchStep record({String? winner, required int points}) {
    if (winner != null) scores[winner] = (scores[winner] ?? 0) + points;

    if (isSingleGame) return const MatchStep(outcome: MatchOutcome.singleGame);

    final sA = scores[playerA]!;
    final sB = scores[playerB]!;
    final leader = sA > sB ? playerA : (sB > sA ? playerB : null);
    final reached = leader != null && scores[leader]! >= (targetPoints ?? 1);

    if (!reached) return _continue(other(firstBlanc));

    // L'ultime partie a déjà été accordée : celui qui mène l'emporte. (À
    // égalité on n'arrive pas ici — sans meneur, la cible n'est pas atteinte
    // et le match continue. Kivy a la même conséquence.)
    if (lastChance) {
      return MatchStep(outcome: MatchOutcome.over, winner: leader);
    }

    // Celui qui mène a-t-il eu les Blancs plus souvent ? Alors l'autre a
    // droit à une dernière partie, Blancs en main.
    final loser = other(leader);
    if (playedBlanc[leader]! > playedBlanc[loser]!) {
      lastChance = true;
      return _continue(loser, lastChance: true);
    }

    return MatchStep(outcome: MatchOutcome.over, winner: leader);
  }

  MatchStep _continue(String nextFirstBlanc, {bool lastChance = false}) =>
      MatchStep(
        outcome: MatchOutcome.next,
        nextFirstBlanc: nextFirstBlanc,
        lastChance: lastChance,
      );

  /// Démarre la partie suivante : les Blancs changent de main.
  void startNext(String nextFirstBlanc) {
    firstBlanc = nextFirstBlanc;
    playedBlanc[nextFirstBlanc] = (playedBlanc[nextFirstBlanc] ?? 0) + 1;
  }

  /// Score, dans l'ordre d'affichage.
  String get scoreLine =>
      '$playerA : ${scores[playerA]}    $playerB : ${scores[playerB]}';
}
