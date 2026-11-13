/// L'heure d'un message, sur demande.
///
/// Nino : « j'aimerai que lorsqu'on clique sur un message, smiley ou image
/// de l'App envoyé ou reçu, ça nous indique la date et l'heure du message
/// (idem pour les "a envoyé une enveloppe") ».
///
/// Le serveur écrit `created_at` en secondes depuis 1970 — `int(time.time())`,
/// comme partout dans `server.py`. L'application ne le lisait pas.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/date_locale.dart';
import 'package:lafuga/game/enveloppe.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/message_hub.dart';
import 'package:lafuga/net/messages.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': 'original',
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  group("L'instant qu'un serveur donne", () {
    test('des secondes depuis 1970, comme server.py les écrit', () {
      final d = dateDuMessage(1762950000)!;
      expect(
        d.millisecondsSinceEpoch,
        DateTime.fromMillisecondsSinceEpoch(
          1762950000 * 1000,
        ).millisecondsSinceEpoch,
      );
    });

    test('et ses variantes, pour ne pas afficher l an 1970', () {
      expect(dateDuMessage('1762950000')!.year, greaterThan(2020));
      expect(
        dateDuMessage(1762950000000)!.year,
        dateDuMessage(1762950000)!.year,
        reason: 'des millisecondes se reconnaissent à leur taille',
      );
      expect(dateDuMessage('2026-11-12T14:20:00Z')!.year, 2026);
    });

    test('rien quand le serveur ne dit rien', () {
      expect(dateDuMessage(null), isNull);
      expect(dateDuMessage(''), isNull);
      expect(dateDuMessage('bonjour'), isNull);
      expect(dateDuMessage(0), isNull);
    });
  });

  // Le serveur donne la même heure au direct : `message_recu` porte son
  // `created_at`. Sans cela, un message arrivé sous les yeux restait muet
  // jusqu'à la relecture suivante.
  test('le direct porte l heure du serveur', () {
    final hub = MessageHub();
    IncomingMessage? recu;
    hub.incoming.listen((m) => recu = m);
    hub.receive({'de': 'toto', 'texte': 'coucou', 'created_at': 1762950000});
    return Future<void>.delayed(Duration.zero, () {
      expect(recu, isNotNull);
      expect(recu!.quand, dateDuMessage(1762950000));
    });
  });

  group('Un appui demande son heure', () {
    /// Une conversation de trois lignes : un mot, des dessins, une enveloppe.
    /// Toutes à la même seconde, pour n'avoir qu'une date à vérifier.
    const quand = 1762950000;

    Future<void> ouvrir(WidgetTester tester, {bool avecHeure = true}) async {
      final online = OnlineService(
        client: OnlineClient(
          api: ApiClient(
            client: MockClient(
              (request) async => http.Response(
                jsonEncode({
                  'ok': true,
                  'messages': [
                    {
                      'texte': 'Et paf',
                      'de_moi': false,
                      if (avecHeure) 'created_at': quand,
                    },
                    {
                      'texte': '😀[Soldat]',
                      'de_moi': true,
                      if (avecHeure) 'created_at': quand,
                    },
                    {
                      'texte': kJetonEnveloppe,
                      'de_moi': false,
                      if (avecHeure) 'created_at': quand,
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'toto'),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Ce que la ligne d'heure doit dire.
    String ligne() {
      final d = DateTime.fromMillisecondsSinceEpoch(quand * 1000);
      final h = d.hour.toString().padLeft(2, '0');
      final mn = d.minute.toString().padLeft(2, '0');
      return '${dateEcriteSelon(d, 'fr')} · $h:$mn';
    }

    testWidgets('sur un mot', (tester) async {
      await ouvrir(tester);
      expect(find.text(ligne()), findsNothing);

      await tester.tap(find.text('Et paf'));
      await tester.pumpAndSettle();
      expect(find.text(ligne()), findsOneWidget);

      // Un second appui la referme.
      await tester.tap(find.text('Et paf'));
      await tester.pumpAndSettle();
      expect(find.text(ligne()), findsNothing);
    });

    testWidgets('sur des dessins, qui n ont pas de bulle', (tester) async {
      await ouvrir(tester);
      // Le jeton est devenu une image : c'est elle qu'on touche.
      await tester.tap(
        find
            .descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(ProfilePhoto),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text(ligne()), findsOneWidget);
    });

    testWidgets("sur l'avis d'enveloppe", (tester) async {
      await ouvrir(tester);
      await tester.tap(find.textContaining('enveloppe').last);
      await tester.pumpAndSettle();
      expect(find.text(ligne()), findsOneWidget);
    });

    testWidgets('une seule heure à la fois', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.text('Et paf'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('enveloppe').last);
      await tester.pumpAndSettle();
      expect(find.text(ligne()), findsOneWidget);
    });

    // Un serveur d'avant ne la donne pas : on se tait plutôt que d'inventer.
    testWidgets('sans heure connue, rien ne paraît', (tester) async {
      await ouvrir(tester, avecHeure: false);
      await tester.tap(find.text('Et paf'));
      await tester.pumpAndSettle();
      expect(find.textContaining('·'), findsNothing);
    });
  });
}
