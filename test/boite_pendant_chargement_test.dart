/// La boîte de messages pendant qu'elle charge.
///
/// Nino : « la boîte de messages charge souvent ainsi » (roue au milieu), et
/// « quand j'envoie un message depuis la boîte, je suis obligé de revenir
/// sur la partie puis de rouvrir la boîte pour que le message s'affiche ».
///
/// Les deux n'en faisaient qu'un : la roue occupait toute la place tant que
/// la liste du serveur n'était pas là, alors que le champ et la touche
/// « Envoyer », eux, restaient utilisables. On pouvait donc écrire, envoyer,
/// et ne RIEN voir — jusqu'à la réouverture.
///
/// Mesuré avant correction : « APRÈS ENVOI : roue=true bulles=[] ».
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('un message écrit pendant le chargement se voit tout de suite', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    DecorsConnus.clear();
    // Deuxième visite : son décor est déjà connu.
    DecorsConnus.remember('toto', 'foret');

    final liste = Completer<void>();
    final messages = <Map<String, Object>>[
      {'texte': 'coucou', 'de_moi': false},
    ];
    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            if (req.url.path.endsWith('/list_conversation')) {
              await liste.future; // le serveur traîne
              return http.Response(
                jsonEncode({'ok': true, 'messages': messages}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            if (req.url.path.endsWith('/send_message')) {
              messages.add({'texte': 'je suis là', 'de_moi': true});
            }
            return http.Response(
              jsonEncode({
                'ok': true,
                'description': 'd',
                'theme': 'foret',
                'photo': 'nurse',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(online: online, pseudo: 'toto'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    List<String> vues() => tester
        .widgetList<MessageBubble>(find.byType(MessageBubble))
        .map((b) => b.texte)
        .toList();
    final roue = find.byType(CircularProgressIndicator);
    debugPrint(
      'PENDANT LE CHARGEMENT : roue=${roue.evaluate().isNotEmpty} '
      'bulles=${vues()}',
    );

    // J'écris quand même : le champ est là, la touche aussi.
    await tester.enterText(find.byType(TextField), 'je suis là');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    debugPrint(
      'APRÈS ENVOI           : roue=${roue.evaluate().isNotEmpty} '
      'bulles=${vues()}',
    );

    // La liste arrive enfin — elle date d'AVANT mon envoi.
    liste.complete();
    await tester.pumpAndSettle();
    expect(vues(), [
      'coucou',
      'je suis là',
    ], reason: 'la liste arrive, et mon message y est UNE fois');
  });
}
