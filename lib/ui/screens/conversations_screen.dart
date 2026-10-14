/// Messagerie — portage de `ConversationsListScreen` et `ConversationScreen`
/// (main.py).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/filet_relecture.dart';
import '../../net/avatar_photos.dart';
import '../../net/decors_connus.dart';
import '../../net/favoris_connus.dart';
import '../../net/message_hub.dart';
import '../../net/messages.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import '../widgets/fuga_background.dart';
import '../widgets/message_bubble.dart';
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
/// Taille de la photo de profil, à côté d'une bulle.
///
/// Plus grosse que les trente-quatre d'avant : à cette taille, un portrait de
/// pièce ne se reconnaissait pas. Les messageries tiennent entre trente-deux
/// et quarante ; on prend le haut de la fourchette, les pièces de La Fuga
/// étant des dessins et non des visages.
double get kAvatarConversation => S(48);

/// Les deux grandes photos du bas : la sienne à gauche, la mienne à droite.
///
/// Nino : « au lieu de faire apparaître plein de fois en petit les images de
/// profil des utilisateurs, je voudrais qu'elles soient une seule fois en plus
/// gros en bas ». Une par personne, posées aux deux coins, comme sur son
/// dessin — et les bulles n'en portent plus aucune.
double get kAvatarBasConversation => S(84);

/// Combien de fois au plus on ressaute vers le bas en ouvrant une conversation.
///
/// Chaque passe avance d'environ une hauteur d'écran de bulles construites.
/// Vingt passes couvrent plusieurs centaines de messages ; au-delà, mieux vaut
/// s'arrêter près du bas que faire tourner l'écran sans fin.
const int kDefilementPassesMax = 20;

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

  /// Ce qu'on sait de lui AVANT la première image : le cache répond sans
  /// réseau, donc une conversation déjà ouverte une fois s'ouvre d'emblée
  /// avec sa photo et son décor.
  late String _theirPhoto = AvatarPhotos.known(widget.pseudo);

  /// Le thème de l'INTERLOCUTEUR : son fond de menu habille la conversation.
  /// On entre chez lui, on voit son décor.
  ///
  /// Nino : « Mon fond ne doit pas être remplacé par celui de mon
  /// adversaire. » La boîte est donc CONSTRUITE avec le bon nom de fond, pas
  /// rhabillée après coup : tant qu'on ne le connaît pas, on n'affiche aucun
  /// décor plutôt que le mien — voir [_decorConnu].
  late String _theirTheme = DecorsConnus.known(widget.pseudo);

  /// Faux tant que les messages OU le nom du fond manquent.
  ///
  /// Les deux partent ensemble et on attend les deux : afficher la
  /// conversation dès les messages, c'était l'afficher avec mon fond, puis la
  /// rhabiller quand le profil arrivait. C'est ce clignotement que Nino a vu.
  bool _loading = true;
  String? _error;

  StreamSubscription<IncomingMessage>? _watch;

  /// Filet de sécurité derrière le temps réel.
  ///
  /// L'écran n'avait QUE l'événement `message_recu` pour se réveiller. Quand il
  /// n'arrive pas — socket coupé, réseau mobile qui a lâché la connexion sans
  /// le dire, application revenue du fond — la conversation restait figée
  /// jusqu'à ce qu'on la quitte et qu'on y revienne. Le socket rend le message
  /// instantané ; cette relecture garantit qu'il arrive.
  Timer? _poll;
  bool _polling = false;
  static const Duration _pollInterval = Duration(seconds: 4);

  /// Tant que le direct répond, cette relecture s'espace : elle n'a plus
  /// qu'à rattraper ce qu'il aurait manqué. Elle reprend son rythme dès que
  /// la socket se tait.
  final FiletRelecture _filet = FiletRelecture();

  @override
  void initState() {
    super.initState();
    _load();
    _watch = widget.online.messages.incoming.listen(_onIncoming);
    _poll = Timer.periodic(_pollInterval, (_) {
      if (!_filet.fautRelire(
        directVivant: widget.online.socket?.isConnected ?? false,
      )) {
        return;
      }
      _filet.note();
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _watch?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Relit la conversation et ne redessine que si elle a changé.
  ///
  /// Sans marquer comme lu : `_load` le fait à l'ouverture, et le refaire
  /// toutes les quatre secondes ajouterait une écriture serveur pour rien.
  Future<void> _refresh() async {
    if (!mounted || _polling) return;
    _polling = true;
    try {
      final r = await widget.online.client.listConversation(widget.pseudo);
      if (!mounted || !r.isOk) return;
      final frais = [
        for (final m in r.get<List<dynamic>>('messages') ?? const [])
          if (m is Map) ChatMessage.fromJson(Map<String, dynamic>.from(m)),
      ];
      if (frais.length == _messages.length) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(frais);
      });
      // Un message vient d'arriver : la conversation est ouverte, donc lue.
      _declareLu();
      _scrollToEnd();
    } finally {
      _polling = false;
    }
  }

  /// La conversation est ouverte, donc ce qui vient d'ici est lu : on
  /// l'annonce au serveur et à la boîte aux lettres, sinon la pastille du
  /// menu s'allumerait pour un message qu'on est en train de lire.
  ///
  /// Le compte local part à la FIN de la frame, pas sur-le-champ. `initState`
  /// tourne au milieu de la construction de l'arbre : prévenir la boîte aux
  /// lettres tout de suite faisait appeler `setState` à l'écran de partie
  /// resté dessous, en pleine construction, et Flutter le refuse — la
  /// pastille gardait alors l'état d'avant. L'avis au serveur, lui, part
  /// tout de suite : il ne réveille personne.
  void _declareLu() {
    unawaited(widget.online.client.markRead(widget.pseudo));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.online.messages.markRead(widget.pseudo);
    });
  }

  /// Message reçu en direct : on ne l'ajoute que s'il vient d'ici.
  void _onIncoming(IncomingMessage message) {
    // Le message peut arriver alors que la conversation vient d'être quittée.
    if (!mounted) return;
    if (message.from != widget.pseudo) return;
    // Le direct vient de livrer : la relecture peut attendre.
    _filet.note();
    setState(
      () => _messages.add(ChatMessage(text: message.text, fromMe: false)),
    );
    _declareLu();
    _scrollToEnd();
  }

  Future<void> _load() async {
    // Ouvrir la conversation vaut lecture.
    _declareLu();

    // Les deux ensemble, et on attend les deux. En série, l'écran s'affichait
    // dès les messages — donc avec MON fond — et changeait de décor quand le
    // profil arrivait. Ensemble, la boîte n'est construite qu'une fois, avec
    // le nom du fond déjà en main, et l'attente ne dure pas plus longtemps
    // que la plus lente des deux requêtes.
    //
    // `DecorsConnus.resolve` fait la requête de profil et retient au passage
    // la photo ET le nom du fond ; il ne demande rien quand il sait déjà.
    // C'est lui, et non le cache des photos, qui décide de demander : une
    // photo déjà connue par un écran de partie ne doit pas empêcher d'aller
    // chercher le fond.
    final (r, _) = await (
      widget.online.client.listConversation(widget.pseudo),
      DecorsConnus.resolve(widget.pseudo, online: widget.online),
    ).wait;
    if (!mounted) return;

    setState(() {
      _loading = false;
      _theirPhoto = AvatarPhotos.known(widget.pseudo, online: widget.online);
      _theirTheme = DecorsConnus.known(widget.pseudo);
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

  /// Amène la conversation à SA FIN, et pas à peu près.
  ///
  /// `ListView.builder` est paresseux : il ne construit que ce qu'il faut
  /// afficher, donc `maxScrollExtent` n'est qu'une ESTIMATION tant que le
  /// reste ne l'est pas. Un seul saut atterrit court — mesuré : 86 pixels,
  /// une bulle, sur une conversation de douze messages ; 2 150 pixels,
  /// vingt-cinq bulles, sur soixante. C'est ce qui ouvrait la conversation
  /// loin de son dernier message.
  ///
  /// Sauter rapproche du bas, ce qui construit de nouvelles bulles, ce qui
  /// allonge l'estimation : on recommence tant qu'elle bouge. Sur soixante
  /// messages, mesuré : saut à 6 326, l'estimation passe à 8 476, saut à
  /// 8 476, elle ne bouge plus. Deux sauts, et 6 326 est exactement où
  /// l'ancien code s'arrêtait.
  ///
  /// Le compte de passes est borné pour qu'un contenu qui n'arrêterait jamais
  /// de grandir — des images qui arrivent une à une — ne fasse pas tourner
  /// l'écran indéfiniment.
  void _scrollToEnd() {
    var precedent = -1.0;
    var passes = 0;
    void encore() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final cible = _scroll.position.maxScrollExtent;
        // L'estimation s'est stabilisée : on est vraiment en bas.
        if (cible == precedent || passes >= kDefilementPassesMax) return;
        precedent = cible;
        passes++;
        _scroll.jumpTo(cible);
        encore();
      });
    }

    encore();
  }

  /// Son décor, ou `null` tant qu'on ne sait pas lequel c'est.
  ///
  /// `null` et non « le mien » : c'est toute la différence entre construire la
  /// boîte avec le bon fond et la rhabiller après coup.
  ThemeAxes? get _decorConnu =>
      _theirTheme.isEmpty ? null : ThemeAxes.parse(_theirTheme);

  @override
  Widget build(BuildContext context) {
    // LE DÉCOR EST À LUI, LES BULLES SONT À MOI.
    //
    // Son fond de menu habille la page — on entre chez lui, on voit son
    // décor — mais les bulles gardent les couleurs de MON thème : c'est mon
    // application, et je dois m'y retrouver d'une conversation à l'autre.
    //
    // Son décor, quand on le connaît. Sinon AUCUN : mon fond ne doit pas
    // apparaître pour être remplacé une seconde plus tard.
    //
    // Le cas « serveur qui ne renvoie pas le thème » existe encore — une
    // version antérieure du serveur, ou un compte introuvable : la boîte
    // s'ouvre alors sur la couleur unie du thème, sans image, et elle y
    // reste. Rien ne clignote.
    final decor = _decorConnu;
    // LES BULLES AUSSI SONT À LUI.
    //
    // Nino : « j'aimerais que les bulles dépendent de la partie "général" du
    // thème de l'adversaire ». C'est l'inverse de ce qu'il demandait d'abord
    // — les bulles à MOI, le fond à lui — et c'est son dernier mot : on entre
    // chez lui, tout l'écran est chez lui.
    //
    // Sans son thème, les miennes : il faut bien des couleurs, et l'écran ne
    // s'affiche de toute façon qu'une fois la question tranchée, donc rien ne
    // change sous les yeux.
    final palette = paletteOf((decor ?? Settings.instance.themeAxes).general);

    return Scaffold(
      backgroundColor: paletteOf(decor?.menu ?? kDefaultTheme).menu,
      body: FugaBackground(
        theme: decor?.menu ?? kSansFond,
        child: SafeArea(
          child: Column(
            children: [
              FugaHeader(
                back: T('< Retour'),
                title: widget.pseudo,
                titleSize: 18,
                // L'étoile vient du cache, et le cache a été rempli par la
                // requête de profil de `_load` : rien de plus n'a été
                // demandé au serveur. Tant qu'on ne sait pas, pas d'étoile —
                // elle paraîtra au `setState` de l'arrivée.
                favori: FavorisConnus.instance.connu(widget.pseudo) ?? false,
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
              _visages(),
              _composer(palette),
            ],
          ),
        ),
      ),
    );
  }

  /// Une bulle, et rien qu'une bulle.
  ///
  /// Elle portait une petite photo à côté d'elle, répétée à chaque message.
  /// Les photos sont maintenant en bas, une seule fois et en grand : la
  /// conversation respire, et le texte gagne la place qu'elles prenaient.
  Widget _bubble(ChatMessage m, ThemePalette palette) => Padding(
    padding: EdgeInsets.symmetric(vertical: S(4)),
    child: Row(
      mainAxisAlignment: m.fromMe
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: MessageBubble(
            texte: m.text,
            deMoi: m.fromMe,
            palette: palette,
            echoue: m.pending == false,
          ),
        ),
      ],
    ),
  );

  /// Les deux visages, en bas : le sien à gauche, le mien à droite.
  ///
  /// Chacun du côté d'où viennent ses bulles — on sait d'un coup d'œil qui
  /// parle de quel côté, et une seule fois suffit à le dire.
  Widget _visages() => Padding(
    padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(6)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ProfilePhoto(
          photo: avatarPhotoFor(widget.pseudo, _theirPhoto),
          size: kAvatarBasConversation,
        ),
        ProfilePhoto(
          photo: avatarPhotoFor(
            widget.online.pseudo,
            widget.online.session?.photo ?? '',
          ),
          size: kAvatarBasConversation,
        ),
      ],
    ),
  );

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
