/// Détection directe des menaces décisives — fugue et mat — sans générer les
/// coups.
///
/// L'évaluation de Deep Grey n'a besoin, de tout le générateur, que de deux
/// réponses : « ce camp peut-il fuguer au coup suivant ? » et « peut-il
/// éjecter l'Héritier d'en face ? ». Les obtenir en construisant les quelque
/// cinquante coups légaux — et donc cinquante plateaux clonés — pour les jeter
/// aussitôt coûtait 70 µs des 74 µs d'une évaluation. Ce fichier répond aux
/// mêmes questions en parcourant le plateau, sans allouer un seul plateau.
///
/// Les réponses doivent être **exactement** celles du générateur : c'est la
/// force de jeu qui en dépend, et `threats_parity_test.dart` le vérifie sur
/// des milliers de positions tirées au hasard.
library;

import 'board.dart';
import 'piece.dart';

/// Ce qu'un camp menace de faire au coup suivant.
final class Threats {
  const Threats({
    required this.canFugue,
    required this.matOnBlanc,
    required this.matOnNoir,
  });

  static const Threats none = Threats(
    canFugue: false,
    matOnBlanc: false,
    matOnNoir: false,
  );

  /// Le camp qui joue a un coup qui le fait fuguer — par déplacement, par
  /// saut, ou en poussant son propre Héritier dans sa zone de ralliement.
  final bool canFugue;

  /// Un de ses coups éjecte l'Héritier blanc / noir hors du plateau.
  final bool matOnBlanc;
  final bool matOnNoir;

  bool matOn(Camp camp) => camp == Camp.blanc ? matOnBlanc : matOnNoir;
}

/// Menaces de `camp` sur `board`.
///
/// La fugue est cherchée en premier : quand elle existe, le mat ne change plus
/// rien au score et le balayage s'arrête là.
Threats threatsOf(Board board, Camp camp) {
  if (_heirCanReachRally(board, camp)) return _fugueOnly;
  return _scanPushes(board, camp);
}

/// Vrai si `camp` peut fuguer au coup suivant. Équivalent de
/// `campCanFugue`, sans générer les coups.
bool campCanFugueDirect(Board board, Camp camp) =>
    threatsOf(board, camp).canFugue;

const Threats _fugueOnly = Threats(
  canFugue: true,
  matOnBlanc: false,
  matOnNoir: false,
);

/// ── Fugue de l'Héritier par ses propres pieds ──
///
/// Réplique exacte de la partie « rondes » de `_generateRoundMoves` : mêmes
/// conditions de voisinage, même parcours de multisauts, même interdiction de
/// re-sauter aussitôt la ronde qu'on vient de sauter.
bool _heirCanReachRally(Board board, Camp camp) {
  var hc = -1, hr = -1;
  Piece? heir;
  for (var c = 0; c < kCols && heir == null; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p != null && p.isHeir && p.camp == camp) {
        heir = p;
        hc = c;
        hr = r;
        break;
      }
    }
  }
  if (heir == null) return false;
  // Une ronde isolée est immobile : ni déplacement, ni saut.
  if (!board.hasRoundNeighbour(hc, hr)) return false;

  // Déplacement d'une case dans la zone de ralliement.
  for (final (dc, dr) in kAllDirs) {
    if (Board.isFugueDest(hc + dc, hr + dr, heir)) return true;
  }

  // Multisauts. Comme le générateur, l'Héritier compte pour absent de sa case
  // de départ pendant toute la simulation : il peut sauter par-dessus la case
  // qu'il vient de libérer. Les cases déjà visitées tiennent dans un entier —
  // 7 × 8 cases, soit 56 bits — plutôt que dans un `Set` recopié à chaque
  // branche, ce qui serait l'essentiel du coût.
  final origin = 1 << (hc * kRows + hr);
  // (colonne, rangée, cases visitées, ronde sautée au coup précédent)
  final stack = <(int, int, int, int)>[(hc, hr, origin, -1)];

  while (stack.isNotEmpty) {
    final (curC, curR, visited, last) = stack.removeLast();
    for (final (jdc, jdr) in kAllDirs) {
      final mc = curC + jdc, mr = curR + jdr;
      final nc = curC + 2 * jdc, nr = curR + 2 * jdr;
      // Anti-aller-retour : pas deux fois de suite par-dessus la même ronde.
      final onB = Board.onBoard(mc, mr);
      final midIndex = onB ? mc * kRows + mr : -1;
      if (midIndex >= 0 && midIndex == last) continue;

      if (Board.isFugueDest(nc, nr, heir)) {
        if (!onB) continue;
        final jumped = _at(board, mc, mr, hc, hr);
        if (jumped != null && jumped.isRound) return true;
        continue;
      }
      if (!onB || !Board.onBoard(nc, nr)) continue;
      final jumped = _at(board, mc, mr, hc, hr);
      if (jumped == null || !jumped.isRound) continue;
      if (_at(board, nc, nr, hc, hr) != null) continue;

      final bit = 1 << (nc * kRows + nr);
      if (visited & bit != 0) continue;
      stack.add((nc, nr, visited | bit, midIndex));
    }
  }
  return false;
}

/// Le plateau vu en considérant (hc,hr) comme vide — la case que l'Héritier a
/// quittée. Évite de cloner le plateau pour une seule case retirée.
Piece? _at(Board board, int c, int r, int hc, int hr) =>
    (c == hc && r == hr) ? null : board.at(c, r);

/// ── Fugue et mat par poussée ──
///
/// Chaque direction de poussée agit sur son propre rayon depuis la case
/// d'arrivée, et deux rayons distincts ne se croisent jamais : le générateur a
/// beau produire toutes les combinaisons de directions, l'ensemble des issues
/// atteignables est l'union des issues de chaque direction prise seule. Il
/// suffit donc de balayer les directions une à une.
Threats _scanPushes(Board board, Camp camp) {
  var matBlanc = false, matNoir = false;

  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p == null || p.camp != camp || !p.isSquare) continue;
      // Une carrée isolée est immobile.
      if (!board.hasSquareNeighbour(c, r)) continue;

      for (final (dc, dr) in kAllDirs) {
        final nc = c + dc, nr = r + dr;
        if (!Board.onBoard(nc, nr) || board.at(nc, nr) != null) continue;
        if (!_pushActivated(p.type, dc, dr)) continue;

        for (final (pdc, pdr) in _pushDirs(p.type)) {
          // Dernière pièce de la ligne contiguë depuis la case d'arrivée. La
          // case de départ, elle, vient d'être libérée : elle coupe la ligne.
          Piece? last;
          var lc = 0, lr = 0;
          var cc = nc + pdc, rr = nr + pdr;
          var offBoard = false;
          while (true) {
            if (!Board.onBoard(cc, rr)) {
              offBoard = true;
              break;
            }
            final q = (cc == c && rr == r) ? null : board.at(cc, rr);
            if (q == null) break;
            if (q.isKnight) {
              // Un Chevalier dans la ligne annule toute la poussée.
              last = null;
              break;
            }
            last = q;
            lc = cc;
            lr = rr;
            cc += pdc;
            rr += pdr;
          }
          // Seule une ligne qui butte sur le bord éjecte quelque chose.
          if (!offBoard || last == null) continue;
          if (!last.isHeir) continue;

          final oc = lc + pdc, or_ = lr + pdr;
          final ownRally = kRally.contains(oc) && or_ == last.camp.rallyRow;
          if (ownRally) {
            // Un Héritier poussé dans SA zone fugue : si c'est le nôtre, plus
            // rien d'autre ne compte.
            if (last.camp == camp) return _fugueOnly;
            continue;
          }
          if (last.camp == Camp.blanc) {
            matBlanc = true;
          } else {
            matNoir = true;
          }
        }
      }
    }
  }

  return Threats(canFugue: false, matOnBlanc: matBlanc, matOnNoir: matNoir);
}

/// Copies locales de `pushActivated` / `pushDirsFor`, pour que ce fichier ne
/// dépende pas du générateur de coups qu'il sert justement à éviter.
bool _pushActivated(PieceType type, int dc, int dr) => type == PieceType.soldat
    ? dc.abs() + dr.abs() == 1
    : dc.abs() == 1 && dr.abs() == 1;

List<(int, int)> _pushDirs(PieceType type) =>
    type == PieceType.soldat ? kSoldatPushDirs : kGardePushDirs;
