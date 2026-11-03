/// LA DATE DANS LE SENS DE LA LANGUE.
///
/// Nino : « lorsqu'un joueur a l'app réglée en anglais, ça doit mettre la
/// date dans le sens anglais, idem pour les autres langues où le sens est
/// différent. »
///
/// Trois ordres suffisent pour les dix langues de l'application :
///
///   — jour / mois / année : français, espagnol, italien, portugais,
///     allemand et russe (les deux derniers avec un point) ;
///   — mois / jour / année : anglais ;
///   — année / mois / jour : chinois, japonais, coréen.
///
/// Le tampon voyage avec l'image : il est écrit dans la langue de CELUI QUI
/// LE POSE, et c'est voulu — une date qu'on recopie plus tard doit vouloir
/// dire la même chose que lorsqu'elle a été écrite. Mais celui qui la
/// corrige la tape dans son ordre à lui, puisque c'est son clavier.
///
/// Dart pur : l'ordre se vérifie sans écran.
library;

/// L'ordre des trois nombres.
enum OrdreDate {
  jourMoisAn,
  moisJourAn,
  anMoisJour;

  /// Le masque qu'on montre dans le champ de saisie.
  String get masque => switch (this) {
    OrdreDate.jourMoisAn => 'JJ/MM/AAAA',
    OrdreDate.moisJourAn => 'MM/JJ/AAAA',
    OrdreDate.anMoisJour => 'AAAA/MM/JJ',
  };

  /// La longueur de chaque nombre, dans l'ordre.
  List<int> get tailles => switch (this) {
    OrdreDate.anMoisJour => const [4, 2, 2],
    _ => const [2, 2, 4],
  };
}

OrdreDate ordreDeLaDate(String langue) => switch (langue) {
  'en' => OrdreDate.moisJourAn,
  'zh' || 'ja' || 'ko' => OrdreDate.anMoisJour,
  _ => OrdreDate.jourMoisAn,
};

/// Le séparateur : le point là où il est d'usage, la barre ailleurs.
String separateurDeDate(String langue) =>
    langue == 'de' || langue == 'ru' ? '.' : '/';

String _deux(int v) => v.toString().padLeft(2, '0');

/// La date écrite dans la langue donnée.
String dateEcriteSelon(DateTime date, String langue) {
  final s = separateurDeDate(langue);
  final j = _deux(date.day);
  final m = _deux(date.month);
  final a = date.year.toString().padLeft(4, '0');
  return switch (ordreDeLaDate(langue)) {
    OrdreDate.jourMoisAn => '$j$s$m$s$a',
    OrdreDate.moisJourAn => '$m$s$j$s$a',
    OrdreDate.anMoisJour => '$a$s$m$s$j',
  };
}

/// Les chiffres d'une saisie, remis en forme avec leurs séparateurs.
///
/// C'est ce qui fait qu'on n'a « qu'à appuyer sur les chiffres voulus » :
/// les barres sont posées toutes seules, au bon endroit, et ce qu'on efface
/// les enlève sans qu'on ait à les viser.
String masqueLaDate(String saisi, String langue) {
  final chiffres = saisi.replaceAll(RegExp(r'[^0-9]'), '');
  final ordre = ordreDeLaDate(langue);
  final s = separateurDeDate(langue);
  final morceaux = <String>[];
  var reste = chiffres;
  for (final taille in ordre.tailles) {
    if (reste.isEmpty) break;
    final pris = reste.length >= taille ? taille : reste.length;
    morceaux.add(reste.substring(0, pris));
    reste = reste.substring(pris);
  }
  return morceaux.join(s);
}

/// La date d'une saisie, ou nulle si elle n'en est pas une.
///
/// On refuse plutôt que de deviner : un 31 février corrigé en 3 mars ferait
/// un tampon que personne n'a demandé.
DateTime? dateDuTexte(String saisi, String langue) {
  final chiffres = saisi.replaceAll(RegExp(r'[^0-9]'), '');
  final ordre = ordreDeLaDate(langue);
  if (chiffres.length != 8) return null;
  int jour;
  int mois;
  int an;
  switch (ordre) {
    case OrdreDate.jourMoisAn:
      jour = int.parse(chiffres.substring(0, 2));
      mois = int.parse(chiffres.substring(2, 4));
      an = int.parse(chiffres.substring(4));
    case OrdreDate.moisJourAn:
      mois = int.parse(chiffres.substring(0, 2));
      jour = int.parse(chiffres.substring(2, 4));
      an = int.parse(chiffres.substring(4));
    case OrdreDate.anMoisJour:
      an = int.parse(chiffres.substring(0, 4));
      mois = int.parse(chiffres.substring(4, 6));
      jour = int.parse(chiffres.substring(6));
  }
  if (mois < 1 || mois > 12 || jour < 1 || jour > 31 || an < 1) return null;
  final date = DateTime(an, mois, jour);
  // Le 31 février n'existe pas : `DateTime` le décale, on le refuse.
  if (date.day != jour || date.month != mois || date.year != an) return null;
  return date;
}
