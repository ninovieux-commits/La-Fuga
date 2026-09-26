/// Partie en ligne.
///
/// Toute la logique vit dans [OnlineGame] ; cet écran l'affiche et lui passe
/// les gestes, exactement comme l'écran local le fait avec le contrôleur.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/move_controller.dart';
import '../../game/game_archive.dart';
import '../../game/online_game.dart';
import '../../game/sound_player.dart';
import '../../game/last_move.dart';
import '../../i18n/translations.dart';
import '../../net/avatar_photos.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import 'conversations_screen.dart';
import '../widgets/fuga_background.dart';
import '../widgets/end_dialogs.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_layout.dart';
import '../widgets/move_strip.dart';
import '../widgets/name_menu.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/pause_dialog.dart';
import '../widgets/player_panel.dart';
import '../widgets/slide_animation.dart';

class OnlineGameScreen extends StatefulWidget {
  const OnlineGameScreen({
    super.key,
    required this.game,
    required this.myPseudo,
    this.archive,
  });

  final OnlineGame game;
  final String myPseudo;

  /// Où ranger chaque partie une fois finie. Injectable pour les tests.
  final GameArchive? archive;

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen>
    with SlideAnimation {
  final SoundPlayer _sounds = SoundPlayer();
  LastMove? _lastMove;

  /// Position d'avant le coup : la mise en évidence en a besoin (type de la
  /// pièce qui pousse, chemin d'un saut).
  Board? _boardBefore;

  OnlineGame get _g => widget.game;

  /// La photo de l'adversaire : le serveur ne l'envoie pas avec la partie, on
  /// va la chercher par son pseudo (voir `AvatarPhotos`). Vide en attendant.
  String _photoAdverse = '';

  /// Demande la photo de l'adversaire et redessine son avatar à l'arrivée.
  Future<void> _chargerPhotoAdverse() async {
    final photo = await AvatarPhotos.resolve(_g.info.opponent);
    if (mounted && photo != _photoAdverse) {
      setState(() => _photoAdverse = photo);
    }
  }

  @override
  void initState() {
    super.initState();
    _photoAdverse = AvatarPhotos.known(_g.info.opponent);
    _chargerPhotoAdverse();
    _sounds.init();
    _g.onChanged = _handleEvent;
    // La pastille du bouton Chat suit les messages en direct.
    OnlineService.instance.messages.addListener(_onMessages);
  }

  void _onMessages() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    OnlineService.instance.messages.removeListener(_onMessages);
    _sounds.dispose();
    _g.dispose();
    super.dispose();
  }

  /// Le popup de fin n'est montré qu'une fois par partie.
  bool _endShown = false;

  /// Parties du match déjà rangées dans l'historique, par identifiant.
  final Set<String> _archivedGames = {};

  late final GameArchive _store = widget.archive ?? GameArchive();

  void _handleEvent(OnlineEvent event) {
    if (!mounted) return;
    if (event == OnlineEvent.drawOffered && _g.drawOffered) {
      _askDraw();
    }
    if (event == OnlineEvent.nextGameStarted) {
      _endShown = false;
      _lastMove = null;
    }

    // Coup de l'adversaire : on reprend sa mise en évidence et son glissement.
    final incoming = _g.pendingHighlight;
    if (incoming != null) {
      _g.pendingHighlight = null;
      _lastMove = incoming.lastMove;
      rememberSlides(incoming.slides);
    }
    setState(() {});

    if (_g.endReason != null && !_endShown) {
      _endShown = true;
      _archive();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEnd();
      });
    }
  }

  void _onTapCell(Cell cell) {
    // La position d'avant le coup est prise au premier geste du tour.
    if (!_g.game.moved) _boardBefore = _g.game.board.clone();
    final result = _g.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    // Chaque geste glisse au moment où il est fait, comme en Kivy.
    rememberSlides(result.slides);
    final notation = result.notation;
    if (notation != null) {
      _lastMove = lastMoveFromNotation(
        notation,
        _boardBefore ?? Board.initial(),
        _g.game.board,
      );
    }
    setState(() {});
    // Le son part après l'écran : le plateau doit répondre au doigt.
    if (notation != null) _sounds.playNotation(notation);
  }

  Future<void> _askDraw() async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Nulle')),
        content: Text('${_g.info.opponent} ${T('propose la nulle')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Refuser')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Accepter')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    accept == true ? _g.acceptDraw() : _g.declineDraw();
  }

  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Abandonner')),
        content: Text(T('Abandonner cette partie ?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Abandonner')),
          ),
        ],
      ),
    );
    if (ok == true) _g.resign();
  }

  /// La boîte de messages UNIFIÉE avec l'adversaire — `_open_chat`.
  ///
  /// La même conversation qu'au menu : Kivy ne tient pas de chat séparé par
  /// partie.
  Future<void> _openChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          online: OnlineService.instance,
          pseudo: _g.info.opponent,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String? get _verdict {
    final reason = _g.endReason;
    if (reason == null) return null;
    final winner = _g.loser?.opposite;
    final base = switch (reason) {
      'fugue' => T('Fugue'),
      'mat' => T('Mat'),
      'papatte' => T('Papatte'),
      'temps' => T('Temps écoulé'),
      'abandon' => T('Abandon'),
      'nulle' || 'nulle_pat' || 'nulle_accord' => T('Match nul'),
      'repetition' => T('Match nul par répétition'),
      _ => T('Partie terminée'),
    };
    if (winner == null) return base;
    final who = winner == _g.myCamp ? T('Gagné !') : T('Perdu');
    return '$base — $who';
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    // Mon camp est toujours en bas — sauf si le joueur retourne le plateau.
    final flipped = _flipOverride ?? (_g.myCamp == Camp.blanc);
    final topCamp = flipped ? Camp.noir : Camp.blanc;
    final bottomCamp = flipped ? Camp.blanc : Camp.noir;

    return FugaScaffold(
      // Le bandeau touche le HAUT de l'écran, comme en Kivy : en plein
      // écran immersif il n'y a pas de barre d'état à éviter, et la bande
      // laissée au-dessus mangeait de la place au plateau.
      body: SafeArea(
        top: false,
        child: GameLayout(
          topBar: GameTopBar(
            palette: palette,
            color: _campColor(palette, topCamp),
            onFlip: _toggleFlip,
            onChat: _openChat,
            // La touche Chat ouvre la conversation privée avec l'adversaire :
            // sa pastille s'allume pour un message de LUI, et pour lui seul.
            unreadChat: OnlineService.instance.messages.unreadFrom(
              _g.info.opponent,
            ),
            onPause: _openPause,
            onMenu: _g.endReason != null
                ? () => Navigator.of(context).pop()
                : null,
          ),
          topPanel: _banner(palette, topCamp),
          board: GameBoardView(
            board: _g.game.board,
            palette: palette,
            flipped: flipped,
            onTapCell: _onTapCell,
            selected: _g.game.selected,
            groupSelection: _g.game.groupSelection,
            highlighted: _g.game.availablePushCells.toSet(),
            lastMove: _lastMove,
            fuguedHeirs: _g.game.fuguedHeirs,
            pieceTheme: axes.pieces,
            boardTheme: axes.board,
            slides: slides,
            slideToken: slideToken,
            slideDuration: slideDuration,
          ),
          bottomPanel: _banner(palette, bottomCamp),
          moveStrip: MoveStrip(
            moves: _g.game.history,
            color: _campColor(palette, bottomCamp),
            palette: palette,
            onSelect: (_) {},
          ),
        ),
      ),
    );
  }

  /// Couleur d'un camp, vive quand il a le trait.
  Color _campColor(ThemePalette palette, Camp camp) {
    final atTrait = _g.game.turn == camp && !_g.game.gameOver;
    if (camp == Camp.blanc) return atTrait ? palette.clair : palette.clairDim;
    return atTrait ? palette.fonce : palette.fonceDim;
  }

  /// Retourner le plateau : Kivy l'autorise même en ligne.
  bool? _flipOverride;

  void _toggleFlip() => setState(
    () => _flipOverride = !(_flipOverride ?? (_g.myCamp == Camp.blanc)),
  );

  /// La pause. En ligne, elle ne propose pas de quitter : on abandonne la
  /// partie par le [×] de son panneau, et le match entre deux parties.
  Future<void> _openPause() async {
    await showPauseDialog(
      context,
      palette: paletteOf(Settings.instance.themeAxes.general),
      quit: PauseQuit.none,
    );
    if (!mounted) return;
    _sounds.applySettings();
    setState(() {});
  }

  Widget _banner(ThemePalette palette, Camp camp) {
    final isMine = camp == _g.myCamp;
    // En ligne, Kivy écrit le mélo à côté du nom : « Nino  (1500) ».
    final melo = isMine
        ? (_g.newMelo ?? OnlineService.instance.session?.melo ?? 1500)
        : _g.info.opponentMelo;
    var label = '${isMine ? widget.myPseudo : _g.info.opponent}  ($melo)';
    var nameColor = kPanelInk;

    // Adversaire déconnecté : son nom porte le décompte, en rouge — c'est lui
    // qui perd le match si le compte arrive à zéro.
    if (!isMine && !_g.opponentConnected) {
      final delay = _g.disconnectGrace;
      label = delay == null || delay <= 0
          ? T('%s (abandon…)').replaceFirst('%s', _g.info.opponent)
          : T(
              '%s (déco %ds)',
            ).replaceFirst('%s', _g.info.opponent).replaceFirst('%d', '$delay');
      nameColor = const Color.fromRGBO(230, 102, 102, 1);
    }

    String? subtitle;
    if (isMine && _g.meloDelta != null) {
      final d = _g.meloDelta!;
      subtitle = '${d >= 0 ? '+' : ''}$d';
    }

    // Les gestes (↶ ½ X) n'appartiennent qu'à MON panneau : en ligne, je ne
    // peux ni annuler ni abandonner à la place de l'adversaire.
    final canAct = isMine && !_g.game.gameOver;

    return PlayerPanel(
      name: label,
      nameColor: nameColor,
      onNameTap: () => showNameMenu(
        context,
        online: OnlineService.instance,
        pseudo: isMine
            ? (OnlineService.instance.pseudo ?? '')
            : _g.info.opponent,
      ),
      subtitle: subtitle,
      clock: _g.clock.displayFor(camp),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _g.game.turn == camp && !_g.game.gameOver,
      captures: _g.game.captured[camp.opposite] ?? const [],
      photo: isMine
          ? (OnlineService.instance.session?.photo ?? '')
          : _photoAdverse,
      score: _g.scoreLine.isEmpty
          ? null
          : (camp == Camp.blanc ? '${_g.scoreBlanc}' : '${_g.scoreNoir}'),
      busy: !isMine && !_g.opponentConnected,
      mirrored: isMine,
      onUndo: canAct && _g.game.canValidate
          ? () {
              if (_g.game.cancelCurrentMove()) setState(() {});
            }
          : null,
      onDraw: canAct ? _g.offerDraw : null,
      onResign: canAct ? _confirmResign : null,
    );
  }

  /// Quitter un match en cours : c'est un abandon du match entier.
  Future<void> _quitMatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(T('Quitter le match ?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Quitter le match')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _g.resignMatch();
    if (mounted) Navigator.of(context).pop();
  }

  /// Range la partie finie dans l'historique en ligne du compte.
  ///
  /// Ce port ne le faisait qu'au départ de l'écran de jeu local : une partie
  /// en ligne n'entrait donc dans l'historique de personne. Chaque partie d'un
  /// match a son propre identifiant serveur, donc sa propre entrée — et le
  /// même des deux côtés.
  void _archive() {
    final id = _g.info.gameId;
    if (id.isEmpty || _archivedGames.contains(id)) return;
    _archivedGames.add(id);
    unawaited(
      _store.store(
        buildOpponentArchive(
          myPseudo: widget.myPseudo,
          opponent: _g.info.opponent,
          myCamp: _g.myCamp,
          winner: _g.loser?.opposite,
          method: _g.endReason ?? 'nulle',
          history: List.of(_g.game.history),
          objectif: _g.info.objectif,
          cadence: _g.info.cadence,
          randomCode: _g.info.randomCode,
          onlineGameId: id,
        ),
      ),
    );
  }

  /// Fin de partie : le popup de Kivy. Si le match continue, il propose la
  /// partie suivante ; sinon il annonce le résultat, le mélo, et le retour au
  /// menu.
  void _showEnd() {
    final palette = paletteOf(Settings.instance.themeAxes.general);
    final title = _verdict ?? T('Partie terminée');

    if (_g.matchContinues) {
      unawaited(
        showOnlineContinueDialog(
          context,
          palette: palette,
          title: title,
          body: _g.scoreLine,
          readySent: _g.readySent,
          onReady: () => setState(_g.readyForNext),
          onQuit: _quitMatch,
        ),
      );
      return;
    }

    final melo = _g.newMelo;
    final delta = _g.meloDelta;
    unawaited(
      showFinishDialog(
        context,
        palette: palette,
        title: title,
        body: _g.scoreLine,
        winner: switch (_g.loser?.opposite) {
          null => null,
          final Camp w => w == _g.myCamp ? widget.myPseudo : _g.info.opponent,
        },
        meloLine: (melo == null || delta == null)
            ? T('Mise à jour du mélo…')
            : T('Mélo : %d  (%s%d)')
                  .replaceFirst('%d', '$melo')
                  .replaceFirst('%s', delta >= 0 ? '+' : '')
                  .replaceFirst('%d', '$delta'),
        onMenu: () {
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
