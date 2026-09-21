/// Galerie des photos de profil — portage de `_open_photo_picker` (main.py).
///
/// Tout est rangé dans le même ordre qu'en Kivy : Deep Grey, puis le logo de
/// chaque thème, puis toutes les pièces de chaque thème, blanche puis noire.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/profile_photo.dart';

/// Toutes les photos proposées, dans l'ordre.
List<String> photoChoices() => [
  kDeepGreyPhoto,
  for (final theme in kThemeOrder) 'logo|$theme',
  for (final theme in kThemeOrder)
    for (final piece in kProfilePieces) ...[
      '$theme|${piece.wire}',
      '$theme|${piece.wire}|${Camp.noir.wire}',
    ],
];

class PhotoPickerScreen extends StatelessWidget {
  const PhotoPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final choices = photoChoices();

    // Kivy l'ouvre en popup : un titre, une grille de quatre colonnes, et
    // « Fermer » en bas.
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
              child: GridView.builder(
                padding: EdgeInsets.all(S(4)),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: choices.length,
                itemBuilder: (context, i) => InkWell(
                  onTap: () => Navigator.of(context).pop(choices[i]),
                  child: Center(
                    child: ProfilePhoto(photo: choices[i], size: S(64)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(S(10)),
              child: FugaButton(
                text: T('Fermer'),
                fontSize: SF(15),
                height: S(52),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
