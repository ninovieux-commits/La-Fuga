/// Une ligne du classement : un rang, un joueur, son mélo.
///
/// Le serveur rend les trente meilleurs d'un mode, déjà triés et déjà
/// numérotés : le rang vient de LUI, et non du numéro de la ligne dans la
/// liste. Deux joueurs à égalité ne feront jamais deux fois le même rang
/// ici — le serveur les départage sur le pseudo — mais si cela devait
/// changer un jour, l'App n'aurait rien à réapprendre.
library;

final class RangClassement {
  const RangClassement({
    required this.rang,
    required this.pseudo,
    required this.melo,
    this.photo = '',
  });

  /// De 1 à 30.
  final int rang;

  final String pseudo;
  final int melo;

  /// La photo de profil, telle que la base la garde. Vide quand le compte
  /// n'en a pas — ou quand le serveur ne sait pas la dire : l'App la
  /// retrouvera alors par `AvatarPhotos`.
  final String photo;

  static RangClassement fromJson(Map<String, dynamic> j) => RangClassement(
    rang: (j['rang'] as num?)?.toInt() ?? 0,
    pseudo: '${j['pseudo'] ?? ''}',
    melo: (j['melo'] as num?)?.toInt() ?? 1500,
    photo: '${j['photo'] ?? ''}',
  );
}
