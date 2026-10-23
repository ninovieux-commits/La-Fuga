/// MESURE : un message envoyé dans une longue conversation se voit-il ?
library;

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

  testWidgets('envoi dans une conversation de quarante messages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    DecorsConnus.clear();
    DecorsConnus.remember('toto', 'foret');

    final messages = [
      for (var i = 0; i < 40; i++)
        {'texte': 'message numéro $i', 'de_moi': i.isEven},
    ];
    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            if (req.url.path.endsWith('/send_message')) {
              messages.add({'texte': 'tout dernier', 'de_moi': true});
            }
            return http.Response(
              jsonEncode({
                'ok': true,
                'messages': messages,
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

    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(online: online, pseudo: 'toto'),
      ),
    );
    await tester.pumpAndSettle();

    final liste = find.byType(Scrollable).last;
    double offset() => tester.widget<Scrollable>(liste).controller!.offset;
    double max() =>
        tester.widget<Scrollable>(liste).controller!.position.maxScrollExtent;
    debugPrint(
      'À L OUVERTURE : offset=${offset().toStringAsFixed(0)} '
      'max=${max().toStringAsFixed(0)}',
    );

    await tester.enterText(find.byType(TextField), 'tout dernier');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    debugPrint(
      'JUSTE APRÈS   : offset=${offset().toStringAsFixed(0)} '
      'max=${max().toStringAsFixed(0)} '
      'visible=${tester.any(find.text('tout dernier'))}',
    );

    await tester.pumpAndSettle();
    final bulles = tester
        .widgetList<MessageBubble>(find.byType(MessageBubble))
        .map((b) => b.texte)
        .toList();
    debugPrint(
      'APRÈS TOUT    : offset=${offset().toStringAsFixed(0)} '
      'max=${max().toStringAsFixed(0)}',
    );
    debugPrint(
      'DERNIÈRES BULLES CONSTRUITES : ${bulles.length > 3 ? bulles.sublist(bulles.length - 3) : bulles}',
    );
    debugPrint(
      '« tout dernier » à l écran : ${tester.any(find.text('tout dernier'))}',
    );
  });
}
