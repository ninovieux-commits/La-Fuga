/// Photo de profil — portage de `parse_photo`, `PiecePhoto` et
/// `draw_profile_piece` (main.py).
///
/// Une photo est un mot : `thème|Type`, `thème|Type|Noir`, `logo|thème`, ou
/// `deepgrey` pour l'image dédiée de l'IA. Rien de tout cela n'est un fichier
/// envoyé au serveur : on n'échange qu'un identifiant, et chaque appareil
/// dessine la pièce avec ses propres images.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../theme/themes.dart';
import 'logo_painter.dart';
import 'piece_painter.dart';
import 'theme_image_cache.dart';

/// Photo par défaut : le logo du thème original.
const String kDefaultPhoto = 'logo|original';

/// Photo de Deep Grey, qui a son image à elle.
const String kDeepGreyPhoto = 'deepgrey';

/// Les pièces qu'on peut prendre comme photo.
const List<PieceType> kProfilePieces = [
  PieceType.heritier,
  PieceType.nurse,
  PieceType.garde,
  PieceType.soldat,
  PieceType.chevalier,
];

/// Quelques thèmes ont un logo au nom différent du leur.
const Map<String, String> _logoAliases = {
  'medieval': 'bataille',
  'fleur': 'fleurs',
  'insectes': 'foret',
};

/// Chemin du logo d'un thème.
String logoAssetOf(String theme) =>
    'assets/logos/logo_${_logoAliases[theme] ?? theme}.webp';

/// Une photo lue : un thème, une pièce, un camp.
typedef PhotoParts = ({String theme, PieceType piece, Camp camp});

/// Lit une photo. Tout ce qui n'est pas reconnu retombe sur l'Héritier blanc
/// du thème original — jamais d'erreur, jamais de trou à l'écran.
PhotoParts parsePhoto(String? photo) {
  var theme = kDefaultTheme;
  var piece = PieceType.heritier;
  var camp = Camp.blanc;

  final parts = (photo ?? '').split('|');
  if (parts.length >= 2) {
    if (kThemes.containsKey(parts[0])) theme = parts[0];
    for (final p in kProfilePieces) {
      if (p.wire == parts[1]) piece = p;
    }
    if (parts.length >= 3 && parts[2] == 'Noir') camp = Camp.noir;
  }
  return (theme: theme, piece: piece, camp: camp);
}

/// Vrai si la photo est un logo de thème (`logo|<thème>`).
bool isLogoPhoto(String? photo) => (photo ?? '').startsWith('logo|');

/// Le thème d'une photo de logo.
String logoThemeOf(String photo) {
  final name = photo.split('|').elementAtOrNull(1) ?? kDefaultTheme;
  return kThemes.containsKey(name) ? name : kDefaultTheme;
}

/// Affiche une photo de profil, carrée.
///
/// Portage de `PiecePhoto._redraw`, sans le carré de fond de Kivy : la pièce,
/// le logo ou l'image de Deep Grey se posent directement sur la page.
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({super.key, required this.photo, this.size = 64});

  final String? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = (photo == null || photo!.isEmpty) ? kDefaultPhoto : photo!;

    if (value == kDeepGreyPhoto) {
      return Image.asset(
        'assets/images/deepgrey.webp',
        width: size,
        height: size,
        fit: BoxFit.contain,
        // Image manquante : on montre le logo plutôt qu'une icône cassée.
        errorBuilder: (_, __, ___) =>
            _logo(kDefaultTheme, paletteOf(kDefaultTheme)),
      );
    }

    if (isLogoPhoto(value)) {
      final theme = logoThemeOf(value);
      return Image.asset(
        logoAssetOf(theme),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _logo(theme, paletteOf(theme)),
      );
    }

    final parts = parsePhoto(value);
    // Les thèmes à images décodent leurs fichiers une fois ; tant que ce n'est
    // pas fait, la pièce se dessine géométriquement plutôt que de clignoter.
    return SizedBox(
      width: size,
      height: size,
      child: ThemeImagesBuilder(
        theme: parts.theme,
        builder: (context, images) => CustomPaint(
          painter: _PiecePhotoPainter(
            piece: Piece(parts.piece, parts.camp),
            palette: paletteOf(parts.theme),
            images: images,
            // Sans le thème, les rendus spéciaux — le corps gris de deepgrey,
            // les accents de l'arc-en-ciel — sont perdus : la photo sort aux
            // couleurs d'un thème quelconque.
            theme: parts.theme,
          ),
        ),
      ),
    );
  }

  /// Repli dessiné : la rosace du thème.
  Widget _logo(String theme, ThemePalette palette) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _LogoPhotoPainter(palette)),
  );
}

/// Grossissement de certaines pièces en photo de profil.
///
/// Sur le plateau, une pièce se lit par rapport à ses voisines. Seule dans un
/// carré de photo de profil, une image dont le sujet occupe peu de place
/// paraît minuscule — c'est le cas de la nurse du thème insectes, la
/// coccinelle. On la grossit dans le MÊME cadre : c'est un zoom, pas un
/// débordement, et rien ne mord sur ce qu'il y a autour.
const Map<(String, PieceType), double> kProfileZoom = {
  ('insectes', PieceType.nurse): 1.15,
};

/// Combien grossir cette pièce en photo de profil. 1 : pas de grossissement.
double profileZoomFor(String? theme, PieceType piece) =>
    kProfileZoom[(theme ?? '', piece)] ?? 1;

/// Dessine la pièce d'une photo de profil dans [frame].
///
/// Le cadre reste celui qu'on lui donne : un grossissement se fait à
/// l'intérieur, l'excédent est coupé.
void paintProfilePiece(
  Canvas canvas,
  Rect frame,
  Piece piece,
  ThemePalette palette, {
  LoadedThemeImages? images,
  String? theme,
}) {
  final zoom = profileZoomFor(theme, piece.type);
  if (zoom == 1) {
    paintPiece(canvas, frame, piece, palette, images: images, theme: theme);
    return;
  }
  canvas.save();
  canvas.clipRect(frame);
  paintPiece(
    canvas,
    Rect.fromCenter(
      center: frame.center,
      width: frame.width * zoom,
      height: frame.height * zoom,
    ),
    piece,
    palette,
    images: images,
    theme: theme,
  );
  canvas.restore();
}

class _PiecePhotoPainter extends CustomPainter {
  const _PiecePhotoPainter({
    required this.piece,
    required this.palette,
    this.images,
    this.theme,
  });

  final Piece piece;
  final ThemePalette palette;
  final LoadedThemeImages? images;

  /// Thème de la photo — `deepgrey` et `arcenciel` ont leur propre rendu.
  final String? theme;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    paintProfilePiece(
      canvas,
      Rect.fromLTWH(
        (size.width - side) / 2,
        (size.height - side) / 2,
        side,
        side,
      ),
      piece,
      palette,
      images: images,
      theme: theme,
    );
  }

  @override
  bool shouldRepaint(_PiecePhotoPainter old) =>
      old.piece != piece ||
      old.palette != palette ||
      old.images != images ||
      old.theme != theme;
}

class _LogoPhotoPainter extends CustomPainter {
  const _LogoPhotoPainter(this.palette);

  final ThemePalette palette;

  @override
  void paint(Canvas canvas, Size size) => paintLogo(
    canvas,
    size.width / 2,
    size.height / 2,
    size.shortestSide / 2,
    clair: palette.clair,
    fonce: palette.fonce,
  );

  @override
  bool shouldRepaint(_LogoPhotoPainter old) => old.palette != palette;
}
