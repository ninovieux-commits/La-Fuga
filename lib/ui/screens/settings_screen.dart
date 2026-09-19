/// Réglages — portage de `open_settings_popup` (main.py).
library;

import 'package:flutter/material.dart';

import '../../game/sound_plan.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Settings get _settings => Settings.instance;

  Future<void> _setLanguage(String code) async {
    await _settings.setLanguage(code);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final axes = _settings.themeAxes;
    final palette = paletteOf(axes.general);

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(T('Réglages')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(T('Thème')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kThemeLabels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: axes.general == entry.key,
                  // Le thème se règle ici sur les cinq axes à la fois. La
                  // composition axe par axe viendra avec le composeur de
                  // thèmes.
                  onSelected: (_) async {
                    await _settings.setTheme(
                      ThemeAxes.uniform(entry.key).toString(),
                    );
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),

          _section(T('Langue')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kLanguageLabels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _settings.language == entry.key,
                  onSelected: (_) => _setLanguage(entry.key),
                ),
            ],
          ),

          _section(T('Son')),
          Text(T('Instrument')),
          Wrap(
            spacing: 8,
            children: [
              for (final name in kInstruments)
                ChoiceChip(
                  label: Text(name),
                  selected: _settings.instrument == name,
                  onSelected: (_) async {
                    await _settings.setInstrument(name);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('${T('Volume')} : ${(_settings.volume * 100).round()} %'),
          Slider(
            value: _settings.volume,
            activeColor: palette.clair,
            onChanged: (v) async {
              await _settings.setVolume(v);
              if (mounted) setState(() {});
            },
          ),

          _section(T('Animation')),
          Text(
            '${T('Vitesse de glissement')} : '
            '${_settings.slideSpeed.toStringAsFixed(2)} s',
          ),
          Slider(
            value: _settings.slideSpeed,
            max: 0.6,
            activeColor: palette.clair,
            onChanged: (v) async {
              await _settings.setSlideSpeed(v);
              if (mounted) setState(() {});
            },
          ),
          Text(
            T('0 = instantané'),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),

          _section(T('Serveur')),
          TextFormField(
            initialValue: _settings.serverUrl,
            decoration: InputDecoration(
              labelText: T('Adresse du serveur'),
              border: const OutlineInputBorder(),
            ),
            onFieldSubmitted: (v) async {
              await _settings.setServerUrl(v);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Text(
            T('Permet de viser un autre serveur sans recompiler.'),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
}
