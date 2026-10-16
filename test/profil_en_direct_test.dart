/// Un profil qui change se voit, et un profil qui ne change pas ne coûte rien.
///
/// Nino : « si un adversaire change sa devise, je dois relancer mon app pour
/// que ça m'affiche la nouvelle dans les parties. Tout doit être en direct
/// dans l'app. »
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/devises_connues.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/profile.dart';
import 'package:lafuga/net/profils_connus.dart';
import 'package:lafuga/net/resolution_profil.dart';
import 'package:lafuga/net/scores_directs.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Profile profil({String devise = 'A', String photo = 'nurse'}) =>
    Profile.fromJson({
      'description': devise,
      'photo': photo,
      'theme': 'original',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'lang_chosen': true});
    await Settings.load();
    AvatarPhotos.clear();
    DecorsConnus.clear();
    DevisesConnues.clear();
    ScoresDirects.clear();
    FavorisConnus.instance.oublie();
  });

  test('un profil qui change prévient les écrans', () {
    var sonneries = 0;
    void compte() => sonneries++;
    profilsConnus.addListener(compte);
    addTearDown(() => profilsConnus.removeListener(compte));

    retiensProfil('ana', profil());
    expect(
      sonneries,
      1,
      reason:
          'on ne savait rien, on sait : c est un chang'
          'ement',
    );

    retiensProfil('ana', profil(devise: 'B'));
    expect(sonneries, 2);
    expect(DevisesConnues.connue('ana'), 'B');
  });

  test('un profil relu à l identique ne redessine rien', () {
    retiensProfil('ana', profil());
    var sonneries = 0;
    void compte() => sonneries++;
    profilsConnus.addListener(compte);
    addTearDown(() => profilsConnus.removeListener(compte));

    retiensProfil('ana', profil());
    retiensProfil('ana', profil());
    expect(
      sonneries,
      0,
      reason: 'le cas courant est « rien n a bougé » : il doit être gratuit',
    );
  });

  test('la relecture forcée repose la question, cache ou pas', () async {
    var devise = 'A';
    var demandes = 0;
    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            if (req.url.path.endsWith('/get_profile')) demandes++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'token': 't',
                'pseudo': 'nino',
                'description': devise,
                'theme': 'original',
                'photo': 'nurse',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    );
    await online.client.login('nino', 'mdp');

    expect(await DevisesConnues.resolve('ana', online: online), 'A');
    expect(demandes, 1);

    // Le `resolve` ordinaire se tait : c est ce qui évite d interroger le
    // serveur à chaque image, et c est aussi ce qui figeait la devise.
    devise = 'B';
    expect(await DevisesConnues.resolve('ana', online: online), 'A');
    expect(demandes, 1, reason: 'le resolve ordinaire ne redemande pas');

    await rafraichisProfil('ana', online: online);
    expect(demandes, 2);
    expect(DevisesConnues.connue('ana'), 'B');
  });

  test('une réponse sans profil n efface rien', () async {
    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient(
            (req) async => http.Response(
              jsonEncode({'ok': true, 'token': 't', 'pseudo': 'nino'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      ),
    );
    await online.client.login('nino', 'mdp');
    DevisesConnues.retiens('ana', 'Je suis là.');

    // Le serveur répond sans aucun champ de profil. Celui d aujourd'hui ne
    // le fait pas — il répond « joueur introuvable » —, mais effacer une
    // devise sur une réponse muette serait un défaut silencieux.
    await rafraichisProfil('ana', online: online);
    expect(DevisesConnues.connue('ana'), 'Je suis là.');
  });

  test('une devise VIDÉE par son auteur s efface bien', () async {
    // L'inverse du test précédent, et il faut les deux : une garde trop
    // large garderait une devise que son auteur vient d'effacer.
    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient(
            (req) async => http.Response(
              jsonEncode({
                'ok': true,
                'token': 't',
                'pseudo': 'nino',
                'description': '',
                'theme': 'original',
                'photo': 'nurse',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      ),
    );
    await online.client.login('nino', 'mdp');
    DevisesConnues.retiens('ana', 'Je suis là.');

    await rafraichisProfil('ana', online: online);
    expect(DevisesConnues.connue('ana'), '');
  });
}
