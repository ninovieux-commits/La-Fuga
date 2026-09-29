/// La file d'attente du matchmaking, vue du client.
///
/// Nino : « Le match making ne marche pas. On est deux à attendre en 15min
/// mais ça ne trouve jamais l'autre. »
///
/// Le serveur apparie correctement — reproduit avec deux vrais clients
/// Socket.IO : critères identiques, appariés en moins d'une seconde. Mais il
/// RETIRE de sa file dès que la socket tombe, et le client ne s'y remettait
/// jamais. Une coupure d'une seconde — écran éteint, passage du Wi-Fi à la
/// 4G — sortait donc le joueur de la file sans rien lui dire : l'application
/// affichait encore « recherche en cours », et plus personne ne le trouvait.
///
/// Reproduit de bout en bout côté serveur (`tests/test_matchmaking.py`) :
/// une seule coupure suffit, et la remise en file répare, même après trois
/// coupures d'affilée.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/net/socket_client.dart';

void main() {
  group('Ce qu on se rappelle en cherchant une partie', () {
    test('rien tant qu on ne cherche pas', () {
      expect(FileAttente().enCours, isNull);
    });

    test('la recherche est retenue, telle qu elle est partie', () {
      final f = FileAttente()
        ..cherche(objectif: 'partie', cadence: '5', random: true);
      expect(f.enCours, {'objectif': 'partie', 'cadence': '5', 'random': true});
    });

    test('et c est une COPIE : la modifier ne change pas la mémoire', () {
      final f = FileAttente()..cherche(objectif: 'partie', cadence: '5');
      f.enCours!['cadence'] = '15';
      expect(
        f.enCours!['cadence'],
        '5',
        reason: 'on se remettrait dans la file avec la mauvaise cadence',
      );
    });
  });

  group('Quand la recherche est finie, on l oublie', () {
    test('partie trouvée', () {
      final f = FileAttente()..cherche(objectif: 'partie', cadence: '5');
      f.surEvenement(FugaEvents.partieTrouvee);
      expect(
        f.enCours,
        isNull,
        reason: 'une reconnexion plus tard le remettrait dans la file',
      );
    });

    test('délai dépassé', () {
      final f = FileAttente()..cherche(objectif: 'partie', cadence: '5');
      f.surEvenement(FugaEvents.rechercheTimeout);
      expect(f.enCours, isNull);
    });

    test('annulation', () {
      final f = FileAttente()..cherche(objectif: 'partie', cadence: '5');
      f.annule();
      expect(f.enCours, isNull);
    });
  });

  group('Mais elle survit à tout le reste', () {
    test('les autres événements ne l effacent pas', () {
      // C est le cœur du correctif : la recherche doit tenir à travers tout
      // ce qui arrive pendant qu on attend.
      for (final event in FugaEvents.all) {
        if (event == FugaEvents.partieTrouvee ||
            event == FugaEvents.rechercheTimeout) {
          continue;
        }
        final f = FileAttente()..cherche(objectif: 'partie', cadence: '5');
        f.surEvenement(event);
        expect(
          f.enCours,
          isNotNull,
          reason: '« $event » a fait oublier la recherche',
        );
      }
    });

    test('et notamment la ré-authentification de la reconnexion', () {
      final f = FileAttente()..cherche(objectif: 'partie', cadence: '5');
      f.surEvenement(FugaEvents.authOk);
      f.surEvenement(FugaEvents.rechercheEnCours);
      expect(
        f.enCours,
        isNotNull,
        reason: 'la reconnexion elle-même effacerait la recherche',
      );
    });
  });
}
