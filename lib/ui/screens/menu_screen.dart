/// Menu principal — portage de `MenuScreen` (main.py).
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../game/clock.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';
import '../../net/online_service.dart';
import 'correspondence_screen.dart';
import 'game_screen.dart';
import 'online_lobby_screen.dart';
import 'settings_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  ThemeAxes get _axes => Settings.instance.themeAxes;

  Future<void> _playAgainstDeepGrey() async {
    final choice = await showModalBottomSheet<_GameChoice>(
      context: context,
      backgroundColor: paletteOf(_axes.general).menu,
      isScrollControlled: true,
      builder: (_) => const _GameSetupSheet(),
    );
    if (choice == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: choice.cadence,
          // Le joueur choisit SA couleur : Deep Grey prend l'autre.
          aiCamp: choice.playerCamp.opposite,
          aiDeepMode: choice.deepMode,
          themeName: _axes.general,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _playLocal() async {
    final choice = await showModalBottomSheet<_GameChoice>(
      context: context,
      backgroundColor: paletteOf(_axes.general).menu,
      isScrollControlled: true,
      builder: (_) => const _GameSetupSheet(local: true),
    );
    if (choice == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: choice.cadence,
          aiCamp: null, // deux joueurs sur le même appareil
          themeName: _axes.general,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _playOnline() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineLobbyScreen(online: OnlineService.instance),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _playCorrespondence() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CorrespondenceScreen(online: OnlineService.instance),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    if (mounted) setState(() {});
  }

  void _showStory() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paletteOf(_axes.menu).menu,
        title: Text(T("L'histoire de La Fuga")),
        content: SingleChildScrollView(child: Text(Translations.current.story)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(T('Fermer')),
          ),
        ],
      ),
    );
  }

  /// Fonctionnalité pas encore portée : on le dit, plutôt que d'offrir un
  /// bouton qui ne fait rien.
  void _notYet(String what) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what — ${T("Bientôt")}')));
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(_axes.general);
    final menuPalette = paletteOf(_axes.menu);

    // Fond d'écran du thème, quand il en a un. Sinon la couleur du thème.
    final background = imagesFor(_axes.menu)?.background;

    return Scaffold(
      backgroundColor: menuPalette.menu,
      body: Container(
        decoration: background == null
            ? null
            : BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(background),
                  fit: BoxFit.cover,
                ),
              ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _title(palette),
                const SizedBox(height: 24),
                _button(
                  palette,
                  T('Jouer contre Deep Grey'),
                  onTap: _playAgainstDeepGrey,
                  primary: true,
                ),
                _button(palette, T('Jouer en local'), onTap: _playLocal),
                _button(palette, T('Jouer en ligne'), onTap: _playOnline),
                _button(
                  palette,
                  T('Correspondance'),
                  onTap: _playCorrespondence,
                ),
                const SizedBox(height: 16),
                _button(palette, T('Tuto'), onTap: () => _notYet(T('Tuto'))),
                _button(
                  palette,
                  T('Historique'),
                  onTap: () => _notYet(T('Historique')),
                ),
                _button(
                  palette,
                  T('Mon compte'),
                  onTap: () => _notYet(T('Mon compte')),
                ),
                _button(palette, T('Réglages'), onTap: _openSettings),
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: _showStory,
                    child: Text(
                      T("L'histoire de La Fuga"),
                      style: TextStyle(color: palette.clair),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(ThemePalette palette) {
    return Column(
      children: [
        GestureDetector(
          onTap: _showStory,
          child: Image.asset(
            'assets/logos/logo_${_axes.logo}.png',
            height: 120,
            // Tous les thèmes n'ont pas leur logo : on retombe sur celui
            // d'origine plutôt que d'afficher une icône cassée.
            errorBuilder: (_, __, ___) =>
                Image.asset('assets/logos/logo_original.png', height: 120),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'La Fuga',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.clair,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _button(
    ThemePalette palette,
    String label, {
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: primary ? palette.clair : FugaColors.buttonGrey,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Choix faits avant de lancer une partie.
final class _GameChoice {
  const _GameChoice({
    required this.cadence,
    required this.playerCamp,
    required this.deepMode,
  });

  final Cadence cadence;

  /// Camp du joueur humain.
  final Camp playerCamp;

  /// Mode profond de Deep Grey.
  final bool deepMode;
}

/// Feuille de réglages d'une partie : couleur, cadence, force de l'IA.
class _GameSetupSheet extends StatefulWidget {
  const _GameSetupSheet({this.local = false});

  /// Partie locale à deux : le choix de couleur ne s'applique pas.
  final bool local;

  @override
  State<_GameSetupSheet> createState() => _GameSetupSheetState();
}

class _GameSetupSheetState extends State<_GameSetupSheet> {
  Cadence _cadence = Cadence.illimitee;
  Camp _camp = Camp.blanc;
  bool _deep = false;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(Settings.instance.themeAxes.general);

    // Défilable : sur un petit écran, couleur + cadence + interrupteur +
    // bouton dépassent la hauteur de la feuille, et « Jouer » deviendrait
    // inatteignable.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.local) ...[
            Text(
              T('Choisissez votre couleur'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<Camp>(
              segments: [
                ButtonSegment(
                  value: Camp.blanc,
                  label: Text(T('Jouer avec les Blancs')),
                ),
                ButtonSegment(
                  value: Camp.noir,
                  label: Text(T('Jouer avec les Noirs')),
                ),
              ],
              selected: {_camp},
              onSelectionChanged: (s) => setState(() => _camp = s.first),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            T('Cadence (min / joueur)'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in Cadence.toutes)
                ChoiceChip(
                  label: Text(
                    c == Cadence.illimitee ? T('Zen (illimité)') : c.label,
                  ),
                  selected: _cadence == c,
                  onSelected: (_) => setState(() => _cadence = c),
                ),
            ],
          ),
          if (!widget.local) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(T('Deep Grey')),
              subtitle: Text(
                _deep ? T('Réflexion profonde') : T('Réflexion normale'),
              ),
              value: _deep,
              onChanged: (v) => setState(() => _deep = v),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.clair),
            onPressed: () => Navigator.of(context).pop(
              _GameChoice(
                cadence: _cadence,
                playerCamp: _camp,
                deepMode: _deep,
              ),
            ),
            child: Text(T('Jouer')),
          ),
        ],
      ),
    );
  }
}
