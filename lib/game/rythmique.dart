/// Les rythmiques de la lecture automatique.
///
/// En lecture automatique, un coup se joue — et donc une note sonne — **à
/// chaque temps**. Choisir une rythmique, c'est donc choisir la durée d'un
/// temps : la vitesse ne se règle plus à la main, elle vient de la danse.
///
/// ## Le temps, et ce qu'il vaut
///
/// Dans une mesure simple (3/4, 2/4, 4/4, 3/2), le temps est l'unité du
/// dénominateur : la noire en 3/4, la blanche en 3/2. Dans une mesure
/// composée (6/8), le temps est la noire pointée — il y en a **deux** par
/// mesure, pas six. Une gigue à 120 joue donc deux coups par mesure, pas six.
///
/// Les tempos sont ceux que ces danses portent d'ordinaire. Ils sont écrits
/// ici en toutes lettres pour qu'on puisse les discuter : ce sont des choix,
/// pas des constantes de la nature.
///
/// Dart pur, sans Flutter.
library;

/// Vitesse réglable à la main, quand aucune rythmique n'est choisie.
const double kVitesseMin = 0.5;
const double kVitesseMax = 5.0;
const double kVitessePas = 0.5;

/// Nombre de crans du curseur, bornes comprises.
int get kVitesseCrans =>
    ((kVitesseMax - kVitesseMin) / kVitessePas).round() + 1;

/// Une danse, sa mesure et son tempo.
enum Rythmique {
  /// Vive, à trois temps, tournée vers le premier.
  valse('Valse', '3/4', 3, 170),

  /// Modéré, le trois temps de cour.
  menuet('Menuet', '3/4', 3, 120),

  /// Lente et grave, à la blanche.
  sarabande('Sarabande', '3/2', 3, 60),

  /// Lente, sur une basse obstinée.
  passacaille('Passacaille', '3/4', 3, 72),

  /// Deux temps, d'un pas régulier.
  marche('Marche', '2/4', 2, 110),

  /// Quatre temps, allant.
  gavotte('Gavotte', '4/4', 4, 100),

  /// Mesure composée : le temps est la noire pointée, deux par mesure.
  gigue('Gigue', '6/8', 2, 120),

  /// La même mesure, balancée et lente.
  sicilienne('Sicilienne', '6/8', 2, 52);

  const Rythmique(this.nom, this.mesure, this.tempsParMesure, this.tempsParMin);

  final String nom;

  /// Telle qu'elle s'écrit : `3/4`, `6/8`…
  final String mesure;

  /// Combien de temps compte une mesure. Deux en 6/8 : le temps y est la
  /// noire pointée.
  final int tempsParMesure;

  /// Temps par minute — le tempo.
  final int tempsParMin;

  /// Ce qui s'affiche sur la touche : « Valse 3/4 ».
  String get etiquette => '$nom $mesure';

  /// Durée d'un temps, donc d'un coup.
  Duration get parCoup =>
      Duration(microseconds: (60000000 / tempsParMin).round());

  /// La même, en secondes, pour l'afficher.
  double get secondesParCoup => 60 / tempsParMin;

  static Rythmique? fromWire(String? s) {
    for (final r in Rythmique.values) {
      if (r.name == s) return r;
    }
    return null;
  }
}

/// Le réglage de la lecture automatique : une rythmique, ou une durée.
///
/// Les deux ne coexistent pas. Choisir une rythmique fige la vitesse ; la
/// régler à la main abandonne la rythmique.
final class TempoLecture {
  const TempoLecture.libre(this.secondes) : rythmique = null;
  const TempoLecture.danse(Rythmique this.rythmique) : secondes = 0;

  /// Secondes entre deux coups, quand on règle à la main.
  final double secondes;

  /// La danse choisie, ou `null` quand on règle à la main.
  final Rythmique? rythmique;

  bool get estLibre => rythmique == null;

  /// Durée entre deux coups, d'où qu'elle vienne.
  Duration get parCoup =>
      rythmique?.parCoup ??
      Duration(microseconds: (secondes * 1000000).round());

  /// La durée telle qu'on l'écrit sous le curseur.
  String get etiquette => rythmique == null
      ? '${secondes.toStringAsFixed(1)} s'
      : '${rythmique!.etiquette} · '
            '${rythmique!.secondesParCoup.toStringAsFixed(2)} s';

  /// Le réglage par défaut : une seconde par coup, à la main.
  static const TempoLecture defaut = TempoLecture.libre(1.0);
}
