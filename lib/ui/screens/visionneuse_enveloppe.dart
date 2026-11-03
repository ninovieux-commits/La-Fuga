/// LA VISIONNEUSE : l'image d'une enveloppe ouverte.
///
/// Nino : « quand on ouvre une image reçue, il y a un bouton télécharger »,
/// « il doit y avoir un bouton [modifier et renvoyer] qui nous permet de
/// modifier l'image reçue avant de la renvoyer », et « l'image n'est
/// supprimée qu'une fois fermée ».
///
/// D'où cet écran plutôt qu'un popup : tant qu'il est ouvert, l'image est là
/// et tout reste possible — la regarder, la ranger dans la galerie, la
/// reprendre pour la renvoyer. Elle ne quitte la conversation qu'en le
/// fermant.
///
/// Le SERVEUR, lui, l'a déjà oubliée : il efface au moment où il la livre,
/// et c'est ce qui garantit qu'elle ne traîne nulle part. Ce qu'on voit ici
/// ne vit plus que dans la mémoire du téléphone.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../suit_les_reglages.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import 'editeur_image_screen.dart';

/// Ce que la visionneuse rend à la conversation en se refermant.
typedef SortieVisionneuse = ({Uint8List? renvoyer});

/// Range une image dans la galerie. Injectable : un test n'a pas de galerie.
typedef Rangeur = Future<void> Function(Uint8List octets, String nom);

Future<void> _rangeDansLaGalerie(Uint8List octets, String nom) =>
    Gal.putImageBytes(octets, name: nom);

Rangeur _rangeur = _rangeDansLaGalerie;

/// Pour les tests.
void poseLeRangeur(Rangeur? remplacant) =>
    _rangeur = remplacant ?? _rangeDansLaGalerie;

class VisionneuseEnveloppe extends StatefulWidget {
  const VisionneuseEnveloppe({
    super.key,
    required this.image,
    required this.deLui,
    required this.moi,
    required this.lui,
  });

  final Uint8List image;

  /// Vrai : c'est une enveloppe REÇUE. On peut alors la télécharger et la
  /// renvoyer modifiée. La sienne, on ne fait que la vérifier.
  final bool deLui;

  final String moi;
  final String lui;

  @override
  State<VisionneuseEnveloppe> createState() => _VisionneuseEnveloppeState();
}

class _VisionneuseEnveloppeState extends State<VisionneuseEnveloppe>
    with SuitLesReglages {
  String? _dit;
  bool _travaille = false;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(Settings.instance.themeAxes.general);
    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Fermer'),
              title: widget.deLui ? widget.lui : T('Votre enveloppe'),
              titleSize: 20,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Image.memory(widget.image),
                ),
              ),
            ),
            if (_dit != null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: S(4)),
                child: Text(
                  _dit!,
                  style: TextStyle(color: palette.clair, fontSize: SF(13)),
                ),
              ),
            _touches(palette),
          ],
        ),
      ),
    );
  }

  Widget _touches(ThemePalette palette) => Padding(
    padding: EdgeInsets.all(S(8)),
    child: Row(
      children: [
        Expanded(
          child: FugaButton(
            text: T('Télécharger'),
            color: palette.fonce,
            fontSize: SF(14),
            onPressed: _travaille ? null : () => unawaited(_telecharger()),
          ),
        ),
        if (widget.deLui) ...[
          SizedBox(width: S(8)),
          Expanded(
            child: FugaButton(
              text: T('Modifier et renvoyer'),
              color: palette.clair,
              textColor: Colors.black,
              fontSize: SF(14),
              onPressed: _travaille ? null : () => unawaited(_renvoyer()),
            ),
          ),
        ],
      ],
    ),
  );

  /// Dans la galerie du téléphone : c'est le seul endroit où l'image reste.
  Future<void> _telecharger() async {
    setState(() => _travaille = true);
    try {
      await _rangeur(
        widget.image,
        'lafuga-${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      setState(() => _dit = T('Image enregistrée dans vos photos.'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _dit = T('Enregistrement impossible.'));
    } finally {
      if (mounted) setState(() => _travaille = false);
    }
  }

  /// La reprendre, la retoucher, et la renvoyer à l'expéditeur.
  Future<void> _renvoyer() async {
    final modifiee = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => EditeurImageScreen(
          image: widget.image,
          moi: widget.moi,
          lui: widget.lui,
        ),
      ),
    );
    if (modifiee == null || !mounted) return;
    Navigator.of(context).pop((renvoyer: modifiee));
  }
}
