/// Qui sait lancer un défi, et d'où on le demande.
///
/// Nino : « câble le défi depuis la correspondance et la boîte de dialogue ».
/// La fiche d'un joueur s'ouvre maintenant partout, et sa touche « Défier »
/// doit marcher d'où qu'elle vienne.
///
/// Or UN SEUL écran sait mener un défi à son terme : le menu. C'est lui qui
/// est branché au serveur en permanence — « sans cela on ne pourrait pas
/// RECEVOIR un défi sans avoir rien fait » — lui qui tient le dialogue
/// d'attente, et lui qui ouvre l'écran de partie quand l'adversaire accepte.
/// Rebrancher tout cela dans chaque écran, ce serait deux salons à l'écoute du
/// même événement, donc deux parties ouvertes pour un seul défi accepté.
///
/// Le menu pose donc ici sa façon de défier, tant qu'il est à l'écoute, et les
/// autres écrans s'en servent. Son dialogue d'attente paraît PAR-DESSUS
/// l'écran courant — `showDialog` passe par le navigateur racine — et la
/// partie s'ouvre au-dessus de lui : on repart de là où l'on était.
library;

class DefiRelais {
  DefiRelais._();

  static Future<void> Function(String pseudo)? _lancer;

  /// Une partie EN DIRECT est-elle en cours ?
  ///
  /// Nino : « de partout tant qu'une partie en direct n'est pas en cours ».
  /// C'est donc un ÉTAT, et non une liste d'écrans : l'écran de partie en
  /// direct le pose en s'ouvrant et le retire en se fermant, et la touche
  /// « Défier » s'éteint d'elle-même partout — dans la fiche ouverte sur le
  /// bandeau, mais aussi dans le chat ouvert depuis cette partie. Personne
  /// n'a plus à y penser.
  static bool enPartieDirecte = false;

  /// Le menu annonce qu'il peut défier. `null` quand il se débranche.
  static void pose(Future<void> Function(String pseudo) lancer) =>
      _lancer = lancer;

  /// Peut-on défier, ici et maintenant ?
  ///
  /// Il faut quelqu'un pour mener le défi — le menu, à l'écoute — et aucune
  /// partie en direct en cours. Sinon la touche pâlit : mieux vaut une
  /// touche visiblement hors service qu'une promesse sans suite.
  static bool get pret => _lancer != null && !enPartieDirecte;

  /// Défie, s'il y a quelqu'un pour le faire.
  static Future<void> defier(String pseudo) async => _lancer?.call(pseudo);

  /// Le menu s'en va — et les tests repartent de zéro.
  static void oublie() {
    _lancer = null;
    enPartieDirecte = false;
  }
}
