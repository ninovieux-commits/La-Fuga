/// Messagerie — portage de `ConversationsListScreen` et `ConversationScreen`
/// (main.py).
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/messages.dart';
import '../../net/online_service.dart';
import '../../net/socket_client.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/profile_photo.dart';

/// Liste de toutes mes conversations, avec la pastille des non-lus.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, required this.online});

  final OnlineService online;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation>? _conversations;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Un message qui arrive pendant qu'on regarde la liste doit s'y voir.
    widget.online.socket?.on(FugaEvents.messageRecu, (_) => _load());
  }

  @override
  void dispose() {
    widget.online.socket?.off(FugaEvents.messageRecu);
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.online.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = T('Connexion requise');
      });
      return;
    }

    setState(() => _loading = true);
    final r = await widget.online.client.listConversations();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.isOk) {
        _error = T('Messagerie indisponible.');
        return;
      }
      _error = null;
      _conversations = [
        for (final c in r.get<List<dynamic>>('conversations') ?? const [])
          if (c is Map) Conversation.fromJson(Map<String, dynamic>.from(c)),
      ];
    });
  }

  Future<void> _open(String pseudo) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ConversationScreen(online: widget.online, pseudo: pseudo),
      ),
    );
    // Au retour, les messages lus ne doivent plus compter comme non-lus.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final conversations = _conversations ?? const <Conversation>[];

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(T('Messages')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : conversations.isEmpty
          ? Center(child: Text(T('Aucune conversation pour le moment.')))
          : ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = conversations[i];
                final preview = c.lastFromMe
                    ? '${T("Vous : ")}${c.lastText}'
                    : c.lastText;
                return ListTile(
                  leading: ProfilePhoto(
                    photo: avatarPhotoFor(c.pseudo, c.photo),
                    size: 44,
                  ),
                  title: Text(
                    c.pseudo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: c.unread > 0 ? _badge(c.unread) : null,
                  onTap: () => _open(c.pseudo),
                );
              },
            ),
    );
  }

  Widget _badge(int count) => Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Color(0xFFD93333),
      shape: BoxShape.circle,
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

/// Une conversation : les messages, et de quoi répondre.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.online,
    required this.pseudo,
  });

  final OnlineService online;

  /// L'interlocuteur.
  final String pseudo;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<ChatMessage> _messages = [];
  String _theirPhoto = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    widget.online.socket?.on(FugaEvents.messageRecu, _onIncoming);
  }

  @override
  void dispose() {
    widget.online.socket?.off(FugaEvents.messageRecu);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Message reçu en direct : on ne l'ajoute que s'il vient d'ici.
  void _onIncoming(Map<String, dynamic> data) {
    if ('${data['de'] ?? ''}' != widget.pseudo) return;
    setState(
      () => _messages.add(
        ChatMessage(text: '${data['texte'] ?? ''}', fromMe: false),
      ),
    );
    _scrollToEnd();
  }

  Future<void> _load() async {
    // Ouvrir la conversation vaut lecture.
    await widget.online.client.markRead(widget.pseudo);
    final r = await widget.online.client.listConversation(widget.pseudo);
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (!r.isOk) {
        _error = T('Conversation indisponible.');
        return;
      }
      _messages
        ..clear()
        ..addAll([
          for (final m in r.get<List<dynamic>>('messages') ?? const [])
            if (m is Map) ChatMessage.fromJson(Map<String, dynamic>.from(m)),
        ]);
    });
    _scrollToEnd();

    final profile = await widget.online.client.getProfile(widget.pseudo);
    if (!mounted || !profile.isOk) return;
    setState(() => _theirPhoto = profile.get<String>('photo') ?? '');
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();

    // Affichage optimiste : le message apparaît tout de suite, comme en Kivy.
    final index = _messages.length;
    setState(
      () => _messages.add(ChatMessage(text: text, fromMe: true, pending: true)),
    );
    _scrollToEnd();

    final r = await widget.online.client.sendMessage(widget.pseudo, text);
    if (!mounted) return;
    setState(() {
      _messages[index] = ChatMessage(
        text: text,
        fromMe: true,
        pending: r.isOk ? null : false,
      );
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
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
        title: Text(widget.pseudo),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _messages.isEmpty
                ? Center(child: Text(T('Aucun message. Écrivez le premier !')))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _bubble(_messages[i], palette),
                  ),
          ),
          _composer(palette),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage m, ThemePalette palette) {
    final avatar = ProfilePhoto(
      photo: m.fromMe
          ? avatarPhotoFor(
              widget.online.pseudo,
              widget.online.session?.photo ?? '',
            )
          : avatarPhotoFor(widget.pseudo, _theirPhoto),
      size: 34,
    );
    final text = Flexible(
      child: Text(
        m.pending == false ? '${m.text}  ${T("(non envoyé)")}' : m.text,
        textAlign: m.fromMe ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color: m.pending == false
              ? Colors.redAccent
              : m.fromMe
              ? palette.clair
              : Colors.white,
          fontSize: 15,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: m.fromMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: m.fromMe
            ? [text, const SizedBox(width: 6), avatar]
            : [avatar, const SizedBox(width: 6), text],
      ),
    );
  }

  Widget _composer(ThemePalette palette) => Container(
    padding: const EdgeInsets.all(8),
    color: Colors.black26,
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: T('Votre message…'),
              hintStyle: const TextStyle(color: Colors.white38),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _send,
          style: FilledButton.styleFrom(backgroundColor: palette.clair),
          child: Text(T('Envoyer')),
        ),
      ],
    ),
  );
}
