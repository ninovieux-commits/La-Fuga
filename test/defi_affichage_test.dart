/// Recevoir un défi : l'aperçu, puis l'écran.
///
/// Nino : « Quand on reçoit un défi par correspondance, l'aperçu doit
/// afficher "Défi de pseudo", "Mode: standard/random/personnalisé", "Bouton
/// (afficher le défi)". Plus de bouton accepter, refuser. Le joueur clique sur
/// afficher le défi et le plateau dans la position de départ s'affiche avec en
/// bas du plateau les boutons (accepter le défi) et (refuser le défi). »
///
/// Et : « ligne "couleur: noir/blanc/aléatoire" à ajouter sur l'aperçu […] le
/// plateau le place du côté déterminé s'il y en a un […] Il faut aussi que le
/// score soit présent sur l'aperçu et sur l'affichage. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/fug.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/challenge_screen.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    clearReplayCache();
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  CorrGame defi({
    String mode = 'standard',
    String position = '',
    String couleur = '',
    bool parMoi = false,
  }) => CorrGame.fromJson({
    'id': 'g1',
    'statut': 'defi',
    'adversaire': 'celia',
    'ma_couleur': 'Blanc',
    'turn': 'Blanc',
    'my_turn': false,
    'moves_text': '',
    'objectif': 'partie',
    'is_defieur': parMoi,
    'mon_score': 3,
    'score_adverse': 1,
    'mode': mode,
    if (position.isNotEmpty) 'position': position,
    if (couleur.isNotEmpty) 'couleur': couleur,
  });

  group('L aperçu d un défi reçu', () {
    Future<void> poser(WidgetTester tester, CorrGame g) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                height: 206,
                child: CorrSlot(
                  game: g,
                  palette: paletteOf('foret'),
                  boardTheme: 'bois',
                  pieceTheme: 'classique',
                  onTap: () {},
                  onAccept: (_) {},
                  onRefuse: (_) {},
                  onCancel: (_) {},
                  onRematch: (_) {},
                  onClose: (_) {},
                  onShow: (_) {},
                  onShowChallenge: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('il dit qui, le mode, la couleur — et mène à l écran', (
      tester,
    ) async {
      await poser(tester, defi(mode: 'personnalise', couleur: 'Blanc'));
      expect(find.textContaining('Défi de'), findsOneWidget);
      expect(find.textContaining('celia'), findsWidgets);
      expect(find.textContaining('Personnalisé'), findsWidgets);
      expect(find.textContaining('Couleur'), findsOneWidget);
      expect(
        find.textContaining('Noirs'),
        findsOneWidget,
        reason: 'il a demandé les Blancs : je joue donc les Noirs',
      );
      expect(find.text('Afficher le défi'), findsOneWidget);
    });

    testWidgets('plus d Accepter ni de Refuser sur l aperçu', (tester) async {
      await poser(tester, defi());
      expect(find.text('Accepter'), findsNothing);
      expect(find.text('Refuser'), findsNothing);
    });

    testWidgets('le score y est', (tester) async {
      await poser(tester, defi());
      expect(find.textContaining('3 - 1'), findsOneWidget);
    });

    testWidgets('aléatoire se dit « Aléatoire », et rien de plus', (
      tester,
    ) async {
      await poser(tester, defi());
      expect(find.textContaining('Aléatoire'), findsOneWidget);
      expect(
        find.textContaining('Blancs'),
        findsNothing,
        reason: 'personne ne doit savoir qui aura les Blancs',
      );
      expect(find.textContaining('Noirs'), findsNothing);
    });

    testWidgets('mon propre défi attend, et s annule', (tester) async {
      await poser(tester, defi(parMoi: true));
      expect(find.textContaining('En attente'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Afficher le défi'), findsNothing);
    });
  });

  group('L écran du défi', () {
    Future<void> ouvrir(WidgetTester tester, CorrGame g) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ChallengeScreen(game: g)));
      await tester.pumpAndSettle();
    }

    testWidgets('les infos au-dessus, les deux touches en dessous', (
      tester,
    ) async {
      await ouvrir(tester, defi(couleur: 'Noir'));
      expect(find.textContaining('Défi de celia'), findsOneWidget);
      expect(find.textContaining('Mode : Standard'), findsOneWidget);
      expect(find.textContaining('Score : 3 - 1'), findsOneWidget);
      // La couleur annoncée est celle du DÉFIEUR ; c'est la MIENNE qui doit
      // s'afficher. Il a demandé les Noirs : je joue donc les Blancs.
      expect(
        find.textContaining('Couleur : Blancs'),
        findsOneWidget,
        reason: 'c est la couleur que JE jouerai qui m intéresse',
      );
      expect(find.text('Accepter le défi'), findsOneWidget);
      expect(find.text('Refuser le défi'), findsOneWidget);

      final plateau = tester.getRect(find.byType(GameBoardView));
      expect(
        tester.getCenter(find.textContaining('Défi de celia')).dy,
        lessThan(plateau.top),
        reason: 'les infos vont AU-DESSUS du plateau',
      );
      expect(
        tester.getCenter(find.text('Accepter le défi')).dy,
        greaterThan(plateau.bottom),
        reason: 'les touches vont EN DESSOUS',
      );
    });

    testWidgets('la position composée est celle qui s affiche', (tester) async {
      final b = Board.empty();
      b.set(0, 0, Piece.blancHeritier);
      b.set(2, 0, Piece.blancSoldat);
      b.set(3, 0, Piece.blancGarde);
      b.set(0, 7, Piece.noirHeritier);
      b.set(2, 7, Piece.noirSoldat);
      b.set(3, 7, Piece.noirGarde);
      await ouvrir(
        tester,
        defi(
          mode: 'personnalise',
          position: fugEnUneLigne(fugEcrire(b, Camp.noir)),
        ),
      );
      expect(
        tester
            .widget<GameBoardView>(find.byType(GameBoardView))
            .board
            .positionKey(Camp.blanc),
        b.positionKey(Camp.blanc),
        reason: 'ce n est pas la position proposée qui s affiche',
      );
    });

    testWidgets('le plateau se place du côté annoncé', (tester) async {
      // Il demande les Blancs : je joue les Noirs, donc mes pièces en bas.
      await ouvrir(tester, defi(couleur: 'Blanc'));
      expect(
        tester.widget<GameBoardView>(find.byType(GameBoardView)).flipped,
        isFalse,
        reason: 'je joue les Noirs : le plateau se retourne',
      );

      await ouvrir(tester, defi(couleur: 'Noir'));
      expect(
        tester.widget<GameBoardView>(find.byType(GameBoardView)).flipped,
        isTrue,
      );
    });

    testWidgets('aléatoire : vue des Blancs, et aucune couleur nommée', (
      tester,
    ) async {
      await ouvrir(tester, defi());
      expect(
        tester.widget<GameBoardView>(find.byType(GameBoardView)).flipped,
        isTrue,
        reason: 'par convention, la vue des Blancs quand rien n est décidé',
      );
      expect(find.textContaining('Couleur : Aléatoire'), findsOneWidget);
    });

    testWidgets('accepter et refuser rendent des réponses différentes', (
      tester,
    ) async {
      for (final (texte, attendu) in [
        ('Accepter le défi', ChallengeAnswer.accepte),
        ('Refuser le défi', ChallengeAnswer.refuse),
      ]) {
        ChallengeAnswer? reponse;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async =>
                    reponse = await Navigator.of(context).push<ChallengeAnswer>(
                      MaterialPageRoute<ChallengeAnswer>(
                        builder: (_) => ChallengeScreen(game: defi()),
                      ),
                    ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(texte));
        await tester.pumpAndSettle();
        await tester.tap(find.text(texte));
        await tester.pumpAndSettle();
        expect(reponse, attendu, reason: texte);
      }
    });
  });
}
