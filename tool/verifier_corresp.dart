// Rejoue les parties de correspondance terminées et dit QUI a vraiment gagné.
//
//     dart run tool/verifier_corresp.dart <export.json>
//
// Le serveur donnait la victoire à celui qui jouait le coup final. C'est faux
// quand ce coup fait gagner l'AUTRE : pousser l'Héritier adverse dans SON
// ralliement le fait fuguer, éjecter son PROPRE Héritier est un mat contre
// soi-même. Le serveur ne peut pas le déduire du texte du coup — « Do1-Do2> »
// ne dit pas QUI a été poussé — alors on rejoue, avec le moteur du jeu.
//
// La relecture est LITTÉRALE, comme partout ailleurs : on déplace les pièces
// comme la notation le dit, sans chercher le coup légal correspondant. C'est
// ce qui garantit qu'on reconstruit la même position que l'appareil qui a
// joué la partie.
//
// N'ÉCRIT RIEN. Ce programme lit un export et imprime un verdict.
import 'dart:convert';
import 'dart:io';

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/move.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/engine/random_fuga.dart';

/// Ce qu'une partie rejouée donne.
typedef Verdict = ({
  /// `1-0`, `0-1`, `nulle`, ou vide si la relecture n'a pas conclu.
  String result,
  String method,
  int points,
  String note,
});

bool _heirOnBoard(Board b, Camp camp) {
  for (var c = 0; c < 7; c++) {
    for (var r = 0; r < 8; r++) {
      final p = b.at(c, r);
      if (p != null && p.isHeir && p.camp == camp) return true;
    }
  }
  return false;
}

/// « Fa4* » quand Fa4 ne porte pas l'Héritier du joueur au trait.
///
/// La notation d'une fugue s'écrit « Départ* » et s'arrête là : quand la
/// fugue vient d'une POUSSÉE, ni la case d'arrivée du pousseur ni ce qu'il a
/// poussé ne sont écrits. La relecture littérale ne peut donc rien en faire.
/// On demande alors au générateur : parmi les coups légaux partant de cette
/// case, lesquels finissent par une fugue ? S'ils désignent tous le même
/// fugueur, le coup est levé sans ambiguïté.
Cell? _fugueParPoussee(Board board, String notation, Camp mover) {
  final m = splitEndMark(notation).move;
  if (!m.endsWith('*') || m.contains('-') || m.startsWith('(')) return null;
  final depart = notationToCell(m.substring(0, m.length - 1));
  if (depart == null) return null;
  final piece = board.at(depart.col, depart.row);
  // L'Héritier du joueur au trait qui sort lui-même : la relecture littérale
  // sait faire, c'est le cas normal.
  if (piece == null || (piece.isHeir && piece.camp == mover)) return null;
  return depart;
}

Verdict _rejouer(List<String> coups, Board depart) {
  var board = depart;
  var turn = Camp.blanc;

  for (var i = 0; i < coups.length; i++) {
    final avant = board;

    // Une fugue par poussée : la notation a perdu le coup, on le retrouve.
    final casePoussee = _fugueParPoussee(board, coups[i], turn);
    if (casePoussee != null) {
      final mover = turn;
      final candidats = <Move>[
        for (final m in generateMoves(board, mover))
          if (m.from == casePoussee && (m.fugue || m.fugueBy != null)) m,
      ];
      final fugueurs = {
        for (final m in candidats) m.fugue ? mover : m.fugueBy!,
      };
      if (fugueurs.length != 1) {
        return (
          result: '',
          method: '',
          points: 0,
          note:
              'coup ${i + 1} «${coups[i]}» : '
              '${candidats.isEmpty ? "aucun" : "${fugueurs.length}"} coup de '
              'fugue possible depuis cette case — indécidable',
        );
      }
      final fugueur = fugueurs.first;
      final apres = candidats.first.board;
      if (fugueur != mover) {
        return (
          result: fugueur == Camp.blanc ? '1-0' : '0-1',
          method: 'fugue',
          points: 2,
          note:
              'coup ${i + 1} : ${mover.name} pousse l Héritier '
              '${fugueur.name} dans son ralliement (${candidats.length} '
              'coup(s) légaux depuis ${coups[i]}, tous de même issue)',
        );
      }
      if (campCanFugue(apres, mover.opposite)) {
        return (
          result: 'nulle',
          method: 'nulle',
          points: 0,
          note: 'double fugue possible au coup ${i + 1}',
        );
      }
      return (
        result: fugueur == Camp.blanc ? '1-0' : '0-1',
        method: 'fugue',
        points: 2,
        note:
            'coup ${i + 1} : ${mover.name} pousse son PROPRE Héritier '
            'dans son ralliement',
      );
    }

    final r = applyNotationLiterally(board, coups[i]);
    board = r.board;
    final mover = turn;
    turn = turn.opposite;

    final partis = <Camp>[
      for (final camp in Camp.values)
        if (_heirOnBoard(avant, camp) && !_heirOnBoard(board, camp)) camp,
    ];
    if (partis.isEmpty) continue;

    final fugues = partis.where(r.fugued.contains).toList();
    final ejectes = partis.where((c) => !r.fugued.contains(c)).toList();

    if (ejectes.isNotEmpty) {
      // Mat : l'Héritier éjecté hors du plateau fait perdre son camp, quel
      // que soit celui qui a joué. Un point.
      final perdant = ejectes.first;
      return (
        result: perdant == Camp.blanc ? '0-1' : '1-0',
        method: 'mat',
        points: 1,
        note:
            'Héritier ${perdant.name} éjecté au coup ${i + 1}'
            '${mover == perdant ? " par LUI-MÊME" : ""}',
      );
    }

    final fugueur = fugues.first;
    if (fugueur != mover) {
      // Poussé jusqu'à SON ralliement : il fugue, donc il gagne.
      return (
        result: fugueur == Camp.blanc ? '1-0' : '0-1',
        method: 'fugue',
        points: 2,
        note:
            'Héritier ${fugueur.name} poussé dans son ralliement '
            'par ${mover.name} au coup ${i + 1}',
      );
    }
    // Sa propre fugue : l'adversaire peut-il égaliser en un coup ?
    if (campCanFugue(board, mover.opposite)) {
      return (
        result: 'nulle',
        method: 'nulle',
        points: 0,
        note: 'double fugue possible au coup ${i + 1}',
      );
    }
    return (
      result: fugueur == Camp.blanc ? '1-0' : '0-1',
      method: 'fugue',
      points: 2,
      note: 'fugue de ${fugueur.name} au coup ${i + 1}',
    );
  }
  return (result: '', method: '', points: 0, note: 'aucune fin trouvée');
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/verifier_corresp.dart <export.json>');
    exit(2);
  }
  final donnees =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final parties = (donnees['parties'] as List).cast<Map<String, dynamic>>();
  final pseudos = {
    for (final u in (donnees['users'] as List).cast<Map<String, dynamic>>())
      u['id'] as int: u['pseudo'] as String,
  };

  // Score reconstruit depuis zéro, par paire ordonnée (petit id, grand id).
  final scores = <String, List<int>>{};
  void ajouter(int gagnant, int perdant, int pts) {
    final a = gagnant < perdant ? gagnant : perdant;
    final b = gagnant < perdant ? perdant : gagnant;
    final l = scores.putIfAbsent('$a|$b', () => [0, 0]);
    l[gagnant == a ? 0 : 1] += pts;
  }

  final corrections = <Map<String, dynamic>>[];

  for (final p in parties) {
    final id = p['id'] as int;
    final blanc = p['blanc_user_id'] as int;
    final noir = p['noir_user_id'] as int;
    final stocke = (p['resultat'] ?? '').toString();
    final methode = (p['methode'] ?? '').toString();
    final coups = (p['moves_text'] ?? '')
        .toString()
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final code = (p['random_code'] ?? '').toString();

    final entete =
        'partie $id  ${pseudos[blanc]} (B) vs ${pseudos[noir]} (N)'
        '${code.isEmpty ? "" : "  [random $code]"}';

    // Défi refusé, ou abandonné avant le premier coup : aucun point, rien à
    // rejouer. L'abandon d'une partie COMMENCÉE, lui, vaut deux points et ne
    // se rejoue pas non plus — il n'est pas dans les coups.
    if (stocke == 'refuse' || stocke == 'abandon_defi') {
      stdout.writeln('$entete\n   défi sans partie ($stocke) — aucun point');
      continue;
    }
    if (methode == 'abandon') {
      final gagnant = stocke == '1-0' ? blanc : noir;
      ajouter(gagnant, gagnant == blanc ? noir : blanc, 2);
      stdout.writeln(
        '$entete\n   abandon — $stocke, 2 pts à '
        '${pseudos[gagnant]} (pas de coup à rejouer)',
      );
      continue;
    }
    if (stocke == 'nulle') {
      stdout.writeln('$entete\n   nulle — aucun point');
      continue;
    }

    final depart = code.isEmpty
        ? Board.initial()
        : (buildRandomFugaBoard(code) ?? Board.initial());
    if (code.isNotEmpty && buildRandomFugaBoard(code) == null) {
      stdout.writeln(
        '$entete\n   ⚠ code Random Fuga illisible : '
        'position de départ standard utilisée, verdict douteux',
      );
    }

    final v = _rejouer(coups, depart);
    final juste = v.result == stocke;
    stdout.writeln(entete);
    stdout.writeln('   ${coups.length} coups — ${v.note}');
    stdout.writeln(
      '   stocké : $stocke ($methode)   '
      'rejoué : ${v.result} (${v.method}, ${v.points} pt)'
      '   ${v.result.isEmpty ? "?" : (juste ? "OK" : "FAUX")}',
    );

    if (v.result.isEmpty) continue;
    if (v.result != 'nulle') {
      final gagnant = v.result == '1-0' ? blanc : noir;
      ajouter(gagnant, gagnant == blanc ? noir : blanc, v.points);
    }
    if (!juste) {
      corrections.add({
        'game_id': id,
        'resultat': v.result,
        'methode': v.method,
        'avant': stocke,
      });
    }
  }

  stdout.writeln('\n══ Scores recalculés depuis zéro ══');
  final attendus = {
    for (final s
        in (donnees['corr_scores'] as List).cast<Map<String, dynamic>>())
      '${s['user_a']}|${s['user_b']}': [
        s['score_a'] as int,
        s['score_b'] as int,
      ],
  };
  for (final cle in {...scores.keys, ...attendus.keys}) {
    final ids = cle.split('|').map(int.parse).toList();
    final calc = scores[cle] ?? [0, 0];
    final base = attendus[cle] ?? [0, 0];
    final pareil = calc[0] == base[0] && calc[1] == base[1];
    stdout.writeln(
      '${pseudos[ids[0]]} vs ${pseudos[ids[1]]} : '
      'base ${base[0]}-${base[1]}   rejoué ${calc[0]}-${calc[1]}'
      '   ${pareil ? "OK" : "À CORRIGER"}',
    );
  }

  stdout.writeln('\n══ Parties au résultat faux : ${corrections.length} ══');
  for (final c in corrections) {
    stdout.writeln(
      '   partie ${c['game_id']} : ${c['avant']} → '
      '${c['resultat']} (${c['methode']})',
    );
  }

  File('corrections.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'corrections': corrections,
      'scores': {for (final e in scores.entries) e.key: e.value},
    }),
  );
  stdout.writeln('\nÉcrit : corrections.json');
}
