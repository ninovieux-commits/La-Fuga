/// Un message qui n'est QUE des émojis.
///
/// Nino : « quand on envoie un smiley seul il apparaît en plus gros. »
///
/// Toutes les messageries font cela, et toutes le font pour un petit nombre :
/// un émoji seul s'affiche très grand, deux un peu moins, trois encore moins,
/// et au-delà le message redevient du texte ordinaire. On suit la même règle.
///
/// ## Ce qui compte pour un émoji
///
/// Un émoji n'est pas un caractère. « 👍🏽 » en fait deux — le pouce et la
/// teinte de peau — et « 👩‍👩‍👧 » en fait cinq, trois personnages cousus par
/// deux liants invisibles. Les compter un par un donnerait cinq émojis là où
/// l'œil en voit un, et le message resterait petit.
///
/// On ignore donc les caractères qui MODIFIENT l'émoji précédent sans en
/// ajouter un : teintes de peau, sélecteurs de variante, liants, étiquettes.
/// Ce qui reste est le compte que l'œil fait.
///
/// Dart pur, sans Flutter.
library;

/// Au-delà, le message redevient du texte ordinaire.
const int kEmojiMaxGrossi = 3;

/// Caractères qui s'accrochent à l'émoji précédent sans en faire un nouveau.
bool _estModificateur(int r) =>
    // Teintes de peau.
    (r >= 0x1F3FB && r <= 0x1F3FF) ||
    // Liant sans chasse (ZWJ), sélecteurs de variante, combinaison d'enceinte.
    r == 0x200D ||
    (r >= 0xFE00 && r <= 0xFE0F) ||
    r == 0x20E3 ||
    // Étiquettes des drapeaux régionaux (Écosse, Pays de Galles…).
    (r >= 0xE0020 && r <= 0xE007F) ||
    // Chiffres et dièse, qui ne sont des émojis qu'avec l'enceinte 20E3 — et
    // celle-ci les suit, donc ils ne comptent jamais seuls.
    (r >= 0x30 && r <= 0x39) ||
    r == 0x23 ||
    r == 0x2A;

/// Vrai si ce point de code est le cœur d'un émoji.
bool _estEmoji(int r) =>
    // Symboles divers et pictogrammes, émoticônes, transports, drapeaux,
    // symboles supplémentaires et étendus-A : tout le plan 1F000–1FAFF.
    (r >= 0x1F000 && r <= 0x1FAFF) ||
    // Symboles divers, dingbats, flèches et formes géométriques décorées.
    (r >= 0x2600 && r <= 0x27BF) ||
    (r >= 0x2B00 && r <= 0x2BFF) ||
    (r >= 0x2190 && r <= 0x21FF) ||
    // Les quelques isolés : ©, ®, ™, ‼, ⁉, 〰, 〽, ⌚, ⌛, ⏩…
    r == 0xA9 ||
    r == 0xAE ||
    r == 0x2122 ||
    r == 0x203C ||
    r == 0x2049 ||
    r == 0x3030 ||
    r == 0x303D ||
    (r >= 0x231A && r <= 0x231B) ||
    (r >= 0x23E9 && r <= 0x23FA) ||
    r == 0x24C2 ||
    (r >= 0x25AA && r <= 0x25FE);

/// Indicateur régional : deux de suite font UN drapeau.
bool _estIndicateur(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;

/// Le texte sans ce qui le suit : espaces et émojis de la fin.
///
/// Nino, à propos des bulles de cri : « le seul truc qu'il doit pouvoir y
/// avoir derrière [le « ! »] et que ça marche toujours sont des espaces ou
/// des emojis. » Un « Et paf ! 🎉 » crie autant qu'un « Et paf ! ».
///
/// On remonte depuis la FIN et on laisse tomber tout ce qui est blanc,
/// émoji, ou morceau d'émoji — teinte de peau, liant, sélecteur de variante,
/// indicateur de drapeau. En remontant ainsi, pas besoin de reconnaître les
/// suites cousues : chacun de leurs morceaux tombe pour son propre compte.
String sansLaQueueDEmojis(String texte) {
  final runes = texte.runes.toList();
  var fin = runes.length;
  while (fin > 0) {
    final r = runes[fin - 1];
    final blanc = r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D;
    // Chiffres et dièse sont « modificateurs » parce qu'ils ne font un émoji
    // qu'avec l'enceinte qui les suit. Ici on remonte : les prendre pour des
    // émojis mangerait le « 3 » de « J'en ai 3 ». On s'arrête donc dessus.
    final partieDEmoji =
        _estModificateur(r) &&
        !(r >= 0x30 && r <= 0x39) &&
        r != 0x23 &&
        r != 0x2A;
    if (!blanc && !partieDEmoji && !_estEmoji(r)) break;
    fin--;
  }
  return String.fromCharCodes(runes.sublist(0, fin));
}

/// Combien d'émojis ce message contient, s'il ne contient QUE des émojis.
///
/// Rend 0 dès qu'il y a autre chose : une lettre, un chiffre isolé, un point.
/// Les espaces et les retours à la ligne sont ignorés — « 😀 😀 » compte deux
/// émojis, pas davantage.
///
/// Ce que l'œil voit comme UN dessin compte pour un :
///
///   — « 👍🏽 », un émoji et sa teinte ;
///   — « 🙋🏿‍♀️ » et « 👩‍👩‍👧 », plusieurs émojis COUSUS par des liants
///     invisibles ; tout ce qui suit un liant appartient au dessin commencé ;
///   — « 🇫🇷 », deux indicateurs régionaux qui font un drapeau.
int compteEmojisSeuls(String texte) {
  final runes = texte.trim().runes.toList();
  if (runes.isEmpty) return 0;
  var compte = 0;
  var i = 0;
  // Vrai juste après un liant : l'émoji qui suit continue le précédent au
  // lieu d'en ouvrir un nouveau.
  var cousu = false;
  while (i < runes.length) {
    final r = runes[i];
    // Les blancs séparent sans rien ajouter. Ils rompent aussi la couture.
    if (r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D) {
      cousu = false;
      i++;
      continue;
    }
    if (_estModificateur(r)) {
      if (r == 0x200D) cousu = true;
      i++;
      continue;
    }
    if (!_estEmoji(r)) return 0;
    // Un drapeau : deux indicateurs d'affilée pour un seul dessin.
    if (_estIndicateur(r) &&
        i + 1 < runes.length &&
        _estIndicateur(runes[i + 1])) {
      i++;
    }
    if (!cousu) compte++;
    cousu = false;
    i++;
  }
  return compte;
}

/// Le message doit-il s'afficher en gros, et à quelle taille.
///
/// Rend le multiplicateur à appliquer à la taille du texte, ou `null` quand le
/// message s'affiche normalement. Un émoji seul est le plus gros ; deux puis
/// trois décroissent, comme partout ailleurs.
double? grossissementEmoji(String texte) {
  final n = compteEmojisSeuls(texte);
  if (n == 0 || n > kEmojiMaxGrossi) return null;
  return switch (n) {
    1 => 3.0,
    2 => 2.4,
    _ => 2.0,
  };
}
