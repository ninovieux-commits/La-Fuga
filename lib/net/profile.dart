/// Profil d'un joueur, tel que le renvoie `/get_profile` — et la fiche courte
/// de `/search_user`.
///
/// Les noms de champs sont ceux du serveur, qui ne change pas.
library;

/// Une personne dans une liste (abonnés, abonnements, bloqués).
final class Person {
  const Person({required this.pseudo, this.melo = 1500, this.online = false});

  final String pseudo;
  final int melo;
  final bool online;

  static Person fromJson(Map<String, dynamic> j) => Person(
    pseudo: '${j['pseudo'] ?? '?'}',
    melo: _int(j['melo'], 1500),
    online: j['online'] == true,
  );
}

/// Score en tête-à-tête : mes victoires et les siennes.
typedef HeadToHead = ({int mine, int theirs});

/// Profil complet.
final class Profile {
  const Profile({
    required this.pseudo,
    required this.isSelf,
    this.melo = 1500,
    this.meloRandom = 1500,
    this.email = '',
    this.photo = '',
    this.description = '',
    this.followers = const [],
    this.following = const [],
    this.blocked = const [],
    this.direct = (mine: 0, theirs: 0),
    this.correspondence = (mine: 0, theirs: 0),
    this.online = false,
    this.isFavorite = false,
    this.isBlocked = false,
  });

  final String pseudo;

  /// Vrai si c'est mon propre profil : seul le mien est modifiable.
  final bool isSelf;

  final int melo;
  final int meloRandom;
  final String email;
  final String photo;
  final String description;

  /// Ceux qui me suivent, ceux que je suis, ceux que j'ai bloqués.
  final List<Person> followers;
  final List<Person> following;
  final List<Person> blocked;

  /// Scores entre lui et moi, en direct et par correspondance.
  final HeadToHead direct;
  final HeadToHead correspondence;

  final bool online;
  final bool isFavorite;
  final bool isBlocked;

  static Profile fromJson(Map<String, dynamic> j) => Profile(
    pseudo: '${j['pseudo'] ?? '?'}',
    isSelf: j['is_self'] == true,
    melo: _int(j['melo'], 1500),
    meloRandom: _int(j['melo_random'], 1500),
    email: '${j['email'] ?? ''}',
    photo: '${j['photo'] ?? ''}',
    description: '${j['description'] ?? ''}',
    followers: _people(j['followers']),
    following: _people(j['following']),
    blocked: _people(j['blocked']),
    direct: (
      mine: _int(j['h2h_direct_moi'], 0),
      theirs: _int(j['h2h_direct_lui'], 0),
    ),
    correspondence: (
      mine: _int(j['h2h_corr_moi'], 0),
      theirs: _int(j['h2h_corr_lui'], 0),
    ),
    online: j['online'] == true,
    isFavorite: j['is_favorite'] == true,
    isBlocked: j['is_blocked'] == true,
  );
}

/// Préférences de notification — portage du dict `notif` d'`/account_info`.
///
/// `mail` est l'interrupteur général : quand il est éteint, les autres ne
/// s'appliquent plus, exactement comme en Kivy.
final class NotifPrefs {
  const NotifPrefs({
    this.mail = true,
    this.turn = true,
    this.msg = true,
    this.defiCorr = true,
    this.defiDirect = true,
  });

  final bool mail;
  final bool turn;
  final bool msg;
  final bool defiCorr;
  final bool defiDirect;

  static NotifPrefs fromJson(Map<String, dynamic>? j) => NotifPrefs(
    mail: j?['mail'] != false,
    turn: j?['turn'] != false,
    msg: j?['msg'] != false,
    defiCorr: j?['defi_corr'] != false,
    defiDirect: j?['defi_direct'] != false,
  );

  Map<String, bool> toJson() => {
    'mail': mail,
    'turn': turn,
    'msg': msg,
    'defi_corr': defiCorr,
    'defi_direct': defiDirect,
  };

  NotifPrefs copyWith({
    bool? mail,
    bool? turn,
    bool? msg,
    bool? defiCorr,
    bool? defiDirect,
  }) => NotifPrefs(
    mail: mail ?? this.mail,
    turn: turn ?? this.turn,
    msg: msg ?? this.msg,
    defiCorr: defiCorr ?? this.defiCorr,
    defiDirect: defiDirect ?? this.defiDirect,
  );

  /// Bascule une préférence par sa clé serveur.
  NotifPrefs toggled(String key) => switch (key) {
    'mail' => copyWith(mail: !mail),
    'turn' => copyWith(turn: !turn),
    'msg' => copyWith(msg: !msg),
    'defi_corr' => copyWith(defiCorr: !defiCorr),
    'defi_direct' => copyWith(defiDirect: !defiDirect),
    _ => this,
  };

  bool operator [](String key) => switch (key) {
    'mail' => mail,
    'turn' => turn,
    'msg' => msg,
    'defi_corr' => defiCorr,
    'defi_direct' => defiDirect,
    _ => false,
  };
}

int _int(Object? v, int fallback) => switch (v) {
  final int n => n,
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? fallback,
  _ => fallback,
};

List<Person> _people(Object? raw) => [
  if (raw is List)
    for (final p in raw)
      if (p is Map) Person.fromJson(Map<String, dynamic>.from(p)),
];
