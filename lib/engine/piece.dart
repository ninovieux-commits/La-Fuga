/// Pièces et camps de La Fuga — Dart pur, aucun import Flutter.
///
/// Ce fichier (et tout `lib/engine/`) doit rester utilisable depuis un
/// `Isolate` : pas de `dart:ui`, pas de `package:flutter`.
library;

/// Les deux camps. Les noms sérialisés restent le français du protocole
/// serveur ("Blanc" / "Noir") : ils transitent dans les payloads Socket.IO.
enum Camp {
  blanc('Blanc'),
  noir('Noir');

  const Camp(this.wire);

  /// Nom tel qu'attendu par le serveur et par la notation `.nmc`.
  final String wire;

  Camp get opposite => this == Camp.blanc ? Camp.noir : Camp.blanc;

  /// Rangée de ralliement : Blanc fugue en 8, Noir en -1.
  int get rallyRow => this == Camp.blanc ? 8 : -1;

  /// Sens de progression sur l'axe des rangées.
  int get forward => this == Camp.blanc ? 1 : -1;

  static Camp fromWire(String s) =>
      s == 'Noir' ? Camp.noir : Camp.blanc;
}

/// Les cinq types de pièces.
enum PieceType {
  heritier('Héritier'),
  nurse('Nurse'),
  soldat('Soldat'),
  garde('Garde'),
  chevalier('Chevalier');

  const PieceType(this.wire);

  final String wire;

  /// Ronde : peut sauter, doit toucher une autre ronde pour bouger.
  bool get isRound => this == PieceType.heritier || this == PieceType.nurse;

  /// Carrée : peut pousser et manœuvrer, doit toucher une autre carrée.
  /// Le Chevalier n'est PAS une carrée (il ne compte pas comme voisin carré).
  bool get isSquare => this == PieceType.soldat || this == PieceType.garde;

  static PieceType fromWire(String s) => switch (s) {
        'Héritier' => PieceType.heritier,
        'Nurse' => PieceType.nurse,
        'Soldat' => PieceType.soldat,
        'Garde' => PieceType.garde,
        'Chevalier' => PieceType.chevalier,
        _ => throw ArgumentError('Type de pièce inconnu : $s'),
      };
}

/// Une pièce est immuable : le moteur déplace des références, il ne mute
/// jamais le contenu d'une pièce. C'est ce qui permet au clone de plateau de
/// ne copier que la structure des colonnes (cf. `_dg_clone` en Python).
final class Piece {
  const Piece(this.type, this.camp);

  final PieceType type;
  final Camp camp;

  bool get isRound => type.isRound;
  bool get isSquare => type.isSquare;
  bool get isKnight => type == PieceType.chevalier;
  bool get isHeir => type == PieceType.heritier;

  /// Les 12 instances possibles, partagées pour éviter toute allocation dans
  /// les boucles chaudes du générateur de coups.
  static const Piece blancHeritier = Piece(PieceType.heritier, Camp.blanc);
  static const Piece blancNurse = Piece(PieceType.nurse, Camp.blanc);
  static const Piece blancSoldat = Piece(PieceType.soldat, Camp.blanc);
  static const Piece blancGarde = Piece(PieceType.garde, Camp.blanc);
  static const Piece blancChevalier = Piece(PieceType.chevalier, Camp.blanc);
  static const Piece noirHeritier = Piece(PieceType.heritier, Camp.noir);
  static const Piece noirNurse = Piece(PieceType.nurse, Camp.noir);
  static const Piece noirSoldat = Piece(PieceType.soldat, Camp.noir);
  static const Piece noirGarde = Piece(PieceType.garde, Camp.noir);
  static const Piece noirChevalier = Piece(PieceType.chevalier, Camp.noir);

  static Piece of(PieceType type, Camp camp) => switch ((type, camp)) {
        (PieceType.heritier, Camp.blanc) => blancHeritier,
        (PieceType.nurse, Camp.blanc) => blancNurse,
        (PieceType.soldat, Camp.blanc) => blancSoldat,
        (PieceType.garde, Camp.blanc) => blancGarde,
        (PieceType.chevalier, Camp.blanc) => blancChevalier,
        (PieceType.heritier, Camp.noir) => noirHeritier,
        (PieceType.nurse, Camp.noir) => noirNurse,
        (PieceType.soldat, Camp.noir) => noirSoldat,
        (PieceType.garde, Camp.noir) => noirGarde,
        (PieceType.chevalier, Camp.noir) => noirChevalier,
      };

  /// Clé compacte d'une case, façon `_dg_board_key` : première lettre du type
  /// + première lettre du camp. 'H'/'N'/'S'/'G'/'C' × 'B'/'N'.
  String get key => '${type.wire[0]}${camp.wire[0]}';

  Map<String, String> toJson() => {'type': type.wire, 'camp': camp.wire};

  static Piece fromJson(Map<String, dynamic> j) =>
      Piece.of(PieceType.fromWire(j['type'] as String),
          Camp.fromWire(j['camp'] as String));

  @override
  String toString() => '${type.wire}(${camp.wire})';
}
