/// Lecteur de parties : on rejoue une partie enregistrée, coup par coup.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../engine/board.dart';
import '../../game/clock.dart';
import '../../game/slides.dart';
import '../../game/nmc.dart';
import '../../game/replay_controller.dart';
import '../../game/vitesse_lecture.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../net/avatar_photos.dart';
import '../../net/favoris_connus.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../suit_les_reglages.dart';
import '../widgets/fuga_background.dart';
import '../widgets/deep_grey_dialog.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_layout.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/move_strip.dart';
import '../../engine/fug.dart';
import '../widgets/nmc_dialog.dart';
import '../widgets/slide_animation.dart';
import '../widgets/auto_play_bar.dart';
import '../../game/defi_relais.dart';
import '../widgets/player_card.dart';
import '../widgets/player_panel.dart';
import 'game_screen.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({
    super.key,
    required this.nmc,
    this.title,
    this.sounds,
    this.online,
  });

  /// Contenu du fichier `.nmc`.
  final String nmc;

  final String? title;

  /// Le lecteur de sons. Injectable pour les tests : sans quoi « la première
  /// note de la valse sonne-t-elle plus fort ? » ne se vérifie qu'à l'oreille.
  final SoundPlayer? sounds;

  /// Le compte, pour les visages et la fiche des joueurs. Injectable aussi :
  /// le service de session est un singleton qui parle au VRAI serveur, et un
  /// test n'a rien à y faire.
  final OnlineService? online;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen>
    with SlideAnimation, SuitLesReglages {
  late final ReplayController _replay;
  late final SoundPlayer _sounds = widget.sounds ?? SoundPlayer();
  OnlineService get _online => widget.online ?? OnlineService.instance;
  bool _flipped = true;

  /// Lecture automatique : les commandes sont-elles ouvertes ?
  bool _auto = false;

  /// Et défile-t-elle ?
  bool _enLecture = false;

  /// Temps entre deux coups, en secondes.
  double _vitesse = kVitesseDefaut;
  Timer? _battement;

  @override
  void initState() {
    super.initState();
    _replay = ReplayController.fromNmc(widget.nmc);
    // Kivy ouvre la relecture sur le premier coup joué, pas sur la position
    // de départ (`viewing_idx = 0` à la fin de `load_replay`).
    _replay.goTo(1);
    _sounds.init();
    unawaited(_visages());
  }

  /// Les visages et les étoiles des deux joueurs de l'en-tête.
  ///
  /// Un `.nmc` ne porte que des NOMS : le lecteur montrait donc la pièce par
  /// défaut pour tout le monde. Quand ce sont des comptes, le serveur connaît
  /// leur photo et sait lesquels sont dans mes favoris — Nino : « dans
  /// l'historique, ce serait bien si ça affichait l'image de profil liée au
  /// nom de compte ».
  ///
  /// Une requête par joueur, et une seule : les deux caches la partagent, et
  /// une partie ouverte après une autre ne redemande rien. Hors ligne, rien
  /// n'est demandé et le lecteur garde ses pièces par défaut.
  Future<void> _visages() async {
    final online = _online;
    if (!online.isLoggedIn) return;
    final meta = _replay.meta;
    for (final nom in {meta.player1, meta.player2}) {
      if (nom.trim().isEmpty) continue;
      await AvatarPhotos.resolve(nom, online: online);
      // Deep Grey n'est pas un compte, et on n'est pas son propre favori :
      // deux requêtes qui ne peuvent rien rapporter.
      if (AvatarPhotos.isDeepGrey(nom) || nom == online.pseudo) continue;
      await FavorisConnus.instance.demande(nom, online: online);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _battement?.cancel();
    _sounds.dispose();
    super.dispose();
  }

  /// Un coup, puis l'attente, puis le suivant.
  ///
  /// Le minuteur est REFAIT à chaque battement plutôt que périodique : la
  /// vitesse peut changer entre deux coups — on tire le curseur — et un
  /// minuteur périodique garderait l'ancienne cadence jusqu'à son prochain
  /// déclenchement.
  void _armer() {
    _battement?.cancel();
    if (!_enLecture) return;
    _battement = Timer(vitesseEnDuree(_vitesse), _battre);
  }

  void _battre() {
    if (!mounted || !_enLecture) return;
    if (_replay.atEnd) {
      // Arrivé au bout, on s'arrête : reboucler sans le dire surprendrait.
      setState(() => _enLecture = false);
      return;
    }
    _move(_replay.next);
    _armer();
  }

  void _playPause() {
    setState(() {
      // Au bout, « lire » recommence depuis le début : sans cela la touche ne
      // ferait rien, et on ne saurait pas pourquoi.
      if (!_enLecture && _replay.atEnd) _move(_replay.toStart);
      _enLecture = !_enLecture;
    });
    _armer();
  }

  void _auDebut() {
    _move(_replay.toStart);
    _armer();
  }

  /// Changer de vitesse : le battement en cours garde sa durée, le suivant
  /// prend la nouvelle. Réarmer ici couperait la note qui sonne.
  void _setVitesse(double secondes) {
    setState(() => _vitesse = secondes);
  }

  /// Avance ou recule, en jouant le son ET le glissement du coup atteint.
  ///
  /// Le son suit la navigation : en avançant on entend le coup joué, en
  /// reculant on entend celui auquel on revient. Les pièces suivent de même —
  /// elles ne le faisaient pas, et parcourir une partie enregistrée faisait
  /// sauter le plateau d'une position à l'autre sans qu'on voie rien bouger.
  void _move(bool Function() action) {
    final avant = _replay.index;
    if (!action()) return;
    _animerVers(avant, _replay.index);
    _sounds.playNotation(_replay.current.notation);
    setState(() {});
  }

  /// Fait glisser les pièces entre deux positions de la partie.
  ///
  /// Toucher un coup du bandeau, même lointain, montre CE coup se jouer : on
  /// part de la position qui le précède. Reculer rejoue le coup à l'envers,
  /// atterrissages de multisaut compris, dans l'autre sens.
  void _animerVers(int depuis, int vers) {
    if (depuis == vers) return;
    final recule = vers < depuis;
    // En reculant : le coup défait est celui qu'on QUITTE — `steps[depuis]`,
    // pas `steps[vers + 1]`, qui ne lui est égal que d'un cran à l'autre. En
    // sautant de plusieurs coups en arrière, on défaisait donc le mauvais.
    // En avançant : le coup qui mène là où l'on va.
    final coup = recule ? _replay.steps[depuis] : _replay.steps[vers];
    final origine = recule ? _replay.steps[depuis] : _replay.steps[vers - 1];
    final arrivee = _replay.steps[vers];
    // Reculer d'un seul cran défait un coup connu : on peut le rejouer à
    // l'envers, atterrissages compris. Sauter plus loin, non.
    final unSeulCran = !recule || depuis - vers == 1;

    final chemin = unSeulCran
        ? (coup.lastMove?.jumpPath ?? const <Cell>[])
        : const <Cell>[];
    final glissees = glisseesDuCoup(
      avant: recule ? arrivee.board : origine.board,
      apres: recule ? origine.board : arrivee.board,
      notation: unSeulCran ? (coup.notation ?? '') : '',
      recule: recule,
    );
    rememberSlides(
      glissees,
      jumpPath: recule ? chemin.reversed.toList() : chemin,
    );
  }

  /// Reprend la partie depuis la position affichée, seul ou contre l'IA.
  ///
  /// Sans camp choisi, on repart en analyse plutôt que contre l'IA : mieux
  /// vaut une partie libre qu'un écran qui se ferme.
  Future<void> _playFromHere(bool againstAi, {Camp? myCamp}) async {
    final step = _replay.current;
    final ai = againstAi ? myCamp?.opposite : null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: Cadence.zen,
          aiCamp: ai,
          initialBoard: step.board.clone(),
          initialTurn: step.turn,
          initialFugued: step.fugued,
          analysis: ai == null,
          // On reprend la position telle qu'on la regardait.
          initialFlipped: ai == null ? _flipped : null,
          themeName: Settings.instance.themeAxes.general,
        ),
      ),
    );
  }

  /// Contre Deep Grey : le joueur choisit son camp, le trait ne change pas.
  Future<void> _playAgainstDeepGrey() async {
    final mine = await askDeepGreyCamp(context);
    if (mine == null || !mounted) return;
    await _playFromHere(true, myCamp: mine);
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final step = _replay.current;
    final meta = _replay.meta;
    // `_flipped` vrai = Blancs en bas, comme en Kivy.
    final topCamp = _flipped ? Camp.noir : Camp.blanc;
    final bottomCamp = _flipped ? Camp.blanc : Camp.noir;

    return FugaScaffold(
      // Le bandeau touche le HAUT de l'écran, comme en Kivy : en plein
      // écran immersif il n'y a pas de barre d'état à éviter, et la bande
      // laissée au-dessus mangeait de la place au plateau.
      body: SafeArea(
        top: false,
        child: GameLayout(
          topBar: GameTopBar(
            palette: palette,
            // En relecture, le bandeau prend la couleur du camp au trait.
            color: step.turn == Camp.blanc ? palette.clair : palette.fonce,
            onFlip: () => setState(() => _flipped = !_flipped),
            pauseLabel: '<<',
            onPause: () => Navigator.of(context).pop(),
            // Deux choses à copier, une seule touche : mesuré, une
            // quatrième touche large déborde du bandeau sur un écran de
            // 320 points.
            onCopyNmc: () => showCopyChoice(
              context,
              nmc: widget.nmc,
              fug: fugEcrire(step.board, step.turn),
            ),
            onAnalyse: () => _playFromHere(false),
            onDeepGrey: _playAgainstDeepGrey,
            onAutoPlay: () => setState(() {
              _auto = !_auto;
              if (!_auto) {
                _enLecture = false;
                _battement?.cancel();
              }
            }),
            autoPlayOn: _auto,
          ),
          notice: _replay.isTruncated ? _truncatedNotice() : null,
          topPanel: _panel(palette, topCamp, meta),
          board: GameBoardView(
            board: step.board,
            palette: palette,
            flipped: _flipped,
            onTapCell: (_) {},
            lastMove: step.lastMove,
            fuguedHeirs: step.fugued,
            slides: slides,
            slideToken: slideToken,
            slideDuration: slideDuration,
            slideJumpPath: slideJumpPath,
            pieceTheme: axes.pieces,
            boardTheme: axes.board,
          ),
          // En lecture automatique, les informations du joueur du bas
          // laissent la place aux commandes — on ne garde que les pièces
          // capturées. Et la bande s'épaissit : un curseur et deux touches ne
          // tiennent pas dans les douze parts d'un panneau.
          bottomParts: _auto ? 24 : 12,
          bottomPanel: _auto
              ? AutoPlayBar(
                  palette: palette,
                  captures:
                      _replay.current.captured[bottomCamp.opposite] ?? const [],
                  secondes: _vitesse,
                  enLecture: _enLecture,
                  onTempo: _setVitesse,
                  onDebut: _auDebut,
                  onPlayPause: _playPause,
                )
              : _panel(palette, bottomCamp, meta),
          moveStrip: MoveStrip(
            moves: [
              for (var i = 1; i < _replay.steps.length; i++)
                _replay.steps[i].notation ?? '',
            ],
            activeIndex: _replay.index - 1,
            color: bottomCamp == Camp.blanc ? palette.clair : palette.fonce,
            palette: palette,
            randomCode: meta.random,
            onSelect: (i) => _move(() => _replay.goTo(i + 1)),
          ),
        ),
      ),
    );
  }

  /// Panneau d'un joueur, rempli avec l'en-tête du fichier : les noms, le
  /// chrono de la cadence enregistrée, et les pièces prises à cet instant.
  Widget _panel(ThemePalette palette, Camp camp, NmcMeta meta) {
    final blancIsFirst = meta.blanc.isEmpty || meta.blanc == meta.player1;
    final name = (camp == Camp.blanc) == blancIsFirst
        ? meta.player1
        : meta.player2;

    return PlayerPanel(
      name: name.isEmpty ? T('Joueur 1') : name,
      // Ce que les caches savent à l'instant : vide tant que la réponse n'est
      // pas là, et le `setState` de `_visages` repasse par ici.
      photo: AvatarPhotos.known(name),
      favori: FavorisConnus.instance.connu(name) ?? false,
      clock: _clockLabel(meta.cadence),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _replay.current.turn == camp,
      captures: _replay.current.captured[camp.opposite] ?? const [],
      score: '0 / ${meta.objectif == 'partie' ? '1' : meta.objectif}',
      // La fiche s'ouvre sur un VRAI joueur, et seulement connecté : « Joueur
      // 1 » et Deep Grey n'ont pas de compte. Sinon, pas de geste du tout —
      // un toucher qui n'ouvre rien ne vaut pas mieux qu'aucun toucher.
      // Nino : « ça doit aussi marcher depuis les parties dans l'historique. »
      onNameTap: _online.isLoggedIn && isRealPlayer(name)
          ? () => _fiche(name, palette)
          : null,
    );
  }

  /// LA fiche du joueur, et le défi qu'elle peut lancer : le menu est resté
  /// à l'écoute sous cet écran, c'est lui qui le mène.
  Future<void> _fiche(String pseudo, ThemePalette palette) async {
    final cible = await showPlayerCard(
      context,
      online: _online,
      palette: palette,
      pseudo: pseudo,
    );
    if (cible != null) await DefiRelais.defier(cible);
  }

  /// Chrono affiché en relecture : Kivy y remet la pendule de la cadence
  /// enregistrée (`load_replay`), pas le temps réellement consommé.
  String _clockLabel(String cadence) {
    if (cadence == 'zen' || cadence.isEmpty) return '∞';
    final minutes = int.tryParse(cadence) ?? 15;
    return '${minutes.toString().padLeft(2, '0')}:00';
  }

  /// La partie n'a pas pu être rejouée jusqu'au bout : on le dit, au lieu de
  /// laisser croire qu'elle s'arrêtait là.
  Widget _truncatedNotice() => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(vertical: S(6), horizontal: S(16)),
    color: FugaColors.immobile.withValues(alpha: 0.85),
    child: Text(
      '${T("Lecture interrompue au coup")} ${_replay.brokenMoveNumber}',
      style: TextStyle(color: Colors.white, fontSize: SF(12)),
    ),
  );
}
