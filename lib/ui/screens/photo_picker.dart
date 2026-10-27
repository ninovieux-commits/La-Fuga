/// Galerie des photos de profil — portage de `_open_photo_picker` (main.py).
///
/// ## Rangée PAR THÈME, comme le choix d'une image à envoyer
///
/// Kivy alignait Deep Grey, puis les dix-sept logos à la file, puis les cent
/// soixante-dix pièces : quatre colonnes de ronds colorés où l'on ne savait
/// plus à quel thème on en était. Nino : « les images doivent être rangées comme
/// sur l'image précédente » — celle du panneau des messages, un bloc par
/// thème. Les deux écrans partagent donc `GrilleDesPhotos`.
///
/// « L'image de profil de deep grey doit être rangée tout à la fin, avec les
/// images du thème deepgrey » : elle ferme la dernière section.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/grille_photos.dart';

/// Toutes les photos proposées, dans l'ordre où la galerie les montre.
List<String> photoChoices() => photosDuCatalogue();

class PhotoPickerScreen extends StatelessWidget {
  const PhotoPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Kivy l'ouvre en popup : un titre, la grille, et « Fermer » en bas.
    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(S(10)),
              child: Text(
                T('Choisis ta photo de profil'),
                style: TextStyle(
                  fontSize: SF(16),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(S(4)),
                child: GrilleDesPhotos(
                  cote: S(52),
                  onChoisie: (photo) => Navigator.of(context).pop(photo),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(S(10)),
              child: FugaButton(
                text: T('Fermer'),
                fontSize: SF(15),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
