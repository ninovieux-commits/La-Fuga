/// Galerie des photos de profil — portage de `_open_photo_picker` (main.py).
///
/// Tout est rangé dans le même ordre qu'en Kivy : Deep Grey, puis le logo de
/// chaque thème, puis toutes les pièces de chaque thème, blanche puis noire.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/profile_photo.dart';

/// Toutes les photos proposées, dans l'ordre.
List<String> photoChoices() => [
  kDeepGreyPhoto,
  for (final theme in kThemes.keys) 'logo|$theme',
  for (final theme in kThemes.keys)
    for (final piece in kProfilePieces) ...[
      '$theme|${piece.wire}',
      '$theme|${piece.wire}|${Camp.noir.wire}',
    ],
];

class PhotoPickerScreen extends StatelessWidget {
  const PhotoPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final choices = photoChoices();

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(T('Choisis ta photo de profil')),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: choices.length,
        itemBuilder: (context, i) => InkWell(
          onTap: () => Navigator.of(context).pop(choices[i]),
          child: ProfilePhoto(photo: choices[i], size: 64),
        ),
      ),
    );
  }
}
