/// La vitesse de la lecture automatique dans l'historique.
///
/// Un seul réglage : le temps entre deux coups, au curseur. Il y a eu ici huit
/// danses — valse, menuet, sarabande… — avec leurs tempos, leurs accents et
/// leurs notes inégales. Essayées sur un vrai téléphone, elles ne tenaient pas
/// à l'oreille : une partie n'est pas une mélodie, et lui imposer une mesure ne
/// la rend pas dansante. Nino : « enlève les rythmiques finalement, laisse
/// juste le curseur de temps. »
///
/// Dart pur, sans Flutter.
library;

/// Temps entre deux coups, en secondes.
const double kVitesseMin = 0.5;
const double kVitesseMax = 5.0;
const double kVitessePas = 0.5;

/// Vitesse de départ : une seconde par coup.
const double kVitesseDefaut = 1.0;

/// Nombre de crans du curseur, bornes comprises.
int get kVitesseCrans =>
    ((kVitesseMax - kVitesseMin) / kVitessePas).round() + 1;

/// La durée entre deux coups, pour un réglage donné.
Duration vitesseEnDuree(double secondes) =>
    Duration(microseconds: (secondes * 1000000).round());
