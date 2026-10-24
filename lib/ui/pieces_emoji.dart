/// Les pièces du jeu, envoyées dans un message comme des émojis.
///
/// Nino : « je voudrais pouvoir envoyer les images des pièces par messages
/// comme si c'était des emojis (ils sont déjà tous listés dans le choix de
/// l'image de profil). »
///
/// ## Un mot, pas une image
///
/// Rien ne part en pièce jointe : le message reste du texte, et une pièce y
/// est un JETON — `[Soldat]`, `[Soldat Noir]`. Chaque appareil le redessine
/// avec son propre thème, exactement comme une photo de profil, qui est déjà
/// un mot (`thème|Type|Noir`) et non un fichier.
///
/// Le jeton est écrit pour se lire tout seul, et c'est voulu : un client qui
/// ne le connaît pas — une ancienne version sur le téléphone d'en face —
/// affiche « [Soldat Noir] », ce qui se comprend encore. Un code privé y
/// aurait montré des carrés vides.
///
/// Dart pur, sans Flutter.
library;

import '../engine/piece.dart';

/// Les pièces qu'on peut envoyer, dans l'ordre de la galerie des photos.
const List<PieceType> kPiecesEnvoyables = [
  PieceType.heritier,
  PieceType.nurse,
  PieceType.garde,
  PieceType.soldat,
  PieceType.chevalier,
];

/// Le jeton d'une pièce, tel qu'il voyage dans le texte du message.
///
/// Le camp blanc n'est pas écrit : c'est le cas courant, et « [Soldat] » se
/// lit mieux que « [Soldat Blanc] » sur un client qui ne sait pas le dessiner.
String jetonPiece(PieceType type, Camp camp) =>
    camp == Camp.blanc ? '[${type.wire}]' : '[${type.wire} ${camp.wire}]';

/// Le motif des jetons, construit depuis les pièces elles-mêmes : renommer
/// une pièce ne peut pas laisser le motif en arrière.
final RegExp _motifJeton = RegExp(
  r'\[(' +
      kPiecesEnvoyables.map((p) => RegExp.escape(p.wire)).join('|') +
      r')(?: (' +
      Camp.values.map((c) => RegExp.escape(c.wire)).join('|') +
      r'))?\]',
);

/// Un morceau de message : du texte, ou une pièce.
///
/// L'un des deux est toujours nul. On découpe plutôt que de remplacer parce
/// qu'une pièce se DESSINE : elle ne peut pas vivre dans une chaîne.
typedef MorceauMessage = ({String? texte, Piece? piece});

/// Découpe un message en texte et en pièces, dans l'ordre.
///
/// Un message sans jeton rend un seul morceau : le coût est une recherche de
/// motif, et rien d'autre ne change pour les messages ordinaires.
List<MorceauMessage> decoupeMessage(String texte) {
  final morceaux = <MorceauMessage>[];
  var curseur = 0;
  for (final trouve in _motifJeton.allMatches(texte)) {
    if (trouve.start > curseur) {
      morceaux.add((
        texte: texte.substring(curseur, trouve.start),
        piece: null,
      ));
    }
    morceaux.add((texte: null, piece: _pieceDe(trouve)));
    curseur = trouve.end;
  }
  if (curseur < texte.length) {
    morceaux.add((texte: texte.substring(curseur), piece: null));
  }
  return morceaux;
}

Piece _pieceDe(RegExpMatch trouve) {
  final type = kPiecesEnvoyables.firstWhere((p) => p.wire == trouve.group(1));
  final camp = trouve.group(2) == Camp.noir.wire ? Camp.noir : Camp.blanc;
  return Piece(type, camp);
}

/// Vrai si le message contient au moins une pièce.
bool contientUnePiece(String texte) => _motifJeton.hasMatch(texte);

/// Combien de pièces, si le message n'est QUE des pièces — zéro sinon.
///
/// Comme pour les émojis : un message qui ne dit rien d'autre se montre en
/// grand, et sans bulle autour.
int comptePiecesSeules(String texte) {
  var pieces = 0;
  for (final morceau in decoupeMessage(texte)) {
    if (morceau.piece != null) {
      pieces++;
    } else if (morceau.texte!.trim().isNotEmpty) {
      return 0;
    }
  }
  return pieces;
}
