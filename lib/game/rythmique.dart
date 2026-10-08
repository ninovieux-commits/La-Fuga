/// Les rythmiques de la lecture automatique.
///
/// Une danse ne se reconnaît pas à des silences entre ses mesures : elle se
/// reconnaît à la LONGUEUR INÉGALE de ses notes. Une valse ne joue pas trois
/// notes puis attend — trois notes et une attente, cela fait quatre temps,
/// c'est-à-dire une mesure à 4/4 avec un silence au bout. La mesure de valse
/// fait trois temps, et la suivante enchaîne sans aucun trou.
///
/// Ce qui fait entendre une valse, c'est son premier temps LONG : une note
/// tenue deux temps, puis une note sur le troisième. Long, court, long,
/// court — et la mesure se referme toute seule sur le retour du long.
///
/// ## Le motif
///
/// Chaque danse porte son [Rythmique.motif] : une case par **pulsation**,
/// `true` quand une note y est frappée, `false` quand la précédente se
/// prolonge. La valse donne `[true, false, true]` — une note tenue deux
/// pulsations, puis une.
///
/// Un `false` n'est donc PAS un silence : c'est la note d'avant qui dure. Avec
/// une note par coup, cela revient au même pour l'oreille — l'écart entre deux
/// coups est la durée de la note.
///
/// De là viennent les [Rythmique.ecarts] : la distance, en pulsations, d'un
/// coup au suivant. C'est leur inégalité qui fait la danse.
///
/// ## La pulsation, le temps, et la mesure
///
/// Le **temps** est l'unité du tempo : la noire en 3/4, la blanche en 3/2, la
/// noire POINTÉE en 6/8 — il y en a deux par mesure, pas six.
///
/// La **pulsation** est la plus petite valeur que la danse écrit. Elle vaut le
/// temps dans une mesure simple, et le tiers du temps en 6/8, où le temps se
/// divise en trois croches. C'est ce qui permet à la gigue de galoper :
/// `1 · 3 | 4 · 6` sur ses six croches, soit long-court long-court, sa marque
/// de fabrique. Sans cette division, une gigue ne serait qu'un pouls à deux.
///
/// Les tempos et les motifs sont écrits ici en toutes lettres pour qu'on
/// puisse les discuter : ce sont des choix, pas des constantes de la nature.
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

/// Une danse : sa mesure, son tempo, et le dessin de ses notes.
enum Rythmique {
  /// Le premier temps long, le troisième court. ONE—— deux-trois.
  valse('Valse', '3/4', 170, 1, [true, false, true]),

  /// Le trois temps de cour : trois notes égales, sans boiterie.
  menuet('Menuet', '3/4', 120, 1, [true, true, true]),

  /// Elle appuie son DEUXIÈME temps, qu'elle allonge : court, puis long.
  /// C'est l'inverse de la valse, et c'est ce qui la rend reconnaissable.
  sarabande('Sarabande', '3/2', 60, 1, [true, true, false]),

  /// Lente et obstinée, le premier temps long comme la valse mais au pas d'un
  /// autre siècle.
  passacaille('Passacaille', '3/4', 72, 1, [true, false, true]),

  /// Le pas, gauche-droite : deux notes égales.
  marche('Marche', '2/4', 110, 1, [true, true]),

  /// Quatre temps carrés, égaux.
  gavotte('Gavotte', '4/4', 100, 1, [true, true, true, true]),

  /// Mesure composée : deux temps de trois croches. Elle galope — une note de
  /// deux croches, une d'une, et ainsi de suite.
  gigue('Gigue', '6/8', 80, 3, [true, false, true, true, false, true]),

  /// Le même galop, balancé et lent.
  sicilienne('Sicilienne', '6/8', 52, 3, [
    true,
    false,
    true,
    true,
    false,
    true,
  ]);

  const Rythmique(
    this.nom,
    this.mesure,
    this.tempsParMin,
    this.pulsationsParTemps,
    this.motif,
  );

  final String nom;

  /// Telle qu'elle s'écrit : `3/4`, `6/8`…
  final String mesure;

  /// Temps par minute — le tempo, sur le TEMPS (noire pointée en 6/8).
  final int tempsParMin;

  /// Combien de pulsations compte un temps. 1 partout, 3 en 6/8.
  final int pulsationsParTemps;

  /// Une case par pulsation : `true` = une note y est frappée, `false` = la
  /// précédente se prolonge.
  final List<bool> motif;

  /// Combien de pulsations compte une mesure.
  int get pulsationsParMesure => motif.length;

  /// Combien de temps compte une mesure. Deux en 6/8, trois en 3/4.
  int get tempsParMesure => motif.length ~/ pulsationsParTemps;

  /// Combien de notes se frappent dans une mesure.
  int get coupsParMesure => motif.where((frappe) => frappe).length;

  /// Ce qui s'affiche sur la touche : « Valse 3/4 ».
  String get etiquette => '$nom $mesure';

  /// Durée d'un temps.
  Duration get parTemps =>
      Duration(microseconds: (60000000 / tempsParMin).round());

  /// Durée d'une pulsation — la plus petite valeur que la danse écrit.
  Duration get parPulsation => Duration(
    microseconds: (60000000 / (tempsParMin * pulsationsParTemps)).round(),
  );

  /// Durée d'une mesure entière.
  Duration get parMesure => parPulsation * pulsationsParMesure;

  /// La distance, en pulsations, d'une note frappée à la suivante.
  ///
  /// Le motif boucle : le dernier écart ramène à la première note de la mesure
  /// suivante. `[true, false, true]` donne donc `[2, 1]` — long, court,
  /// indéfiniment. C'est cette inégalité qui fait la danse.
  List<int> get ecarts {
    final frappes = <int>[
      for (var i = 0; i < motif.length; i++)
        if (motif[i]) i,
    ];
    return [
      for (var k = 0; k < frappes.length; k++)
        k + 1 < frappes.length
            ? frappes[k + 1] - frappes[k]
            : motif.length - frappes[k] + frappes[0],
    ];
  }

  /// Le motif écrit : « 1 · 3 » pour la valse, « 1 2 · » pour la sarabande.
  String get motifEcrit => [
    for (var i = 0; i < motif.length; i++) motif[i] ? '${i + 1}' : '·',
  ].join(' ');

  /// Ce qu'on lit sous le nom, dans le choix des danses.
  String get detail => '$tempsParMin/min  ·  $motifEcrit';

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
  /// motif, qui boucle avec la mesure : d'où les notes longues et les courtes.
  Duration ecartAvant(int n) {
    final r = rythmique;
    if (r == null) {
      return Duration(microseconds: (secondes * 1000000).round());
    }
    final e = r.ecarts;
    return r.parPulsation * e[n % e.length];
  }

  /// La durée telle qu'on l'écrit sous le curseur.
  String get etiquette => rythmique == null
      ? '${secondes.toStringAsFixed(1)} s'
      : rythmique!.etiquette;

  /// Le réglage par défaut : une seconde par coup, à la main.
  static const TempoLecture defaut = TempoLecture.libre(1.0);
}
