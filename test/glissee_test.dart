/// Trois bugs de la glissée, rapportés par Nino.
///
///   1. « quand on revient en arrière avec la flèche directionnelle, la
///      glissée n'est pas inversée » ;
///   2. « lors d'un multisaut, la pièce va trop vite. Les glissées doivent
///      toujours laisser les pièces aller à la même vitesse » ;
///   3. « quand plusieurs pièces identiques bougent en même temps, ces pièces
///      identiques s'inversent parfois ».
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/game/slides.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
import 'package:lafuga/ui/widgets/board_painter.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Cell _c(String n) => notationToCell(n)!;

/// Trois vraies parties, prises telles quelles sur le serveur.
const _vraiesParties = <List<String>>[
  [
    // partie 1 — 34 coups
    'Fa3-Sol4',
    'Fa6-Sol5',
    'Sol2-Fa3',
    '(Si7Si8)-Si6',
    'Fa2-Fa4',
    'Fa8-La6',
    'Fa1-Fa2',
    'La7-La5',
    'Fa4-Fa5',
    'Sol5-Fa4',
    'Sol4-Sol5',
    'Sol7-Sol6',
    'Fa2-Sol3',
    'La6-Fa2',
    '(Mi1Do1Ré1)-Fa1',
    'Fa7-Mi6',
    'Sol3-Sol4',
    '(Mi8Do8Ré8)-Fa8',
    '(Si2Si1)-Si3',
    'Ré8-Do8>',
    'Mi2-Si4',
    'Do8-Ré8>Mi7',
    'Fa3-Mi4',
    'Ré8-Ré7>Mi6',
    'La2-La6',
    '(Ré7Do7)-Mi7',
    'Si2-La2',
    'Fa4-Sol3',
    'La2-Fa4',
    'La5-Fa3',
    'Ré1-Do1>',
    'Mi8-Fa7>Fa6',
    'Fa3-La7',
    'Fa1*',
  ],
  [
    // partie 18 — 65 coups
    'Fa3-Sol4',
    'Fa6-Sol5',
    'Fa1-La3',
    'La7-Sol6',
    'Sol2-Sol3',
    'Fa8-Fa6',
    'Fa2-La4',
    'Sol7-Mi5',
    'La2-Ré6',
    'Fa7-Fa5',
    'La3-Fa7',
    '(Sol8La8Si7Si8)-Fa8',
    'Ré2-Fa2',
    'Ré7-Ré5',
    'Sol3-Fa4',
    'Mi7-Mi6',
    'Sol4-Fa3',
    'La8-Sol7>Fa7',
    'Mi7-Fa7',
    '(La7Do7Do8Ré8Mi8Fa8Sol7Sol8)-Si7',
    'Mi2-Mi3',
    'Ré8-Mi7',
    '(Mi1Do1Do2Ré1)-Mi2',
    'Ré5-Ré4',
    '(Ré2Do2Do3)-Ré3',
    'Mi6-Ré5',
    'Ré3-Mi4>Mi5Fa4',
    'Ré7-Ré8',
    'Do3-Ré3>Mi4',
    'Mi8-Ré7>Ré6Mi7',
    'Mi2-Mi1>',
    'Si7-La6',
    '(Sol1La1Si1Si2)-Sol2',
    'Ré8-Mi7>Fa7',
    'Mi3-Mi5',
    'Sol8-Fa7>Sol7Fa6',
    'Si3-La3>Sol4',
    'Mi7-Ré8>Ré7',
    'Sol2-La1>',
    'Do8-Ré7>Ré6',
    'La1-Sol2>',
    '(Ré7Ré8)-Ré6',
    'La4-Si4>La5',
    'La6-La5>Si4',
    'Ré4-La6',
    'La7-Sol7>La6',
    'Sol6-La7',
    'Mi6-Mi2',
    'Si7-La6',
    'Sol7-Sol8>',
    'La6-Sol6',
    'La8-La7>Si6',
    'Do3-Do2>',
    'Ré2-Fa2',
    '(Sol2La3Si2)-Fa1',
    'Ré6-Mi7>Mi6',
    'Fa5-Fa6',
    'La7-La6>Si5',
    'Fa6-Sol7',
    '(La5La6)-La4',
    'Sol2-Sol3>La4',
    'Ré7-Mi6>Mi5',
    'Sol3-La3>',
    'La5-Sol4',
    'Fa4*',
  ],
  [
    // partie 9 — 59 coups
    'Fa1-La3',
    'Fa8-Ré6',
    'La3-Sol4',
    'Fa6-Sol5',
    'Fa2-Sol3',
    'Ré7-Mi6',
    'Ré2-Fa4',
    '(Sol8La8Si8)-Fa8',
    '(Sol1La1Si1)-Fa1',
    'Mi7-Mi5',
    'Si2-Si1>',
    'Fa7-Ré5',
    '(Do2Ré1)-Do3',
    'Mi6-Mi4',
    'Sol4-Fa5',
    '(Fa8Ré8Mi8)-Fa7',
    'Fa3-Sol4',
    'Sol7-Fa6',
    'Do1-Ré1>',
    'Fa6-Ré4',
    'Do3-Do2',
    'Ré5-Ré3',
    '(La1Si1)-La2',
    'Do7-Do6',
    'Ré2-Mi3>Mi4Ré3',
    'Do6-Ré5',
    'Sol2-Sol6',
    'Mi7-Mi8>Fa7',
    'Do2-Ré3>Ré4Do3',
    'Ré6-Ré4',
    'Ré3-Mi4>Ré4Mi5',
    'Do4-Ré3',
    'Mi3-Ré4>Ré5Ré3',
    'Ré7-Ré5',
    'Ré4-Mi5>Mi6',
    'Ré6-Ré4',
    '(Mi5Mi4)-Mi6',
    'Ré5-Ré3',
    'Mi6-Ré7>Ré8',
    'Sol8-Fa8>',
    'Ré7-Mi6>Ré6',
    'La8-Sol7',
    'Mi6-Fa7>',
    'Ré3-Mi2',
    '(La2Si2)-La3',
    'Ré2-Fa2',
    'La3-Sol2>Fa2',
    'Sol6-La6',
    'Sol2-La3',
    'Sol5-Fa6',
    'La3-Si2',
    'La6-Sol5>Fa5La5',
    'Mi5-Mi6',
    'Ré2-Fa2',
    'Sol3-Mi5',
    'Mi2-Sol2',
    'Mi6-Mi7',
    'Fa2-La2',
    'Mi7*',
  ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Reculer défait le coup', () {
    test('chaque pièce repart d où elle est arrivée', () {
      final avant = Board.empty();
      avant.set(3, 1, const Piece(PieceType.soldat, Camp.blanc));
      final apres = Board.empty();
      apres.set(3, 2, const Piece(PieceType.soldat, Camp.blanc));

      final aller = glisseesDuCoup(
        avant: avant,
        apres: apres,
        notation: 'Fa2-Fa3',
      );
      expect(aller.single.$2, _c('Fa2'));
      expect(aller.single.$3, _c('Fa3'));

      final retour = glisseesDuCoup(
        avant: avant,
        apres: apres,
        notation: 'Fa2-Fa3',
        recule: true,
      );
      expect(
        retour.single.$2,
        _c('Fa3'),
        reason: 'en reculant, la pièce doit partir de son arrivée',
      );
      expect(retour.single.$3, _c('Fa2'));
    });

    test('une poussée se défait dans l ordre inverse', () {
      // Le pousseur glisse en premier à l aller ; en arrière il doit rentrer
      // en dernier, sinon il traverse la pièce qu il avait poussée.
      final b = Board.empty();
      b.set(3, 1, const Piece(PieceType.soldat, Camp.blanc));
      b.set(3, 3, const Piece(PieceType.soldat, Camp.noir));

      final aller = glisseesDuCoup(avant: b, apres: b, notation: 'Fa2-Fa3>Fa4');
      final retour = glisseesDuCoup(
        avant: b,
        apres: b,
        notation: 'Fa2-Fa3>Fa4',
        recule: true,
      );
      expect(aller.length, retour.length);
      expect(
        retour.map((g) => (g.$2, g.$3)).toList(),
        aller.reversed.map((g) => (g.$3, g.$2)).toList(),
        reason: 'le retour n est pas l aller à l envers',
      );
    });
  });

  group('2. La même vitesse, toujours', () {
    test('une case reste une case, en droite comme en diagonale', () {
      expect(cellDistance(_c('Fa2'), _c('Fa3')), 1);
      expect(cellDistance(_c('Fa2'), _c('Sol3')), 1);
      expect(cellDistance(_c('Fa2'), _c('Fa4')), 2);
    });

    test('un multisaut est plus LONG à parcourir qu un pas', () {
      // C est tout le bug : trois bonds de deux cases, c est six cases. À
      // durée fixe la pièce filait six fois plus vite qu un pas simple.
      final pas = slideSpan([
        (const Piece(PieceType.soldat, Camp.blanc), _c('Fa2'), _c('Fa3')),
      ], const []);
      final saut = slideSpan(
        [(const Piece(PieceType.soldat, Camp.blanc), _c('Fa2'), _c('Fa8'))],
        [_c('Fa4'), _c('Fa6')],
      );

      expect(pas, 1);
      expect(saut, 6, reason: 'trois bonds de deux cases font six cases');
    });

    test('la pièce avance à distance égale, pas à bonds égaux', () {
      // Chemin à bonds INÉGAUX : un pas, puis un saut de deux. À mi-temps
      // la pièce doit avoir fait 1,5 case — donc être au milieu du second
      // bond — et non avoir fini le premier.
      final g = BoardGeometry(size: const Size(700, 800), flipped: false);
      final etapes = [_c('Do1'), _c('Do2'), _c('Do4')];
      final depart = g.cellRect(_c('Do1').col, _c('Do1').row).center;
      final milieu = slidePosition(g, etapes, 0.5).center;
      final parcouru = (milieu - depart).distance / g.cellSize;

      // Trois cases en tout : à mi-temps, une case et demie.
      expect(
        parcouru,
        closeTo(1.5, 0.01),
        reason: 'à temps égal par bond, la pièce n aurait fait qu une case',
      );
    });

    testWidgets('et la durée suit la distance', (tester) async {
      setScaleSize(const Size(400, 800));
      const unite = Duration(milliseconds: 100);

      Future<double> progresApres(
        List<(Piece, Cell, Cell)> glissees,
        List<Cell> chemin,
        Duration attente,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 400,
              height: 400,
              child: GameBoardView(
                board: Board.empty(),
                palette: paletteOf('original'),
                flipped: false,
                onTapCell: (_) {},
                slides: glissees,
                slideJumpPath: chemin,
                slideToken: DateTime.now().microsecondsSinceEpoch,
                slideDuration: unite,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(attente);
        final peintures = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<FlyingPiecesPainter>()
            .toList();
        expect(peintures, isNotEmpty, reason: 'aucune couche animée');
        return peintures.first.progress;
      }

      final piece = const Piece(PieceType.soldat, Camp.blanc);

      // Un pas d une case : fini au bout de l unité.
      expect(
        await progresApres([(piece, _c('Fa2'), _c('Fa3'))], const [], unite),
        1.0,
        reason: 'un pas simple doit durer exactement le réglage',
      );

      // Six cases : au bout de la même unité, un sixième du chemin.
      final apresUnite = await progresApres(
        [(piece, _c('Fa2'), _c('Fa8'))],
        [_c('Fa4'), _c('Fa6')],
        unite,
      );
      expect(
        apresUnite,
        lessThan(0.5),
        reason: 'le multisaut va encore trop vite : il est déjà à mi-chemin',
      );
      expect(apresUnite, closeTo(1 / 6, 0.12));
    });
  });

  group('1 bis. La flèche arrière, dans une vraie partie', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
      });
      await Settings.load();
      await Translations.load('fr');
      clearReplayCache();
    });

    testWidgets('elle défait le coup qu on QUITTE, pas le précédent', (
      tester,
    ) async {
      setScaleSize(const Size(400, 800));
      // Trois coups d une vraie partie. Reculer depuis le troisième doit
      // ramener la pièce de Fa3 vers Sol2 — le troisième coup à l envers.
      // Le bug animait le DEUXIÈME coup à l envers : Sol5 vers Fa6.
      const coups = 'Fa3-Sol4\nFa6-Sol5\nSol2-Fa3';
      final client = OnlineClient(
        api: ApiClient(
          client: MockClient(
            (r) async => http.Response(
              jsonEncode({'ok': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson(const {
              'id': 'g1',
              'statut': 'en_cours',
              'adversaire': 'celia',
              'ma_couleur': 'Blanc',
              'turn': 'Blanc',
              'my_turn': true,
              'moves_text': coups,
              'objectif': 'partie',
            }),
            service: CorrespondenceService(client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bandeau = tester.widget<MoveStrip>(find.byType(MoveStrip));
      bandeau.onSelect(1); // reculer d un coup depuis le dernier
      await tester.pump();

      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      expect(vue.slides, isNotEmpty, reason: 'rien ne glisse en reculant');
      final (_, de, vers) = vue.slides.first;
      expect(
        (de, vers),
        (_c('Fa3'), _c('Sol2')),
        reason: 'la flèche arrière défait le mauvais coup',
      );
    });
  });

  group('La règle de Nino, tenue sur de vraies parties', () {
    // « Quand plusieurs pièces se déplacent, c'est forcément d'une seule
    // case. Si une pièce se déplace de plusieurs cases, c'est toujours un
    // multisaut et ça ne concerne qu'une seule pièce. »
    //
    // C'est ce qui rend la glissée simple : un coup, c'est SOIT une seule
    // pièce qui peut aller loin, SOIT plusieurs qui font une case chacune.
    // Jamais les deux. Si l'invariant tombe, la durée et le chemin des
    // pièces reposent sur du sable.
    test('un coup : une pièce loin, ou plusieurs d une case', () {
      var verifies = 0;
      var groupes = 0;
      for (final partie in _vraiesParties) {
        var board = Board.initial();
        for (final coup in partie) {
          final avant = board;
          final relu = applyNotationLiterally(avant, coup);
          board = relu.board;
          final glissees = relu.slides.where((g) => g.$2 != g.$3).toList();
          if (glissees.isEmpty) continue;
          verifies++;
          if (glissees.length == 1) continue;
          groupes++;
          for (final (_, from, to) in glissees) {
            expect(
              cellDistance(from, to),
              1,
              reason:
                  'coup « $coup » : plusieurs pièces bougent et l une '
                  'fait ${cellDistance(from, to)} cases',
            );
          }
        }
      }
      expect(verifies, greaterThan(100), reason: 'trop peu de coups vérifiés');
      // Sans coups à plusieurs pièces, la boucle ne vérifierait rien.
      expect(
        groupes,
        greaterThan(20),
        reason: 'aucun coup à plusieurs pièces : le test ne prouve rien',
      );
    });
  });

  group('3. Des pièces identiques ne se croisent pas', () {
    test('une chaîne poussée : chacune avance d UNE case', () {
      // Trois soldats identiques en colonne, poussés d un cran. En comparant
      // les plateaux, seuls les deux bouts changent : on voyait donc UNE
      // pièce filer sur toute la chaîne.
      final b = Board.empty();
      b.set(3, 0, const Piece(PieceType.soldat, Camp.blanc));
      for (final r in [2, 3, 4]) {
        b.set(3, r, const Piece(PieceType.soldat, Camp.noir));
      }

      final glissees = glisseesDuCoup(
        avant: b,
        apres: b,
        notation: 'Fa1-Fa2>Fa3',
      );

      expect(
        glissees.length,
        4,
        reason: 'le pousseur et les trois poussés doivent tous glisser',
      );
      for (final (_, from, to) in glissees) {
        expect(
          cellDistance(from, to),
          1,
          reason: 'une pièce traverse la chaîne au lieu d avancer d une case',
        );
      }
      // Et aucune ne va là d où une autre part : elles ne se croisent pas.
      final departs = {for (final g in glissees) g.$2};
      final arrivees = {for (final g in glissees) g.$3};
      expect(departs.length, glissees.length);
      expect(arrivees.length, glissees.length);
    });

    test('un déplacement de groupe : chaque carrée garde sa place', () {
      // Deux carrées identiques côte à côte avancent ensemble. Appariées au
      // plus court, elles pouvaient permuter.
      final b = Board.empty();
      b.set(0, 0, const Piece(PieceType.soldat, Camp.blanc));
      b.set(1, 0, const Piece(PieceType.soldat, Camp.blanc));

      final glissees = glisseesDuCoup(
        avant: b,
        apres: b,
        notation: '(Do1Ré1)-Do2',
      );
      expect(glissees.length, 2);
      for (final (_, from, to) in glissees) {
        expect(
          to.col,
          from.col,
          reason: 'la pièce change de colonne : les deux se sont croisées',
        );
        expect(to.row, from.row + 1);
      }
    });
  });
}
