/// Le filet derrière le temps réel.
///
/// Trois écrans — le menu et ses aperçus, une partie par correspondance, une
/// conversation — redemandaient tout au serveur toutes les quatre secondes.
/// C'était la seule façon d'apprendre quoi que ce soit : la correspondance
/// n'émettait aucun événement, et la socket, elle, ne s'ouvrait jamais. Quinze
/// requêtes par minute et par écran ouvert, pour un coup qui mettait quand
/// même jusqu'à quatre secondes à apparaître.
///
/// Le direct fait maintenant le travail, à vingt millisecondes. Mais une
/// socket tombe — écran éteint, Wi-Fi vers 4G, serveur redémarré — et parfois
/// sans le dire. On garde donc la relecture, en l'espaçant tant que le direct
/// répond, et en revenant au rythme rapide dès qu'il se tait.
///
/// Rien de temporel ici n'est caché : [fautRelire] prend l'heure en argument,
/// ce qui se teste sans attendre.
library;

class FiletRelecture {
  FiletRelecture({this.espace = const Duration(seconds: 30)});

  /// L'intervalle entre deux relectures quand le direct fonctionne.
  final Duration espace;

  DateTime? _derniere;

  /// Faut-il relire maintenant ?
  ///
  /// Sans direct, à chaque battement : c'est le seul moyen de savoir. Avec,
  /// seulement de loin en loin — le direct a déjà prévenu de tout ce qui a
  /// bougé, et cette relecture ne fait que rattraper ce qu'il aurait manqué.
  bool fautRelire({required bool directVivant, DateTime? maintenant}) {
    if (!directVivant) return true;
    final precedente = _derniere;
    if (precedente == null) return true;
    final t = maintenant ?? DateTime.now();
    return t.difference(precedente) >= espace;
  }

  /// On vient de relire — par le battement ou parce que le direct l'a
  /// demandé. Dans les deux cas l'état est frais, et le filet peut attendre.
  void note([DateTime? maintenant]) => _derniere = maintenant ?? DateTime.now();

  /// Le direct s'est tu ou la session a changé : on repart au rythme rapide.
  void oublie() => _derniere = null;
}
