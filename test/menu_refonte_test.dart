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
import 'package:lafuga/theme/themes.dart';
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
    // Une touche qui porte deux lignes — « Jouer en ligne » et son mélo —
    // n'a pas de `text` : on la retrouve par le mot qu'elle affiche.
    final parSonMot = find.ancestor(
      of: find.text(mot),
      matching: find.byType(FugaButton),
    );
    if (parSonMot.evaluate().isNotEmpty) {
      return tester.getRect(parSonMot.first);
    }
    fail('touche « $mot » introuvable');
  }

  testWidgets('l interstice est le même entre toutes les touches, en '
      'largeur aussi', (tester) async {
    await ouvre(tester);

    final attendu = intervalleDuMenu();
    final cadences = [
      '5 min',
      '15 min',
      '30 min',
    ].map((m) => touche(tester, m)).toList();
    final local = touche(tester, 'Jouer en local');
    final ligne = touche(tester, 'Jouer en ligne');
    final recherche = tester.getRect(find.byKey(kBarreRechercheKey));
    final etoile = touche(tester, '★');

    final ecarts = <String, double>{
      'entre 5 et 15 min': cadences[1].left - cadences[0].right,
      'entre 15 et 30 min': cadences[2].left - cadences[1].right,
      'entre local et ligne': ligne.left - local.right,
      'entre la recherche et l étoile': etoile.left - recherche.right,
    };
    for (final e in ecarts.entries) {
      expect(
        e.value,
        moreOrLessEquals(attendu, epsilon: 0.5),
        reason:
            '« ${e.key} » : ${e.value.toStringAsFixed(1)} au lieu de '
            '${attendu.toStringAsFixed(1)}',
      );
    }
  });

  testWidgets('les deux rangées de la bande tombent au même alignement', (
    tester,
  ) async {
    await ouvre(tester);
    final cadences = ['5 min', '30 min'].map((m) => touche(tester, m)).toList();
    final local = touche(tester, 'Jouer en local');
    final ligne = touche(tester, 'Jouer en ligne');
    expect(local.left, moreOrLessEquals(cadences.first.left, epsilon: 0.5));
    expect(ligne.right, moreOrLessEquals(cadences.last.right, epsilon: 0.5));
  });

  testWidgets('chacune des deux prend une moitié', (tester) async {
    await ouvre(tester);
    final local = touche(tester, 'Jouer en local');
    final ligne = touche(tester, 'Jouer en ligne');
    expect(local.width, moreOrLessEquals(ligne.width, epsilon: 0.5));
    expect(local.right, lessThan(ligne.left), reason: 'elles sont séparées');
  });

  /// La boîte d'une des quatre grosses touches : le `Material` le plus
  /// proche du mot qu'elle porte.
  Rect grosse(WidgetTester tester, String mot) => tester.getRect(
    find.ancestor(of: find.text(mot), matching: find.byType(Material)).first,
  );

  testWidgets('l interligne du menu est partout le même', (tester) async {
    await ouvre(tester);

    final attendu = intervalleDuMenu();
    final cadence = touche(tester, '15 min');
    final local = touche(tester, 'Jouer en local');
    final recherche = tester.getRect(find.byKey(kBarreRechercheKey));
    final conversations = grosse(tester, 'Conversations');
    final deepGrey = grosse(tester, nomInsecable('Affronter Deep Grey'));
    final trait = tester.getRect(find.byType(AnimatedContainer).first);

    final ecarts = <String, double>{
      'cadences → jouer': local.top - cadence.bottom,
      'jouer → recherche': recherche.top - local.bottom,
      'recherche → grosses touches': conversations.top - recherche.bottom,
      'entre les deux rangées de grosses touches':
          deepGrey.top - conversations.bottom,
      'grosses touches → barre': trait.top - deepGrey.bottom,
    };
    for (final e in ecarts.entries) {
      expect(
        e.value,
        moreOrLessEquals(attendu, epsilon: 0.5),
        reason:
            '« ${e.key} » : ${e.value.toStringAsFixed(1)} au lieu de '
            '${attendu.toStringAsFixed(1)}',
      );
    }
  });

  testWidgets('les deux colonnes sont écartées comme les deux rangées', (
    tester,
  ) async {
    await ouvre(tester);
    final gauche = grosse(tester, 'Conversations');
    final droite = grosse(tester, 'Classement');
    expect(
      droite.left - gauche.right,
      moreOrLessEquals(intervalleDuMenu(), epsilon: 0.5),
    );
  });

  testWidgets('une grosse touche vaut deux touches ordinaires', (tester) async {
    await ouvre(tester);
    expect(
      grosse(tester, 'Classement').height,
      moreOrLessEquals(touchHeight() * 2, epsilon: 0.5),
      reason: 'elle porte un dessin ET un mot, donc deux fois une touche',
    );
  });

  testWidgets('les quatre grosses touches sont séparées et larges comme '
      'les anciennes', (tester) async {
    await ouvre(tester);

    final mots = [
      'Conversations',
      'Classement',
      nomInsecable('Affronter Deep Grey'),
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

  testWidgets('le menu tient en un écran, la barre en ferme le bas', (
    tester,
  ) async {
    await ouvre(tester);
    final trait = tester.getRect(find.byType(AnimatedContainer).first);
    // Pas collée au rebord : le même interstice que partout. Nino : « il
    // doit y avoir le même espace entre la barre de séparation et le bord de
    // l'écran qu'entre la barre de séparation et les touches au-dessus. »
    expect(
      tester.view.physicalSize.height - trait.bottom,
      moreOrLessEquals(intervalleDuMenu(), epsilon: 0.5),
      reason:
          'les touches et la barre prennent tout l écran, à un '
          'interstice près',
    );
  });

  testWidgets('le titre et le logo gardent leur taille', (tester) async {
    await ouvre(tester);
    expect(
      tester.getSize(find.byType(Image).first).height,
      moreOrLessEquals(SH(0.16), epsilon: 0.5),
      reason: 'le titre ne se laisse pas rogner par la place qui manque',
    );
  });

  group('La cadence', () {
    /// La couleur de fond de la touche qui porte ce mot.
    Color fond(WidgetTester tester, String mot) {
      for (final e in find.byType(FugaButton).evaluate()) {
        final b = e.widget as FugaButton;
        if (b.text == mot) return b.color;
      }
      fail('touche « $mot » introuvable');
    }

    testWidgets('aucune n est choisie en arrivant', (tester) async {
      await ouvre(tester);
      for (final m in ['5 min', '15 min', '30 min']) {
        expect(
          fond(tester, m),
          kGrisTouche,
          reason:
              'Nino : « quand on arrive sur le menu, aucun des trois ne '
              'doit être sélectionné » — $m',
        );
      }
    });

    testWidgets('la toucher une seconde fois la retire', (tester) async {
      await ouvre(tester);
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      expect(fond(tester, '15 min'), isNot(kGrisTouche));

      // Nino : « il faut que cliquer sur une cadence sélectionnée la
      // désélectionne. » C'est le seul moyen de revenir à une partie locale
      // sans chrono une fois qu'on a choisi.
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      expect(fond(tester, '15 min'), kGrisTouche);
    });

    testWidgets('les deux bords s allument en couleur 1, le milieu en 2', (
      tester,
    ) async {
      await ouvre(tester);
      final palette = paletteOf(Settings.instance.themeAxes.general);

      await tester.tap(find.text('5 min'));
      await tester.pumpAndSettle();
      expect(fond(tester, '5 min'), palette.clair);
      expect(fond(tester, '15 min'), kGrisTouche);

      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();
      expect(fond(tester, '30 min'), palette.clair);
      expect(fond(tester, '5 min'), kGrisTouche);

      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      expect(
        fond(tester, '15 min'),
        palette.fonce,
        reason: 'Nino : « 15 min continue à s allumer en couleur 2 »',
      );
    });
  });

  group('La barre de séparation se touche', () {
    /// Où en est le défilement du menu.
    ScrollPosition defilement(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    testWidgets('elle descend aux parties par correspondance', (tester) async {
      await ouvre(tester);
      expect(defilement(tester).pixels, 0, reason: 'on part du haut');

      await tester.tap(find.byType(AnimatedContainer).first);
      await tester.pumpAndSettle();

      final position = defilement(tester);
      expect(position.pixels, greaterThan(0), reason: 'ça a défilé');

      // Nino : « ça fait défiler l'écran jusqu'à ce que ce soit comme sur la
      // photo » — le trait sous les deux touches du bandeau — « s'il n'y a
      // pas assez d'aperçus pour descendre aussi bas, ça descend le plus bas
      // possible ».
      final place = SH(0.015) + touchHeight() + intervalleDuMenu();
      final haut = tester.getRect(find.byType(AnimatedContainer).first).top;
      final enBas = position.pixels >= position.maxScrollExtent - 0.5;
      expect(
        enBas || haut <= place + 1,
        isTrue,
        reason:
            'le trait doit monter à $place, ou le menu descendre au bout — '
            'trait à $haut, défilement ${position.pixels} sur '
            '${position.maxScrollExtent}',
      );
    });

    testWidgets('la surface sensible vaut une touche, pas un trait', (
      tester,
    ) async {
      await ouvre(tester);
      final trait = tester.getRect(find.byType(AnimatedContainer).first);
      final sensible = tester.getRect(
        find
            .ancestor(
              of: find.byType(AnimatedContainer).first,
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(
        sensible.height,
        greaterThan(trait.height * 3),
        reason: 'un trait de onze points est une cible de quatre millimètres',
      );
      expect(
        sensible.height,
        moreOrLessEquals(trait.height + 2 * intervalleDuMenu(), epsilon: 0.5),
      );
    });
  });
}
