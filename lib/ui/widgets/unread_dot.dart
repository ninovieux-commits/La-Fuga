/// LA PASTILLE DES MESSAGES NON LUS, la même partout.
///
/// Un compteur entre parenthèses — « Messages (1) » — allonge l'intitulé et
/// le fait déborder dès qu'il y a deux chiffres. La pastille dit la même
/// chose sans toucher au texte.
///
/// ## Une seule pastille, trois endroits
///
/// Nino, trois captures en main : « celle de la photo 1 est mangée et celle
/// de la photo 2 est à l'ancienne. Arrange ça. La pastille doit être en
/// couleur 1 avec le contour noir. Elle doit apparaître et disparaître à
/// intervalles de 1,5 seconde. »
///
/// Elle vivait à trois endroits et de trois façons : un rond rouge cerclé de
/// blanc sur la touche du menu, le même débordant du bandeau d'une partie —
/// donc ROGNÉ, puisqu'un dessin qui sort de la boîte de son parent est
/// coupé — et un rond rouge à chiffre dans la liste des conversations. C'est
/// maintenant ce widget, et lui seul.
///
/// ## Dedans, et non dehors
///
/// Elle se pose DANS la boîte de la touche. Débordante, elle était plus jolie
/// sur une grande touche et invisible sur une petite : le bandeau d'une
/// partie rogne ce qui dépasse, et la pastille y perdait sa moitié basse.
///
/// ## Elle bat
///
/// Une seconde et demie allumée, une seconde et demie éteinte. Un point fixe
/// se confond avec le décor ; un point qui bat se voit du coin de l'œil, et
/// c'est tout ce qu'on lui demande.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../suit_les_reglages.dart';
import 'fuga_button.dart';

/// Le temps que la pastille reste allumée, puis éteinte.
const Duration kBattementPastille = Duration(milliseconds: 1500);

/// LE ROND LUI-MÊME, qui bat.
///
/// À part, parce que la liste des conversations le pose seul, sans touche
/// dessous : le même dessin, le même battement, deux usages.
class PastilleNonLue extends StatefulWidget {
  const PastilleNonLue({super.key, required this.cote, this.couleur});

  final double cote;

  /// La couleur du rond. Par défaut la PREMIÈRE du thème de celui qui lit —
  /// c'est son application, et la pastille n'appartient à personne d'autre.
  final Color? couleur;

  @override
  State<PastilleNonLue> createState() => _PastilleNonLueState();
}

class _PastilleNonLueState extends State<PastilleNonLue> with SuitLesReglages {
  Timer? _battement;
  bool _allumee = true;

  @override
  void initState() {
    super.initState();
    _battement = Timer.periodic(kBattementPastille, (_) {
      if (mounted) setState(() => _allumee = !_allumee);
    });
  }

  @override
  void dispose() {
    _battement?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _allumee ? 1 : 0,
    duration: const Duration(milliseconds: 180),
    child: Container(
      width: widget.cote,
      height: widget.cote,
      decoration: BoxDecoration(
        color:
            widget.couleur ??
            paletteOf(Settings.instance.themeAxes.general).clair,
        shape: BoxShape.circle,
        // Le trait noir des touches : la pastille se détache de n'importe
        // quel fond, clair comme sombre.
        border: const Border.fromBorderSide(kTraitDeTouche),
      ),
    ),
  );
}

/// La pastille POSÉE SUR UNE TOUCHE.
class UnreadDot extends StatelessWidget {
  const UnreadDot({
    super.key,
    required this.child,
    required this.show,
    this.couleur,
  });

  final Widget child;

  /// Vrai quand il y a quelque chose à signaler.
  final bool show;

  final Color? couleur;

  /// La part de la touche qu'occupe la pastille, et ses deux bornes.
  ///
  /// ELLE SE MESURE SUR LA TOUCHE, et non en points fixes : vingt points
  /// conviennent à la large touche « Messages » du menu et recouvrent le
  /// CENTRE de la touche chat d'un bandeau, qui n'en fait que trente-six.
  /// Mesuré : l'appui tombait sur la pastille, et le chat ne s'ouvrait plus.
  static const double kPartDeLaTouche = 0.34;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return LayoutBuilder(
      builder: (context, boite) {
        final place = math.min(boite.maxWidth, boite.maxHeight);
        final cote = (place.isFinite ? place * kPartDeLaTouche : S(20))
            .clamp(S(11), S(22))
            .toDouble();
        return Stack(
          children: [
            child,
            Positioned(
              // DANS la touche, pas dehors : ce qui dépasse est rogné par le
              // bandeau d'une partie, et la pastille y perdait sa moitié
              // basse.
              right: cote * 0.15,
              bottom: cote * 0.15,
              // ELLE NE PREND AUCUN APPUI. Un rond décoré avale le doigt là
              // où il se trouve : posée sur une petite touche, elle en volait
              // le coin — et le centre, quand elle était trop grosse.
              child: IgnorePointer(
                child: PastilleNonLue(cote: cote, couleur: couleur),
              ),
            ),
          ],
        );
      },
    );
  }
}
