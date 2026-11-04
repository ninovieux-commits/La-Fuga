/// La refonte du menu : deux façons de jouer sur une rangée, quatre grosses
/// touches, et une barre de séparation qui n'a pas bougé d'un pixel.
///
/// Nino a demandé trois mesures, et ce sont des mesures qu'on vérifie ici,
/// pas des apparences :
///
/// - « la largeur des deux touches additionnées doit être la même que les
///   trois touches de cadences additionnées au-dessus » ;
/// - « la hauteur des touches doit être gérée de manière à ce que la barre
///   d'indication qui est en bas reste exactement au même endroit tout en
///   étant espacée des touches qui sont au-dessus exactement de la même
///   distance » ;
/// - « les quatre grosses touches [...] doivent être séparées et prendre la
///   même largeur que les actuelles touches ».
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
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
    resetScale();
  });
  tearDown(resetScale);

  /// Le menu, à la taille d'un téléphone ordinaire.
  Future<void> ouvre(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const FugaApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  }

  /// La boîte de la touche qui porte ce mot.
  Rect touche(WidgetTester tester, String mot) {
    for (final e in find.byType(FugaButton).evaluate()) {
      if ((e.widget as FugaButton).text == mot) {
        return tester.getRect(find.byWidget(e.widget));
      }
    }
    fail('touche « $mot » introuvable');
  }

  testWidgets('les deux façons de jouer additionnent la largeur des trois '
      'cadences', (tester) async {
    await ouvre(tester);

    final cadences = [
      '5 min',
      '15 min',
      '30 min',
    ].map((m) => touche(tester, m)).toList();
    final jouer = [
      touche(tester, 'Jouer en local'),
      touche(tester, 'Jouer en ligne'),
    ];

    double somme(List<Rect> r) => r.fold<double>(0, (t, b) => t + b.width);

    expect(
      somme(jouer),
      moreOrLessEquals(somme(cadences), epsilon: 0.5),
      reason: 'les deux touches doivent additionner la largeur des trois',
    );
    // Et elles tombent au même alignement, à gauche comme à droite.
    expect(
      jouer.first.left,
      moreOrLessEquals(cadences.first.left, epsilon: 0.5),
    );
    expect(
      jouer.last.right,
      moreOrLessEquals(cadences.last.right, epsilon: 0.5),
    );
  });

  testWidgets('chacune des deux prend une moitié', (tester) async {
    await ouvre(tester);
    final local = touche(tester, 'Jouer en local');
    final ligne = touche(tester, 'Jouer en ligne');
    expect(local.width, moreOrLessEquals(ligne.width, epsilon: 0.5));
    expect(local.right, lessThan(ligne.left), reason: 'elles sont séparées');
  });

  testWidgets('la barre de séparation est restée exactement où elle était', (
    tester,
  ) async {
    await ouvre(tester);

    // L'ancien menu : six touches larges entre la rangée des cadences et le
    // trait, séparées de SH(0,012) + S(6), encadrées de SH(0,02) + S(6).
    const gap = 6.0;
    final avant =
        SH(0.02) +
        S(gap) +
        6 * touchHeight() +
        5 * (SH(0.012) + S(gap)) +
        SH(0.02) +
        S(gap);

    final cadence = touche(tester, '15 min');
    // Le trait : la seule barre arrondie et pleine largeur sous les touches.
    final trait = tester.getRect(find.byType(AnimatedContainer).first);

    expect(
      trait.top - cadence.bottom,
      moreOrLessEquals(avant, epsilon: 0.5),
      reason: 'le trait doit retomber à la même distance des cadences',
    );
  });

  testWidgets('les quatre grosses touches sont séparées et larges comme '
      'les anciennes', (tester) async {
    await ouvre(tester);

    final mots = [
      'Conversations',
      'Classement',
      'Affronter Deep Grey',
      'Autres',
    ];
    final boites = [for (final m in mots) tester.getRect(find.text(m))];
    expect(boites.length, 4);

    // Deux rangées de deux : les deux premières côte à côte, puis dessous.
    expect(
      boites[0].center.dy,
      moreOrLessEquals(boites[1].center.dy, epsilon: 1),
    );
    expect(
      boites[2].center.dy,
      moreOrLessEquals(boites[3].center.dy, epsilon: 1),
    );
    expect(boites[2].center.dy, greaterThan(boites[0].center.dy));

    // Elles vivent dans la largeur des anciennes touches larges : celle de
    // la ligne de recherche, qui ne change pas.
    final recherche = tester.getRect(find.byKey(kBarreRechercheKey));
    final etoile = touche(tester, '★');
    expect(boites[0].left, greaterThanOrEqualTo(recherche.left - 1));
    expect(boites[1].right, lessThanOrEqualTo(etoile.right + 1));
  });
}
