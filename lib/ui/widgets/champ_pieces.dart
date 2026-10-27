/// Un champ de saisie où les pièces se VOIENT, et ne s'écrivent pas.
///
/// Nino : « quand on sélectionne une icône, ça doit l'afficher directement
/// avant l'envoi plutôt que d'afficher son nom. » On tapait « [insectes|
/// Nurse|Noir] » dans la boîte de saisie, ce qui disait ce qui partirait sans
/// jamais le montrer.
///
/// ## Un caractère, pas un mot
///
/// Un champ de saisie Flutter affiche du TEXTE : pour y poser un dessin, il
/// faut un `WidgetSpan`. Et un `WidgetSpan` compte pour UN caractère dans la
/// chaîne éditée — les deux longueurs doivent concorder, sans quoi le curseur
/// et la sélection ne tombent plus au bon endroit et Flutter le refuse.
///
/// Le champ ne porte donc pas le jeton mais un seul caractère, pris dans la
/// zone à usage privé d'Unicode, qui n'apparaît dans aucune langue. Ce
/// caractère se dessine comme la pièce, s'efface d'une seule touche arrière —
/// ce qui est exactement ce qu'on attend d'une icône — et [texteEnvoyable]
/// le rend à son jeton au moment de partir.
library;

import 'package:flutter/material.dart';

import '../mesure_emoji.dart';
import '../pieces_emoji.dart';
import 'profile_photo.dart';

/// Premier caractère de la zone à usage privé : aucun texte ne l'emploie.
const int kPremierCodePiece = 0xE000;

class ControleurAvecPieces extends TextEditingController {
  ControleurAvecPieces({super.text});

  /// Ce que chaque caractère privé posé dans le champ représente.
  final Map<String, String> _jetons = {};

  /// Le prochain caractère libre.
  int _suivant = kPremierCodePiece;

  /// Pose la pièce de [jeton] à l'endroit du curseur.
  ///
  /// Et pas à la fin : on écrit souvent la pièce au milieu d'une phrase, et
  /// la renvoyer au bout ferait reculer la main à chaque fois.
  void insererPiece(String jeton) {
    final marque = String.fromCharCode(_suivant++);
    _jetons[marque] = jeton;
    final avant = value;
    final debut = avant.selection.isValid
        ? avant.selection.start
        : avant.text.length;
    final fin = avant.selection.isValid
        ? avant.selection.end
        : avant.text.length;
    value = TextEditingValue(
      text: avant.text.replaceRange(debut, fin, marque),
      selection: TextSelection.collapsed(offset: debut + marque.length),
    );
  }

  /// Le message tel qu'il part : chaque pièce redevient son jeton.
  String texteEnvoyable() {
    var sortie = text;
    for (final e in _jetons.entries) {
      sortie = sortie.replaceAll(e.key, e.value);
    }
    return sortie;
  }

  @override
  void clear() {
    _jetons.clear();
    super.clear();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_jetons.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    // La place d'un émoji, mesurée : la pièce se pose dans la ligne
    // comme un smiley, sans la déformer.
    final taille = tailleDUnEmoji(style?.fontSize ?? 16);
    final morceaux = <InlineSpan>[];
    final tampon = StringBuffer();
    void vide() {
      if (tampon.isEmpty) return;
      morceaux.add(TextSpan(text: tampon.toString()));
      tampon.clear();
    }

    for (final ch in text.split('')) {
      final jeton = _jetons[ch];
      if (jeton == null) {
        tampon.write(ch);
        continue;
      }
      vide();
      morceaux.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(
            width: taille,
            height: taille,
            child: ProfilePhoto(photo: _photoDe(jeton), size: taille),
          ),
        ),
      );
    }
    vide();
    return TextSpan(style: style, children: morceaux);
  }

  /// La photo que ce jeton décrit, au sens de [ProfilePhoto].
  static String _photoDe(String jeton) {
    final m = decoupeMessage(jeton).firstWhere((e) => e.piece != null);
    final noir = m.piece!.camp.wire == 'Noir' ? '|Noir' : '';
    return '${m.theme ?? 'original'}|${m.piece!.type.wire}$noir';
  }
}
