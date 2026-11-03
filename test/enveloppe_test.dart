/// Les enveloppes : leur chrono, et ce qui se balance.
///
/// Nino : « il y a un minuteur de 48 heures sur chaque enveloppe. Quand le
/// minuteur s'est écoulé, l'enveloppe est supprimée automatiquement. Le
/// minuteur affiche le temps selon le modèle 48h00 -> 47h59 », puis « les
/// enveloppes qu'on peut ouvrir doivent osciller ».
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/enveloppe.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/enveloppe_jeton.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/picto_touche.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une enveloppe qui expire dans [reste], vue de [maintenant].
Enveloppe enveloppe(Duration reste, {bool deMoi = false}) {
  final maintenant = DateTime(2026, 11, 3, 12);
  return Enveloppe(
    id: 1,
    deMoi: deMoi,
    creeA: maintenant.millisecondsSinceEpoch ~/ 1000,
    expireA: maintenant.add(reste).millisecondsSinceEpoch ~/ 1000,
  );
}

final DateTime _maintenant = DateTime(2026, 11, 3, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });

  group('Le chrono', () {
    // Nino : « je ne veux pas que ça arrondisse à la minute. »
    test('posée, elle affiche 48h00 — puis 47h59 dès la première seconde', () {
      expect(chronoEnveloppe(kEnveloppeVie), '48h00');
      expect(
        chronoEnveloppe(kEnveloppeVie - const Duration(seconds: 1)),
        '47h59',
        reason: 'la minute entamée ne compte pas : on tronque',
      );
    });

    test('et 47h59 dure la minute entière', () {
      expect(
        chronoEnveloppe(kEnveloppeVie - const Duration(seconds: 59)),
        '47h59',
      );
      expect(
        chronoEnveloppe(kEnveloppeVie - const Duration(minutes: 1)),
        '47h59',
        reason: 'une minute pleine passée : elle bascule à 47h58 juste après',
      );
      expect(
        chronoEnveloppe(kEnveloppeVie - const Duration(minutes: 1, seconds: 1)),
        '47h58',
      );
    });

    test('les minutes prennent deux chiffres, les heures non', () {
      expect(chronoEnveloppe(const Duration(hours: 1, minutes: 5)), '1h05');
      expect(chronoEnveloppe(const Duration(minutes: 59)), '0h59');
      // La dernière minute affiche « 0h00 » : il ne reste vraiment plus rien.
      expect(chronoEnveloppe(const Duration(seconds: 30)), '0h00');
    });

    test('au bout, 0h00 — mais l enveloppe est déjà partie', () {
      expect(chronoEnveloppe(Duration.zero), '0h00');
      expect(chronoEnveloppe(const Duration(seconds: -5)), '0h00');
    });
  });

  group('Ce qui s ouvre, et ce qui se balance', () {
    test('celle qu on a reçue s ouvre, la sienne non', () {
      expect(enveloppe(kEnveloppeVie).ouvrable, isTrue);
      expect(enveloppe(kEnveloppeVie, deMoi: true).ouvrable, isFalse);
    });

    test('expirée se reconnaît, et ne reste rien', () {
      final morte = enveloppe(Duration.zero);
      expect(morte.expiree(_maintenant), isTrue);
      expect(morte.restant(_maintenant), Duration.zero);
    });

    Future<void> poser(WidgetTester tester, Enveloppe e) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EnveloppeJeton(
                enveloppe: e,
                couleur: Colors.orange,
                maintenant: _maintenant,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Le SINUS de l'angle sous lequel le jeton est dessiné.
    ///
    /// Le sinus plutôt que le cosinus : à trois degrés près de zéro, le
    /// cosinus ne bouge pas du quatrième chiffre, tandis que le sinus suit
    /// l'angle et change même de signe.
    double penche(WidgetTester tester) {
      final t = tester.widget<Transform>(find.byKey(cleDuBalancement));
      return t.transform.storage[1];
    }

    // Nino : « l'oscillement n'est pas bon. L'enveloppe doit faire un
    // oscillement SEC toutes les 1,3 secondes. »
    testWidgets('celle qu on peut ouvrir a une secousse sèche', (tester) async {
      await poser(tester, enveloppe(kEnveloppeVie));
      expect(penche(tester), 0, reason: 'elle part droite');

      // Les instants sont comptés depuis le début du cycle, qui en dure
      // 1300 : la secousse occupe les 300 premiers, le reste est immobile.

      // 100 — LA SECOUSSE.
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        penche(tester),
        isNot(0),
        reason: 'elle doit sursauter pour appeler l œil',
      );

      // 600 puis 700 — LE REPOS, et c'est lui qui rend la secousse sèche :
      // passé les 300 premiers, elle est droite et parfaitement immobile.
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        penche(tester),
        0,
        reason: 'entre deux secousses, elle ne bouge plus',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(penche(tester), 0);

      // 1400, soit 100 du cycle suivant — ELLE RECOMMENCE.
      await tester.pump(const Duration(milliseconds: 700));
      expect(penche(tester), isNot(0));
    });

    testWidgets('la sienne se tient droite', (tester) async {
      await poser(tester, enveloppe(kEnveloppeVie, deMoi: true));
      expect(
        find.byKey(cleDuBalancement),
        findsNothing,
        reason: 'aucune rotation : elle n appelle personne',
      );
    });

    // Nino : « toutes les bulles doivent être en couleur 1 et toutes les
    // enveloppes en couleur 2, histoire d'équilibrer. »
    test('une enveloppe porte la SECONDE couleur, les bulles la première', () {
      final palette = paletteOf('original');
      expect(couleurEnveloppe(palette), palette.fonce);
      expect(
        couleurEnveloppe(palette),
        isNot(palette.clair),
        reason: 'les bulles ont la première : les deux se partagent l écran',
      );
    });

    testWidgets('le chrono est écrit par-dessus le dessin', (tester) async {
      await poser(tester, enveloppe(const Duration(hours: 12, minutes: 34)));
      expect(find.text('12h34'), findsOneWidget);
    });

    // Nino, la rangée sous les yeux : « les enveloppes reçues et envoyées
    // sont trop petites. Mets-les de la même taille que celle qui est dans le
    // bouton en haut à droite. »
    testWidgets('le jeton fait la taille de la touche, donc son dessin aussi', (
      tester,
    ) async {
      await poser(tester, enveloppe(kEnveloppeVie));
      final jeton = tester.getSize(find.byType(EnveloppeJeton));
      expect(jeton.width, touchHeight());
      expect(
        jeton.height,
        touchHeight(),
        reason: 'le même carré que la touche : le même dessin dedans',
      );
    });
  });

  group('La touche qui envoie', () {
    Future<void> poserLaTouche(WidgetTester tester, {bool actif = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: touchHeight(),
                child: ToucheEnveloppePlus(
                  palette: paletteOf('original'),
                  actif: actif,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // Nino : « pour remplacer l'enveloppe avec le plus, voici un symbole
    // qui le contient déjà. » Plus de signe dessiné par-dessus : il
    // recouvrait l'enveloppe.
    testWidgets('le symbole porte son « + », on n en dessine pas un second', (
      tester,
    ) async {
      await poserLaTouche(tester);

      expect(find.text('+'), findsNothing);
      final picto = tester.widget<PictoTouche>(find.byType(PictoTouche));
      expect(picto.asset, 'assets/images/enveloppe_plus.webp');
    });

    // Nino : « le fond de la touche doit être du même gris que [retour]. »
    testWidgets('le gris est celui des touches de bandeau', (tester) async {
      await poserLaTouche(tester);
      final fond = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(ToucheEnveloppePlus),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(fond.color, kFugaGrey);
    });

    testWidgets('éteinte, elle pâlit sans disparaître', (tester) async {
      await poserLaTouche(tester, actif: false);
      expect(find.byType(ToucheEnveloppePlus), findsOneWidget);
      final fond = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(ToucheEnveloppePlus),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(fond.color, isNot(kFugaGrey));
    });
  });
}
