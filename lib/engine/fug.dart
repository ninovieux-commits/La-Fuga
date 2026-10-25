/// Le format `.fug` : une POSITION, là où le `.nmc` décrit une partie.
///
/// Un `.nmc` part d'une position de départ connue — la standard, ou celle d'un
/// code Random Fuga — et énumère les coups. Il ne sait donc pas dire « voici
/// un plateau quelconque ». C'est ce que `.fug` fait.
///
/// ## La forme
///
/// Une première ligne pour le camp au trait, puis les huit rangées du plateau,
/// une par ligne, de **do1 à si1**, puis do2 à si2, et ainsi de suite jusqu'à
/// si8. Sept caractères par ligne — le plateau compte sept colonnes, une par
/// note.
///
///     B
///     sgshgsg
///     gnnnnns
///     ---c---
///     -------
///     -------
///     ---C---
///     GNNNNNS
///     SGSHGSG
///
/// Une lettre par pièce, **minuscule pour les Blancs, majuscule pour les
/// Noirs** :
///
/// | lettre | pièce |
/// |--------|-------|
/// | `h`    | Héritier |
/// | `n`    | Nurse |
/// | `c`    | Chevalier |
/// | `g`    | Garde |
/// | `s`    | Soldat |
/// | `-`    | case vide |
///
/// La première ligne vaut `B` quand les Blancs sont au trait, `N` pour les
/// Noirs. Elle est en majuscule dans les deux cas : elle ne désigne pas une
/// pièce, la règle des casses ne s'y applique pas.
///
/// ## Les zones de ralliement, quand elles ne sont pas celles d'origine
///
/// Nino : « il faut que le code .fug contienne deux nouvelles lignes avant le
/// N ou B qui indique qui commence. » Sept caractères chacune, `r` pour une
/// case de ralliement et `-` pour le reste ; la première est celle des
/// Blancs, la seconde celle des Noirs.
///
///     rr-----
///     --r-r--
///     B
///     sgshgsg
///     …
///
/// « S'il n'y a pas ces deux lignes dans un code .fug, alors il s'agit de la
/// position originale (`--rrr--` / `--rrr--`). » Les anciens codes se lisent
/// donc tels quels, et on n'écrit les deux lignes que lorsqu'elles disent
/// quelque chose — un `.fug` ordinaire reste identique à ce qu'il était.
///
/// Les deux formes ne se confondent pas : une ligne de ralliement fait sept
/// caractères, celle du trait en fait un.
///
/// Le texte se lit de bas en haut de l'écran quand les Blancs sont en bas —
/// la première ligne est leur rangée de fond. C'est voulu : on lit `do1` en
/// premier, comme on le dit.
///
/// ## Ce que le format ne garantit pas
///
/// Il décrit une position, il ne la juge pas. Une position lisible peut être
/// injouable (sans Héritier, par exemple) : c'est [fugRefus] qui le dit, et
/// seulement là où une position doit être jouable.
///
/// Dart pur, sans Flutter.
library;

import 'board.dart';
import 'piece.dart';

/// Case vide.
const String kFugVide = '-';

/// La lettre d'un type de pièce, en minuscule.
const Map<PieceType, String> kFugLettres = {
  PieceType.heritier: 'h',
  PieceType.nurse: 'n',
  PieceType.chevalier: 'c',
  PieceType.garde: 'g',
  PieceType.soldat: 's',
};

final Map<String, PieceType> _typeParLettre = {
  for (final e in kFugLettres.entries) e.value: e.key,
};

/// Une position lue : le plateau, et le camp au trait.
typedef FugPosition = ({Board board, Camp turn});

/// Pourquoi un texte `.fug` n'est pas lisible.
enum FugErreur {
  /// Vide, ou rien d'autre que des blancs.
  vide,

  /// La première ligne n'est ni `B` ni `N`.
  traitInconnu,

  /// Il n'y a pas exactement huit rangées.
  rangees,

  /// Une rangée ne fait pas sept caractères.
  colonnes,

  /// Un caractère qui n'est ni une pièce ni une case vide.
  lettre,

  /// Une ligne de ralliement contient autre chose que `r` et `-`, ou il n'y
  /// en a qu'une : elles vont par deux.
  ralliement,
}

/// La lettre d'une case de ralliement.
const String kFugRallie = 'r';

/// Écrit les deux lignes de ralliement, ou rien si elles sont d'origine.
String fugEcrireRalliements(Ralliements rall) {
  if (rall.estStandard) return '';
  final out = StringBuffer();
  for (final camp in [Camp.blanc, Camp.noir]) {
    for (var c = 0; c < kCols; c++) {
      out.write(rall.contient(camp, c) ? kFugRallie : kFugVide);
    }
    out.write('\n');
  }
  return out.toString();
}

/// Lit une ligne de ralliement, ou `null` si ce n'en est pas une.
int? _masqueDeLigne(String ligne) {
  if (ligne.length != kCols) return null;
  var masque = 0;
  for (var c = 0; c < kCols; c++) {
    final ch = ligne[c].toLowerCase();
    if (ch == kFugRallie) {
      masque |= 1 << c;
    } else if (ch != kFugVide) {
      return null;
    }
  }
  return masque;
}

/// Pourquoi une position ne peut pas servir de départ à une partie.
enum FugRefus {
  /// Un camp n'a pas d'Héritier, ou en a plusieurs. Il en faut un, et un seul.
  heritier,

  /// Un camp n'a aucune pièce carrée capable de bouger. La position serait
  /// nulle d'entrée : une carrée ne bouge que si elle touche une autre carrée.
  carreesBloquees,

  /// Moins de [kFugVidesMin] cases libres. Un plateau plein ne laisse nulle
  /// part où aller.
  casesVides,
}

/// Combien de cases doivent rester libres pour qu'une position se joue.
const int kFugVidesMin = 3;

/// Le résultat d'une lecture : la position, ou la raison du refus.
typedef FugLecture = ({FugPosition? position, FugErreur? erreur, int? ligne});

/// Écrit une position au format `.fug`.
String fugEcrire(Board board, Camp turn) {
  final out = StringBuffer(fugEcrireRalliements(board.rall));
  out.write(turn == Camp.blanc ? 'B' : 'N');
  for (var r = 0; r < kRows; r++) {
    out.write('\n');
    for (var c = 0; c < kCols; c++) {
      final p = board.at(c, r);
      if (p == null) {
        out.write(kFugVide);
        continue;
      }
      final lettre = kFugLettres[p.type]!;
      out.write(p.camp == Camp.noir ? lettre.toUpperCase() : lettre);
    }
  }
  return out.toString();
}

/// Lit un texte `.fug`.
///
/// Tolérant sur ce qui ne change pas le sens : lignes vides en tête ou en
/// queue, espaces de fin, retours à la ligne de Windows. Strict sur le reste —
/// une position à moitié lue vaut moins que rien.
FugLecture fugLire(String texte) {
  final lignes = [
    for (final l in texte.replaceAll('\r\n', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lignes.isEmpty) {
    return (position: null, erreur: FugErreur.vide, ligne: null);
  }

  // LES DEUX LIGNES DE RALLIEMENT, s'il y en a. Une ligne de sept caractères
  // en tête ne peut être que cela : celle du trait en fait un.
  var rall = Ralliements.standard;
  final premier = _masqueDeLigne(lignes.first);
  if (premier != null) {
    final second = lignes.length >= 2 ? _masqueDeLigne(lignes[1]) : null;
    if (second == null) {
      // Elles vont par deux : une seule ne dit pas qui rallie où.
      return (position: null, erreur: FugErreur.ralliement, ligne: 2);
    }
    rall = Ralliements(blanc: premier, noir: second);
    lignes.removeRange(0, 2);
    if (lignes.isEmpty) {
      return (position: null, erreur: FugErreur.traitInconnu, ligne: 3);
    }
  }

  final trait = switch (lignes.first.toUpperCase()) {
    'B' => Camp.blanc,
    'N' => Camp.noir,
    _ => null,
  };
  if (trait == null) {
    return (position: null, erreur: FugErreur.traitInconnu, ligne: 1);
  }

  final rangees = lignes.sublist(1);
  if (rangees.length != kRows) {
    return (position: null, erreur: FugErreur.rangees, ligne: null);
  }

  final board = Board.empty(rall: rall);
  for (var i = 0; i < kRows; i++) {
    final ligne = rangees[i];
    if (ligne.length != kCols) {
      return (position: null, erreur: FugErreur.colonnes, ligne: i + 2);
    }
    // La première rangée écrite est do1..si1, donc la rangée d'indice 0.
    for (var c = 0; c < kCols; c++) {
      final ch = ligne[c];
      if (ch == kFugVide) continue;
      final type = _typeParLettre[ch.toLowerCase()];
      if (type == null) {
        return (position: null, erreur: FugErreur.lettre, ligne: i + 2);
      }
      final camp = ch == ch.toUpperCase() ? Camp.noir : Camp.blanc;
      // `Piece.of` et non `Piece(...)` : le moteur partage douze instances et
      // compare les pièces par IDENTITÉ — une pièce fraîchement allouée n'est
      // égale à aucune autre, et les comparaisons échouent en silence.
      board.set(c, i, Piece.of(type, camp));
    }
  }
  return (position: (board: board, turn: trait), erreur: null, ligne: null);
}

/// Combien de pièces de ce type et de ce camp sont sur le plateau.
int fugCompte(Board board, PieceType type, Camp camp) {
  var n = 0;
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p != null && p.type == type && p.camp == camp) n++;
    }
  }
  return n;
}

/// Combien d'Héritiers [camp] a sur le plateau.
int fugHeritiers(Board board, Camp camp) =>
    fugCompte(board, PieceType.heritier, camp);

/// Vrai si [camp] possède au moins une pièce carrée capable de bouger.
///
/// Une carrée ne bouge que si elle touche une autre carrée, de n'importe quel
/// camp ; le Chevalier ne compte pas comme voisine. Un camp dont aucune carrée
/// ne peut bouger ne peut rien entreprendre.
bool fugCarreeMobile(Board board, Camp camp) {
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = board.at(c, r);
      if (p == null || !p.isSquare || p.camp != camp) continue;
      if (board.hasSquareNeighbour(c, r)) return true;
    }
  }
  return false;
}

/// Combien de cases du plateau sont libres.
int fugCasesVides(Board board) {
  var n = 0;
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      if (board.at(c, r) == null) n++;
    }
  }
  return n;
}

/// Pourquoi cette position ne peut pas servir de départ — ou `null` si elle le
/// peut.
///
/// Les règles de Nino, et elles seules : un Héritier par camp, des carrées qui
/// peuvent bouger des deux côtés, et au moins [kFugVidesMin] cases libres.
/// Pour le reste on ne juge rien — dix Gardes d'un côté, c'est permis.
///
/// LE CHEVALIER ÉTAIT COMPTÉ, lui aussi : il n'en existait qu'un par camp.
/// Nino : « enlève la contrainte sur le nombre de chevalier, que l'on puisse
/// en mettre plusieurs comme les autres pièces. Seul l'héritier conserve la
/// règle de "un seul". »
///
/// Rien n'est dit des zones de ralliement : un camp qui n'en a aucune ne peut
/// pas fuguer, mais il peut encore mater, et la position se joue.
FugRefus? fugRefus(Board board) {
  for (final camp in Camp.values) {
    if (fugHeritiers(board, camp) != 1) return FugRefus.heritier;
  }
  for (final camp in Camp.values) {
    if (!fugCarreeMobile(board, camp)) return FugRefus.carreesBloquees;
  }
  // Un plateau presque plein ne laisse nulle part où aller : rien ne peut
  // avancer, et la partie serait nulle d'entrée comme avec des carrées
  // bloquées.
  if (fugCasesVides(board) < kFugVidesMin) return FugRefus.casesVides;
  return null;
}

/// La position écrite sur UNE ligne, pour un en-tête `.nmc`.
///
/// Les rangées y sont séparées par des barres obliques : un en-tête `.nmc`
/// s'écrit `[Clé "valeur"]` sur une ligne, un texte à huit lignes n'y entre
/// pas. `B/sgshgsg/gnnnnns/…`
String fugEnUneLigne(String fug) =>
    fugLire(fug).position == null ? '' : fug.trim().split('\n').join('/');

/// L'inverse : la forme à huit lignes depuis la forme d'un en-tête.
String fugDepuisUneLigne(String ligne) => ligne.trim().split('/').join('\n');
