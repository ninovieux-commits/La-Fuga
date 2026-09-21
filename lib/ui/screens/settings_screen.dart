/// Réglages — portage d'`open_settings_popup` (main.py).
///
/// L'ordre et le contenu sont ceux de Kivy : langue (depuis le menu
/// seulement), volume, instrument, vitesse de glissée, thème avec son aperçu,
/// puis « Appliquer ce thème » et « Fermer ». Le thème ne s'applique qu'au
/// bouton : on peut se promener dans la liste sans rien changer.
///
/// Kivy n'offre PAS de réglage d'adresse de serveur — il efface même celle
/// qu'un vieux fichier de configuration aurait gardée. On n'en met donc pas.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../game/sound_plan.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/theme_preview.dart';
import 'theme_composer_screen.dart';

/// Nom affiché de chaque instrument — `INSTRUMENT_LABELS` de Kivy.
const Map<String, String> kInstrumentLabels = {
  'piano': 'Piano',
  'orgue': 'Orgue',
  'guitare': 'Guitare',
  'cloche': 'Cloche',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.fromMenu = true});

  /// Kivy ne montre la langue et le composeur de thèmes que depuis le menu :
  /// changer de langue en cours de partie reconstruirait l'écran sous les
  /// pieds du joueur.
  final bool fromMenu;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Settings get _settings => Settings.instance;

  /// Un lecteur à part : l'aperçu d'instrument ne doit pas couper les sons
  /// d'une partie en cours.
  final SoundPlayer _preview = SoundPlayer();

  late int _themeIndex = _indexOf(kThemeOrder, _settings.themeAxes.general);
  late int _langIndex = _indexOf(
    kLanguageLabels.keys.toList(),
    _settings.language,
  );
  late int _instrumentIndex = _indexOf(kInstruments, _settings.instrument);

  static int _indexOf(List<String> list, String value) {
    final i = list.indexOf(value);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _preview.setInstrument(_settings.instrument);
    _preview.setVolume(_settings.volume);
    unawaited(_preview.init());
  }

  @override
  void dispose() {
    unawaited(_preview.dispose());
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _applyLanguage() async {
    await _settings.setLanguage(kLanguageLabels.keys.elementAt(_langIndex));
    if (mounted) setState(() {});
  }

  Future<void> _setInstrument(int delta) async {
    setState(() {
      _instrumentIndex = (_instrumentIndex + delta) % kInstruments.length;
      if (_instrumentIndex < 0) _instrumentIndex += kInstruments.length;
    });
    final name = kInstruments[_instrumentIndex];
    await _settings.setInstrument(name);
    // Kivy joue un do pour faire entendre l'instrument choisi.
    _preview.setInstrument(name);
    _preview.setVolume(_settings.volume);
    _preview.play(const [SoundCue('do4', Duration.zero)]);
  }

  /// Applique le thème choisi, et le retient sur le compte : on le retrouve
  /// depuis un autre appareil.
  Future<void> _applyTheme() async {
    final name = kThemeOrder[_themeIndex];
    await _settings.setTheme(ThemeAxes.uniform(name).toString());
    final online = OnlineService.instance;
    if (online.isLoggedIn) await online.client.setTheme(name);
    if (mounted) setState(() {});
  }

  /// Étiquette de la vitesse de glissée — `speed_text` de Kivy.
  String _speedLabel(double v) {
    if (v < 0.02) return T('Instantané');
    if (v < 0.20) return T('Rapide');
    if (v < 0.40) return T('Moyen');
    return T('Lent');
  }

  // ── Affichage ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final axes = _settings.themeAxes;
    final palette = paletteOf(axes.general);

    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(S(16), S(12), S(16), S(4)),
              child: Text(
                T('Réglages'),
                style: TextStyle(
                  fontSize: SF(20),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(S(16), S(6), S(16), S(6)),
                children: [
                  if (widget.fromMenu) ...[
                    _label(T('Langue'), size: S(15)),
                    _selector(
                      kLanguageLabels.values.elementAt(_langIndex),
                      (d) => setState(() {
                        _langIndex = (_langIndex + d) % kLanguageLabels.length;
                        if (_langIndex < 0) {
                          _langIndex += kLanguageLabels.length;
                        }
                      }),
                    ),
                    SizedBox(height: S(6)),
                    FugaButton(
                      text: T('Valider la langue'),
                      color: palette.clair,
                      fontSize: SF(14),
                      height: S(52),
                      onPressed: _applyLanguage,
                    ),
                  ],

                  _label(T('Volume')),
                  Slider(
                    value: _settings.volume,
                    activeColor: palette.clair,
                    onChanged: (v) async {
                      await _settings.setVolume(v);
                      _preview.setVolume(v);
                      if (mounted) setState(() {});
                    },
                  ),
                  _sub('${(_settings.volume * 100).round()}%'),

                  _selector(
                    T(kInstrumentLabels[kInstruments[_instrumentIndex]] ?? ''),
                    _setInstrument,
                  ),

                  _label(T('Vitesse de glissée des pièces')),
                  Slider(
                    value: _settings.slideSpeed.clamp(0.0, 0.6),
                    max: 0.6,
                    activeColor: palette.clair,
                    onChanged: (v) async {
                      await _settings.setSlideSpeed(v);
                      if (mounted) setState(() {});
                    },
                  ),
                  _sub(_speedLabel(_settings.slideSpeed)),

                  _label(T('Thème')),
                  SizedBox(
                    height: S(80),
                    child: Row(
                      children: [
                        _arrow('<', () => _moveTheme(-1)),
                        Expanded(
                          flex: 32,
                          child: Center(
                            child: Text(
                              T(
                                kThemeLabels[kThemeOrder[_themeIndex]] ??
                                    kThemeOrder[_themeIndex],
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: SF(14),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 36,
                          child: ThemePreview(theme: kThemeOrder[_themeIndex]),
                        ),
                        _arrow('>', () => _moveTheme(1)),
                      ],
                    ),
                  ),

                  // « Appliquer » juste sous l'aperçu : c'est lui qu'on
                  // regarde quand on décide.
                  SizedBox(height: S(6)),
                  FugaButton(
                    text: T('Appliquer ce thème'),
                    color: palette.clair,
                    fontSize: SF(14),
                    height: S(52),
                    onPressed: _applyTheme,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S(16), S(4), S(16), S(12)),
              child: Row(
                children: [
                  // Composer un thème ne se fait que depuis le menu : en
                  // pleine partie, l'écran se reconstruirait sous les pieds
                  // du joueur.
                  if (widget.fromMenu) ...[
                    Expanded(
                      flex: 72,
                      child: FugaButton(
                        text: T('Composer le thème'),
                        color: palette.fonce,
                        fontSize: SF(14),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<bool>(
                              builder: (_) => const ThemeComposerScreen(),
                            ),
                          );
                          if (!mounted) return;
                          setState(
                            () => _themeIndex = _indexOf(
                              kThemeOrder,
                              _settings.themeAxes.general,
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(width: S(8)),
                  ],
                  Expanded(
                    flex: widget.fromMenu ? 28 : 100,
                    child: FugaButton(
                      text: T('Fermer'),
                      fontSize: SF(14),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveTheme(int delta) => setState(() {
    _themeIndex = (_themeIndex + delta) % kThemeOrder.length;
    if (_themeIndex < 0) _themeIndex += kThemeOrder.length;
  });

  Widget _label(String text, {double size = 17}) => Padding(
    padding: EdgeInsets.only(top: S(10), bottom: S(2)),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  );

  Widget _sub(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: SF(13),
      color: const Color.fromRGBO(217, 217, 217, 1),
    ),
  );

  /// Ligne `<  valeur  >` : le sélecteur de Kivy, partout le même.
  Widget _selector(String value, void Function(int delta) onMove) => SizedBox(
    height: S(44),
    child: Row(
      children: [
        _arrow('<', () => onMove(-1)),
        Expanded(
          flex: 68,
          child: Center(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: SF(15),
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        _arrow('>', () => onMove(1)),
      ],
    ),
  );

  Widget _arrow(String text, VoidCallback onPressed) => Expanded(
    flex: 16,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: S(3)),
      child: FugaButton(
        text: text,
        fontSize: SF(16),
        height: double.infinity,
        onPressed: onPressed,
      ),
    ),
  );
}
