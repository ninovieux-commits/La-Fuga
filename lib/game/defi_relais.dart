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

  /// Le menu annonce qu'il peut défier. `null` quand il se débranche.
  static void pose(Future<void> Function(String pseudo) lancer) =>
      _lancer = lancer;

  /// Y a-t-il quelqu'un pour mener le défi ? Sinon la touche « Défier »
  /// paraît hachurée : mieux vaut une touche visiblement hors service qu'une
  /// promesse sans suite.
  static bool get pret => _lancer != null;

  /// Défie, s'il y a quelqu'un pour le faire.
  static Future<void> defier(String pseudo) async => _lancer?.call(pseudo);

  /// Le menu s'en va — et les tests repartent de zéro.
  static void oublie() => _lancer = null;
}
