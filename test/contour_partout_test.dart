/// LE CONTOUR NOIR, DE PARTOUT.
///
/// Nino, devant une fiche de joueur : « pourquoi les textes ici n'ont pas
/// tous le contour noir ? Il faut vérifier chacune des parties de l'App et
/// mettre ce contour noir de partout. De partout. »
///
/// Deux façons de le vérifier, et il faut les deux :
///
///  * à la SOURCE — plus un seul `Text(` dans l'interface, c'est [Texte] qui
///    écrit, et lui cerne ce qu'il écrit. Un essai de source attrape la
///    prochaine ligne écrite, celle qu'aucun écran de test ne montera ;
///  * à l'ÉCRAN — on monte des écrans et on relit chaque mot peint.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/screens/settings_screen.dart';
import 'package:lafuga/ui/theme_fuga.dart';
import 'package:lafuga/ui/widgets/player_card.dart';
import 'package:lafuga/ui/widgets/texte.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

/// Les deux seuls fichiers qui ont le droit d'écrire `Text(` : celui qui
/// pose le contour, et celui qui le dessine.
const Set<String> kSansContour = {
  'lib/ui/widgets/texte.dart',
  'lib/ui/widgets/picto_touche.dart',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('À la source', () {
    final fichiers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('il y a bien des fichiers à relire', () {
      expect(fichiers.length, greaterThan(50));
    });

    test('plus un seul « Text( » dans l application', () {
      final fautifs = <String>[];
      for (final f in fichiers) {
        if (kSansContour.contains(f.path)) continue;
        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          final l = lignes[i].trim();
          if (l.startsWith('//')) continue;
          // `Text(` précédé d'une lettre, c'est un autre nom —
          // `SelectableText(`, `RichText(`.
          if (RegExp(r'(?<![A-Za-z0-9_.$])Text(\.rich)?\(').hasMatch(l)) {
            fautifs.add('${f.path}:${i + 1}  $l');
          }
        }
      }
      expect(
        fautifs,
        isEmpty,
        reason:
            'Texte() écrit à la place de Text() : il cerne ce qu il écrit.\n'
            '${fautifs.join('\n')}',
      );
    });

    test('ce qui peint hors de Texte porte le contour lui-même', () {
      // Un texte peint sur une toile ([TextPainter]) ou qu'on peut choisir à
      // la main ([SelectableText]) ne passe pas par [Texte] : il doit
      // nommer [contourDesLettres].
      const mesurentSeulement = {
        'lib/ui/mesure_emoji.dart',
        'lib/ui/widgets/texte_remplissant.dart',
      };
      for (final f in fichiers) {
        final src = f.readAsStringSync();
        final peint =
            src.contains('TextPainter(') || src.contains('SelectableText(');
        if (!peint || mesurentSeulement.contains(f.path)) continue;
        expect(
          src.contains('contourDesLettres'),
          isTrue,
          reason: '${f.path} peint du texte sans lui donner son contour',
        );
      }
    });
  });

  group('À l écran', () {
    late OnlineService online;
    late Map<String, Map<String, dynamic>> reponses;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
      });
      await Settings.load();
      await Translations.load('fr');
      setScaleSize(const Size(393, 851));
      reponses = {
        '/login': {'ok': true, 'token': 't', 'pseudo': 'nino'},
        '/get_profile': {
          'ok': true,
          'pseudo': 'mesange',
          'is_self': false,
          'melo': 1500,
          'melo_random': 1500,
          'description': 'prout',
          'followers': const [],
          'following': const [],
          'blocked': const [],
          'h2h_direct_moi': 0,
          'h2h_direct_lui': 0,
        },
        '/list_conversations': {
          'ok': true,
          'conversations': const [
            {
              'pseudo': 'celia',
              'last_text': 'caca',
              'last_from_me': false,
              'unread': 2,
            },
          ],
        },
      };
      online = OnlineService(
        client: OnlineClient(
          api: ApiClient(
            client: MockClient(
              (r) async => http.Response(
                jsonEncode(reponses[r.url.path] ?? {'ok': true}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
            ),
          ),
        ),
        // Le menu ouvre un salon en se montant : sans faux salon, l essai
        // attend une vraie connexion qui ne viendra jamais.
        socketFactory: (_) => FakeRealtime(),
      );
      await online.client.login('nino', 'mdp');
    });
    tearDown(resetScale);

    /// Chaque mot peint à l'écran, et ce qu'il porte autour.
    void relisTout(WidgetTester tester) {
      final nus = <String>[];
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final style = t.style;
        if (style?.shadows != null && style!.shadows!.isNotEmpty) continue;
        nus.add('« ${t.data ?? t.textSpan?.toPlainText() ?? '?'} »');
      }
      expect(nus, isEmpty, reason: 'ces mots n ont pas de contour : $nus');
    }

    Future<void> pose(WidgetTester tester, Widget ecran) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: themeFuga(), home: ecran));
      await tester.pumpAndSettle();
    }

    testWidgets('le profil de quelqu un', (tester) async {
      await pose(tester, AccountScreen(online: online, pseudo: 'mesange'));
      relisTout(tester);
    });

    testWidgets('la liste des conversations', (tester) async {
      await pose(tester, ConversationsScreen(online: online));
      relisTout(tester);
    });

    testWidgets('le menu, et tout ce qu il porte', (tester) async {
      reponses['/corr_list'] = {'ok': true, 'games': const []};
      await pose(tester, MenuScreen(online: online));
      relisTout(tester);
    });

    testWidgets('une boîte de discussion', (tester) async {
      reponses['/get_messages'] = {'ok': true, 'messages': const []};
      await pose(tester, ConversationScreen(online: online, pseudo: 'celia'));
      relisTout(tester);
    });

    testWidgets('les réglages', (tester) async {
      await pose(tester, const SettingsScreen());
      relisTout(tester);
    });

    testWidgets('l historique en ligne', (tester) async {
      reponses['/list_games'] = {'ok': true, 'games': const []};
      await pose(tester, HistoryScreen(online: online));
      relisTout(tester);
    });

    testWidgets('la fiche d un joueur', (tester) async {
      await pose(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showPlayerCard(
                  context,
                  online: online,
                  palette: paletteOf('original'),
                  pseudo: 'mesange',
                ),
                child: const Texte('ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      relisTout(tester);
    });
  });
}
