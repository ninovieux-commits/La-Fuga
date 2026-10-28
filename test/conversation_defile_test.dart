/// Ouvrir une conversation, c'est tomber sur son DERNIER message.
///
/// Nino : « quand je vais dans une discussion ça m'envoie au début de celle-ci
/// au lieu de la fin. »
///
/// `ListView.builder` est paresseux : il ne construit que ce qu'il faut
/// afficher, donc `maxScrollExtent` n'est qu'une estimation tant que le reste
/// ne l'est pas. Un seul `jumpTo` atterrissait court, et d'autant plus court
/// que la conversation est longue — mesuré avant correction : 86 pixels (une
/// bulle) sur douze messages, 2 150 pixels (vingt-cinq bulles) sur soixante.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/messages_caches.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
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

  ScrollPosition position(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!.position;

  /// Vrai quand ce texte est non seulement construit, mais DANS la fenêtre.
  bool souslesYeux(WidgetTester tester, String texte) {
    final cible = find.text(texte);
    if (cible.evaluate().isEmpty) return false;
    final liste = tester.getRect(find.byType(ListView));
    final r = tester.getRect(cible);
    return r.top >= liste.top - 0.5 && r.bottom <= liste.bottom + 0.5;
  }

  /// Une conversation de [combien] messages, ouverte.
  Future<OnlineService> ouvre(WidgetTester tester, int combien) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient(
            (req) async => http.Response(
              jsonEncode(
                req.url.path == '/list_conversation'
                    ? {
                        'ok': true,
                        'messages': [
                          for (var i = 0; i < combien; i++)
                            {'texte': 'message numero $i', 'de_moi': i.isEven},
                        ],
                      }
                    : {'ok': true, 'photo': '', 'theme': 'insectes'},
              ),
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
    return online;
  }

  group('Dès le cache, sans attendre le serveur', () {
    late Completer<http.Response> muet;
    setUp(() => muet = Completer<http.Response>());

    // Nino : « ça me fait apparaître tout en haut de la conversation
    // pendant une demi-seconde, puis je suis téléporté tout en bas. Ça le
    // faisait plus ça normalement. »
    //
    // Le cache pose les messages d'avant dès la première image ; rien ne
    // descendait avant la réponse du serveur. Avant le cache, la première
    // image était vide : il n'y avait pas de haut à voir.

    /// Un cache de [combien] messages, et un serveur qui ne répond JAMAIS :
    /// seul le cache est à l'écran.
    Future<void> ouvreSurLeCache(WidgetTester tester, int combien) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
        'conv_toto': jsonEncode([
          for (var i = 0; i < combien; i++)
            {'t': 'message numero $i', 'm': i.isEven},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      MessagesCaches.utilise(prefs);

      // UN SERVEUR QUI SE TAIT, le temps des premières images : ce qu'on
      // mesure ne peut alors venir que du cache. Il répondra à la fin, pour
      // qu'aucune requête ne reste en l'air.
      final online = OnlineService(
        client: OnlineClient(
          api: ApiClient(client: MockClient((req) => muet.future)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'toto'),
        ),
      );
      // Des images, sans avancer l'horloge : la minuterie de relecture ne
      // doit pas se déclencher, on ne mesure que l'ouverture.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    testWidgets('on ouvre en bas, et non en haut', (tester) async {
      await ouvreSurLeCache(tester, 40);

      final p = position(tester);
      expect(
        p.maxScrollExtent,
        greaterThan(0),
        reason: 'le cache a de quoi défiler',
      );
      expect(
        p.pixels,
        moreOrLessEquals(p.maxScrollExtent, epsilon: 0.5),
        reason: 'le haut de la conversation ne doit jamais se montrer',
      );
      expect(souslesYeux(tester, 'message numero 39'), isTrue);

      // Le serveur répond enfin, et l'écran se démonte : ni requête ni
      // minuterie ne traînent après le test.
      // L'écran se démonte D'ABORD : sa minuterie de relecture s'arrête, et
      // plus aucune requête ne part. Le serveur répond ensuite à celles qui
      // attendaient encore, pour qu'il ne reste rien en l'air.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      muet.complete(http.Response('{}', 500));
      // Assez loin pour que le délai maximal des requêtes soit passé : il ne
      // reste alors plus une seule minuterie en l'air.
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
    });
  });

  group('On ouvre sur la fin', () {
    testWidgets('une conversation courte tient à l écran, rien à défiler', (
      tester,
    ) async {
      await ouvre(tester, 3);
      expect(position(tester).maxScrollExtent, 0);
      expect(souslesYeux(tester, 'message numero 0'), isTrue);
      expect(souslesYeux(tester, 'message numero 2'), isTrue);
    });

    testWidgets('douze messages : on est en bas, pas une bulle plus haut', (
      tester,
    ) async {
      await ouvre(tester, 12);
      final p = position(tester);
      expect(
        p.pixels,
        moreOrLessEquals(p.maxScrollExtent, epsilon: 0.5),
        reason: 'un seul saut atterrissait 86 pixels trop haut',
      );
      expect(
        souslesYeux(tester, 'message numero 11'),
        isTrue,
        reason: 'le dernier message doit être sous les yeux',
      );
    });

    testWidgets('soixante messages : en bas aussi', (tester) async {
      await ouvre(tester, 60);
      final p = position(tester);
      expect(
        p.pixels,
        moreOrLessEquals(p.maxScrollExtent, epsilon: 0.5),
        reason: 'un seul saut atterrissait vingt-cinq bulles trop haut',
      );
      expect(souslesYeux(tester, 'message numero 59'), isTrue);
      expect(
        souslesYeux(tester, 'message numero 0'),
        isFalse,
        reason: 'le début est loin derrière : sinon le test ne prouve rien',
      );
    });

    testWidgets('cinq cents messages : en bas encore', (tester) async {
      // La paresse de la liste grandit avec elle : c'est le cas qui condamne
      // le saut unique.
      await ouvre(tester, 500);
      final p = position(tester);
      expect(p.maxScrollExtent, greaterThan(10000));
      expect(p.pixels, moreOrLessEquals(p.maxScrollExtent, epsilon: 0.5));
      expect(souslesYeux(tester, 'message numero 499'), isTrue);
    });
  });

  group('Et on y reste', () {
    testWidgets('un message envoyé reste sous les yeux', (tester) async {
      await ouvre(tester, 40);
      await tester.enterText(find.byType(TextField), 'ma réponse');
      await tester.tap(find.widgetWithText(FilledButton, T('Envoyer')));
      await tester.pumpAndSettle();

      final p = position(tester);
      expect(p.pixels, moreOrLessEquals(p.maxScrollExtent, epsilon: 0.5));
      expect(souslesYeux(tester, 'ma réponse'), isTrue);
    });

    testWidgets('un message reçu en direct amène jusqu à lui', (tester) async {
      final online = await ouvre(tester, 40);
      online.messages.receive({'de': 'toto', 'texte': 'coucou'});
      await tester.pumpAndSettle();

      final p = position(tester);
      expect(p.pixels, moreOrLessEquals(p.maxScrollExtent, epsilon: 0.5));
      expect(souslesYeux(tester, 'coucou'), isTrue);
    });
  });
}
