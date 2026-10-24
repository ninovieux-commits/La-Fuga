/// Les pièces envoyées comme des émojis.
///
/// Nino : « je voudrais pouvoir envoyer les images des pièces par messages
/// comme si c'était des emojis (ils sont déjà tous listés dans le choix de
/// l'image de profil). »
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/pieces_emoji.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
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
  });
  tearDown(resetScale);

  group('Le jeton', () {
    test('le blanc ne dit pas son camp, le noir si', () {
      expect(jetonPiece(PieceType.soldat, Camp.blanc), '[Soldat]');
      expect(jetonPiece(PieceType.soldat, Camp.noir), '[Soldat Noir]');
      expect(jetonPiece(PieceType.heritier, Camp.blanc), '[Héritier]');
    });

    test('il se lit tout seul sur un client qui l ignore', () {
      // C'est la raison du format : une ancienne version en face affiche
      // « [Soldat Noir] », ce qui se comprend encore. Un code privé y aurait
      // montré un carré vide.
      for (final type in kPiecesEnvoyables) {
        for (final camp in Camp.values) {
          final jeton = jetonPiece(type, camp);
          expect(jeton, contains(type.wire));
          expect(jeton, startsWith('['));
          expect(jeton, endsWith(']'));
        }
      }
    });
  });

  group('Le découpage', () {
    test('un message ordinaire reste d un seul morceau', () {
      final m = decoupeMessage('bien joué !');
      expect(m, hasLength(1));
      expect(m.single.texte, 'bien joué !');
      expect(m.single.piece, isNull);
      expect(contientUnePiece('bien joué !'), isFalse);
    });

    test('la pièce se détache du texte, dans l ordre', () {
      final m = decoupeMessage('ton [Garde Noir] est perdu');
      expect(m.map((e) => e.texte).toList(), ['ton ', null, ' est perdu']);
      // `Piece` est une valeur sans égalité propre : on compare ce qu'elle
      // dit.
      expect(m[1].piece!.type, PieceType.garde);
      expect(m[1].piece!.camp, Camp.noir);
    });

    test('deux pièces collées font deux morceaux', () {
      final m = decoupeMessage('[Soldat][Nurse Noir]');
      expect(m, hasLength(2));
      expect(m[0].piece!.type, PieceType.soldat);
      expect(m[0].piece!.camp, Camp.blanc);
      expect(m[1].piece!.type, PieceType.nurse);
      expect(m[1].piece!.camp, Camp.noir);
    });

    test('ce qui ressemble à un jeton sans en être reste du texte', () {
      for (final faux in ['[Roi]', '[soldat]', '[Soldat Vert]', '[Soldat']) {
        expect(
          contientUnePiece(faux),
          isFalse,
          reason: '« $faux » ne nomme pas une pièce du jeu',
        );
      }
    });
  });

  group('Un message qui n est QUE des pièces', () {
    test('se compte, comme les émojis', () {
      expect(comptePiecesSeules('[Soldat]'), 1);
      expect(comptePiecesSeules('[Soldat] [Garde Noir]'), 2);
      expect(comptePiecesSeules('[Soldat] et [Garde]'), 0);
      expect(comptePiecesSeules('bonjour'), 0);
    });
  });

  group('Dans la bulle', () {
    Future<void> pose(WidgetTester tester, String texte) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setScaleSize(const Size(393, 851));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageBubble(
                texte: texte,
                deMoi: true,
                palette: paletteOf('foret'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('le jeton se dessine, et le texte autour reste écrit', (
      tester,
    ) async {
      await pose(tester, 'ton [Garde Noir] est perdu');
      expect(find.byType(ProfilePhoto), findsOneWidget);
      expect(
        find.textContaining('[Garde Noir]'),
        findsNothing,
        reason: 'le jeton ne doit pas rester écrit à côté du dessin',
      );
      expect(find.textContaining('est perdu'), findsOneWidget);
    });

    testWidgets('une pièce seule se montre en grand, sans bulle', (
      tester,
    ) async {
      await pose(tester, '[Soldat]');
      final seule = tester.widget<ProfilePhoto>(find.byType(ProfilePhoto));

      await pose(tester, 'ton [Soldat] est perdu');
      final dansLaPhrase = tester.widget<ProfilePhoto>(
        find.byType(ProfilePhoto),
      );
      expect(
        seule.size,
        greaterThan(dansLaPhrase.size * 2),
        reason: 'comme un émoji seul : elle sort de sa bulle et grandit',
      );
    });

    testWidgets('trois pièces se dessinent toutes les trois', (tester) async {
      await pose(tester, '[Soldat] [Garde] [Nurse Noir]');
      expect(find.byType(ProfilePhoto), findsNWidgets(3));
    });

    testWidgets('la pièce suit le thème de CELUI QUI LIT', (tester) async {
      await Settings.instance.setTheme('ocean');
      await pose(tester, '[Soldat]');
      expect(
        tester.widget<ProfilePhoto>(find.byType(ProfilePhoto)).photo,
        startsWith('ocean|'),
        reason: 'le jeton ne porte pas de thème : chacun dessine avec le sien',
      );
    });
  });

  group('La touche des pièces, au-dessus de la saisie', () {
    // Nino : « au milieu […] uniquement lorsque [le clavier] est déployé. Ça
    // doit faire la taille d'une touche de clavier mais carré pas
    // rectangle, et à l'effigie du logo (correspondant au thème choisi). »
    late _Serveur serveur;
    late OnlineService enLigne;

    setUp(() async {
      serveur = _Serveur();
      enLigne = OnlineService(
        client: OnlineClient(api: ApiClient(client: serveur.client)),
      );
      serveur.reponses['/login'] = {'ok': true, 'token': 't', 'pseudo': 'nino'};
      await enLigne.login('nino', 'mdp');
    });

    /// Ouvre une conversation, clavier rangé ou déployé.
    Future<void> ouvrir(WidgetTester tester, {required bool clavier}) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      // Le clavier se reconnaît à la place qu'il prend par le bas.
      tester.view.viewInsets = clavier
          ? const FakeViewPadding(bottom: 300)
          : FakeViewPadding.zero;
      addTearDown(tester.view.reset);
      setScaleSize(const Size(393, 851));
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: enLigne, pseudo: 'Ana'),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder laTouche() => find.byTooltip(T('Envoyer une pièce'));

    testWidgets('clavier rangé, elle n est pas là', (tester) async {
      await ouvrir(tester, clavier: false);
      expect(laTouche(), findsNothing);
    });

    testWidgets('clavier déployé, elle paraît, carrée et au milieu', (
      tester,
    ) async {
      await ouvrir(tester, clavier: true);
      expect(laTouche(), findsOneWidget);

      final place = tester.getRect(laTouche());
      expect(
        place.width,
        moreOrLessEquals(place.height, epsilon: 0.5),
        reason: 'carré, pas rectangle',
      );
      expect(
        place.center.dx,
        moreOrLessEquals(393 / 2, epsilon: 1),
        reason: 'au milieu, comme Nino l a demandé',
      );
    });

    testWidgets('elle porte le logo du thème choisi', (tester) async {
      await Settings.instance.setTheme('volcan');
      await ouvrir(tester, clavier: true);
      final logo = tester.widget<ProfilePhoto>(
        find.descendant(of: laTouche(), matching: find.byType(ProfilePhoto)),
      );
      expect(logo.photo, 'logo|volcan');
    });

    testWidgets('elle insère le jeton à l endroit du curseur', (tester) async {
      await ouvrir(tester, clavier: true);
      await tester.enterText(find.byType(TextField), 'ton  est perdu');
      // Curseur après « ton  ».
      final champ = tester.widget<TextField>(find.byType(TextField));
      champ.controller!.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();

      await tester.tap(laTouche());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(PieceType.garde.wire).first);
      await tester.pumpAndSettle();

      expect(champ.controller!.text, 'ton [Garde] est perdu');
      expect(
        champ.controller!.selection.baseOffset,
        'ton [Garde]'.length,
        reason: 'le curseur reste derrière la pièce, pas au bout du message',
      );
    });
  });
}

/// Serveur simulé : répond ce qu'on lui dit.
final class _Serveur {
  final Map<String, Map<String, dynamic>> reponses = {};

  http.Client get client => MockClient(
    (requete) async => http.Response(
      jsonEncode(reponses[requete.url.path] ?? {'ok': true}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  );
}
