/// Connexion et inscription — portage de `LoginScreen` (main.py).
///
/// Un seul écran pour les deux : le bouton du haut bascule entre « Pas encore
/// inscrit ? » et « J'ai déjà un compte », et la page change de titre, de
/// bouton et de champs.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../net/push_notifications.dart';
import '../../state/local_games.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/fuga_button.dart';

class LoginScreen extends StatefulWidget {
  LoginScreen({super.key, required this.online, LocalGamesStore? local})
    : local = local ?? LocalGamesStore();

  final OnlineService online;

  /// Parties de l'appareil, effacées à la connexion. Injectable pour les
  /// tests.
  final LocalGamesStore local;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pseudo = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  bool _passwordShown = false;

  /// Ligne d'état sous le bouton : rouge pour une erreur, bleue pendant
  /// l'attente, verte au succès — comme `status_lbl`.
  String _status = '';
  Color _statusColor = const Color.fromRGBO(179, 26, 26, 1);

  @override
  void dispose() {
    _pseudo.dispose();
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  void _toggleMode() => setState(() {
    _registering = !_registering;
    _status = '';
  });

  Future<void> _submit() async {
    final pseudo = _pseudo.text.trim();
    final password = _password.text;
    if (pseudo.isEmpty || password.isEmpty) {
      setState(() {
        _statusColor = const Color.fromRGBO(179, 26, 26, 1);
        _status = T('Pseudo et mot de passe requis');
      });
      return;
    }

    setState(() {
      _busy = true;
      _statusColor = const Color.fromRGBO(51, 51, 128, 1);
      _status = T('Connexion au serveur...');
    });

    final error = _registering
        ? await widget.online.register(
            pseudo,
            password,
            email: _email.text.trim(),
          )
        : await widget.online.login(pseudo, password);

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _statusColor = const Color.fromRGBO(179, 26, 26, 1);
        _status = error;
      });
      return;
    }

    // Le compte est ouvert : le serveur peut désormais associer le jeton de
    // notification de cet appareil.
    unawaited(PushNotifications.sendPendingToken());

    // Le jeu est pensé pour être connecté : les parties jouées hors compte
    // sont effacées, l'historique vient désormais du compte (tous appareils).
    try {
      await widget.local.clear();
    } catch (_) {
      // Un effacement qui échoue ne doit pas empêcher d'entrer.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusColor = const Color.fromRGBO(26, 153, 26, 1);
      _status = T('Connecté');
    });
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);

    return Scaffold(
      backgroundColor: palette.menu,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 120,
                  child: FugaButton(
                    text: T('< Menu'),
                    fontSize: 14,
                    height: 36,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _registering ? T('Inscription') : T('Connexion'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: Color.fromRGBO(13, 13, 13, 1),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: 240,
                  child: FugaButton(
                    text: _registering
                        ? T("J'ai déjà un compte")
                        : T('Pas encore inscrit ?'),
                    fontSize: 13,
                    height: 38,
                    onPressed: _busy ? null : _toggleMode,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pseudo,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: T('Pseudo'),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _password,
                      obscureText: !_passwordShown,
                      decoration: InputDecoration(
                        hintText: T('Mot de passe'),
                        filled: true,
                        fillColor: Colors.white,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: FugaButton(
                      text: _passwordShown ? T('Cacher') : T('Voir'),
                      fontSize: 10,
                      height: 48,
                      onPressed: () =>
                          setState(() => _passwordShown = !_passwordShown),
                    ),
                  ),
                ],
              ),
              if (_registering) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: T('Email (optionnel)'),
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FugaButton(
                text: _registering ? T('Créer le compte') : T('Se connecter'),
                color: palette.clair,
                fontSize: 17,
                height: 52,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: 14),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: _statusColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
