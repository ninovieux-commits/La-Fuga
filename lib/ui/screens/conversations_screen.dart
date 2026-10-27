/// Messagerie — portage de `ConversationsListScreen` et `ConversationScreen`
/// (main.py).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/filet_relecture.dart';
import '../../net/avatar_photos.dart';
import '../../net/decors_connus.dart';
import '../../net/profils_connus.dart';
import '../../net/push_notifications.dart';
import '../../net/resolution_profil.dart';
import '../../net/favoris_connus.dart';
import '../../net/message_hub.dart';
import '../../net/messages.dart';
import '../../net/online_service.dart';
import '../../state/messages_caches.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../suit_les_reglages.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import '../widgets/fuga_background.dart';
import '../widgets/message_bubble.dart';
import '../../game/defi_relais.dart';
import '../widgets/player_card.dart';
import '../widgets/profile_photo.dart';
import '../widgets/champ_pieces.dart';
import '../widgets/pieces_dialog.dart';

/// Liste de toutes mes conversations, avec la pastille des non-lus.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, required this.online});

  final OnlineService online;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen>
    with SuitLesReglages {
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

class _ConversationScreenState extends State<ConversationScreen>
    with SuitLesReglages {
  final ControleurAvecPieces _input = ControleurAvecPieces();
  final ScrollController _scroll = ScrollController();

  /// Ce qu'on affichait la dernière fois, tout de suite — et la relecture
  /// remplace derrière. La boîte n'ouvre donc plus sur une roue dès qu'on
  /// est déjà venu.
  late final List<ChatMessage> _messages = [
    ...MessagesCaches.connus(widget.pseudo),
  ];

  /// Combien de listes du serveur ont déjà été posées à l'écran.
  ///
  /// Deux requêtes peuvent se croiser — celle de l'ouverture et celle que
  /// déclenche un envoi. Ce compteur dit laquelle est arrivée en dernier, et
  /// la plus ancienne s'efface devant la plus récente au lieu de l'écraser.
  int _tourListe = 0;

  /// Les messages que je viens d'envoyer, tant que le serveur ne les a pas
  /// rendus dans SA liste.
  ///
  /// Ils vivent À PART de [_messages], et c'est tout l'objet de cette liste :
  /// la relecture de sécurité remplace [_messages] en bloc par ce que dit le
  /// serveur, toutes les quatre secondes. Un message parti depuis moins de
  /// quatre secondes n'y est pas encore — il disparaissait donc de l'écran,
  /// pour ne revenir qu'à la relecture suivante.
  ///
  /// Mesuré avant correction, avec un envoi lent et une relecture au milieu :
  /// « après envoi : [coucou, je suis là] », « après relecture : [coucou] »,
  /// puis un RangeError quand la réponse arrivait enfin, parce que l'indice
  /// retenu avant l'attente ne désignait plus rien. C'est ce que Nino voyait :
  /// « certains de mes messages se perdent ou sont ralentis ».
  final List<_EnVol> _enVol = [];

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
    // Son décor ou sa photo peuvent changer pendant qu'on se parle.
    profilsConnus.addListener(_surProfil);
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
    profilsConnus.removeListener(_surProfil);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Son profil a bougé : le décor et la photo de l'écran suivent.
  void _surProfil() {
    if (!mounted) return;
    setState(() {
      _theirTheme = DecorsConnus.known(widget.pseudo);
      _theirPhoto = AvatarPhotos.known(widget.pseudo, online: widget.online);
    });
  }

  /// Deux listes de messages disent-elles autre chose ?
  ///
  /// Le texte ET le côté : un même mot renvoyé par l'autre n'est pas le mien.
  /// L'état d'envoi, lui, ne compte pas — il n'appartient qu'à l'écran.
  static bool _differe(List<ChatMessage> a, List<ChatMessage> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text || a[i].fromMe != b[i].fromMe) return true;
    }
    return false;
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

      // Ceux de mes envois que cette liste porte désormais : ils quittent le
      // vol au moment même où la liste les reprend, donc sans clignoter ni
      // paraître deux fois. On compte les occurrences plutôt que de se
      // contenter d'un « ce texte est présent » : deux fois le même mot
      // envoyé, c'est deux bulles, et une seule doit partir.
      final restants = <String, int>{};
      for (final m in frais) {
        if (m.fromMe) restants[m.text] = (restants[m.text] ?? 0) + 1;
      }
      final atterris = <_EnVol>[];
      for (final v in _enVol) {
        if (!v.confirme) continue;
        final n = restants[v.texte] ?? 0;
        if (n == 0) continue;
        restants[v.texte] = n - 1;
        atterris.add(v);
      }

      // LA LONGUEUR NE SUFFIT PAS À DIRE QUE RIEN N'A BOUGÉ, et c'est le
      // plafond du serveur qui le prouve : passé 200 messages, il efface le
      // plus ancien à chaque nouveau. La boîte en garde donc 200 pour
      // toujours — et une relecture qui compare les LONGUEURS ne voyait plus
      // jamais rien arriver. Nino : « même quand la discussion est bien
      // affichée, le message le plus récent n'apparaît pas en temps réel. »
      //
      // Le comptage était aussi ce qui faisait disparaître un message qu'on
      // venait d'envoyer : il quittait la liste des envois en vol, puisque le
      // serveur le portait, mais la liste affichée n'était pas remplacée.
      final listeChangee = _differe(frais, _messages);
      if (!listeChangee && atterris.isEmpty) return;
      setState(() {
        if (listeChangee) {
          _messages
            ..clear()
            ..addAll(frais);
          _tourListe++;
          unawaited(MessagesCaches.retiens(widget.pseudo, frais));
        }
        _enVol.removeWhere(atterris.contains);
      });
      if (!listeChangee) return;
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
    // Et ce qui en reste dans le volet de notifications s'en va : le message
    // est sous les yeux, l'annonce n'a plus lieu d'être. Le retour au premier
    // plan le fait déjà — mais il ne se produit pas quand on lit sans avoir
    // quitté l'application.
    unawaited(PushNotifications.clearAll());
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

    // LES DEUX PARTENT ENSEMBLE, MAIS ON N'ATTEND PAS LES DEUX.
    //
    // On les attendait toutes les deux, pour que la boîte ne s'ouvre pas sur
    // MON fond avant de changer de décor à l'arrivée du profil. C'était juste
    // à la PREMIÈRE visite — et seulement là. Aux suivantes, son décor est
    // déjà connu, l'écran est déjà juste, et attendre le profil ne faisait
    // que retarder les messages de la plus lente des deux requêtes. Nino :
    // « la boîte de messages charge souvent ainsi », roue au milieu.
    //
    // Son profil est quand même RELU à chaque ouverture — un décor ou une
    // photo changés doivent se voir — mais il arrive quand il arrive, et
    // `profilsConnus` redessine l'écran à ce moment-là.
    final tour = _tourListe;
    final profil = rafraichisProfil(widget.pseudo, online: widget.online);
    final liste = widget.online.client.listConversation(widget.pseudo);
    if (DecorsConnus.known(widget.pseudo).isEmpty) {
      // Première visite : rien ne presse autant qu'un fond qui ne clignote
      // pas, et il n'y a de toute façon aucun message à l'écran.
      await profil;
    } else {
      unawaited(profil);
    }
    final r = await liste;
    if (!mounted) return;

    // Une relecture a pu passer PENDANT que celle-ci voyageait — l'envoi d'un
    // message en déclenche une. Sa liste est plus fraîche que la nôtre :
    // l'écraser avec celle-ci ferait disparaître le message qu'on vient
    // d'écrire, jusqu'à la réouverture de la boîte.
    if (tour != _tourListe) {
      setState(() => _loading = false);
      return;
    }

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
      _tourListe++;
      unawaited(MessagesCaches.retiens(widget.pseudo, _messages));
    });
    _scrollToEnd();
  }

  Future<void> _send() async {
    final text = _input.texteEnvoyable().trim();
    if (text.isEmpty) return;
    _input.clear();

    // Affichage optimiste : le message apparaît tout de suite, comme en Kivy.
    //
    // Dans [_enVol] et non dans [_messages] : ce dernier appartient au
    // serveur, qui le remplace en bloc toutes les quatre secondes. Retenir un
    // INDICE dans cette liste-là, puis l'utiliser après l'attente, c'était
    // écrire dans une liste qui n'est plus la même.
    final vol = _EnVol(text);
    setState(() => _enVol.add(vol));
    _scrollToEnd();

    // La partie ouverte dessous montre ce mot dans sa bande, comme s'il
    // avait été écrit depuis le plateau : un seul chemin pour tous mes
    // messages.
    widget.online.messages.noteEnvoi(widget.pseudo, text);

    final r = await widget.online.client.sendMessage(widget.pseudo, text);
    if (!mounted) return;
    setState(() => r.isOk ? vol.confirme = true : vol.echoue = true);
    // Le serveur l'a : on va le chercher pour que la liste le reprenne, au
    // lieu d'attendre la relecture suivante.
    if (r.isOk) unawaited(_refresh());
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
    // SES BULLES SONT À LUI, LES MIENNES SONT À MOI.
    //
    // Nino, d'abord : « j'aimerais que les bulles dépendent de la partie
    // "général" du thème de l'adversaire ». Puis, l'ayant vu : « les bulles
    // de l'adversaire restent à sa couleur, mais mes bulles doivent être à ma
    // couleur ! »
    //
    // Les deux tiennent ensemble, et c'est même ce qui donne son sens à
    // l'écran : on entre chez lui, son décor habille la page et ses mots
    // portent ses couleurs — mais ce que J'ÉCRIS reste à moi, d'une
    // conversation à l'autre.
    //
    // Sans son thème, le mien : il faut bien des couleurs, et l'écran ne
    // s'affiche de toute façon qu'une fois la question tranchée, donc rien ne
    // change sous les yeux.
    final palette = paletteOf((decor ?? Settings.instance.themeAxes).general);
    final mienne = paletteOf(Settings.instance.themeAxes.general);

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
                // Son nom ouvre SA fiche — la même qu'en partie.
                onTitleTap: () => unawaited(_fiche(widget.pseudo, palette)),
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                // LA ROUE NE CACHE JAMAIS UN MESSAGE. Dès qu'il y a
                // quelque chose à montrer — la conversation, ou seulement ce
                // qu'on vient d'écrire — c'est la liste qui passe, chargement
                // ou pas. Sinon on pouvait écrire et envoyer sans RIEN voir,
                // le champ et la touche étant, eux, toujours là.
                child: _messages.isNotEmpty || _enVol.isNotEmpty
                    ? ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.all(S(10)),
                        itemCount: _messages.length + _enVol.length,
                        itemBuilder: (context, i) => _bubble(
                          i < _messages.length
                              ? _messages[i]
                              : _enVol[i - _messages.length].commeMessage,
                          palette,
                          mienne,
                        ),
                      )
                    : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(child: Text(_error!))
                    : Center(
                        child: Text(T('Aucun message. Écrivez le premier !')),
                      ),
              ),
              _visages(palette),
              _composer(palette),
            ],
          ),
        ),
      ),
    );
  }

  /// LA fiche du joueur, la même que partout ailleurs — et le défi qu'elle
  /// peut lancer.
  ///
  /// Nino : « câble le défi depuis la correspondance et la boîte de
  /// dialogue ». C'est le menu qui le mène, par le relais : son dialogue
  /// d'attente paraît par-dessus la conversation, et la partie par-dessus
  /// lui. On revient ici en la quittant.
  Future<void> _fiche(String pseudo, ThemePalette palette) async {
    final cible = await showPlayerCard(
      context,
      online: widget.online,
      palette: palette,
      pseudo: pseudo,
    );
    if (cible != null) await DefiRelais.defier(cible);
  }

  /// Une bulle, et rien qu'une bulle.
  ///
  /// Elle portait une petite photo à côté d'elle, répétée à chaque message.
  /// Les photos sont maintenant en bas, une seule fois et en grand : la
  /// conversation respire, et le texte gagne la place qu'elles prenaient.
  Widget _bubble(ChatMessage m, ThemePalette sienne, ThemePalette mienne) =>
      Padding(
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
                // Chacun les siennes.
                palette: m.fromMe ? mienne : sienne,
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
  Widget _visages(ThemePalette palette) => Padding(
    padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(6)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Les deux photos ouvrent la même fiche que les noms : la sienne, et
        // la mienne — qui n'offre que « Profil », puisqu'on ne se défie pas,
        // ne se met pas en favori et ne se bloque pas soi-même.
        GestureDetector(
          onTap: () => unawaited(_fiche(widget.pseudo, palette)),
          child: ProfilePhoto(
            photo: avatarPhotoFor(widget.pseudo, _theirPhoto),
            size: kAvatarBasConversation,
          ),
        ),
        _toucheDesPieces(palette),
        GestureDetector(
          onTap: () => unawaited(_fiche(widget.online.pseudo ?? '', palette)),
          child: ProfilePhoto(
            photo: avatarPhotoFor(
              widget.online.pseudo,
              widget.online.session?.photo ?? '',
            ),
            size: kAvatarBasConversation,
          ),
        ),
      ],
    ),
  );

  Future<void> _ouvrirLesPieces(ThemePalette palette) async {
    final jeton = await choisirPieceEmoji(context, palette: palette);
    if (jeton != null) _input.insererPiece(jeton);
  }

  /// La touche qui ouvre les pièces, ENTRE LES DEUX VISAGES.
  ///
  /// Nino : « le bouton doit apparaître entre nos deux images de profil, pas
  /// dessous. » Elle y trouve sa place sans rien pousser : les deux photos
  /// sont aux deux bouts d'une rangée, et un enfant de plus au milieu ne les
  /// déplace pas d'un pixel.
  ///
  /// Elle ne paraît que CLAVIER DÉPLOYÉ, comme il l'avait demandé d'abord.
  /// Le clavier se reconnaît à la place qu'il prend : `viewInsets.bottom`
  /// vaut sa hauteur quand il est là, et zéro sinon.
  Widget _toucheDesPieces(ThemePalette palette) {
    if (MediaQuery.viewInsetsOf(context).bottom <= 0) {
      return const SizedBox.shrink();
    }
    final cote = touchHeight();
    return Center(
      child: Tooltip(
        message: T('Envoyer une pièce'),
        child: Material(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(S(10)),
          child: InkWell(
            borderRadius: BorderRadius.circular(S(10)),
            onTap: () => unawaited(_ouvrirLesPieces(palette)),
            child: SizedBox(
              width: cote,
              height: cote,
              child: Center(
                child: ProfilePhoto(
                  photo: 'logo|${Settings.instance.themeAxes.general}',
                  size: cote * 0.72,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _composer(ThemePalette palette) => Container(
    padding: EdgeInsets.all(S(8)),
    color: Colors.black26,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
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
      ],
    ),
  );
}

/// Un message parti, dont le serveur n'a pas encore rendu compte.
class _EnVol {
  _EnVol(this.texte);

  final String texte;

  /// Le serveur a répondu « reçu » : il paraîtra dans sa prochaine liste.
  bool confirme = false;

  /// L'envoi a échoué : la bulle le dit, et elle reste à l'écran. Un message
  /// qu'on croit parti et qui n'est jamais arrivé est pire que pas de message.
  bool echoue = false;

  ChatMessage get commeMessage =>
      ChatMessage(text: texte, fromMe: true, pending: !echoue);
}
