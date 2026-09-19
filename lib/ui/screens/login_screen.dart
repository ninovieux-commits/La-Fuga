/// Connexion et inscription — portage de `LoginScreen` (main.py).
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.online});

  final OnlineService online;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pseudo = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pseudo.dispose();
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pseudoError = validatePseudo(_pseudo.text);
    if (pseudoError != null) {
      setState(() => _error = pseudoError);
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = T('Mot de passe'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final error = _registering
        ? await widget.online.register(
            _pseudo.text,
            _password.text,
            email: _email.text,
          )
        : await widget.online.login(_pseudo.text, _password.text);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(_registering ? T('Inscription') : T('Connexion')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pseudo,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: T('Pseudo'),
                border: const OutlineInputBorder(),
                helperText: '3–20 · A-Z a-z 0-9 _ -',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: T('Mot de passe'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_registering) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: T('Email (optionnel)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: FugaColors.immobile)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.clair,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_registering ? T("S'inscrire") : T('Se connecter')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _registering = !_registering;
                      _error = null;
                    }),
              child: Text(
                _registering ? T('Connexion') : T('Inscription'),
                style: TextStyle(color: palette.clair),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
