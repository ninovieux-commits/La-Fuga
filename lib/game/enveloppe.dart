/// Les ENVELOPPES : une image qui passe, et qui ne reste nulle part.
///
/// Nino : « je voudrais qu'on puisse envoyer des images mais je ne veux pas
/// que ça me coûte cher sur le serveur. » D'où ce sas plutôt qu'un
/// hébergeur : deux enveloppes en attente par correspondant, quarante-huit
/// heures de vie, et l'image s'efface du serveur dès que le destinataire
/// l'ouvre. Celui qui la reçoit reste libre de la garder sur son téléphone —
/// c'est à ça que sert la touche « Télécharger » — mais ni le serveur ni
/// l'application n'en conservent quoi que ce soit.
///
/// Dart pur : la règle se vérifie sans écran ni réseau.
library;

/// Durée de vie d'une enveloppe. Le serveur tient la même.
const Duration kEnveloppeVie = Duration(hours: 48);

/// Combien d'enveloppes non ouvertes on peut laisser chez le même
/// correspondant. Nino : « on ne peut avoir que deux enveloppes en attente
/// par correspondant (4 si on compte les deux correspondants). »
const int kEnveloppesEnAttente = 2;

/// Le plus grand côté d'une image envoyée : 720p, réduit par le téléphone.
///
/// Le serveur ne décode jamais l'image — c'est ce qui rend l'affaire bon
/// marché — donc cette limite-ci est la seule qui décide du poids. Le
/// serveur se contente d'un plafond dur en octets, au cas où.
const int kEnveloppeCote = 1280;

/// Une enveloppe en attente, dans un sens ou dans l'autre.
final class Enveloppe {
  const Enveloppe({
    required this.id,
    required this.deMoi,
    required this.creeA,
    required this.expireA,
    this.taille = 0,
  });

  /// Son identifiant chez le serveur.
  final int id;

  /// Vrai : c'est MOI qui l'ai envoyée. Je peux la vérifier et la reprendre,
  /// pas l'ouvrir pour de bon — ouvrir, c'est le geste du destinataire.
  final bool deMoi;

  /// Secondes depuis l'époque, comme le serveur les compte.
  final int creeA;
  final int expireA;

  /// Poids de l'image, en octets.
  final int taille;

  /// Celle qu'on a reçue s'ouvre ; la sienne, non.
  bool get ouvrable => !deMoi;

  /// Ce qu'il lui reste à vivre, vu de [maintenant].
  Duration restant(DateTime maintenant) {
    final fin = DateTime.fromMillisecondsSinceEpoch(expireA * 1000);
    final reste = fin.difference(maintenant);
    return reste.isNegative ? Duration.zero : reste;
  }

  bool expiree(DateTime maintenant) => restant(maintenant) == Duration.zero;

  static Enveloppe fromJson(Map<String, dynamic> j) => Enveloppe(
    id: _entier(j['id']),
    deMoi: j['de_moi'] == true,
    creeA: _entier(j['cree_a']),
    expireA: _entier(j['expire_a']),
    taille: _entier(j['taille']),
  );

  @override
  String toString() => 'Enveloppe($id, ${deMoi ? "envoyée" : "reçue"})';
}

int _entier(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Le chrono d'une enveloppe, au format que Nino a dicté : « 48h00 -> 47h59 ».
///
/// Les heures d'abord, les minutes ensuite sur deux chiffres, et LA MINUTE
/// ENTAMÉE NE COMPTE PAS : on tronque. Nino : « je ne veux pas que ça
/// arrondisse à la minute. » Une enveloppe qui vient d'être posée affiche
/// donc « 48h00 » pendant une seconde, puis « 47h59 » pendant la minute
/// entière qui suit — c'est le compte à rebours qu'il a décrit, et c'est
/// aussi le temps qu'il RESTE vraiment, jamais une minute de plus.
String chronoEnveloppe(Duration restant) {
  if (restant <= Duration.zero) return '0h00';
  final minutes = restant.inMinutes;
  final heures = minutes ~/ 60;
  final reste = minutes % 60;
  return '${heures}h${reste.toString().padLeft(2, '0')}';
}
