/// Les touches d'une case de correspondance sont taillées à leur case.
///
/// Elles étaient figées à `S(34)` — une hauteur de référence en LARGEUR — ce
/// qui, dans une case haute de deux cents pixels, donnait dix-huit pixels là
/// où Kivy en met trente. Elles suivent maintenant le `size_hint` et le
/// `pos_hint` de `_make_corr_slot` : une fraction de la case, à une hauteur
/// donnée depuis le bas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
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

  CorrGame gameOf(Map<String, Object?> extra) => CorrGame.fromJson({
    'game_uid': 'x',
    'adversaire': 'toto',
    'mon_camp': 'Blanc',
    'coups': '',
    ...extra,
  });

  /// Affiche une case de la largeur qu'elle a dans la grille du menu, et rend
  /// les rectangles de ses touches.
  Future<List<Rect>> slotButtons(WidgetTester tester, CorrGame game) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FugaScale(
          child: Center(
            child: SizedBox(
              width: 178,
              child: CorrSlot(
                game: game,
                palette: paletteOf(kDefaultTheme),
                boardTheme: kDefaultTheme,
                onTap: () {},
                onAccept: (_) {},
                onRefuse: (_) {},
                onCancel: (_) {},
                onRematch: (_) {},
                onClose: (_) {},
                onShow: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return [
      for (final element in find.byType(FugaButton).evaluate())
        tester.getRect(find.byWidget(element.widget)),
    ];
  }

  /// Hauteur intérieure d'une case de 178 de large : forme 7/8, moins la
  /// marge de `S(6)` de chaque côté.
  double innerHeight() => 178 * 8 / 7 - 2 * S(6);

  testWidgets('un défi reçu : deux touches, chacune à 15 % de la case', (
    tester,
  ) async {
    final rects = await slotButtons(
      tester,
      gameOf({'statut': 'defi', 'je_suis_challenger': false}),
    );
    expect(rects, hasLength(2));
    for (final r in rects) {
      expect(
        r.height,
        moreOrLessEquals(innerHeight() * 0.15, epsilon: 0.5),
        reason: 'la touche fait 15 % de la case, comme en Kivy',
      );
    }
    // Et elles ne se chevauchent pas : Kivy laisse 3 % entre les deux.
    final sorted = rects.toList()..sort((a, b) => a.top.compareTo(b.top));
    expect(
      sorted[1].top - sorted[0].bottom,
      greaterThan(0),
      reason: 'les deux touches doivent rester séparées',
    );
    // Tout tient dans la case.
    final slot = tester.getRect(find.byType(CorrSlot));
    for (final r in rects) {
      expect(slot.contains(r.topLeft), isTrue);
      expect(slot.contains(r.bottomRight - const Offset(0.5, 0.5)), isTrue);
    }
  });

  testWidgets('une partie finie : Afficher, Revanche et Fermer tiennent', (
    tester,
  ) async {
    // Trois touches depuis qu'on peut revoir une partie finie. Le test en
    // attendait deux et vérifiait UNE séparation ; avec trois, une paire
    // pouvait se chevaucher sans qu'il le voie. Il vérifie maintenant chaque
    // paire consécutive, ce qui vaut pour n'importe quel nombre de touches.
    final rects = await slotButtons(
      tester,
      gameOf({'statut': 'termine', 'resultat': '1-0', 'gagne': true}),
    );
    expect(rects, hasLength(3));
    expect(find.text('Afficher'), findsOneWidget);
    expect(find.text('Revanche'), findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);

    final slot = tester.getRect(find.byType(CorrSlot));
    final sorted = rects.toList()..sort((a, b) => a.top.compareTo(b.top));
    for (var i = 1; i < sorted.length; i++) {
      expect(
        sorted[i].top - sorted[i - 1].bottom,
        greaterThan(0),
        reason: 'les touches $i et ${i - 1} se chevauchent',
      );
    }
    for (final r in rects) {
      expect(r.height, moreOrLessEquals(innerHeight() * 0.15, epsilon: 0.5));
      expect(slot.bottom - r.bottom, greaterThan(0));
      expect(slot.contains(r.topLeft), isTrue, reason: 'une touche déborde');
    }

    // Le résultat de la partie reste lisible au-dessus des trois touches.
    final texte = tester.getRect(find.text('Gagné !'));
    expect(
      sorted.first.top - texte.bottom,
      greaterThan(0),
      reason: 'le résultat chevauche la première touche',
    );
  });
}
