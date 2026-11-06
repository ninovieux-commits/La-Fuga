/// Bandeau de titre des écrans secondaires — portage du `header` que tous les
/// écrans de Kivy construisent à l'identique (`BoxLayout(size_hint=(1, 0.08))`
/// avec un bouton de retour large de 110, le titre au centre, et un vide de
/// même largeur à droite pour que le titre reste centré).
///
/// LE TITRE N'EST PLUS EN ITALIQUE, IL EST GRAVÉ. Nino : « je ne veux pas que
/// les titres des menus soient marqués en italique. J'aimerais en revanche
/// qu'ils aient l'air gravés. » L'italique venait de Kivy et ne disait rien ;
/// la gravure dit quelque chose — c'est un titre posé DANS la page, pas
/// dessus.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'etoile_favori.dart';
import 'fuga_button.dart';
import '../scale.dart';

class FugaHeader extends StatelessWidget implements PreferredSizeWidget {
  const FugaHeader({
    super.key,
    required this.back,
    required this.title,
    required this.onBack,
    this.titleSize = 28,
    this.titleColor = Colors.black,
    this.bold = false,
    this.favori = false,
    this.onTitleTap,
    this.action,
  });

  /// Intitulé du bouton de retour, barre chevron comprise : `< Menu`.
  final String back;

  final String title;
  final VoidCallback onBack;

  /// Kivy varie la taille du titre d'un écran à l'autre : 32 pour
  /// l'historique, 28 pour ses deux listes, 26 pour le lecteur.
  final double titleSize;

  /// Noir partout, sauf sur le composeur de thèmes où Kivy l'écrit en blanc.
  final Color titleColor;

  /// Les titres en gras : la messagerie, le composeur.
  final bool bold;

  /// Le titre est le pseudo de quelqu'un, et il est dans MES favoris :
  /// l'étoile se range devant, comme dans les bandeaux de partie.
  ///
  /// Nino, en montrant l'en-tête d'une boîte de discussion : « à ces
  /// endroits, l'étoile doit aussi apparaître devant le nom. »
  final bool favori;

  /// Quand le titre EST un pseudo, le toucher ouvre la fiche du joueur —
  /// comme son nom en partie, comme sa photo.
  final VoidCallback? onTitleTap;

  /// Ce qui occupe la place de DROITE, en face de la touche de retour.
  ///
  /// Elle était vide, et réservée : c'est elle qui tient le titre au milieu.
  /// La boîte de discussion y pose sa touche d'enveloppe — Nino l'a entourée
  /// en vert à cet endroit précis.
  final Widget? action;

  static const double _sideWidth = 110;

  /// Hauteur du bandeau : la plus grande de sa touche et de son titre, plus
  /// les marges.
  ///
  /// Le titre était écrit à sa taille de référence BRUTE, sans passer par
  /// `SF` — un `32` fixe dans un bandeau qui n'en faisait que 24 de haut, et
  /// le mot était coupé par le milieu. Il suit maintenant l'échelle de
  /// l'écran, et le bandeau s'ouvre pour le laisser tenir en entier.
  @override
  Size get preferredSize => Size.fromHeight(
    math.max(touchHeight(), SF(titleSize) * _lineHeight) + 2 * S(6),
  );

  /// Hauteur d'une ligne rapportée à la taille de police. Mesurée sur la
  /// police de l'appli : 1,43. Arrondie au-dessus, pour les accents.
  static const double _lineHeight = 1.45;

  /// LE RELIEF D'UNE GRAVURE : le creux, puis la lèvre qu'il laisse.
  ///
  /// Une lettre gravée se lit à deux traits et non à un contour : l'ombre du
  /// creux du côté d'où vient la lumière, et la lumière sur la lèvre de
  /// l'autre côté. Ici la lumière vient d'en haut à gauche, comme partout
  /// ailleurs dans l'application.
  ///
  /// Les deux traits s'échangent selon l'encre : sous une encre sombre
  /// c'est la lèvre CLAIRE qui se voit, sous une encre claire c'est
  /// l'ombre. Le même raisonnement que les cernes des touches, et il tombe
  /// juste pour les deux titres que l'application écrit — noir sur le gris
  /// des pages, blanc sur le composeur.
  /// L'ÉPAISSEUR DU RELIEF SUIT LA LETTRE, et non l'écran : une gravure se
  /// voit en proportion de ce qui est gravé. Un seizième de la hauteur de
  /// police, et le trait reste net — pas de flou : une incision a un bord.
  static List<Shadow> gravure(Color encre, double taille) {
    final e = taille / 20;
    // LE CREUX EST TOUJOURS EN HAUT À GAUCHE, LA LÈVRE EN BAS À DROITE : la
    // lumière vient d'en haut à gauche, la paroi qui lui tourne le dos est
    // dans l'ombre, celle d'en face la reçoit. Ce qui change avec l'encre,
    // c'est LEQUEL DES DEUX se voit — la lèvre claire sous une encre
    // sombre, l'ombre sous une encre claire.
    final sombre = encre.computeLuminance() < 0.5;
    return [
      Shadow(
        color: const Color(0xFF000000).withValues(alpha: sombre ? 0.22 : 0.65),
        offset: Offset(-e / 2, -e / 2),
      ),
      Shadow(
        color: const Color(0xFFFFFFFF).withValues(alpha: sombre ? 0.95 : 0.25),
        offset: Offset(e, e),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: preferredSize.height,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: S(8), vertical: S(6)),
      child: Row(
        children: [
          SizedBox(
            width: _sideWidth,
            child: FugaButton(text: back, fontSize: SF(16), onPressed: onBack),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTitleTap,
              child: Text.rich(
                // L'étoile est un peu plus petite que les lettres du titre :
                // elle accompagne le nom, elle ne le concurrence pas.
                nomEtoile(title, favori: favori, taille: SF(titleSize) * 0.82),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: SF(titleSize),
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: titleColor,
                  shadows: gravure(titleColor, SF(titleSize)),
                ),
              ),
            ),
          ),
          // La place de droite : vide, elle tient le titre au milieu ; prise,
          // elle porte la touche de l'écran.
          SizedBox(
            width: _sideWidth,
            child: action == null
                ? null
                : Align(alignment: Alignment.centerRight, child: action),
          ),
        ],
      ),
    ),
  );
}
