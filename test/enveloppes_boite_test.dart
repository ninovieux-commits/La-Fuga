/// LES ENVELOPPES DANS LA BOÎTE DE MESSAGES, et ce qui en passe en partie.
///
/// Nino : « quand on reçoit une image, ça affiche une enveloppe à côté de
/// l'image de profil […] quand on clique sur l'enveloppe, un popup demande
/// "ouvrir l'enveloppe pour visionner l'image ? (une fois une enveloppe
/// ouverte, elle disparaît de la conversation)" [Ouvrir] [annuler]
/// [supprimer] », « on peut voir les enveloppes en attente chez le
/// correspondant, les ouvrir pour vérifier et les supprimer avant qu'il ne
/// les ait ouvertes », « on ne peut pas en envoyer de nouvelles si on en a
/// déjà envoyé [deux] et que le correspondant ne les a pas ouvertes », et
/// « en partie, on ne voit pas l'image s'afficher comme les messages
/// rapides, seulement le symbole d'enveloppe qui passe comme un émoticône ».
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lafuga/game/enveloppe.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/corr_hub.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/visionneuse_enveloppe.dart';
import 'package:lafuga/ui/widgets/choix_source_image.dart';
import 'package:lafuga/ui/widgets/enveloppe_jeton.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:lafuga/ui/widgets/picto_touche.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kMonTheme = 'foret';
const String kSonTheme = 'volcan';

/// Serveur simulé : répond ce qu'on lui dit, et retient ce qu'on lui envoie.
final class _Server {
  final List<({String path, Map<String, dynamic> body})> calls = [];
  final Map<String, Map<String, dynamic>> replies = {};

  http.Client get client => MockClient((request) async {
    calls.add((
      path: request.url.path,
      body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
    ));
    return http.Response(
      jsonEncode(replies[request.url.path] ?? {'ok': true}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  bool called(String path) => calls.any((c) => c.path == path);

  int fois(String path) => calls.where((c) => c.path == path).length;

  Map<String, dynamic> bodyOf(String path) =>
      calls.lastWhere((c) => c.path == path).body;
}

/// Une enveloppe telle que le serveur la décrit.
Map<String, dynamic> ligne({
  required int id,
  required bool deMoi,
  Duration reste = const Duration(hours: 12, minutes: 34, seconds: 30),
}) {
  final maintenant = DateTime.now();
  return {
    'id': id,
    'de_moi': deMoi,
    'cree_a': maintenant.millisecondsSinceEpoch ~/ 1000,
    'expire_a': maintenant.add(reste).millisecondsSinceEpoch ~/ 1000,
    'taille': 12345,
  };
}

/// UNE IMAGE QUI SE DÉCODE VRAIMENT : un PNG d'un pixel. La visionneuse la
/// peint, et une suite d'octets au hasard ferait échouer le décodage.
final Uint8List kPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH'
  '/q842iQAAAABJRU5ErkJggg==',
);

/// LES JETONS NE S'ARRÊTENT JAMAIS DE SE BALANCER : `pumpAndSettle`
/// n'aboutirait pas une fois la rangée affichée. On bat donc des images à la
/// main — c'est assez pour laisser les requêtes simulées se résoudre.
Future<void> battre(WidgetTester tester, {int fois = 8}) async {
  for (var i = 0; i < fois; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;
  late OnlineService online;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': kMonTheme,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    server = _Server();
    online = OnlineService(
      client: OnlineClient(api: ApiClient(client: server.client)),
    );
    AvatarPhotos.clear();
    DecorsConnus.clear();
    FavorisConnus.instance.oublie();
    // LE THÈME DU COMPTE EST CELUI DU SERVEUR : la connexion réconcilie les
    // deux, et un `/login` muet ramènerait le thème par défaut — mes
    // enveloppes paraîtraient alors dans une palette que je n'ai pas choisie.
    server.replies['/login'] = {
      'ok': true,
      'token': 't',
      'pseudo': 'Nino',
      'theme': kMonTheme,
    };
    server.replies['/list_conversation'] = {'ok': true, 'messages': []};
    server.replies['/get_profile'] = {'ok': true, 'theme': kSonTheme};
  });

  tearDown(() {
    resetScale();
    poseLeChoisisseurDImage(null);
  });

  Future<void> ouvrir(WidgetTester tester) async {
    await tester.runAsync(() => online.login('Nino', 'mdp'));
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(online: online, pseudo: 'Ana'),
      ),
    );
    await battre(tester);
  }

  group('La rangée de jetons', () {
    testWidgets('les reçues et les envoyées, avec leur chrono', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [
          ligne(id: 7, deMoi: false),
          ligne(
            id: 8,
            deMoi: true,
            reste: const Duration(hours: 1, seconds: 30),
          ),
        ],
      };

      await ouvrir(tester);

      expect(find.byType(EnveloppeJeton), findsNWidgets(2));
      expect(find.text('12h34'), findsOneWidget);
      expect(find.text('1h00'), findsOneWidget);
    });

    // Nino : « je veux que les enveloppes envoyées prennent ma couleur et les
    // reçues, la couleur de mon correspondant (exactement comme les bulles de
    // conversation en fait). »
    testWidgets('chacune porte la couleur de son auteur', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 7, deMoi: false), ligne(id: 8, deMoi: true)],
      };

      await ouvrir(tester);

      final jetons = tester.widgetList<EnveloppeJeton>(
        find.byType(EnveloppeJeton),
      );
      final sienne = jetons.firstWhere((j) => !j.enveloppe.deMoi);
      final mienne = jetons.firstWhere((j) => j.enveloppe.deMoi);
      expect(sienne.couleur, paletteOf(kSonTheme).fonce);
      expect(mienne.couleur, paletteOf(kMonTheme).fonce);
    });

    testWidgets('aucune enveloppe, aucun jeton', (tester) async {
      server.replies['/env_liste'] = {'ok': true, 'enveloppes': const []};
      await ouvrir(tester);
      expect(find.byType(EnveloppeJeton), findsNothing);
    });
  });

  group('La touche qui envoie', () {
    testWidgets('elle est dans le bandeau, et elle est vive', (tester) async {
      server.replies['/env_liste'] = {'ok': true, 'enveloppes': const []};
      await ouvrir(tester);

      expect(find.byType(ToucheEnveloppePlus), findsOneWidget);
      expect(
        tester
            .widget<ToucheEnveloppePlus>(find.byType(ToucheEnveloppePlus))
            .actif,
        isTrue,
      );
    });

    // Nino : « on ne peut pas en envoyer de nouvelles si on en a déjà envoyé
    // [deux] et que le correspondant ne les a pas ouvertes. »
    testWidgets('deux des miennes en attente : elle s éteint', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 1, deMoi: true), ligne(id: 2, deMoi: true)],
      };
      await ouvrir(tester);

      expect(
        tester
            .widget<ToucheEnveloppePlus>(find.byType(ToucheEnveloppePlus))
            .actif,
        isFalse,
        reason: 'deux enveloppes attendent déjà chez lui',
      );
    });

    testWidgets('les SIENNES ne m empêchent pas d envoyer', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 1, deMoi: false), ligne(id: 2, deMoi: false)],
      };
      await ouvrir(tester);

      expect(
        tester
            .widget<ToucheEnveloppePlus>(find.byType(ToucheEnveloppePlus))
            .actif,
        isTrue,
        reason: 'la limite compte les miennes, pas les deux à la fois',
      );
    });
  });

  group('Le popup d une enveloppe', () {
    testWidgets('reçue : elle disparaît de la conversation', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 7, deMoi: false)],
      };
      await ouvrir(tester);

      await tester.tap(find.byType(EnveloppeJeton));
      await battre(tester, fois: 20);

      expect(
        find.text("Ouvrir l'enveloppe pour visionner l'image ?"),
        findsOneWidget,
      );
      expect(
        find.text('Une fois ouverte, elle disparaît de la conversation.'),
        findsOneWidget,
      );
      expect(find.text('Ouvrir'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
    });

    testWidgets('la mienne : la vérifier ne la reprend pas', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 8, deMoi: true)],
      };
      await ouvrir(tester);

      await tester.tap(find.byType(EnveloppeJeton));
      await battre(tester, fois: 20);

      expect(
        find.text('Ouvrir votre enveloppe pour la vérifier ?'),
        findsOneWidget,
      );
      expect(
        find.text('La vérifier ne la reprend pas : elle restera en attente.'),
        findsOneWidget,
      );
    });

    testWidgets('« Annuler » ne touche à rien', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 7, deMoi: false)],
      };
      await ouvrir(tester);

      await tester.tap(find.byType(EnveloppeJeton));
      await battre(tester, fois: 20);
      await tester.tap(find.text('Annuler'));
      await battre(tester, fois: 20);

      expect(server.called('/env_ouvrir'), isFalse);
      expect(server.called('/env_supprimer'), isFalse);
      expect(find.byType(EnveloppeJeton), findsOneWidget);
    });

    testWidgets('« Supprimer » la reprend avant lecture', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 8, deMoi: true)],
      };
      await ouvrir(tester);

      await tester.tap(find.byType(EnveloppeJeton));
      await battre(tester, fois: 20);
      server.replies['/env_liste'] = {'ok': true, 'enveloppes': const []};
      await tester.tap(find.text('Supprimer'));
      await battre(tester, fois: 20);

      expect(server.bodyOf('/env_supprimer')['id'], 8);
      expect(
        find.byType(EnveloppeJeton),
        findsNothing,
        reason: 'la rangée est relue après coup',
      );
    });

    testWidgets('« Ouvrir » montre l image, et le jeton reste le temps qu on '
        'la regarde', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 7, deMoi: false)],
      };
      server.replies['/env_ouvrir'] = {
        'ok': true,
        'image': base64Encode(kPixel),
      };
      await ouvrir(tester);

      await tester.tap(find.byType(EnveloppeJeton));
      await battre(tester, fois: 20);
      // Le serveur l'a effacée en la rendant : sa prochaine liste est vide.
      server.replies['/env_liste'] = {'ok': true, 'enveloppes': const []};
      await tester.tap(find.text('Ouvrir'));
      await battre(tester, fois: 30);

      expect(server.bodyOf('/env_ouvrir')['id'], 7);
      expect(find.byType(VisionneuseEnveloppe), findsOneWidget);
      expect(
        find.text('Télécharger'),
        findsOneWidget,
        reason: 'on doit pouvoir la garder dans son téléphone',
      );
      expect(find.text('Modifier et renvoyer'), findsOneWidget);
    });
  });

  group('Envoyer une enveloppe', () {
    /// Un greffon qui rend toujours la même image, sans caméra ni pellicule.
    void poseUnePhoto() => poseLeChoisisseurDImage(
      ({
        required ImageSource source,
        double? maxWidth,
        double? maxHeight,
        int? imageQuality,
      }) async => XFile.fromData(kPixel, name: 'photo.png'),
    );

    testWidgets('appareil photo ou photos, puis envoyer', (tester) async {
      server.replies['/env_liste'] = {'ok': true, 'enveloppes': const []};
      poseUnePhoto();
      await ouvrir(tester);

      await tester.tap(find.byType(ToucheEnveloppePlus));
      await battre(tester, fois: 20);
      expect(find.text('Appareil photo'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);

      await tester.tap(find.text('Photos'));
      await battre(tester, fois: 20);
      expect(find.text('Cette image ?'), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);

      // « Envoyer » est écrit deux fois à l'écran : la touche du champ de
      // saisie, derrière, et celle du popup. On vise celle du popup.
      await tester.tap(find.widgetWithText(FugaButton, 'Envoyer'));
      await battre(tester, fois: 20);

      expect(server.bodyOf('/env_envoyer')['pseudo'], 'Ana');
      expect(server.bodyOf('/env_envoyer')['image'], base64Encode(kPixel));
    });

    testWidgets('la touche éteinte ne demande rien', (tester) async {
      server.replies['/env_liste'] = {
        'ok': true,
        'enveloppes': [ligne(id: 1, deMoi: true), ligne(id: 2, deMoi: true)],
      };
      poseUnePhoto();
      await ouvrir(tester);

      await tester.tap(find.byType(ToucheEnveloppePlus));
      await battre(tester, fois: 20);

      expect(find.text('Appareil photo'), findsNothing);
      expect(server.called('/env_envoyer'), isFalse);
    });
  });

  group('En partie', () {
    // Nino : « en partie, on ne voit pas l'image s'afficher comme les
    // messages rapides, seulement le symbole d'enveloppe qui passe comme un
    // émoticône. »
    testWidgets('le symbole passe, sans bulle et sans texte', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              texte: kJetonEnveloppe,
              deMoi: false,
              palette: paletteOf(kSonTheme),
              selectionnable: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PictoTouche), findsOneWidget);
      expect(
        find.text(kJetonEnveloppe),
        findsNothing,
        reason: 'le jeton ne doit jamais se lire',
      );
      expect(
        tester.widget<PictoTouche>(find.byType(PictoTouche)).couleur,
        paletteOf(kSonTheme).fonce,
        reason: 'toutes les enveloppes sont en couleur 2',
      );
    });

    test('une enveloppe annoncée en direct ne relit pas les parties', () async {
      final hub = CorrHub();
      addTearDown(hub.dispose);
      final enveloppes = <String>[];
      final parties = <CorrChange>[];
      hub.enveloppes.listen(enveloppes.add);
      hub.changes.listen(parties.add);

      hub.receive({'type': 'enveloppe', 'de': 'Ana', 'id': '7'});
      await Future<void>.delayed(Duration.zero);

      expect(enveloppes, ['Ana']);
      expect(parties, isEmpty);
    });

    test('un coup de correspondance passe toujours', () async {
      final hub = CorrHub();
      addTearDown(hub.dispose);
      final parties = <CorrChange>[];
      hub.changes.listen(parties.add);

      hub.receive({'type': 'corr_turn', 'game_id': '12'});
      await Future<void>.delayed(Duration.zero);

      expect(parties, [(type: 'corr_turn', gameId: '12')]);
    });
  });
}
