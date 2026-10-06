/// Les règles du pré-coup, sans écran.
///
/// Nino : « On doit pouvoir faire jusqu'à 6 variantes différentes sur 6 coups
/// de longueur, et aucunes variantes ne doivent se contredire. »
///
/// Contredire, c'est répondre deux choses différentes à la même suite de
/// coups. Deux variantes qui se séparent sur un coup de l'ADVERSAIRE ne se
/// contredisent pas : ce sont deux lignes, chacune sa réponse.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/premove.dart';

/// Une variante, écrite comme on la lit : « son coup, le nôtre, … ».
PremoveVariante v(List<String> coups, {String? methode, String? gagnant}) =>
    PremoveVariante(coups, methode: methode, gagnant: gagnant);

void main() {
  group('Une variante bien formée', () {
    test('s arrête toujours sur un de NOS coups', () {
      expect(v(['Fa6-Sol5', 'Sol2-Fa3']).estValide, isTrue);
      expect(
        v(['Fa6-Sol5']).estValide,
        isFalse,
        reason: 's arrêter sur le coup de l adversaire ne prépare rien',
      );
      expect(v(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6']).estValide, isFalse);
    });

    test('ne dépasse pas six demi-coups', () {
      final six = ['a', 'b', 'c', 'd', 'e', 'f'];
      expect(v(six).estValide, isTrue);
      expect(v([...six, 'g', 'h']).estValide, isFalse);
    });

    test('ne contient pas de coup vide', () {
      expect(v(['Fa6-Sol5', '  ']).estValide, isFalse);
      expect(v([]).estValide, isFalse);
    });
  });

  group('Six variantes au plus', () {
    test('la septième est refusée', () {
      var plan = const PremovePlan(base: 4);
      for (var i = 0; i < kPremoveMaxVariantes; i++) {
        // Chacune commence par un coup adverse DIFFÉRENT : six vraies lignes.
        final suivant = plan.avec(v(['adv$i', 'moi$i']));
        expect(suivant, isNotNull, reason: 'la variante ${i + 1} est refusée');
        plan = suivant!;
      }
      expect(plan.variantes.length, 6);
      expect(plan.peutEnAjouter, isFalse);
      expect(plan.refusDe(v(['adv6', 'moi6'])), PremoveRefus.tropDeVariantes);
    });
  });

  group('Aucune variante n en contredit une autre', () {
    final plan = const PremovePlan(
      base: 4,
    ).avec(v(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6', 'Do2-Do3']))!;

    test('deux réponses au même coup : refusé', () {
      expect(
        plan.refusDe(v(['Fa6-Sol5', 'Re2-Re3'])),
        PremoveRefus.contradiction,
        reason: 'il joue Fa6-Sol5 : on ne peut pas répondre deux choses',
      );
    });

    test('la contradiction se voit aussi au fond de la variante', () {
      expect(
        plan.refusDe(v(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6', 'Re2-Re3'])),
        PremoveRefus.contradiction,
        reason: 'même début, même troisième coup : une seule réponse possible',
      );
    });

    test('se séparer sur SON coup, c est une autre ligne : accepté', () {
      final deux = plan.avec(v(['Fa6-Sol5', 'Sol2-Fa3', 'Si7-Si6', 'Re2-Re3']));
      expect(
        deux,
        isNotNull,
        reason:
            'il a deux coups possibles au troisième demi-coup ; chacun '
            'mérite sa réponse',
      );
      expect(deux!.variantes.length, 2);
    });

    test('un autre premier coup : accepté', () {
      expect(plan.refusDe(v(['Si7-Si6', 'Re2-Re3'])), isNull);
    });

    test('la même variante deux fois : doublon', () {
      expect(
        plan.refusDe(v(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6', 'Do2-Do3'])),
        PremoveRefus.doublon,
      );
    });

    test('une variante qui commence une autre n ajoute rien : doublon', () {
      expect(
        plan.refusDe(v(['Fa6-Sol5', 'Sol2-Fa3'])),
        PremoveRefus.doublon,
        reason: 'ces deux coups-là sont déjà prévus, en plus long',
      );
    });

    test('et une plus longue qui prolonge : doublon aussi', () {
      expect(
        plan.refusDe(
          v([
            'Fa6-Sol5',
            'Sol2-Fa3',
            'Do7-Do6',
            'Do2-Do3',
            'Re7-Re6',
            'Re2-Re3',
          ]),
        ),
        PremoveRefus.doublon,
        reason: 'on prolonge la variante existante, on n en crée pas une autre',
      );
    });
  });

  group('Quelle réponse jouer', () {
    // Construit DANS chaque test : un refus au chargement du groupe ferait
    // tomber le fichier entier sans dire quelle règle a cédé.
    PremovePlan plan() {
      final un = const PremovePlan(
        base: 4,
      ).avec(v(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6', 'Do2-Do3']));
      expect(un, isNotNull, reason: 'la première variante est refusée');
      final deux = un!.avec(
        v(['Si7-Si6', 'Re2-Re3', 'La7-La6', 'La2-La3', 'Mi7-Mi6', 'Mi2-Mi3']),
      );
      expect(
        deux,
        isNotNull,
        reason:
            'deux lignes qui se séparent dès son PREMIER coup ne se '
            'contredisent pas',
      );
      return deux!;
    }

    test('il joue le coup prévu : on répond', () {
      expect(plan().reponsePour(['Fa6-Sol5'])?.coup, 'Sol2-Fa3');
      expect(plan().reponsePour(['Si7-Si6'])?.coup, 'Re2-Re3');
    });

    test('il suit la variante : on répond encore, plus loin', () {
      expect(
        plan().reponsePour(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6'])?.coup,
        'Do2-Do3',
      );
      expect(
        plan().reponsePour([
          'Si7-Si6',
          'Re2-Re3',
          'La7-La6',
          'La2-La3',
          'Mi7-Mi6',
        ])?.coup,
        'Mi2-Mi3',
      );
    });

    test('il joue autre chose : rien ne part', () {
      expect(plan().reponsePour(['Re7-Re6']), isNull);
      expect(plan().reponsePour(['Fa6-Sol5', 'Sol2-Fa3', 'Re7-Re6']), isNull);
    });

    test('la variante est épuisée : rien ne part', () {
      expect(
        plan().reponsePour(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6', 'Do2-Do3', 'X']),
        isNull,
      );
    });

    test('une ligne qui s arrête sur NOTRE coup n attend pas de réponse', () {
      expect(
        plan().reponsePour(['Fa6-Sol5', 'Sol2-Fa3']),
        isNull,
        reason: 'c est à l adversaire ; il n y a rien à jouer',
      );
    });
  });

  group('Un coup qui termine la partie', () {
    final plan = const PremovePlan(base: 4).avec(
      v(
        ['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6', 'Do2-Do3'],
        methode: 'mat',
        gagnant: 'Blanc',
      ),
    )!;

    test('la méthode accompagne le DERNIER coup', () {
      final fin = plan.reponsePour(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6']);
      expect(fin?.coup, 'Do2-Do3');
      expect(fin?.methode, 'mat');
      expect(fin?.gagnant, 'Blanc');
    });

    test('et pas les coups du milieu', () {
      final milieu = plan.reponsePour(['Fa6-Sol5']);
      expect(milieu?.coup, 'Sol2-Fa3');
      expect(
        milieu?.methode,
        isNull,
        reason: 'clore la partie au deuxième coup serait un faux mat',
      );
    });
  });

  group('Le plan meurt quand l adversaire en sort', () {
    final plan = const PremovePlan(
      base: 4,
    ).avec(v(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6', 'Do2-Do3']))!;

    test('tant qu il suit, le plan vit', () {
      expect(plan.suitEncore(['Fa6-Sol5']), isTrue);
      expect(plan.suitEncore(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6']), isTrue);
    });

    test('dès qu il dévie, le plan est mort', () {
      expect(plan.suitEncore(['Re7-Re6']), isFalse);
      expect(
        plan.suitEncore(['Fa6-Sol5', 'Sol2-Fa3', 'Do7-Do6', 'Do2-Do3']),
        isFalse,
        reason: 'la variante est allée jusqu au bout : plus rien à préparer',
      );
    });
  });

  group('Aller et revenir du serveur', () {
    test('le plan se recompose à l identique', () {
      final plan = const PremovePlan(base: 7)
          .avec(v(['a', 'b', 'c', 'd'], methode: 'fugue', gagnant: 'Noir'))!
          .avec(v(['e', 'f']))!;
      final relu = PremovePlan.fromJson(plan.toJson());

      expect(relu.base, 7);
      expect(relu.variantes.length, 2);
      expect(relu.variantes.first.coups, ['a', 'b', 'c', 'd']);
      expect(relu.variantes.first.methode, 'fugue');
      expect(relu.variantes.first.gagnant, 'Noir');
      expect(relu.variantes.last.methode, isNull);
      expect(
        relu.reponsePour(['a', 'b', 'c'])?.methode,
        'fugue',
        reason: 'ce qui clôt la partie doit survivre à l aller-retour',
      );
    });

    test('un plan vide ou abîmé ne fait pas tomber', () {
      expect(PremovePlan.fromJson(const {}).variantes, isEmpty);
      expect(PremovePlan.fromJson(const {'variantes': 3}).variantes, isEmpty);
      expect(PremovePlan.fromJson(const {'base': 'deux'}).base, 0);
      expect(
        PremovePlan.fromJson(const {
          'variantes': [
            {'coups': 'Fa3-Sol4'},
          ],
        }).variantes.single.estValide,
        isFalse,
      );
      expect(
        PremovePlan.fromJson(const {
          'base': 2,
          'variantes': [{}],
        }).variantes.single.estValide,
        isFalse,
      );
    });
  });
}
