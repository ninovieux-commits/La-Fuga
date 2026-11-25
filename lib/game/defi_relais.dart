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

  /// Et celle de défier PAR CORRESPONDANCE, posée par le même écran.
  ///
  /// Nino : « tous les boutons défier doivent lancer un popup avec [direct]
  /// et [correspondance], ce qui fait qu'on n'est plus obligés de passer par
  /// les plateaux vides pour lancer une corresp. » Une partie par
  /// correspondance ne se joue pas dans l'instant : il n'y a ni défi à
  /// attendre ni salon à tenir, mais il faut le service de correspondance et
  /// la grille à rafraîchir — c'est encore le menu qui les a.
  static Future<void> Function(String pseudo)? _lancerCorresp;

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
  static void pose(
    Future<void> Function(String pseudo) lancer, {
    Future<void> Function(String pseudo)? correspondance,
  }) {
    _lancer = lancer;
    _lancerCorresp = correspondance;
  }

  /// Peut-on défier, ici et maintenant ?
  ///
  /// Il faut quelqu'un pour mener le défi — le menu, à l'écoute — et aucune
  /// partie en direct en cours. Sinon la touche pâlit : mieux vaut une
  /// touche visiblement hors service qu'une promesse sans suite.
  static bool get pret => _lancer != null && !enPartieDirecte;

  /// Peut-on défier PAR CORRESPONDANCE ?
  ///
  /// LA MÊME RÈGLE QUE LE DIRECT, partie en direct comprise. Nino, en voyant
  /// sa fiche pendant une partie : « lors d'une partie en direct, ce popup
  /// doit avoir la touche défier désactivée. » Elle désigne maintenant le
  /// choix entre les deux défis, et non plus le seul direct : c'est donc le
  /// choix entier qui s'éteint, sans quoi la touche se rallumerait en pleine
  /// partie.
  static bool get pretCorresp => _lancerCorresp != null && !enPartieDirecte;

  /// Y a-t-il seulement une façon de défier ? C'est ce que regarde une touche
  /// « Défier », qui n'est plus la promesse d'une partie en direct mais d'un
  /// choix entre les deux.
  static bool get disponible => pret || pretCorresp;

  /// Défie, s'il y a quelqu'un pour le faire.
  static Future<void> defier(String pseudo) async => _lancer?.call(pseudo);

  /// Défie par correspondance, s'il y a quelqu'un pour le faire.
  static Future<void> defierParCorrespondance(String pseudo) async =>
      _lancerCorresp?.call(pseudo);

  /// Le menu s'en va — et les tests repartent de zéro.
  static void oublie() {
    _lancer = null;
    _lancerCorresp = null;
    enPartieDirecte = false;
  }
}
