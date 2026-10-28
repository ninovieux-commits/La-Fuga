/// Les images du jeu, envoyées dans un message comme des émojis.
///
/// Nino : « je voudrais pouvoir envoyer les images des pièces par messages
/// comme si c'était des emojis (ils sont déjà tous listés dans le choix de
/// l'image de profil). »
///
/// ## Un mot, pas une image
///
/// Rien ne part en pièce jointe : le message reste du texte, et une image y
/// est un JETON — `[fs]`, `[vgn]`. Chaque appareil le redessine avec son
/// propre thème, exactement comme une photo de profil, qui est déjà un mot
/// (`thème|Type|Noir`) et non un fichier.
///
/// ## Tout le catalogue des photos, pas seulement les pièces
///
/// Nino : « là, il manque les logos », puis « la photo de profil de deep grey
/// doit aussi être envoyable dans les messages ». Un jeton désigne donc une
/// PHOTO, entre crochets : `[lf]` le logo de foret, `[pdg]` le portrait de
/// Deep Grey, `[vgn]` le Garde noir de volcan. C'est le vocabulaire de
/// `ProfilePhoto`, abrégé.
///
/// ## Court, et c'est pour les notifications
///
/// Le jeton s'est d'abord écrit en toutes lettres — `[volcan|Garde|Noir]` —
/// pour qu'une ancienne version en face affiche quelque chose de lisible.
/// Mais le serveur recopie le message brut dans le texte de la notification,
/// et une rangée de sept pièces y faisait cent soixante-huit caractères,
/// au-delà des cent vingt qu'il garde : la notification arrivait tronquée et
/// illisible. Nino : « il suffit qu'il y ait un nouvel identifiant pour les
/// images dans l'app. On ne garde que les initiales quoi. » La même rangée en
/// fait maintenant quarante-deux.
///
/// ON LIT ENCORE L'ANCIENNE ÉCRITURE : les messages déjà envoyés dorment sur
/// le serveur dans cette forme-là, et une version pas encore mise à jour en
/// enverra d'autres. On écrit court, on lit les deux.
///
/// Dart pur, sans Flutter.
library;

import '../engine/piece.dart';

/// Le code court d'un thème dans un jeton.
///
/// UNE SEULE LETTRE PARTOUT OÙ ELLE SUFFIT, deux là où deux thèmes se
/// disputent la même. Nino : « mets donc les deux lettres, mais que là où il
/// y en a besoin. »
///
/// Quatre couples se marchaient dessus : dragon/deepgrey, foret/fleur,
/// imperial/insectes, original/ocean. Dans deux d'entre eux, LE CHOIX DE
/// CELUI QUI GARDE LA LETTRE SEULE N'EN EST PAS UN :
///
///   — `ocean` doit prendre `o`, car `oc` suivi d'une pièce se confondrait
///     avec `o` + Chevalier : `[ocn]` serait à la fois « original Chevalier
///     Noir » et « ocean Nurse » ;
///   — `insectes` doit prendre `i`, car `in` se confondrait de même avec
///     `i` + Nurse : `[inn]` serait « imperial Nurse Noir » et « insectes
///     Nurse » à la fois.
///
/// Les deux autres couples étaient libres : dragon garde `d`, comme Nino l'a
/// demandé, et foret garde `f`.
const Map<String, String> kCodeDeTheme = {
  'original': 'or',
  'foret': 'f',
  'ocean': 'o',
  'volcan': 'v',
  'hemo': 'h',
  'spatial': 's',
  'imperial': 'im',
  'royal': 'r',
  'terre': 't',
  'bonbon': 'b',
  'arcenciel': 'a',
  'etoile': 'e',
  'medieval': 'm',
  'fleur': 'fl',
  'insectes': 'i',
  'dragon': 'd',
  'deepgrey': 'de',
};

/// La lettre d'un type de pièce. Les cinq sont distinctes d'elles-mêmes.
const Map<PieceType, String> kCodeDePiece = {
  PieceType.heritier: 'h',
  PieceType.nurse: 'n',
  PieceType.soldat: 's',
  PieceType.garde: 'g',
  PieceType.chevalier: 'c',
};

/// Le code du portrait de Deep Grey.
///
/// `p` comme portrait, et non `dg` : `[dg]` se lirait aussi « dragon Garde ».
const String kCodePortrait = 'pdg';

/// La lettre qui ouvre le code d'un logo. Aucun thème ne commence par elle.
const String kCodeLogo = 'l';

String _themeDuCode(String code) => kCodeDeTheme.entries
    .firstWhere((e) => e.value == code, orElse: () => const MapEntry('', ''))
    .key;

PieceType? _pieceDuCode(String code) {
  for (final e in kCodeDePiece.entries) {
    if (e.value == code) return e.key;
  }
  return null;
}

/// Le jeton d'une photo, quelle qu'elle soit : `[lf]`, `[pdg]`, `[vgn]`.
///
/// LE JETON EST COURT, ET C'EST POUR LES NOTIFICATIONS. Il s'écrivait en
/// toutes lettres — `[volcan|Garde|Noir]`, vingt-quatre caractères — et le
/// serveur recopie le message brut dans le texte de la notification : une
/// rangée de sept pièces en faisait cent soixante-huit, au-delà de ce que le
/// serveur garde. Nino : « il suffit qu'il y ait un nouvel identifiant pour
/// les images dans l'app. On ne garde que les initiales quoi. » La même
/// rangée en fait maintenant quarante-deux.
///
/// Le mot reçu est celui de `ProfilePhoto` : `deepgrey`, `logo|foret`,
/// `volcan|Garde|Noir`.
String jetonDePhoto(String photo) {
  if (photo == 'deepgrey') return '[$kCodePortrait]';
  final bouts = photo.split('|');
  if (bouts.first == 'logo') {
    final code = kCodeDeTheme[bouts.last];
    return code == null ? '[$photo]' : '[$kCodeLogo$code]';
  }
  final theme = kCodeDeTheme[bouts.first];
  final type = kPiecesEnvoyables.where((p) => p.wire == bouts[1]);
  if (theme == null || type.isEmpty) return '[$photo]';
  final noir = bouts.length > 2 && bouts[2] == Camp.noir.wire ? 'n' : '';
  return '[$theme${kCodeDePiece[type.first]}$noir]';
}

/// Les pièces qu'on peut envoyer, dans l'ordre de la galerie des photos.
const List<PieceType> kPiecesEnvoyables = [
  PieceType.heritier,
  PieceType.nurse,
  PieceType.garde,
  PieceType.soldat,
  PieceType.chevalier,
];

/// Le jeton d'une pièce, tel qu'il voyage dans le texte du message.
///
/// Avec son THÈME, quand on en a choisi un. Nino : « ça doit donner accès aux
/// pièces de TOUS les thèmes, pas d'un seul. » Choisir la pièce d'un thème et
/// la voir arriver dans un autre n'aurait pas de sens : le jeton porte donc
/// celui qu'on a pris, et il s'écrit comme une photo de profil —
/// `[foret|Soldat|Noir]`, le même mot que `ProfilePhoto` sait déjà dessiner.
///
/// Sans thème, la forme courte reste lisible : `[Soldat]`, `[Soldat Noir]`.
/// C'est ce qu'écrivaient les messages d'avant, et chaque appareil les dessine
/// alors avec SON thème. Le camp blanc ne s'y écrit pas : c'est le cas
/// courant, et « [Soldat] » se lit mieux que « [Soldat Blanc] » sur un client
/// qui ne sait pas le dessiner.
String jetonPiece(PieceType type, Camp camp, {String? theme}) {
  if (theme == null) {
    return camp == Camp.blanc
        ? '[${type.wire}]'
        : '[${type.wire} ${camp.wire}]';
  }
  final noir = camp == Camp.noir ? '|${camp.wire}' : '';
  // Par la photo, pour qu'il n'y ait qu'un seul endroit où s'écrit un jeton.
  return jetonDePhoto('$theme|${type.wire}$noir');
}

/// Les noms que le motif épelle, pris aux pièces elles-mêmes : renommer une
/// pièce ne peut pas laisser le motif en arrière.
final String _lesTypes = kPiecesEnvoyables
    .map((p) => RegExp.escape(p.wire))
    .join('|');
final String _lesCamps = Camp.values
    .map((c) => RegExp.escape(c.wire))
    .join('|');

/// Les codes de thème, les plus longs d'abord : `or` doit être essayé avant
/// `o`, sans quoi `[orn]` se lirait « ocean ... » et resterait en travers.
final String _lesCodes =
    (kCodeDeTheme.values.toList()..sort((a, b) => b.length.compareTo(a.length)))
        .map(RegExp.escape)
        .join('|');

final String _lesLettres = kCodeDePiece.values.join();

/// Le motif des jetons : un logo, le portrait de Deep Grey, ou une pièce.
///
/// DEUX ÉCRITURES, ET ON LIT LES DEUX. La courte est celle qu'on écrit
/// aujourd'hui ; la longue est celle des messages déjà envoyés, qui dorment
/// sur le serveur, et de ceux qu'enverra une version pas encore mise à jour.
/// Les oublier rendrait illisible tout ce qui a précédé.
///
/// Dans la forme longue, le thème n'est pas énuméré — n'importe quel mot en
/// minuscules passe, et c'est `ProfilePhoto` qui retombe sur le thème
/// d'origine s'il ne le connaît pas.
final RegExp _motifJeton = RegExp(
  '\\[(?:'
  // La forme courte.
  '(?<portrait>$kCodePortrait)'
  '|$kCodeLogo(?<logoc>$_lesCodes)'
  '|(?<themec>$_lesCodes)(?<typec>[$_lesLettres])(?<noirc>n)?'
  // La forme longue, celle d'avant.
  '|logo\\|(?<logo>[a-z]+)'
  '|(?<deepgrey>deepgrey)'
  '|(?:(?<theme>[a-z]+)\\|)?(?<type>$_lesTypes)'
  '(?:[ |](?<camp>$_lesCamps))?'
  ')\\]',
);

/// Un morceau de message : du texte, ou une image.
///
/// [texte] et l'image s'excluent — on découpe plutôt que de remplacer parce
/// qu'une image se DESSINE, et qu'elle ne peut pas vivre dans une chaîne.
/// Un morceau sans [texte] est donc une image : une [piece], le [logo] d'un
/// thème, ou le portrait de Deep Grey ([deepGrey]).
///
/// [theme] n'accompagne qu'une pièce, et vaut `null` quand le jeton n'en
/// nomme pas : à celui qui lit d'employer le sien.
typedef MorceauMessage = ({
  String? texte,
  Piece? piece,
  String? theme,
  String? logo,
  bool deepGrey,
});

/// La photo — au sens de `ProfilePhoto` — que ce morceau dessine.
///
/// [themeDuLecteur] ne sert qu'aux vieux jetons sans thème (`[Soldat]`) :
/// eux se dessinent dans le thème de celui qui LIT, comme avant.
String photoDuMorceau(MorceauMessage m, String themeDuLecteur) {
  if (m.deepGrey) return 'deepgrey';
  if (m.logo != null) return 'logo|${m.logo}';
  final piece = m.piece!;
  final noir = piece.camp == Camp.noir ? '|${Camp.noir.wire}' : '';
  return '${m.theme ?? themeDuLecteur}|${piece.type.wire}$noir';
}

/// Découpe un message en texte et en pièces, dans l'ordre.
///
/// Un message sans jeton rend un seul morceau : le coût est une recherche de
/// motif, et rien d'autre ne change pour les messages ordinaires.
List<MorceauMessage> decoupeMessage(String texte) {
  final morceaux = <MorceauMessage>[];
  var curseur = 0;
  for (final trouve in _motifJeton.allMatches(texte)) {
    if (trouve.start > curseur) {
      morceaux.add(_duTexte(texte.substring(curseur, trouve.start)));
    }
    morceaux.add(_deLImage(trouve));
    curseur = trouve.end;
  }
  if (curseur < texte.length) {
    morceaux.add(_duTexte(texte.substring(curseur)));
  }
  return morceaux;
}

MorceauMessage _duTexte(String texte) =>
    (texte: texte, piece: null, theme: null, logo: null, deepGrey: false);

MorceauMessage _deLImage(RegExpMatch trouve) {
  // La forme courte d'abord : c'est celle qu'on écrit.
  if (trouve.namedGroup('portrait') != null) {
    return (texte: null, piece: null, theme: null, logo: null, deepGrey: true);
  }
  final logoc = trouve.namedGroup('logoc');
  if (logoc != null) {
    return (
      texte: null,
      piece: null,
      theme: null,
      logo: _themeDuCode(logoc),
      deepGrey: false,
    );
  }
  final themec = trouve.namedGroup('themec');
  if (themec != null) {
    return (
      texte: null,
      piece: Piece(
        _pieceDuCode(trouve.namedGroup('typec')!)!,
        trouve.namedGroup('noirc') == null ? Camp.blanc : Camp.noir,
      ),
      theme: _themeDuCode(themec),
      logo: null,
      deepGrey: false,
    );
  }
  if (trouve.namedGroup('deepgrey') != null) {
    return (texte: null, piece: null, theme: null, logo: null, deepGrey: true);
  }
  final logo = trouve.namedGroup('logo');
  if (logo != null) {
    return (texte: null, piece: null, theme: null, logo: logo, deepGrey: false);
  }
  final type = kPiecesEnvoyables.firstWhere(
    (p) => p.wire == trouve.namedGroup('type'),
  );
  final camp = trouve.namedGroup('camp') == Camp.noir.wire
      ? Camp.noir
      : Camp.blanc;
  return (
    texte: null,
    piece: Piece(type, camp),
    theme: trouve.namedGroup('theme'),
    logo: null,
    deepGrey: false,
  );
}

/// Vrai si le message contient au moins une image.
bool contientUneImage(String texte) => _motifJeton.hasMatch(texte);

/// Combien d'images, si le message n'est QUE des images — zéro sinon.
///
/// Comme pour les émojis : un message qui ne dit rien d'autre se montre en
/// grand, et sans bulle autour.
int compteImagesSeules(String texte) {
  var images = 0;
  for (final morceau in decoupeMessage(texte)) {
    if (morceau.texte == null) {
      images++;
    } else if (morceau.texte!.trim().isNotEmpty) {
      return 0;
    }
  }
  return images;
}
