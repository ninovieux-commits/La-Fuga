/// Format de fichier `.nmc` — portage de `make_nmc_content`,
/// `parse_nmc_content` et `format_nmc_moves` (main.py).
///
/// Un fichier `.nmc` est un en-tête de style PGN, une ligne vide, puis les
/// coups numérotés. C'est le format d'échange entre l'app et le serveur
/// (`nmc_text` des routes `/save_game` et `/get_game`) : il ne change pas.
library;

/// En-tête d'une partie enregistrée.
final class NmcMeta {
  const NmcMeta({
    required this.date,
    required this.player1,
    required this.player2,
    required this.blanc,
    required this.objectif,
    required this.cadence,
    required this.result,
    required this.method,
    required this.points,
    this.random,
  });

  final String date;
  final String player1;
  final String player2;

  /// Joueur qui tenait les Blancs.
  final String blanc;

  /// `partie` ou un nombre de points.
  final String objectif;

  final String cadence;

  /// `1-0`, `0-1` ou `½-½`.
  final String result;

  /// `fugue`, `mat`, `papatte`, `nulle`, `temps`, `abandon`…
  final String method;

  final String points;

  /// Code Random Fuga, quand la partie est partie d'une position tirée au
  /// sort. Sans lui, la position de départ serait irrécupérable à la
  /// relecture.
  final String? random;

  Map<String, String> toFields() => {
    'Date': date,
    'Joueur1': player1,
    'Joueur2': player2,
    'Blanc': blanc,
    'Objectif': objectif,
    'Cadence': cadence,
    'Resultat': result,
    'Methode': method,
    'Points': points,
    if (random != null) 'Random': random!,
  };

  /// Construit depuis les champs bruts de l'en-tête (clés en minuscules).
  factory NmcMeta.fromFields(Map<String, String> f) => NmcMeta(
    date: f['date'] ?? '',
    player1: f['joueur1'] ?? '',
    player2: f['joueur2'] ?? '',
    blanc: f['blanc'] ?? f['joueur1'] ?? '',
    objectif: f['objectif'] ?? '',
    cadence: f['cadence'] ?? '',
    result: f['resultat'] ?? '',
    method: f['methode'] ?? '',
    points: f['points'] ?? '',
    random: f['random'],
  );
}

/// Une partie enregistrée : son en-tête et ses coups.
final class NmcGame {
  const NmcGame(this.meta, this.moves);

  final NmcMeta meta;

  /// Notations dans l'ordre, Blanc puis Noir, Blanc puis Noir…
  final List<String> moves;
}

/// Formate l'historique : `1.Do1-Do2/Do8-Do7  2.Ré1-Ré2`.
String formatMoves(List<String> history) {
  final parts = <String>[];
  var i = 0;
  var turn = 1;
  while (i < history.length) {
    final blanc = history[i];
    final noir = (i + 1 < history.length) ? history[i + 1] : '';
    parts.add(noir.isEmpty ? '$turn.$blanc' : '$turn.$blanc/$noir');
    i += 2;
    turn++;
  }
  return parts.join('  ');
}

/// Découpe un texte de coups en notations, dans l'ordre.
///
/// Tolère les numéros de tour, les séparateurs multiples et les retours à la
/// ligne : un fichier écrit à la main doit rester lisible.
List<String> parseMoves(String movesText) {
  final out = <String>[];
  for (final token in movesText.split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    // Retirer le numéro de tour : « 12.Do1-Do2 ».
    var t = token;
    final dot = t.indexOf('.');
    if (dot >= 0 && int.tryParse(t.substring(0, dot)) != null) {
      t = t.substring(dot + 1);
    }
    for (final half in t.split('/')) {
      final m = half.trim();
      if (m.isNotEmpty) out.add(m);
    }
  }
  return out;
}

/// Génère le contenu d'un fichier `.nmc`.
String buildNmc(NmcMeta meta, List<String> history) {
  final buffer = StringBuffer();
  meta.toFields().forEach((key, value) {
    buffer.writeln('[$key "$value"]');
  });
  buffer.writeln();
  buffer.write(formatMoves(history));
  return buffer.toString();
}

/// Analyse le contenu d'un fichier `.nmc`.
///
/// L'en-tête s'arrête à la première ligne vide, comme au format PGN.
NmcGame parseNmc(String content) {
  final fields = <String, String>{};
  final moveLines = <String>[];
  var inHeader = true;

  final headerLine = RegExp(r'^\[(\w+)\s+"(.*)"\]$');
  for (final raw in content.split('\n')) {
    final line = raw.trimRight();
    if (inHeader && line.startsWith('[') && line.endsWith(']')) {
      final m = headerLine.firstMatch(line);
      if (m != null) fields[m.group(1)!.toLowerCase()] = m.group(2)!;
      continue;
    }
    if (line.trim().isEmpty) {
      inHeader = false;
      continue;
    }
    inHeader = false;
    moveLines.add(line);
  }

  return NmcGame(
    NmcMeta.fromFields(fields),
    parseMoves(moveLines.join(' ').trim()),
  );
}

/// Symbole de résultat, du point de vue des Blancs.
String resultSymbol({required String? loserCamp}) => switch (loserCamp) {
  'Blanc' => '0-1',
  'Noir' => '1-0',
  _ => '½-½',
};
