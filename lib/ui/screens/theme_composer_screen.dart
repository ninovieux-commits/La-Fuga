/// Composeur de thèmes — portage de `ThemeComposerScreen` (main.py).
///
/// Cinq axes indépendants : on peut prendre les couleurs d'un thème, les
/// pièces d'un autre et le plateau d'un troisième. Chaque axe a son défilement
/// horizontal d'aperçus.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import '../widgets/profile_photo.dart';

/// Les cinq axes, dans l'ordre de Kivy.
const List<(String, String)> kThemeAxisLabels = [
  ('general', 'Général'),
  ('pieces', 'Pièces'),
  ('logo', 'Logo'),
  ('menu', 'Fond du menu'),
  ('board', 'Plateau'),
];

class ThemeComposerScreen extends StatefulWidget {
  const ThemeComposerScreen({super.key});

  @override
  State<ThemeComposerScreen> createState() => _ThemeComposerScreenState();
}

class _ThemeComposerScreenState extends State<ThemeComposerScreen> {
  late ThemeAxes _axes = Settings.instance.themeAxes;

  String _themeOf(String axis) => switch (axis) {
    'pieces' => _axes.pieces,
    'logo' => _axes.logo,
    'menu' => _axes.menu,
    'board' => _axes.board,
    _ => _axes.general,
  };

  void _pick(String axis, String theme) => setState(() {
    _axes = ThemeAxes(
      general: axis == 'general' ? theme : _axes.general,
      pieces: axis == 'pieces' ? theme : _axes.pieces,
      logo: axis == 'logo' ? theme : _axes.logo,
      menu: axis == 'menu' ? theme : _axes.menu,
      board: axis == 'board' ? theme : _axes.board,
    );
  });

  /// Applique la composition et la retient, ici et sur le compte.
  Future<void> _apply() async {
    final value = _axes.toString();
    await Settings.instance.setTheme(value);
    final online = OnlineService.instance;
    if (online.isLoggedIn) await online.client.setTheme(value);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(_axes.general);

    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Retour'),
              title: T('Composer le thème'),
              titleSize: 17,
              titleColor: Colors.white,
              bold: true,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(S(8)),
                children: [
                  for (final (axis, label) in kThemeAxisLabels)
                    _section(axis, label),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S(10), S(6), S(10), S(10)),
              child: FugaButton(
                text: T('Appliquer'),
                color: palette.clair,
                fontSize: SF(16),
                height: S(48),
                onPressed: _apply,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String axis, String label) {
    final selected = _themeOf(axis);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S(16), S(12), S(16), S(4)),
          child: Text(
            T(label),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: S(104),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: S(12)),
            children: [
              for (final theme in kThemeOrder)
                _cell(axis, theme, chosen: theme == selected),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(String axis, String theme, {required bool chosen}) {
    return GestureDetector(
      onTap: () => _pick(axis, theme),
      child: Container(
        width: S(78),
        margin: EdgeInsets.symmetric(horizontal: S(4), vertical: S(6)),
        padding: EdgeInsets.all(S(4)),
        decoration: BoxDecoration(
          color: chosen
              ? paletteOf(_axes.general).clair
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(S(10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: S(54), child: _preview(axis, theme)),
            SizedBox(height: S(4)),
            Text(
              T(kThemeLabels[theme] ?? theme),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: SF(10)),
            ),
          ],
        ),
      ),
    );
  }

  /// Aperçu d'un axe : ce que l'axe change, et rien d'autre.
  Widget _preview(String axis, String theme) {
    switch (axis) {
      case 'pieces':
        return ProfilePhoto(
          photo: '$theme|${PieceType.heritier.wire}',
          size: S(54),
        );
      case 'logo':
        return ProfilePhoto(photo: 'logo|$theme', size: S(54));
      case 'menu':
      case 'board':
        final images = imagesFor(theme);
        final asset = axis == 'menu' ? images?.background : images?.board;
        final palette = paletteOf(theme);
        return ClipRRect(
          borderRadius: BorderRadius.circular(S(8)),
          child: asset == null
              // Sans image, l'axe ne change qu'une couleur : on la montre.
              ? Container(color: axis == 'menu' ? palette.menu : palette.board)
              : Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  width: S(54),
                  height: S(54),
                ),
        );
      default:
        return _colorPreview(paletteOf(theme));
    }
  }

  /// Aperçu « général » : le foncé du thème, avec son clair au centre.
  Widget _colorPreview(ThemePalette palette) => Container(
    decoration: BoxDecoration(
      color: palette.fonce,
      borderRadius: BorderRadius.circular(S(8)),
    ),
    child: Center(
      child: Container(
        width: S(24),
        height: S(24),
        decoration: BoxDecoration(
          color: palette.clair,
          borderRadius: BorderRadius.circular(S(5)),
        ),
      ),
    ),
  );
}
