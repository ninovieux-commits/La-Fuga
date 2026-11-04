/// Le panneau d'un volet posé SUR le menu.
///
/// Un `showDialog` ouvre une route par-dessus l'écran : plus rien de ce qui
/// est dessous ne reçoit un doigt, pas même les deux touches du bandeau du
/// haut. Nino : « lorsqu'il apparaît les boutons "standard/random" et "nino"
/// doivent rester accessibles [...] ce serait bien que le popup favoris en
/// question ainsi que les autres popups qui s'affichent directement sur le
/// menu laissent également accessibles les boutons "nino" et
/// "standard/random". »
///
/// Le menu pose donc ses volets dans SA propre pile, sous le bandeau — et
/// c'est ce fichier qui leur donne l'allure d'un popup : le fond sombre, le
/// trait noir tout autour, un titre, et la touche qui referme.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'picto_touche.dart';

class PanneauDuVolet extends StatelessWidget {
  const PanneauDuVolet({
    super.key,
    required this.titre,
    required this.enfant,
    required this.onFermer,
    this.largeur = 0.94,
    this.hauteur = 0.68,
  });

  /// Le bandeau du haut. Il porte le trait noir comme tout le reste.
  final String titre;

  /// Ce qui défile au milieu.
  final Widget enfant;

  final VoidCallback onFermer;

  /// Fractions de l'écran, comme le `size_hint` d'un `Popup` de Kivy.
  ///
  /// Large : les lignes qu'il porte valent par ce qu'elles alignent — un
  /// rang, un visage, un nom, un nombre — et chaque point gagné sur les
  /// bords est un point donné aux noms. Nino : « les lignes doivent être
  /// plus larges. »
  final double largeur;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final ecran = MediaQuery.sizeOf(context);
    return Material(
      // Le gris SOMBRE, et non celui des touches : un panneau n'est pas une
      // touche, et les touches qu'il porte doivent s'en détacher.
      color: kFugaGrey,
      shape: formeDeTouche(BorderRadius.circular(S(14))),
      child: ConstrainedBox(
        // La hauteur est un PLAFOND : le volet prend ce que son contenu
        // demande, et pas un pixel de plus.
        constraints: BoxConstraints(maxHeight: ecran.height * hauteur),
        child: SizedBox(
          width: ecran.width * largeur,
          child: Padding(
            padding: EdgeInsets.all(S(12)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (titre.isNotEmpty) ...[
                  MotTouche(
                    texte: titre,
                    couleur: Colors.white,
                    style: TextStyle(
                      fontSize: SF(18),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: S(10)),
                ],
                Flexible(child: enfant),
                SizedBox(height: S(10)),
                SizedBox(
                  width: S(140),
                  child: FugaButton(
                    text: T('Fermer'),
                    fontSize: SF(15),
                    onPressed: onFermer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
