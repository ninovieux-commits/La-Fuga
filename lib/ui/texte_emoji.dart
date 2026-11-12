/// Un message qui n'est QUE des émojis.
///
/// Nino : « quand on envoie un smiley seul il apparaît en plus gros. »
///
/// Les autres messageries rapetissent les dessins quand il y en a plusieurs.
/// Pas ici — Nino : « je veux pas que ça rétrécisse quand il y en a
/// plusieurs, je trouve ça naze. » Un dessin fait donc toujours la même
/// taille, seul ou en rangée, et une rangée trop longue passe à la ligne au
/// lieu de maigrir.
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

/// La taille d'un dessin, seul ou en rangée.
const double kEmojiGrossi = 3.0;

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

/// Le multiplicateur de taille pour un message de [n] dessins.
///
/// Le même pour tous : un dessin seul et une rangée de dessins font la même
/// taille. Ils rapetissaient à mesure qu'ils étaient nombreux, comme dans
/// les autres messageries, et Nino n'en veut pas.
///
/// Sert aux émojis comme aux images : ce sont les mêmes dessins pour l'œil,
/// donc la même règle.
double grossissementDe(int n) => n <= 0 ? 1 : kEmojiGrossi;
