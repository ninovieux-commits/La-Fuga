/// Un défi de correspondance, en grand : la position proposée, et de quoi
/// répondre.
///
/// L'aperçu du menu ne porte plus les touches « Accepter » et « Refuser ». On
/// ne dit plus oui à une partie sans avoir vu d'où elle part — et depuis qu'un
/// défi peut arriver avec une position composée de toutes pièces, la question
/// n'est plus rhétorique.
///
/// Le plateau se place du côté qui est annoncé, quand il l'est. En mode
/// aléatoire, rien n'est annoncé : la couleur sera tirée quand la partie
/// démarrera, et personne ne la connaît avant — on affiche donc la vue des
/// Blancs, par convention.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/correspondence.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_top_bar.dart';

/// Ce que le joueur a répondu.
enum ChallengeAnswer { accepte, refuse }

class ChallengeScreen extends StatelessWidget {
  const ChallengeScreen({super.key, required this.game});

  final CorrGame game;

  /// La couleur annoncée, DE MON point de vue : celle que je jouerai.
  ///
  /// Le serveur range la couleur du défieur ; c'est la mienne qui m'intéresse.
  String get _couleurDite {
    final sienne = game.couleurAnnoncee;
    if (sienne == null) return T('Aléatoire');
    // Je reçois le défi : j'ai l'autre couleur.
    final mienne = game.isChallenger ? sienne : sienne.opposite;
    return mienne == Camp.blanc ? T('Blancs') : T('Noirs');
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final sienne = game.couleurAnnoncee;
    final mienne = sienne == null
        ? null
        : (game.isChallenger ? sienne : sienne.opposite);

    return FugaScaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 7 / 104,
              child: GameTopBar(
                palette: palette,
                color: palette.fonce,
                onFlip: () {},
                pauseLabel: '<<',
                onPause: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(S(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infos(palette),
                    SizedBox(height: S(8)),
                    AspectRatio(
                      // La place que le plateau dessine, zones de ralliement
                      // comprises.
                      aspectRatio: kCols / kExtRows,
                      child: GameBoardView(
                        board: game.startBoard,
                        palette: palette,
                        // Mes pièces en bas quand ma couleur est connue ;
                        // sinon la vue des Blancs, qui n'apprend rien.
                        flipped: (mienne ?? Camp.blanc) == Camp.blanc,
                        onTapCell: (_) {},
                        pieceTheme: axes.pieces,
                        boardTheme: axes.board,
                      ),
                    ),
                    SizedBox(height: S(10)),
                    if (!game.isChallenger)
                      Row(
                        children: [
                          Expanded(
                            child: FugaButton(
                              text: T('Accepter le défi'),
                              color: palette.fonce,
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(ChallengeAnswer.accepte),
                            ),
                          ),
                          SizedBox(width: S(8)),
                          Expanded(
                            child: FugaButton(
                              text: T('Refuser le défi'),
                              color: const Color(0xFF8C1A1A),
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(ChallengeAnswer.refuse),
                            ),
                          ),
                        ],
                      )
                    else
                      // Mon propre défi : rien à accepter, il est en attente.
                      Center(
                        child: Text(
                          T('En attente…'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: SF(16),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Les informations du défi, au-dessus du plateau : qui, d'où part la
  /// partie, avec quelle couleur, et où en est le score entre nous.
  Widget _infos(ThemePalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        game.isChallenger
            ? '${T('Défi à')} ${game.opponent}'
            : '${T('Défi de')} ${game.opponent}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: SF(18),
          fontWeight: FontWeight.bold,
        ),
      ),
      SizedBox(height: S(4)),
      for (final (cle, valeur) in [
        (T('Mode'), game.mode.label),
        (T('Couleur'), _couleurDite),
        (T('Score'), '${game.myScore} - ${game.opponentScore}'),
        (T('Mélo'), '${game.opponentMelo}'),
      ])
        Padding(
          padding: EdgeInsets.symmetric(vertical: S(1)),
          child: Text(
            '$cle : $valeur',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.clair, fontSize: SF(14)),
          ),
        ),
    ],
  );
}
