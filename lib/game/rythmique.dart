/// Les rythmiques de la lecture automatique.
///
/// Un coup se joue — et donc une note sonne — **sur les temps joués**, pas sur
/// tous les temps. Une danse n'est pas un métronome : une valse à trois temps
/// appuie le premier et laisse les deux autres en silence. Ce sont ces
/// silences qui font entendre la mesure ; sans eux, les huit danses sonneraient
/// toutes pareil, à des vitesses différentes.
///
/// ## Le motif
///
/// Chaque danse porte son [Rythmique.motif] : un temps par case, `true` quand
/// un coup s'y joue, `false` quand c'est une pause. La valse donne
/// `[true, false, false]` — un coup, deux pauses, et le coup suivant tombe
/// trois temps plus loin.
///
/// De là viennent les [Rythmique.ecarts] : la distance, en temps, d'un coup
/// joué au suivant. Elle n'est pas forcément constante. La sarabande appuie son
/// DEUXIÈME temps (`[true, true, false]`), donc ses coups boitent : un temps,
/// puis deux. C'est exactement ce qui la rend reconnaissable.
///
/// ## Le temps, et ce qu'il vaut
///
/// Dans une mesure simple (3/4, 2/4, 4/4, 3/2), le temps est l'unité du
/// dénominateur : la noire en 3/4, la blanche en 3/2. Dans une mesure
/// composée (6/8), le temps est la noire pointée — il y en a **deux** par
/// mesure, pas six. Une gigue à 120 joue donc deux coups par mesure, pas six.
///
/// Les tempos et les motifs sont écrits ici en toutes lettres pour qu'on puisse
/// les discuter : ce sont des choix, pas des constantes de la nature.
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

/// Une danse : sa mesure, son tempo, et les temps qu'elle joue.
enum Rythmique {
  /// Vive, tournée vers le premier temps — les deux autres se taisent.
  valse('Valse', '3/4', 170, [true, false, false]),

  /// Le trois temps de cour, modéré, appuyé sur le premier.
  menuet('Menuet', '3/4', 120, [true, false, false]),

  /// Lente et grave, à la blanche, et elle appuie son DEUXIÈME temps : ses
  /// coups boitent, un temps puis deux.
  sarabande('Sarabande', '3/2', 60, [true, true, false]),

  /// Lente, sur une basse obstinée qui retombe sur le premier temps.
  passacaille('Passacaille', '3/4', 72, [true, false, false]),

  /// Le pas, gauche-droite : les deux temps sont marqués.
  marche('Marche', '2/4', 110, [true, true]),

  /// Quatre temps, marqués un et trois.
  gavotte('Gavotte', '4/4', 100, [true, false, true, false]),

  /// Mesure composée : le temps est la noire pointée, deux par mesure, et les
  /// deux sont joués.
  gigue('Gigue', '6/8', 120, [true, true]),

  /// La même mesure, balancée et lente.
  sicilienne('Sicilienne', '6/8', 52, [true, true]);

  const Rythmique(this.nom, this.mesure, this.tempsParMin, this.motif);

  final String nom;

  /// Telle qu'elle s'écrit : `3/4`, `6/8`…
  final String mesure;

  /// Temps par minute — le tempo.
  final int tempsParMin;

  /// Un temps par case : `true` = un coup s'y joue, `false` = une pause.
  final List<bool> motif;

  /// Combien de temps compte une mesure. Deux en 6/8 : le temps y est la
  /// noire pointée.
  int get tempsParMesure => motif.length;

  /// Combien de coups se jouent dans une mesure.
  int get coupsParMesure => motif.where((joue) => joue).length;

  /// Ce qui s'affiche sur la touche : « Valse 3/4 ».
  String get etiquette => '$nom $mesure';

  /// Durée d'un temps.
  Duration get parTemps =>
      Duration(microseconds: (60000000 / tempsParMin).round());

  /// Durée d'une mesure entière.
  Duration get parMesure => parTemps * tempsParMesure;

  /// La distance, en temps, d'un coup joué au suivant.
  ///
  /// Le motif boucle : le dernier écart ramène au premier temps joué de la
  /// mesure suivante. `[true, true, false]` donne donc `[1, 2]` — un temps,
  /// puis deux, indéfiniment.
  List<int> get ecarts {
    final joues = <int>[
      for (var i = 0; i < motif.length; i++)
        if (motif[i]) i,
    ];
    return [
      for (var k = 0; k < joues.length; k++)
        k + 1 < joues.length
            ? joues[k + 1] - joues[k]
            : motif.length - joues[k] + joues[0],
    ];
  }

  /// Le motif écrit : « 1 · · » pour la valse, « 1 2 · » pour la sarabande.
  String get motifEcrit => [
    for (var i = 0; i < motif.length; i++) motif[i] ? '${i + 1}' : '·',
  ].join(' ');

  /// Ce qu'on lit sous le nom, dans le choix des danses.
  String get detail =>
      '$tempsParMin/min  ·  $motifEcrit  ·  '
      '$coupsParMesure coup${coupsParMesure > 1 ? 's' : ''} par mesure';

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

  /// Le temps d'attente AVANT le coup numéro [n] de la lecture (0 = le
  /// premier).
  ///
  /// À la main, c'est toujours la même durée. Dans une danse, c'est l'écart du
  /// motif, qui boucle avec la mesure : d'où les pauses.
  Duration ecartAvant(int n) {
    final r = rythmique;
    if (r == null) {
      return Duration(microseconds: (secondes * 1000000).round());
    }
    final e = r.ecarts;
    return r.parTemps * e[n % e.length];
  }

  /// La durée telle qu'on l'écrit sous le curseur.
  String get etiquette => rythmique == null
      ? '${secondes.toStringAsFixed(1)} s'
      : rythmique!.etiquette;

  /// Le réglage par défaut : une seconde par coup, à la main.
  static const TempoLecture defaut = TempoLecture.libre(1.0);
}
