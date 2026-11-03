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

/// LA COULEUR D'UNE ENVELOPPE EST CELLE DE SA BULLE.
///
/// Nino : « je veux que les enveloppes envoyées prennent ma couleur et les
/// reçues, la couleur de mon correspondant (exactement comme les bulles de
/// conversation en fait) ». Les bulles prennent `clair` pour les miennes et
/// `fonce` pour les siennes, dans le thème qui habille la conversation —
/// donc le sien. Une enveloppe suit exactement la même règle, et on lit d'un
/// coup d'œil de quel côté elle vient.
Color couleurEnveloppe(Enveloppe e, ThemePalette palette) =>
    e.deMoi ? palette.clair : palette.fonce;

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
    final cote = widget.cote ?? S(38);
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
