/// CE QUE LE JOUEUR A SOUS LES YEUX, pour que la notification sache se taire.
///
/// Une notification ne s'affichait pas du tout tant que l'application était
/// devant le joueur : « il est déjà là ». C'était trop large. Nino, réseau
/// coupé puis rallumé pendant qu'il regardait l'appli : « je te confirme que
/// si je désactive internet sur mon téléphone et qu'on me répond dans une
/// partie, quand mon téléphone se reconnecte à internet je ne reçois pas la
/// notif. » La push arrivait bien — mesuré, elle tombe parfaitement
/// application fermée — et l'application la jetait.
///
/// Elle ne jette plus que ce qui annonce L'ÉCRAN OÙ L'ON EST : le coup d'une
/// partie qu'on regarde, le message d'une conversation qu'on lit. Tout le
/// reste s'affiche, application ouverte ou non.
///
/// Deux champs statiques, et c'est assez : on ne regarde qu'un écran à la
/// fois. Chaque écran pose le sien en arrivant et l'enlève en partant — en
/// vérifiant que c'est bien le sien, car le suivant peut s'être posé avant
/// que le précédent ne se range.
library;

class EcranCourant {
  const EcranCourant._();

  /// L'identifiant de la partie par correspondance ouverte, ou nul.
  static String? partieCorr;

  /// Le pseudo de l'interlocuteur dont la conversation est ouverte, ou nul.
  static String? conversation;

  static void ouvrePartieCorr(String id) => partieCorr = id;

  static void fermePartieCorr(String id) {
    if (partieCorr == id) partieCorr = null;
  }

  static void ouvreConversation(String pseudo) => conversation = pseudo;

  static void fermeConversation(String pseudo) {
    if (conversation == pseudo) conversation = null;
  }

  /// Pour les tests : on repart d'un écran vide.
  static void oublie() {
    partieCorr = null;
    conversation = null;
  }
}
