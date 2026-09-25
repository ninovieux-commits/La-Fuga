/// Menu de l'historique — portage de `PartiesMenuScreen` (main.py).
///
/// Trois boutons : les parties du compte, celles de l'appareil, et le lecteur
/// de fichiers `.nmc`.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import 'history_screen.dart';
import 'reader_screen.dart';

class PartiesMenuScreen extends StatelessWidget {
  const PartiesMenuScreen({super.key, required this.online});

  final OnlineService online;

  Future<void> _push(BuildContext context, Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// L'historique en ligne demande un compte : sinon Kivy explique pourquoi.
  Future<void> _openOnline(BuildContext context) async {
    if (!online.isLoggedIn) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: kFugaGrey,
          content: Text(
            T('Connectez-vous à un compte\npour voir vos parties en ligne.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: SF(15)),
          ),
          actions: [
            FugaButton(
              text: T('OK'),
              color: paletteOf(Settings.instance.themeAxes.general).fonce,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
      return;
    }
    if (context.mounted) {
      await _push(context, HistoryScreen(online: online));
    }
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);

    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Menu'),
              title: T('Historique'),
              titleSize: 32,
              onBack: () => Navigator.of(context).pop(),
            ),
            // Kivy place les trois boutons à 85 %, 70 % et 55 % de la hauteur,
            // sur 80 % de la largeur.
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    for (final (fraction, label, color, action)
                        in <(double, String, Color, VoidCallback)>[
                          (
                            0.85,
                            T('Historique en ligne'),
                            palette.fonce,
                            () => _openOnline(context),
                          ),
                          (
                            0.70,
                            T('Historique en local'),
                            palette.clair,
                            () => _push(
                              context,
                              HistoryScreen(
                                online: online,
                                mode: HistoryMode.local,
                              ),
                            ),
                          ),
                          (
                            0.55,
                            T('Lecteur nmc'),
                            kFugaGrey,
                            () => _push(context, const ReaderScreen()),
                          ),
                        ])
                      Positioned(
                        top: box.maxHeight * (1 - fraction),
                        left: box.maxWidth * 0.1,
                        width: box.maxWidth * 0.8,
                        height: touchHeight(),
                        child: FugaButton(
                          text: label,
                          color: color,
                          fontSize: SF(17),
                          height: double.infinity,
                          onPressed: action,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
