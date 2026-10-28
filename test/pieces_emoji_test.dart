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
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/champ_pieces.dart';
import 'package:lafuga/ui/widgets/grille_photos.dart';
import 'package:lafuga/ui/widgets/panneau_pieces.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/mesure_emoji.dart';
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
    test('sans thème, le blanc ne dit pas son camp, le noir si', () {
      expect(jetonPiece(PieceType.soldat, Camp.blanc), '[Soldat]');
      expect(jetonPiece(PieceType.soldat, Camp.noir), '[Soldat Noir]');
      expect(jetonPiece(PieceType.heritier, Camp.blanc), '[Héritier]');
    });

    test('avec un thème, il s écrit comme une photo de profil', () {
      // Nino : « ça doit donner accès aux pièces de TOUS les thèmes, pas d un
      // seul. » Le jeton porte donc celui qu on a pris.
      expect(
        jetonPiece(PieceType.soldat, Camp.blanc, theme: 'foret'),
        '[foret|Soldat]',
      );
      expect(
        jetonPiece(PieceType.garde, Camp.noir, theme: 'volcan'),
        '[volcan|Garde|Noir]',
      );
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
      expect(contientUneImage('bien joué !'), isFalse);
    });

    test('un jeton à thème se lit, et rend son thème', () {
      final m = decoupeMessage('voilà [volcan|Garde|Noir] !');
      expect(m[1].piece!.type, PieceType.garde);
      expect(m[1].piece!.camp, Camp.noir);
      expect(m[1].theme, 'volcan');
    });

    test('un jeton sans thème n en rend aucun : à chacun le sien', () {
      expect(decoupeMessage('[Soldat]').single.theme, isNull);
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
      for (final faux in [
        '[Roi]',
        '[soldat]',
        '[Soldat Vert]',
        '[Soldat',
        '[Foret|Soldat]',
      ]) {
        expect(
          contientUneImage(faux),
          isFalse,
          reason: '« $faux » ne nomme pas une pièce du jeu',
        );
      }
    });
  });

  group('Un message qui n est QUE des pièces', () {
    test('se compte, comme les émojis', () {
      expect(compteImagesSeules('[Soldat]'), 1);
      expect(compteImagesSeules('[Soldat] [Garde Noir]'), 2);
      expect(compteImagesSeules('[Soldat] et [Garde]'), 0);
      expect(compteImagesSeules('bonjour'), 0);
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

    testWidgets('dans une phrase, elle fait la taille d un émoji', (
      tester,
    ) async {
      // Nino : « taille smiley ». Et cette taille se MESURE : un émoji
      // déborde la taille de police qu'on lui donne, et de combien dépend de
      // la police qui le dessine.
      await pose(tester, 'ton [Garde] est perdu');
      final piece = tester.widget<ProfilePhoto>(find.byType(ProfilePhoto));
      expect(piece.size, tailleDUnEmoji(SF(16)));
    });

    testWidgets('trois pièces se dessinent toutes les trois', (tester) async {
      await pose(tester, '[Soldat] [Garde] [Nurse Noir]');
      expect(find.byType(ProfilePhoto), findsNWidgets(3));
    });

    testWidgets('une pleine rangée reste grosse', (tester) async {
      // Nino : « quand on envoie que des smileys ou que des images ça doit
      // aussi le mettre en plus gros ». Sept pièces rapetissent donc par
      // rapport à une seule, mais pas jusqu'à la taille qu'elles auraient
      // dans une phrase.
      await pose(tester, '[Soldat] ' * 7);
      final photos = tester
          .widgetList<ProfilePhoto>(find.byType(ProfilePhoto))
          .toList();
      expect(photos, hasLength(7));

      await pose(tester, '[Soldat]');
      final seule = tester.widget<ProfilePhoto>(find.byType(ProfilePhoto));

      expect(photos.first.size, lessThan(seule.size));
      expect(
        photos.first.size,
        greaterThan(tailleDUnEmoji(SF(16))),
        reason: 'plus grosse que dans une phrase',
      );
    });

    testWidgets('sans thème, la pièce suit celui de CELUI QUI LIT', (
      tester,
    ) async {
      await Settings.instance.setTheme('ocean');
      await pose(tester, '[Soldat]');
      expect(
        tester.widget<ProfilePhoto>(find.byType(ProfilePhoto)).photo,
        startsWith('ocean|'),
        reason: 'le jeton ne porte pas de thème : chacun dessine avec le sien',
      );
    });

    testWidgets('avec un thème, elle garde CELUI QU ON A CHOISI', (
      tester,
    ) async {
      await Settings.instance.setTheme('ocean');
      await pose(tester, '[volcan|Garde|Noir]');
      expect(
        tester.widget<ProfilePhoto>(find.byType(ProfilePhoto)).photo,
        'volcan|Garde|Noir',
        reason:
            'choisir la pièce d un thème et la voir arriver dans un autre '
            'n aurait pas de sens',
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

    testWidgets('elle se tient ENTRE les deux visages', (tester) async {
      // Nino : « le bouton doit apparaître entre nos deux images de profil,
      // pas dessous. » Les deux photos du bas sont les plus grandes de
      // l écran : on les reconnaît à leur taille.
      await ouvrir(tester, clavier: true);
      final visages = tester
          .widgetList<ProfilePhoto>(find.byType(ProfilePhoto))
          .where((p) => p.size == kAvatarBasConversation)
          .toList();
      expect(visages, hasLength(2), reason: 'les deux grandes photos du bas');

      final places = find
          .byWidgetPredicate(
            (w) => w is ProfilePhoto && w.size == kAvatarBasConversation,
          )
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .toList();
      final touche = tester.getRect(laTouche());
      expect(touche.center.dx, greaterThan(places[0].right));
      expect(touche.center.dx, lessThan(places[1].left));
      expect(
        (touche.center.dy - places[0].center.dy).abs(),
        lessThan(places[0].height),
        reason: 'sur la même rangée qu elles, et non dessous',
      );
    });

    testWidgets('la grille offre les pièces de TOUS les thèmes', (
      tester,
    ) async {
      await ouvrir(tester, clavier: true);
      await tester.tap(laTouche());
      await tester.pumpAndSettle();

      final photos = tester
          .widgetList<ProfilePhoto>(find.byType(ProfilePhoto))
          .map((p) => p.photo)
          .whereType<String>()
          .toSet();
      for (final theme in kThemeOrder) {
        expect(
          photos.any((p) => p.startsWith('$theme|')),
          isTrue,
          reason: 'le thème « $theme » n est pas proposé',
        );
      }
      expect(
        photos.where((p) => p.startsWith('${kThemeOrder.first}|')),
        hasLength(kPiecesEnvoyables.length * 2),
        reason: 'cinq pièces, deux camps, pour chaque thème',
      );
    });

    testWidgets('elle insère le jeton à l endroit du curseur', (tester) async {
      // La grille s ouvre sur le thème qu on porte : c est sa première
      // rangée, donc la première pièce trouvée.
      final theme = Settings.instance.themeAxes.general;
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

      // DANS LE CHAMP, la pièce n est qu UN caractère — celui qui la
      // dessine. Nino : « quand on sélectionne une icône, ça doit l afficher
      // directement avant l envoi plutôt que d afficher son nom. »
      final controleur = champ.controller! as ControleurAvecPieces;
      expect(
        controleur.text.length,
        'ton  est perdu'.length + 1,
        reason: 'le jeton ne doit pas s écrire en toutes lettres',
      );
      expect(
        controleur.selection.baseOffset,
        'ton '.length + 1,
        reason: 'le curseur reste derrière la pièce, pas au bout du message',
      );

      // ET C EST LE JETON QUI PART, pas le caractère privé.
      final attendu = jetonPiece(PieceType.garde, Camp.blanc, theme: theme);
      expect(controleur.texteEnvoyable(), 'ton $attendu est perdu');
    });

    testWidgets('le panneau reste ouvert d une image à l autre', (
      tester,
    ) async {
      // Nino : « quand on clique sur l'une des images, le popup ne doit pas
      // partir, ainsi on peut mettre plusieurs images d'affilée sans avoir
      // à rouvrir le popup. »
      await ouvrir(tester, clavier: true);
      await tester.tap(laTouche());
      await tester.pumpAndSettle();
      expect(find.byType(PanneauDesPieces), findsOneWidget);

      final champ = tester.widget<TextField>(find.byType(TextField));
      final controleur = champ.controller! as ControleurAvecPieces;

      await tester.tap(find.byTooltip(PieceType.garde.wire).first);
      await tester.pumpAndSettle();
      expect(find.byType(PanneauDesPieces), findsOneWidget);

      await tester.tap(find.byTooltip(PieceType.nurse.wire).first);
      await tester.pumpAndSettle();
      expect(find.byType(PanneauDesPieces), findsOneWidget);

      expect(controleur.text.length, 2, reason: 'deux images d affilée');
      final theme = Settings.instance.themeAxes.general;
      expect(
        controleur.texteEnvoyable(),
        '${jetonPiece(PieceType.garde, Camp.blanc, theme: theme)}'
        '${jetonPiece(PieceType.nurse, Camp.blanc, theme: theme)}',
      );
    });

    testWidgets('le clavier reste déployé : la saisie garde le focus', (
      tester,
    ) async {
      // Un popup de route prend le focus, et le clavier se range avec lui.
      // Nino : « le clavier doit rester déployé ».
      await ouvrir(tester, clavier: true);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(laTouche());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(PieceType.garde.wire).first);
      await tester.pumpAndSettle();

      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason: 'aucune route ne s est ouverte, donc rien n a volé le focus',
      );
    });

    testWidgets('un doigt posé à côté le referme', (tester) async {
      await ouvrir(tester, clavier: true);
      await tester.tap(laTouche());
      await tester.pumpAndSettle();
      expect(find.byType(PanneauDesPieces), findsOneWidget);

      // Dans la conversation, au-dessus du panneau — qui s'arrête avant le
      // haut pour qu'il reste justement de la place où poser le doigt.
      final haut = tester.getRect(find.byType(PanneauDesPieces)).top;
      final panneau = tester
          .getRect(
            find
                .descendant(
                  of: find.byType(PanneauDesPieces),
                  matching: find.byType(Material),
                )
                .first,
          )
          .top;
      expect(panneau, greaterThan(haut), reason: 'il reste de quoi toucher');
      await tester.tapAt(Offset(200, (haut + panneau) / 2));
      await tester.pumpAndSettle();
      expect(find.byType(PanneauDesPieces), findsNothing);
    });

    testWidgets('les logos et Deep Grey s envoient aussi', (tester) async {
      // Nino : « là, il manque les logos », puis « la photo de profil de
      // deep grey doit aussi être envoyable dans les messages ».
      await ouvrir(tester, clavier: true);
      await tester.tap(laTouche());
      await tester.pumpAndSettle();
      final champ = tester.widget<TextField>(find.byType(TextField));
      final controleur = champ.controller! as ControleurAvecPieces;

      final theme = Settings.instance.themeAxes.general;
      await tester.tap(find.byTooltip(kThemeLabels[theme] ?? theme).first);
      await tester.pumpAndSettle();
      expect(controleur.texteEnvoyable(), '[logo|$theme]');

      // Le portrait ferme la section du thème deepgrey, tout en bas : la
      // colonne est entièrement bâtie, il suffit de la faire défiler jusqu'à
      // lui.
      // Deux images portent ce nom : le logo du thème « Deep Grey », en
      // tête de sa section, et le portrait qui la ferme. C'est le second.
      final portrait = find.byTooltip('Deep Grey').last;
      await tester.ensureVisible(portrait);
      await tester.pumpAndSettle();
      await tester.tap(portrait);
      await tester.pumpAndSettle();
      expect(controleur.texteEnvoyable(), '[logo|$theme][deepgrey]');
    });
  });

  group('Les images autres que des pièces', () {
    test('un logo se lit et se dessine', () {
      final m = decoupeMessage('voilà [logo|foret] !').toList();

      expect(m[1].logo, 'foret');
      expect(m[1].piece, isNull);
      expect(photoDuMorceau(m[1], 'volcan'), 'logo|foret');
    });

    test('le portrait de Deep Grey se lit et se dessine', () {
      final m = decoupeMessage('[deepgrey]').single;

      expect(m.deepGrey, isTrue);
      expect(photoDuMorceau(m, 'volcan'), 'deepgrey');
    });

    test('une image seule se montre en grand, comme un émoji', () {
      expect(compteImagesSeules('[logo|foret]'), 1);
      expect(compteImagesSeules('[deepgrey] [Soldat]'), 2);
      expect(compteImagesSeules('[deepgrey] bonjour'), 0);
    });

    test('un jeton se construit depuis la photo, sans la retoucher', () {
      for (final photo in photosDuCatalogue()) {
        final m = decoupeMessage(jetonDePhoto(photo)).single;
        expect(m.texte, isNull, reason: 'le jeton de « $photo » se relit');
        expect(
          photoDuMorceau(m, kDefaultTheme),
          photo,
          reason: 'et redonne exactement la photo choisie',
        );
      }
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
