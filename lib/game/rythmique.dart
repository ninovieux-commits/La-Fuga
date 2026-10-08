/// Les rythmiques de la lecture automatique.
///
/// Une danse ne se reconnaît pas à des silences entre ses mesures : elle se
/// reconnaît à ses notes INÉGALES, en durée comme en force. Une valse ne joue
/// pas trois notes puis attend — trois notes et une attente, cela fait quatre
/// temps, c'est-à-dire une mesure à 4/4 avec un silence au bout. La mesure de
/// valse fait trois temps, et la suivante enchaîne sans aucun trou.
///
/// ## Une note : une durée et une force
///
/// Chaque danse est une suite de [NoteDansee] : combien de pulsations la note
/// occupe, et à quel volume elle sonne. La valse donne trois notes, la
/// première **tenue** (un temps et quart au lieu d'un) et **appuyée**, les
/// deux autres plus brèves et plus douces. C'est le ONE—— deux-trois.
///
/// La somme des durées fait la mesure : rien ne traîne au bout, la suivante
/// enchaîne.
///
/// ## L'accent se fait en BAISSANT les autres
///
/// Le mélangeur plafonne le volume d'une note à 1 (`pcm.dart`) : monter
/// au-dessus n'aurait aucun effet, et saturerait si on levait le plafond. Le
/// temps fort garde donc sa pleine voix et ce sont les temps faibles qu'on
/// retient. À l'oreille c'est le même accent, sans un bruit de trop.
///
/// ## La pulsation, le temps, et la mesure
///
/// Le **temps** est l'unité du tempo : la noire en 3/4, la blanche en 3/2, la
/// noire POINTÉE en 6/8 — il y en a deux par mesure, pas six.
///
/// La **pulsation** est la plus petite valeur que la danse écrit : la double
/// croche pour la valse, dont le premier temps vaut cinq pulsations sur douze ;
/// la croche pour la gigue, qui galope en deux-plus-une. Sans cette division,
/// une gigue ne serait qu'un pouls à deux et une valse qu'un métronome.
///
/// Les tempos, les durées et les forces sont écrits ici en toutes lettres pour
/// qu'on puisse les discuter : ce sont des choix, pas des constantes de la
/// nature.
///
/// Dart pur, sans Flutter.
library;

/// Une note d'une danse : ce qu'elle dure, et ce qu'elle pèse.
typedef NoteDansee = ({
  /// Durée en pulsations — c'est aussi l'écart jusqu'à la note suivante.
  int duree,

  /// Volume, de 0 à 1. Le temps fort vaut 1 et les faibles moins : voir
  /// « L'accent se fait en BAISSANT les autres ».
  double force,
});

/// Vitesse réglable à la main, quand aucune rythmique n'est choisie.
const double kVitesseMin = 0.5;
const double kVitesseMax = 5.0;
const double kVitessePas = 0.5;

/// Nombre de crans du curseur, bornes comprises.
int get kVitesseCrans =>
    ((kVitesseMax - kVitesseMin) / kVitessePas).round() + 1;

/// Une danse : sa mesure, son tempo, et le dessin de ses notes.
enum Rythmique {
  /// Trois notes, la première TENUE et appuyée : un temps et quart, puis trois
  /// quarts, puis un. C'est le ONE—— deux-trois, et la mesure se referme juste.
  valse('Valse', '3/4', 170, 4, [
    (duree: 5, force: 1.0),
    (duree: 3, force: 0.70),
    (duree: 4, force: 0.70),
  ]),

  /// Le trois temps de cour : trois notes égales, le premier temps appuyé.
  menuet('Menuet', '3/4', 120, 1, [
    (duree: 1, force: 1.0),
    (duree: 1, force: 0.75),
    (duree: 1, force: 0.75),
  ]),

  /// Elle appuie et ALLONGE son deuxième temps : l'inverse de la valse, et sa
  /// marque de fabrique.
  sarabande('Sarabande', '3/2', 60, 1, [
    (duree: 1, force: 0.80),
    (duree: 2, force: 1.0),
  ]),

  /// Lente et obstinée : premier temps long et pesé, comme une valse d'un
  /// autre siècle.
  passacaille('Passacaille', '3/4', 72, 1, [
    (duree: 2, force: 1.0),
    (duree: 1, force: 0.75),
  ]),

  /// Le pas, gauche-droite.
  marche('Marche', '2/4', 110, 1, [
    (duree: 1, force: 1.0),
    (duree: 1, force: 0.80),
  ]),

  /// Quatre temps carrés : le premier fort, le troisième un peu moins.
  gavotte('Gavotte', '4/4', 100, 1, [
    (duree: 1, force: 1.0),
    (duree: 1, force: 0.70),
    (duree: 1, force: 0.85),
    (duree: 1, force: 0.70),
  ]),

  /// Mesure composée : deux temps de trois croches. Elle galope — deux
  /// croches, une croche, et le temps fort devant.
  gigue('Gigue', '6/8', 80, 3, [
    (duree: 2, force: 1.0),
    (duree: 1, force: 0.70),
    (duree: 2, force: 0.90),
    (duree: 1, force: 0.70),
  ]),

  /// Le même galop, balancé et lent.
  sicilienne('Sicilienne', '6/8', 52, 3, [
    (duree: 2, force: 1.0),
    (duree: 1, force: 0.70),
    (duree: 2, force: 0.90),
    (duree: 1, force: 0.70),
  ]);

  const Rythmique(
    this.nom,
    this.mesure,
    this.tempsParMin,
    this.pulsationsParTemps,
    this.notes,
  );

  final String nom;

  /// Telle qu'elle s'écrit : `3/4`, `6/8`…
  final String mesure;

  /// Temps par minute — le tempo, sur le TEMPS (noire pointée en 6/8).
  final int tempsParMin;

  /// Combien de pulsations compte un temps. 1 quand la danse n'écrit que des
  /// temps entiers, 3 en 6/8, 4 pour la valse et ses quarts de temps.
  final int pulsationsParTemps;

  /// Les notes d'une mesure, dans l'ordre.
  final List<NoteDansee> notes;

  /// Combien de pulsations compte une mesure — la somme des durées.
  int get pulsationsParMesure => notes.fold(0, (somme, n) => somme + n.duree);

  /// Combien de temps compte une mesure. Deux en 6/8, trois en 3/4.
  int get tempsParMesure => pulsationsParMesure ~/ pulsationsParTemps;

  /// Combien de notes se jouent dans une mesure.
  int get coupsParMesure => notes.length;

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

  /// La distance, en pulsations, d'une note à la suivante.
  ///
  /// C'est la durée de chaque note : elles s'enchaînent sans trou, et la
  /// dernière ramène à la première de la mesure suivante.
  List<int> get ecarts => [for (final n in notes) n.duree];

  /// Le volume de chaque note, dans l'ordre.
  List<double> get forces => [for (final n in notes) n.force];

  /// Le dessin des notes, lisible par un musicien : la durée de chacune en
  /// temps, précédée de `>` quand elle est accentuée.
  ///
  /// La valse donne « >1,25  0,75  1 ».
  String get motifEcrit => [
    for (final n in notes)
      '${n.force >= 1 ? '>' : ''}'
          '${_enTemps(n.duree / pulsationsParTemps)}',
  ].join('  ');

  static String _enTemps(double v) {
    final s = v.toStringAsFixed(2);
    return s
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

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

  /// Le volume du coup numéro [n] — l'accent de la danse.
  ///
  /// Pleine voix quand on règle à la main : hors d'une danse, aucun coup n'est
  /// plus fort qu'un autre.
  double forceDe(int n) {
    final r = rythmique;
    if (r == null) return 1;
    final f = r.forces;
    return f[n % f.length];
  }

  /// La durée telle qu'on l'écrit sous le curseur.
  String get etiquette => rythmique == null
      ? '${secondes.toStringAsFixed(1)} s'
      : rythmique!.etiquette;

  /// Le réglage par défaut : une seconde par coup, à la main.
  static const TempoLecture defaut = TempoLecture.libre(1.0);
}
