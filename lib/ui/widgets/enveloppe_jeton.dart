/// Le jeton d'une enveloppe : le dessin, son chrono, et son balancement.
///
/// Nino : « les carrés rouges indiquent l'endroit où se trouvent les
/// enveloppes reçues et envoyées avec le petit chrono par dessus », « il ne
/// doit pas être sur un bouton pour les reçus et envoyés », et « les
/// enveloppes qu'on peut ouvrir doivent osciller ».
///
/// D'où ces trois choses, et rien d'autre : le dessin nu — pas de touche
/// sous lui — le chrono posé par-dessus, et le balancement réservé à CELLES
/// QU'ON PEUT OUVRIR. Celle qu'on a envoyée ne bouge pas : on ne peut que la
/// vérifier ou la reprendre, elle n'appelle personne.
library;

import 'package:flutter/material.dart';

import '../../game/enveloppe.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'picto_touche.dart';

/// L'angle du balancement, en radians. Trois degrés et demi : assez pour
/// attraper l'œil au bord du champ de vision, pas assez pour agacer celui
/// qui lit ses messages.
const double kEnveloppeAngle = 0.06;

/// Le temps d'un aller-retour complet.
const Duration kEnveloppeBalancement = Duration(milliseconds: 1400);

/// La rotation du balancement, repérée pour les tests : une pile de widgets
/// en compte des dizaines, et celle-ci est la seule qui nous regarde.
const Key cleDuBalancement = ValueKey('balancement enveloppe');

/// UNE ENVELOPPE PORTE LA SECONDE COULEUR DU THÈME DE SON AUTEUR.
///
/// Nino : « je veux que les enveloppes envoyées prennent ma couleur et les
/// reçues, la couleur de mon correspondant (exactement comme les bulles de
/// conversation en fait) », puis : « toutes les bulles doivent être en
/// couleur 1 et toutes les enveloppes en couleur 2, histoire d'équilibrer. »
///
/// Donc : la palette est celle de CELUI QUI L'A ENVOYÉE, comme pour une
/// bulle — la mienne porte mes couleurs sur son écran comme sur le mien — et
/// la teinte est la seconde, celle que les bulles n'emploient plus. Les deux
/// couleurs du thème se partagent ainsi la conversation au lieu de se
/// disputer les côtés.
Color couleurEnveloppe(ThemePalette palette) => palette.fonce;

class EnveloppeJeton extends StatefulWidget {
  const EnveloppeJeton({
    super.key,
    required this.enveloppe,
    required this.couleur,
    required this.onTap,
    required this.maintenant,
    this.cote,
  });

  final Enveloppe enveloppe;

  /// La couleur du dessin. Voir [couleurEnveloppe] : c'est celle de la bulle
  /// du même côté.
  final Color couleur;

  final VoidCallback onTap;

  /// L'instant où l'on se place pour écrire le chrono. L'écran le rafraîchit
  /// chaque minute ; le jeton, lui, ne décide pas du temps.
  final DateTime maintenant;

  final double? cote;

  @override
  State<EnveloppeJeton> createState() => _EnveloppeJetonState();
}

class _EnveloppeJetonState extends State<EnveloppeJeton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _balance = AnimationController(
    vsync: this,
    duration: kEnveloppeBalancement,
  );

  @override
  void initState() {
    super.initState();
    _suitLOscillation();
  }

  @override
  void didUpdateWidget(EnveloppeJeton vieux) {
    super.didUpdateWidget(vieux);
    _suitLOscillation();
  }

  /// Seule celle qu'on peut ouvrir se balance ; les autres se tiennent
  /// droites, et leur animation ne tourne même pas.
  void _suitLOscillation() {
    if (widget.enveloppe.ouvrable) {
      if (!_balance.isAnimating) _balance.repeat(reverse: true);
    } else if (_balance.isAnimating) {
      _balance
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // LE MÊME DESSIN QUE DANS LA TOUCHE, À LA MÊME TAILLE. Nino, la rangée
    // sous les yeux : « les enveloppes reçues et envoyées sont trop petites.
    // Mets-les de la même taille que celle qui est dans le bouton en haut à
    // droite. »
    //
    // La touche est un carré d'une hauteur de touche, et son symbole y occupe
    // [kPartPicto] : un jeton de la même largeur porte donc un dessin de la
    // même taille, puisqu'il passe par le même [PictoTouche]. Le chiffre ne
    // se recopie pas d'un endroit à l'autre — c'est la même expression.
    final cote = widget.cote ?? touchHeight();
    final dessin = SizedBox(
      width: cote,
      height: cote,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // LE DESSIN NU, sans touche sous lui : « il ne doit pas être sur un
          // bouton pour les reçus et envoyés ». Il garde le trait noir des
          // autres symboles, qui vient avec [PictoTouche].
          Positioned.fill(
            child: PictoTouche(
              asset: 'assets/images/enveloppe.webp',
              couleur: widget.couleur,
              secours: '✉',
            ),
          ),
          // LE CHRONO PAR-DESSUS, comme sur le dessin de Nino — mais posé
          // EN BAS : au milieu, il couvrait l'enveloppe au lieu de la
          // compléter.
          Align(alignment: Alignment.bottomCenter, child: _chrono(cote)),
        ],
      ),
    );

    return Tooltip(
      message: widget.enveloppe.ouvrable
          ? T('Ouvrir l\'enveloppe')
          : T('Votre enveloppe'),
      child: GestureDetector(
        onTap: widget.onTap,
        // Le balancement est une peinture à part : il ne redessine que le
        // jeton, jamais la conversation derrière lui.
        child: RepaintBoundary(
          child: widget.enveloppe.ouvrable
              ? AnimatedBuilder(
                  animation: _balance,
                  builder: (context, enfant) => Transform.rotate(
                    key: cleDuBalancement,
                    // Un aller-retour, et non un tour : la valeur va de 0 à 1
                    // puis revient, on la ramène entre −1 et 1.
                    angle: kEnveloppeAngle * (_balance.value * 2 - 1),
                    child: enfant,
                  ),
                  child: dessin,
                )
              : dessin,
        ),
      ),
    );
  }

  /// Le temps qui reste, au format que Nino a dicté : « 48h00 -> 47h59 ».
  Widget _chrono(double cote) => Container(
    padding: EdgeInsets.symmetric(horizontal: cote * 0.06),
    decoration: BoxDecoration(
      color: const Color(0xD9000000),
      borderRadius: BorderRadius.circular(cote * 0.1),
    ),
    child: Text(
      chronoEnveloppe(widget.enveloppe.restant(widget.maintenant)),
      maxLines: 1,
      style: TextStyle(
        color: Colors.white,
        fontSize: cote * 0.24,
        fontWeight: FontWeight.bold,
        height: 1.15,
      ),
    ),
  );
}

/// LA TOUCHE QUI ENVOIE une enveloppe : le dessin, et un petit « + ».
///
/// Nino : « sur l'image ci-jointe, le carré vert dessiné indique l'endroit où
/// se trouvera l'icône d'enveloppe avec un petit + ajouté, permettant
/// d'envoyer une image », et : « il ne doit pas être sur un bouton pour les
/// reçus et envoyés, mais doit être sur un bouton pour les envoyer. »
///
/// Celle-ci est donc une VRAIE touche — gris des touches, trait noir, coins
/// arrondis — là où les jetons de la conversation sont des dessins nus.
class ToucheEnveloppePlus extends StatelessWidget {
  const ToucheEnveloppePlus({
    super.key,
    required this.palette,
    required this.onPressed,
    this.actif = true,
  });

  final ThemePalette palette;
  final VoidCallback onPressed;

  /// Faux quand on a déjà deux enveloppes en attente chez ce correspondant :
  /// la touche s'éteint au lieu de disparaître, et son infobulle dit
  /// pourquoi.
  final bool actif;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: actif
        ? T('Envoyer une image')
        : T('Deux enveloppes attendent déjà'),
    child: AspectRatio(
      aspectRatio: 1,
      child: Material(
        // LE GRIS DE « < RETOUR », et c'est un autre que celui des touches
        // du plateau. Nino : « le fond de la touche doit être du même gris
        // que [retour]. » Les deux se tiennent dans le même bandeau, à deux
        // doigts l'une de l'autre : la moindre différence s'y voit.
        color: actif ? kFugaGrey : fondEteint(kFugaGrey),
        shape: formeDeTouche(BorderRadius.circular(S(14))),
        child: InkWell(
          borderRadius: BorderRadius.circular(S(14)),
          onTap: actif ? onPressed : null,
          child: Opacity(
            opacity: actif ? 1 : kOpaciteEteinte,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PictoTouche(
                  asset: 'assets/images/enveloppe.webp',
                  couleur: palette.fonce,
                  secours: '✉',
                ),
                // UN SEUL « + », NOIR, EN PLEIN MILIEU. Nino : « il y a deux
                // +, un noir et un tout fin orange, et ils sont tous les deux
                // mal placés. Mets un seul + noir en plein milieu de la
                // touche. »
                //
                // Les deux venaient de [MotTouche], dont le contour est peint
                // dans la boîte pendant que la lettre, elle, débordait de la
                // sienne : le trait noir et l'orange se retrouvaient décalés,
                // et aucun des deux n'était là où on l'attendait. Un signe
                // noir, plein, posé au centre, n'a pas ce défaut — et le
                // dessin qu'il recouvre porte déjà son propre trait noir.
                Center(
                  child: FractionallySizedBox(
                    // Assez grand pour se voir d'un coup d'œil, assez petit
                    // pour que l'enveloppe reste lisible dessous : le signe
                    // couvre un peu plus du tiers de la touche.
                    heightFactor: 0.62,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Text(
                        '+',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          height: 1,
                          fontSize: S(40),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
