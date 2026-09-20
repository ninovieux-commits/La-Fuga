/// Profil d'un joueur — portage d'`AccountScreen` (main.py).
///
/// Le même écran sert pour soi et pour les autres : sur son propre profil, la
/// photo, la description, l'adresse mail et les notifications deviennent
/// modifiables, et la liste des joueurs bloqués apparaît.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../net/profile.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/fuga_button.dart';
import '../widgets/profile_photo.dart';
import 'history_screen.dart';
import 'photo_picker.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.online, this.pseudo});

  final OnlineService online;

  /// Profil à afficher ; `null` pour le sien.
  final String? pseudo;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  /// Les trois notifications secondaires, dans l'ordre de Kivy.
  static const List<(String, String)> _subNotifs = [
    ('turn', "quand c'est à moi de jouer (corresp.)"),
    ('msg', 'quand je reçois un message'),
    ('defi_corr', 'quand quelqu un me défie (corresp.)'),
  ];

  Profile? _profile;
  NotifPrefs _notif = const NotifPrefs();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final r = await widget.online.client.getProfile(widget.pseudo);
    if (!mounted) return;
    if (!r.isOk) {
      setState(() {
        _loading = false;
        _error = T('Profil indisponible.');
      });
      return;
    }

    final profile = Profile.fromJson(r.data!);
    setState(() {
      _loading = false;
      _profile = profile;
    });

    // Les préférences de notification ne sont pas dans le profil : elles
    // viennent d'`/account_info`, et seulement pour soi.
    if (profile.isSelf) {
      final info = await widget.online.client.accountInfo();
      if (!mounted || !info.isOk) return;
      final raw = info.get<Map<String, dynamic>>('notif');
      setState(() => _notif = NotifPrefs.fromJson(raw));
    }
  }

  Future<void> _toggleNotif(String key) async {
    // L'interrupteur général éteint : les autres cases ne répondent plus.
    if (key != 'mail' && !_notif.mail) return;
    final next = _notif.toggled(key);
    setState(() => _notif = next);
    await widget.online.client.setNotifPrefs(next.toJson());
  }

  Future<void> _editText({
    required String title,
    required String initial,
    required String hint,
    required int maxLength,
    required Future<void> Function(String) save,
    bool multiline = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          maxLines: multiline ? 5 : 1,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(T('Enregistrer')),
          ),
        ],
      ),
    );
    if (value == null) return;
    await save(value);
    if (mounted) await _load();
  }

  Future<void> _pickPhoto() async {
    final photo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PhotoPickerScreen()),
    );
    if (photo == null) return;
    await widget.online.client.setPhoto(photo);
    if (mounted) await _load();
  }

  Future<void> _unblock(String pseudo) async {
    await widget.online.client.unblockUser(pseudo);
    if (mounted) await _load();
  }

  Future<void> _logout() async {
    await widget.online.logout();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _openHistory(String mode) async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          online: widget.online,
          opponent: profile.isSelf ? null : profile.pseudo,
          h2hMode: mode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final profile = _profile;

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  flex: (profile?.isSelf ?? false) ? 6 : 10,
                  child: FugaButton(
                    text: T('Revenir au menu'),
                    color: palette.clair,
                    fontSize: 13,
                    height: double.infinity,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                if (profile?.isSelf ?? false) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: FugaButton(
                      text: T('Se déconnecter'),
                      fontSize: 12,
                      height: double.infinity,
                      onPressed: _logout,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
          ? Center(child: Text(_error ?? T('Profil indisponible.')))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _identity(profile, palette),
                if (!profile.isSelf) ..._headToHead(profile),
                if (profile.isSelf) _action(T('Changer la photo'), _pickPhoto),
                _title(T('Description')),
                _description(profile),
                if (profile.isSelf)
                  _action(
                    T('Modifier la description'),
                    () => _editText(
                      title: T('Description'),
                      initial: profile.description,
                      hint: T('Écris ta description…'),
                      maxLength: 500,
                      multiline: true,
                      save: widget.online.client.setDescription,
                    ),
                  ),
                if (profile.isSelf) ..._selfSettings(profile),
                _title(
                  profile.isSelf
                      ? T('Personnes qui me suivent')
                      : T('Le suivent'),
                ),
                ..._people(profile.followers, T('Personne ne le suit encore.')),
                _title(
                  profile.isSelf ? T('Personnes que je suis') : T('Il suit'),
                ),
                ..._people(profile.following, T('Ne suit personne.')),
                if (profile.isSelf) ...[
                  _title(T('Joueurs bloqués')),
                  ..._people(
                    profile.blocked,
                    T('Aucun joueur bloqué.'),
                    unblockable: true,
                  ),
                ],
                _title(T('Historique')),
                Row(
                  children: [
                    Expanded(
                      child: _action(
                        T('Historique local'),
                        () => _push(
                          HistoryScreen(
                            online: widget.online,
                            mode: HistoryMode.local,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _action(
                        T('Historique en ligne'),
                        () => _push(HistoryScreen(online: widget.online)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _identity(Profile profile, ThemePalette palette) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      ProfilePhoto(photo: profile.photo, size: 96),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.pseudo,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${T("Standard : %d").replaceAll('%d', '${profile.melo}')}'
              '    '
              '${T("Random : %d").replaceAll('%d', '${profile.meloRandom}')}',
              style: TextStyle(
                color: palette.clair,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// Les deux scores en tête-à-tête, qui ouvrent l'historique filtré.
  List<Widget> _headToHead(Profile profile) => [
    _title(T('Moi contre %s :').replaceAll('%s', profile.pseudo)),
    _action(
      T('En direct : %d - %d')
          .replaceFirst('%d', '${profile.direct.mine}')
          .replaceFirst('%d', '${profile.direct.theirs}'),
      () => _openHistory('direct'),
    ),
    _action(
      T('Correspondance : %d - %d')
          .replaceFirst('%d', '${profile.correspondence.mine}')
          .replaceFirst('%d', '${profile.correspondence.theirs}'),
      () => _openHistory('corr'),
    ),
  ];

  List<Widget> _selfSettings(Profile profile) => [
    _title(T('Adresse mail')),
    Text(
      profile.email.isEmpty ? T('Aucune adresse mail') : profile.email,
      style: const TextStyle(color: Colors.white),
    ),
    _action(
      T("Renseigner ou changer l'adresse mail"),
      () => _editText(
        title: T('Adresse mail'),
        initial: profile.email,
        hint: T('Nouvelle adresse mail'),
        maxLength: 120,
        save: widget.online.client.setEmail,
      ),
    ),
    _checkbox('mail', T('Recevoir des notifications :'), sub: false),
    for (final (key, label) in _subNotifs) _checkbox(key, T(label)),
  ];

  Widget _checkbox(String key, String label, {bool sub = true}) {
    final enabled = key == 'mail' || _notif.mail;
    return Padding(
      padding: EdgeInsets.only(left: sub ? 24 : 0),
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _notif[key] && enabled,
        onChanged: enabled ? (_) => _toggleNotif(key) : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white38,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _description(Profile profile) => Text(
    profile.description.isEmpty
        ? T('(Aucune description)')
        : profile.description,
    style: TextStyle(
      color: profile.description.isEmpty ? Colors.white38 : Colors.white70,
      fontStyle: profile.description.isEmpty
          ? FontStyle.italic
          : FontStyle.normal,
    ),
  );

  List<Widget> _people(
    List<Person> people,
    String empty, {
    bool unblockable = false,
  }) {
    if (people.isEmpty) {
      return [
        Text(
          empty,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ];
    }
    return [
      for (final p in people)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(
            p.online ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: p.online ? Colors.greenAccent : Colors.white30,
          ),
          title: Text(
            p.pseudo,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          subtitle: Text(
            T('Mélo : %d').replaceAll('%d', '${p.melo}'),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          trailing: unblockable
              ? TextButton(
                  onPressed: () => _unblock(p.pseudo),
                  child: Text(T('Débloquer')),
                )
              : null,
          onTap: unblockable
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AccountScreen(online: widget.online, pseudo: p.pseudo),
                  ),
                ),
        ),
    ];
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 15,
      ),
    ),
  );

  /// Les boutons du profil, tels que Kivy les dessine : pleins, gris, sans
  /// icône.
  Widget _action(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: FugaButton(text: label, fontSize: 12, height: 40, onPressed: onTap),
  );
}
