/// Les images du jeu, envoyées dans un message comme des émojis.
///
/// Nino : « je voudrais pouvoir envoyer les images des pièces par messages
/// comme si c'était des emojis (ils sont déjà tous listés dans le choix de
/// l'image de profil). »
///
/// ## Un mot, pas une image
///
/// Rien ne part en pièce jointe : le message reste du texte, et une image y
/// est un JETON — `[Soldat]`, `[Soldat Noir]`. Chaque appareil le redessine
/// avec son propre thème, exactement comme une photo de profil, qui est déjà
/// un mot (`thème|Type|Noir`) et non un fichier.
///
/// ## Tout le catalogue des photos, pas seulement les pièces
///
/// Nino : « là, il manque les logos », puis « la photo de profil de deep grey
/// doit aussi être envoyable dans les messages ». Un jeton est donc le mot
/// d'une PHOTO, entre crochets : `[logo|foret]`, `[deepgrey]`,
/// `[volcan|Garde|Noir]`. C'est le même vocabulaire que `ProfilePhoto`, et
/// rien d'autre n'a eu à apparaître pour les deux nouvelles images.
///
/// Le jeton est écrit pour se lire tout seul, et c'est voulu : un client qui
/// ne le connaît pas — une ancienne version sur le téléphone d'en face —
/// affiche « [Soldat Noir] », ce qui se comprend encore. Un code privé y
/// aurait montré des carrés vides.
///
/// Dart pur, sans Flutter.
library;

import '../engine/piece.dart';

/// Le jeton d'une photo, quelle qu'elle soit : `[logo|foret]`,
/// `[deepgrey]`, `[volcan|Garde|Noir]`.
///
/// Le mot entre crochets est celui de `ProfilePhoto`, sans rien y changer :
/// ce qui se choisit dans la galerie s'envoie donc tel quel.
String jetonDePhoto(String photo) => '[$photo]';

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
  return '[$theme|${type.wire}$noir]';
}

/// Les noms que le motif épelle, pris aux pièces elles-mêmes : renommer une
/// pièce ne peut pas laisser le motif en arrière.
final String _lesTypes = kPiecesEnvoyables
    .map((p) => RegExp.escape(p.wire))
    .join('|');
final String _lesCamps = Camp.values
    .map((c) => RegExp.escape(c.wire))
    .join('|');

/// Le motif des jetons : un logo, le portrait de Deep Grey, ou une pièce.
///
/// Le thème n'est pas énuméré — n'importe quel mot en minuscules passe, et
/// c'est `ProfilePhoto` qui retombe sur le thème d'origine s'il ne le connaît
/// pas. Lister les thèmes ici ferait d'un thème ajouté demain un jeton
/// illisible aujourd'hui.
final RegExp _motifJeton = RegExp(
  '\\[(?:'
  'logo\\|(?<logo>[a-z]+)'
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
