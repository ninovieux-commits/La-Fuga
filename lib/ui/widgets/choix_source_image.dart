/// « Appareil photo » ou « Photos » : d'où vient l'image qu'on envoie.
///
/// Nino : « quand on appuie sur l'enveloppe avec le +, ça nous demande
/// [appareil photo] ou [photos] avec les petites icônes habituelles (les
/// mêmes que quand je veux t'envoyer une photo). »
///
/// L'image revient DÉJÀ RÉDUITE : c'est le greffon qui s'en charge, avec le
/// décodeur du système, et c'est ce qui permet au serveur de ne jamais
/// décoder quoi que ce soit. Voir `docs/ENVELOPPES.md`.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../game/enveloppe.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'fuga_popup.dart';

/// Qualité JPEG demandée au greffon. Quatre-vingts : la limite au-delà de
/// laquelle le poids monte vite sans que l'œil y gagne.
const int kQualiteEnveloppe = 80;

/// Ce qui ouvre l'appareil photo et la galerie. Injectable : un test n'a ni
/// caméra ni pellicule.
typedef ChoisisseurImage =
    Future<XFile?> Function({
      required ImageSource source,
      double? maxWidth,
      double? maxHeight,
      int? imageQuality,
    });

ChoisisseurImage _choisisseur = ImagePicker().pickImage;

/// Pour les tests : on remplace le greffon par une fonction qui rend ce
/// qu'on veut, et on le remet après.
void poseLeChoisisseurDImage(ChoisisseurImage? remplacant) =>
    _choisisseur = remplacant ?? ImagePicker().pickImage;

/// Demande la source, ouvre ce qu'il faut, et rend les octets de l'image.
///
/// Nul si l'on a refermé sans choisir, ou si rien n'a été pris.
Future<Uint8List?> choisirUneImage(
  BuildContext context, {
  required ThemePalette palette,
}) async {
  final source = await showFugaPopup<ImageSource>(
    context,
    widthFactor: 0.8,
    heightFactor: 0.34,
    rows: [
      (0.34, popupText(T('Envoyer une image'), size: 17, bold: true)),
      (
        kTouchRow,
        Row(
          children: [
            Expanded(
              child: FugaButton(
                enfant: _choix(
                  Icons.photo_camera,
                  T('Appareil photo'),
                  Colors.white,
                ),
                color: palette.fonce,
                onPressed: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ),
            SizedBox(width: S(8)),
            Expanded(
              child: FugaButton(
                enfant: _choix(Icons.photo_library, T('Photos'), Colors.black),
                color: palette.clair,
                onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  if (source == null) return null;

  final prise = await _choisisseur(
    source: source,
    // 720p : le plus grand côté. Une photo de téléphone en 12 mégapixels
    // devient 300 Ko sans qu'on la regarde de moins près.
    maxWidth: kEnveloppeCote.toDouble(),
    maxHeight: kEnveloppeCote.toDouble(),
    imageQuality: kQualiteEnveloppe,
  );
  if (prise == null) return null;
  return prise.readAsBytes();
}

/// Une icône et son mot, comme partout ailleurs quand on choisit une photo.
///
/// L'encre est donnée : une touche porte la couleur claire du thème, l'autre
/// la foncée, et le noir ne se lit pas sur l'une comme sur l'autre.
Widget _choix(IconData icone, String mot, Color encre) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icone, size: SF(18), color: encre),
    SizedBox(width: S(6)),
    Flexible(
      child: Text(
        mot,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: SF(14),
          fontWeight: FontWeight.bold,
          color: encre,
        ),
      ),
    ),
  ],
);
