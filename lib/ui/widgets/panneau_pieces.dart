/// Le choix d'une image à envoyer dans un message.
///
/// Nino : « je voudrais pouvoir envoyer les images des pièces par messages
/// comme si c'était des emojis (ils sont déjà tous listés dans le choix de
/// l'image de profil). »
///
/// ## Un panneau, pas un popup
///
/// C'était un popup, et il avait trois défauts que Nino a relevés d'un coup :
/// « le clavier doit rester déployé (le popup déroulant doit donc être plus
/// court et plus haut). Quand on clique sur l'une des images, le popup ne
/// doit pas partir, ainsi on peut mettre plusieurs images d'affilée sans
/// avoir à rouvrir le popup. Celui-ci s'enlève quand on clique en dehors du
/// popup. »
///
/// Les trois tiennent au même choix : ouvrir une ROUTE — `showDialog` — donne
/// le focus à la page qui s'ouvre, et le clavier se range. Le panneau n'est
/// donc plus une route mais un enfant de la conversation, posé par-dessus la
/// liste des messages : la saisie garde le focus, le clavier reste là, et
/// chaque appui insère une image sans rien fermer.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../scale.dart';
import 'grille_photos.dart';

/// Côté d'une image dans la grille : assez grand pour se viser au doigt.
double get kCotePieceChoix => touchHeight();

/// Part de la hauteur de l'ÉCRAN que le panneau ne dépasse pas.
///
/// « Plus court et plus haut » : il doit tenir au-dessus du clavier, donc
/// dans la place qui reste quand celui-ci occupe déjà la moitié basse.
const double kHauteurPanneauPieces = 0.42;

/// Part de la PLACE DISPONIBLE qu'il ne dépasse pas non plus.
///
/// Clavier déployé, la conversation ne fait plus que quelques centimètres :
/// un panneau qui la remplirait ne laisserait plus rien à toucher à côté,
/// et il n'y aurait plus moyen de le refermer. Il s'arrête donc avant, et
/// ce qui dépasse défile.
const double kPartDisponiblePanneau = 0.78;

class PanneauDesPieces extends StatelessWidget {
  const PanneauDesPieces({
    super.key,
    required this.onChoisie,
    required this.onFermer,
  });

  /// Appelée à chaque appui — le panneau RESTE ouvert.
  final void Function(String photo) onChoisie;

  /// Appelée quand on touche à côté.
  final VoidCallback onFermer;

  @override
  Widget build(BuildContext context) {
    final ecran = MediaQuery.sizeOf(context);

    return LayoutBuilder(
      builder: (context, place) => Stack(
        children: [
          // Le voile ne noircit rien : il n'est là que pour recueillir le
          // doigt qui se pose à côté. Un popup sombre aurait caché la
          // conversation qu'on est en train de commenter.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onFermer,
              child: const SizedBox.expand(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: [
                  ecran.height * kHauteurPanneauPieces,
                  place.maxHeight * kPartDisponiblePanneau,
                ].reduce((a, b) => a < b ? a : b),
              ),
              child: Material(
                color: const Color.fromRGBO(60, 60, 60, 0.96),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(S(14)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: S(6)),
                      child: Text(
                        T('Envoyer une pièce'),
                        style: TextStyle(
                          fontSize: SF(15),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // LE CATALOGUE DÉFILE. Dix-sept thèmes de onze images ne
                    // tiennent sur aucun écran ; le panneau s'arrête à son
                    // plafond et laisse glisser le reste.
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(bottom: S(8)),
                        child: GrilleDesPhotos(
                          cote: kCotePieceChoix,
                          themeDabord: Settings.instance.themeAxes.general,
                          onChoisie: onChoisie,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
