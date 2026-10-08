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
import '../../game/rythmique.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
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
import '../widgets/player_panel.dart';
import 'game_screen.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key, required this.nmc, this.title, this.sounds});

  /// Contenu du fichier `.nmc`.
  final String nmc;

  final String? title;

  /// Le lecteur de sons. Injectable pour les tests : sans quoi « la première
  /// note de la valse sonne-t-elle plus fort ? » ne se vérifie qu'à l'oreille.
  final SoundPlayer? sounds;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> with SlideAnimation {
  late final ReplayController _replay;
  late final SoundPlayer _sounds = widget.sounds ?? SoundPlayer();
  bool _flipped = true;

  /// Lecture automatique : les commandes sont-elles ouvertes ?
  bool _auto = false;

  /// Et défile-t-elle ?
  bool _enLecture = false;

  TempoLecture _tempo = TempoLecture.defaut;
  Timer? _battement;

  /// Combien de coups la lecture a joués depuis qu'elle est partie.
  ///
  /// C'est ce qui dit OÙ L'ON EN EST DANS LA MESURE : les écarts d'une danse ne
  /// sont pas tous égaux — la sarabande boite — et il faut donc savoir quel
  /// écart vient ensuite. Remis à zéro dès qu'on repart : une mesure commence.
  int _coupsJoues = 0;

  @override
  void initState() {
    super.initState();
    _replay = ReplayController.fromNmc(widget.nmc);
    // Kivy ouvre la relecture sur le premier coup joué, pas sur la position
    // de départ (`viewing_idx = 0` à la fin de `load_replay`).
    _replay.goTo(1);
    _sounds.init();
  }

  @override
  void dispose() {
    _battement?.cancel();
    _sounds.dispose();
    super.dispose();
  }

  /// Un coup sur chaque temps JOUÉ — et une pause sur les autres.
  ///
  /// Le minuteur est REFAIT à chaque battement plutôt que périodique, pour deux
  /// raisons. La vitesse peut changer entre deux coups — on tire le curseur, on
  /// choisit une danse — et un minuteur périodique garderait l'ancienne cadence
  /// jusqu'à son prochain déclenchement. Et surtout, dans une danse les écarts
  /// ne sont pas tous égaux : la sarabande attend un temps, puis deux. Un seul
  /// intervalle ne saurait pas les dire.
  void _armer() {
    _battement?.cancel();
    if (!_enLecture) return;
    _battement = Timer(_tempo.ecartAvant(_coupsJoues), _battre);
  }

  void _battre() {
    if (!mounted || !_enLecture) return;
    if (_replay.atEnd) {
      // Arrivé au bout, on s'arrête : reboucler sans le dire surprendrait.
      setState(() => _enLecture = false);
      return;
    }
    // L'accent de la danse : le temps fort garde sa pleine voix, les faibles
    // sont retenus. Hors d'une danse, tous les coups valent 1.
    _move(_replay.next, force: _tempo.forceDe(_coupsJoues));
    _coupsJoues++;
    _armer();
  }

  void _playPause() {
    setState(() {
      // Au bout, « lire » recommence depuis le début : sans cela la touche ne
      // ferait rien, et on ne saurait pas pourquoi.
      if (!_enLecture && _replay.atEnd) _move(_replay.toStart);
      _enLecture = !_enLecture;
      // On repart au premier temps de la mesure : reprendre au milieu d'un
      // motif ferait entrer la danse de travers.
      _coupsJoues = 0;
    });
    _armer();
  }

  void _auDebut() {
    _move(_replay.toStart);
    _coupsJoues = 0;
    _armer();
  }

  /// Changer de vitesse : le battement en cours garde sa durée, le suivant
  /// prend la nouvelle. Réarmer ici couperait la note qui sonne.
  ///
  /// Changer de danse remet la mesure à son début — le motif de la nouvelle
  /// n'a rien à voir avec l'endroit où l'ancienne en était.
  void _setTempo(TempoLecture t) {
    setState(() {
      if (t.rythmique != _tempo.rythmique) _coupsJoues = 0;
      _tempo = t;
    });
  }

  /// Avance ou recule, en jouant le son ET le glissement du coup atteint.
  ///
  /// Le son suit la navigation : en avançant on entend le coup joué, en
  /// reculant on entend celui auquel on revient. Les pièces suivent de même —
  /// elles ne le faisaient pas, et parcourir une partie enregistrée faisait
  /// sauter le plateau d'une position à l'autre sans qu'on voie rien bouger.
  void _move(bool Function() action, {double force = 1}) {
    final avant = _replay.index;
    if (!action()) return;
    _animerVers(avant, _replay.index);
    _sounds.playNotation(_replay.current.notation, gain: force);
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
          // capturées. Et la bande s'épaissit : un curseur et trois touches
          // ne tiennent pas dans les douze parts d'un panneau.
          bottomParts: _auto ? 30 : 12,
          bottomPanel: _auto
              ? AutoPlayBar(
                  palette: palette,
                  captures:
                      _replay.current.captured[bottomCamp.opposite] ?? const [],
                  tempo: _tempo,
                  enLecture: _enLecture,
                  onTempo: (v) => _setTempo(TempoLecture.libre(v)),
                  onRythmique: (r) => _setTempo(
                    r == null
                        ? TempoLecture.libre(
                            _tempo.secondes == 0
                                ? kVitesseMin * 2
                                : _tempo.secondes,
                          )
                        : TempoLecture.danse(r),
                  ),
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
      clock: _clockLabel(meta.cadence),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _replay.current.turn == camp,
      captures: _replay.current.captured[camp.opposite] ?? const [],
      score: '0 / ${meta.objectif == 'partie' ? '1' : meta.objectif}',
    );
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
