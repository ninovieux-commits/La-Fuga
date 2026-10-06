/// Pré-coups : les réponses qu'on prépare pendant que l'adversaire réfléchit.
///
/// En correspondance, l'attente se compte en heures. Quand on sait déjà quoi
/// répondre à ce que l'adversaire va jouer, on peut le préparer : s'il joue
/// le coup prévu, notre réponse part toute seule, et c'est aussitôt de
/// nouveau à lui.
///
/// Une VARIANTE est une suite de demi-coups qui part de la position où
/// l'adversaire a le trait :
///
///     indice 0 : son coup      indice 1 : le nôtre
///     indice 2 : son coup      indice 3 : le nôtre      …
///
/// Les indices PAIRS sont donc à lui, les IMPAIRS à nous. Une variante
/// s'arrête toujours sur un de NOS coups : s'arrêter sur le sien ne
/// préparerait rien.
///
/// On peut en préparer six, de six demi-coups au plus, et **aucune ne doit
/// contredire une autre** : deux variantes qui partagent le même début ne
/// peuvent pas y répondre de deux façons différentes. C'est tout : le reste
/// de ce fichier ne fait que le vérifier.
///
/// Dart pur, sans Flutter : la règle se vérifie sans écran.
library;

/// Au plus six variantes.
const int kPremoveMaxVariantes = 6;

/// Au plus six demi-coups par variante.
const int kPremoveMaxCoups = 6;

/// Vrai si l'indice [i] d'une variante est un de NOS coups.
bool premoveEstANous(int i) => i.isOdd;

/// Une variante préparée.
final class PremoveVariante {
  const PremoveVariante(this.coups, {this.methode, this.gagnant});

  /// Les demi-coups, en commençant par celui de l'ADVERSAIRE.
  final List<String> coups;

  /// Si notre DERNIER coup termine la partie : par quoi (`mat`, `fugue`,
  /// `papatte`, `nulle`…) et quel camp gagne (`Blanc` / `Noir`).
  ///
  /// Le serveur ne connaît pas les règles : sans cela, il enchaînerait une
  /// partie déjà gagnée. C'est nous qui avons calculé la position, c'est donc
  /// à nous de dire ce qu'elle vaut.
  final String? methode;
  final String? gagnant;

  /// Notre dernier coup, celui qui sera joué si l'adversaire suit la variante
  /// jusqu'au bout.
  String get dernier => coups.last;

  /// Vrai si la variante est bien formée : des coups non vides, en nombre
  /// pair, dans la limite autorisée.
  bool get estValide =>
      coups.isNotEmpty &&
      coups.length.isEven &&
      coups.length <= kPremoveMaxCoups &&
      coups.every((c) => c.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
    'coups': coups,
    if (methode != null) 'methode': methode,
    if (gagnant != null) 'gagnant': gagnant,
  };

  static PremoveVariante fromJson(Map<String, dynamic> j) => PremoveVariante(
    [
      // Ce qui vient du réseau n'est jamais sûr : un champ d'un autre type ne
      // doit pas faire tomber l'application, juste donner une variante vide,
      // que `estValide` refusera.
      for (final c in _liste(j['coups'])) c.toString().trim(),
    ],
    methode: _texteOuNull(j['methode']),
    gagnant: _texteOuNull(j['gagnant']),
  );

  @override
  String toString() => coups.join(' ');
}

/// Ce qui n'est pas une liste n'en est pas une : on n'y lit rien.
List<Object?> _liste(Object? v) => v is List ? v : const [];

String? _texteOuNull(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Pourquoi une variante a été refusée.
enum PremoveRefus {
  /// Six variantes, c'est le maximum.
  tropDeVariantes,

  /// Mal formée : vide, de longueur impaire, ou trop longue.
  malFormee,

  /// Exactement la même qu'une variante déjà préparée.
  doublon,

  /// Elle répond autrement qu'une variante existante à la même suite de
  /// coups. C'est la règle de Nino : rien ne doit se contredire.
  contradiction,
}

/// La réponse à jouer, et ce qu'elle vaut.
typedef PremoveReponse = ({String coup, String? methode, String? gagnant});

/// Ce qu'on prépare pour une partie : les variantes, et la position d'où
/// elles partent.
final class PremovePlan {
  const PremovePlan({required this.base, this.variantes = const []});

  /// Nombre de demi-coups déjà joués quand le plan a été composé.
  ///
  /// C'est l'ancre du plan : les variantes décrivent ce qui se passe APRÈS
  /// ces coups-là. Si la partie en compte d'autres, le plan ne parle plus de
  /// la position où il est appliqué, et il ne vaut plus rien.
  final int base;

  final List<PremoveVariante> variantes;

  bool get estVide => variantes.isEmpty;

  /// Reste-t-il de la place pour une variante de plus ?
  bool get peutEnAjouter => variantes.length < kPremoveMaxVariantes;

  /// Le plan sans aucune variante.
  PremovePlan videDe() => PremovePlan(base: base);

  /// Le plan privé de la variante [index].
  PremovePlan sans(int index) => PremovePlan(
    base: base,
    variantes: [
      for (var i = 0; i < variantes.length; i++)
        if (i != index) variantes[i],
    ],
  );

  /// Pourquoi [v] ne peut pas rejoindre le plan — ou `null` si elle peut.
  ///
  /// La contradiction se lit à l'endroit où deux variantes se SÉPARENT :
  ///
  ///  * elles se séparent sur un coup de l'ADVERSAIRE : ce sont deux lignes
  ///    différentes, chacune sa réponse. Rien à redire.
  ///  * elles se séparent sur un des NÔTRES : même début, même coup de
  ///    l'adversaire, et deux réponses. C'est la contradiction.
  ///  * elles ne se séparent pas : l'une commence l'autre. La plus courte
  ///    n'ajoute rien, c'est un doublon.
  PremoveRefus? refusDe(PremoveVariante v) {
    if (!v.estValide) return PremoveRefus.malFormee;
    if (!peutEnAjouter) return PremoveRefus.tropDeVariantes;
    for (final autre in variantes) {
      final ecart = _premierEcart(v.coups, autre.coups);
      if (ecart == null) return PremoveRefus.doublon;
      if (premoveEstANous(ecart)) return PremoveRefus.contradiction;
    }
    return null;
  }

  /// Le plan avec [v] en plus, ou `null` si elle est refusée.
  PremovePlan? avec(PremoveVariante v) => refusDe(v) != null
      ? null
      : PremovePlan(base: base, variantes: [...variantes, v]);

  /// Notre réponse quand la partie est arrivée jusqu'à [ligne].
  ///
  /// [ligne] est la suite des demi-coups joués DEPUIS la composition du plan ;
  /// le dernier est celui de l'adversaire, c'est pourquoi sa longueur est
  /// impaire. Rien ne répond à une ligne qu'aucune variante ne prolonge.
  PremoveReponse? reponsePour(List<String> ligne) {
    if (ligne.isEmpty || ligne.length.isEven) return null;
    for (final v in variantes) {
      if (v.coups.length <= ligne.length) continue;
      if (!_commencePar(v.coups, ligne)) continue;
      final i = ligne.length;
      final dernier = i == v.coups.length - 1;
      return (
        coup: v.coups[i],
        // La méthode ne vaut que pour le DERNIER coup de la variante : c'est
        // lui, et lui seul, dont on a mesuré qu'il terminait la partie.
        methode: dernier ? v.methode : null,
        gagnant: dernier ? v.gagnant : null,
      );
    }
    return null;
  }

  /// Vrai si [ligne] peut encore mener à une de nos réponses, maintenant ou
  /// plus tard. Faux : l'adversaire est sorti de tout ce qu'on avait prévu,
  /// et le plan est mort.
  bool suitEncore(List<String> ligne) {
    if (ligne.isEmpty) return variantes.isNotEmpty;
    for (final v in variantes) {
      if (v.coups.length <= ligne.length) continue;
      if (_commencePar(v.coups, ligne)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'base': base,
    'variantes': [for (final v in variantes) v.toJson()],
  };

  static PremovePlan fromJson(Map<String, dynamic> j) => PremovePlan(
    base: (j['base'] is num) ? (j['base'] as num).toInt() : 0,
    variantes: [
      for (final v in _liste(j['variantes']))
        if (v is Map) PremoveVariante.fromJson(Map<String, dynamic>.from(v)),
    ],
  );
}

/// Indice du premier demi-coup où [a] et [b] diffèrent, ou `null` si l'une
/// commence l'autre.
int? _premierEcart(List<String> a, List<String> b) {
  final commun = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < commun; i++) {
    if (a[i] != b[i]) return i;
  }
  return null;
}

bool _commencePar(List<String> coups, List<String> debut) {
  if (coups.length < debut.length) return false;
  for (var i = 0; i < debut.length; i++) {
    if (coups[i] != debut[i]) return false;
  }
  return true;
}
