/// Messagerie — portage de `ConversationsListScreen` et `ConversationScreen`
/// (main.py).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/message_hub.dart';
import '../../net/messages.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
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

  StreamSubscription<IncomingMessage>? _watch;

  @override
  void initState() {
    super.initState();
    _load();
    // Un message qui arrive pendant qu'on regarde la liste doit s'y voir.
    _watch = widget.online.messages.incoming.listen((_) => _load());
  }

  @override
  void dispose() {
    _watch?.cancel();
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
    final conversations = _conversations ?? const <Conversation>[];

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Retour'),
              title: T('Messages'),
              titleSize: 18,
              bold: true,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: _loading
                  ? _notice(T('Chargement…'))
                  : _error != null
                  ? _notice(
                      _error!,
                      color: const Color.fromRGBO(153, 77, 77, 1),
                    )
                  : conversations.isEmpty
                  ? _notice(T('Aucune conversation pour le moment.'))
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(S(10), S(8), S(10), S(8)),
                      itemCount: conversations.length,
                      separatorBuilder: (_, __) => SizedBox(height: S(8)),
                      itemBuilder: (context, i) => _row(conversations[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(String text, {Color color = const Color(0xFF666666)}) =>
      Padding(
        padding: EdgeInsets.all(S(20)),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: SF(13),
              fontStyle: FontStyle.italic,
              color: color,
            ),
          ),
        ),
      );

  /// Une conversation : carte grise, avatar, pseudo, aperçu du dernier
  /// message, et la pastille des non-lus.
  Widget _row(Conversation c) {
    final preview = c.lastFromMe ? '${T("Vous : ")}${c.lastText}' : c.lastText;

    return Material(
      color: kFugaGrey,
      borderRadius: BorderRadius.circular(S(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(S(10)),
        onTap: () => _open(c.pseudo),
        child: SizedBox(
          height: S(80),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(6)),
            child: Row(
              children: [
                ProfilePhoto(
                  photo: avatarPhotoFor(c.pseudo, c.photo),
                  size: S(46),
                ),
                SizedBox(width: S(10)),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.pseudo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: SF(15),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color.fromRGBO(209, 209, 209, 1),
                          fontSize: SF(12),
                        ),
                      ),
                    ],
                  ),
                ),
                if (c.unread > 0) _badge(c.unread),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(int count) => Container(
    width: S(26),
    height: S(26),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Color(0xFFD93333),
      shape: BoxShape.circle,
    ),
    child: Text(
      '$count',
      style: TextStyle(
        color: Colors.white,
        fontSize: SF(13),
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

  StreamSubscription<IncomingMessage>? _watch;

  @override
  void initState() {
    super.initState();
    _load();
    _watch = widget.online.messages.incoming.listen(_onIncoming);
  }

  @override
  void dispose() {
    _watch?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Message reçu en direct : on ne l'ajoute que s'il vient d'ici.
  ///
  /// La conversation est ouverte, donc lue : on l'annonce au serveur et à la
  /// boîte aux lettres, sinon la pastille du menu s'allumerait pour un
  /// message qu'on est en train de lire.
  void _onIncoming(IncomingMessage message) {
    // Le message peut arriver alors que la conversation vient d'être quittée.
    if (!mounted) return;
    if (message.from != widget.pseudo) return;
    setState(
      () => _messages.add(ChatMessage(text: message.text, fromMe: false)),
    );
    widget.online.messages.markRead(widget.pseudo);
    unawaited(widget.online.client.markRead(widget.pseudo));
    _scrollToEnd();
  }

  Future<void> _load() async {
    // Ouvrir la conversation vaut lecture.
    widget.online.messages.markRead(widget.pseudo);
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
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Retour'),
              title: widget.pseudo,
              titleSize: 18,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _messages.isEmpty
                  ? Center(
                      child: Text(T('Aucun message. Écrivez le premier !')),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.all(S(10)),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) =>
                          _bubble(_messages[i], palette),
                    ),
            ),
            _composer(palette),
          ],
        ),
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
      size: S(34),
    );
    final text = Flexible(
      child: Text(
        m.pending == false ? '${m.text}  ${T("(non envoyé)")}' : m.text,
        textAlign: m.fromMe ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          // Le doré de Kivy pour mes messages, le blanc cassé pour les
          // siens : `(1, 0.82, 0.4)` et `(0.95, 0.95, 0.95)`.
          color: m.pending == false
              ? Colors.redAccent
              : m.fromMe
              ? const Color.fromRGBO(255, 209, 102, 1)
              : const Color.fromRGBO(242, 242, 242, 1),
          fontSize: SF(16),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: S(4)),
      child: Row(
        mainAxisAlignment: m.fromMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: m.fromMe
            ? [text, SizedBox(width: S(6)), avatar]
            : [avatar, SizedBox(width: S(6)), text],
      ),
    );
  }

  Widget _composer(ThemePalette palette) => Container(
    padding: EdgeInsets.all(S(8)),
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
        SizedBox(width: S(8)),
        FilledButton(
          onPressed: _send,
          style: FilledButton.styleFrom(backgroundColor: palette.clair),
          child: Text(T('Envoyer')),
        ),
      ],
    ),
  );
}
