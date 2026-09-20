/// Lecteur `.nmc` — portage de `ReaderScreen` (main.py).
///
/// On colle le contenu d'un fichier et le bouton « Lire » ouvre la partie en
/// relecture. Un contenu illisible ne mène nulle part : Kivy affiche une
/// erreur et reste sur place.
library;

import 'package:flutter/material.dart';

import '../../game/replay_controller.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import 'replay_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final text = _input.text.trim();
    if (text.isEmpty || !isReadableNmc(text)) {
      await _showError();
      return;
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReplayScreen(nmc: text)));
  }

  Future<void> _showError() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      title: Text(T('Erreur'), style: const TextStyle(color: Colors.white)),
      content: Text(
        T(
          'désolé, le fichier nmc est invalide,\nla lecture ne peut pas s effectuer',
        ),
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(T('OK')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);

    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Historique'),
              title: T('Lecteur nmc'),
              titleSize: 26,
              onBack: () => Navigator.of(context).pop(),
            ),
            SizedBox(
              height: 30,
              child: Center(
                child: Text(
                  T("Collez le contenu d'un fichier .nmc ci-dessous :"),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color.fromRGBO(26, 26, 26, 1),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: TextField(
                  controller: _input,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 13, color: Colors.black),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    hintText:
                        '[Date "..."]\n[Joueur1 "..."]\n...\n\n'
                        '1.Do1-Do2/Do8-Do7  2...',
                    hintMaxLines: 5,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: FugaButton(
                text: T('Lire'),
                color: palette.clair,
                height: 50,
                onPressed: _read,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
