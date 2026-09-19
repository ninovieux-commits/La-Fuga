/// Profil et préférences de notification : lecture de ce que renvoie le
/// serveur, et photos de profil.
library;

import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/net/profile.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
import 'package:test/test.dart';

void main() {
  group('Profil', () {
    test('tout ce que le serveur renvoie est lu', () {
      final p = Profile.fromJson({
        'ok': true,
        'pseudo': 'Nino',
        'is_self': true,
        'melo': 1620,
        'melo_random': 1480,
        'email': 'a@b.c',
        'photo': 'dragon|Héritier',
        'description': 'Joue vite.',
        'followers': [
          {'pseudo': 'Ana', 'melo': 1700, 'online': true},
        ],
        'following': [
          {'pseudo': 'Bob', 'melo': 1400},
        ],
        'blocked': [
          {'pseudo': 'Zed'},
        ],
        'h2h_direct_moi': 3,
        'h2h_direct_lui': 1,
        'h2h_corr_moi': 0,
        'h2h_corr_lui': 2,
      });

      expect(p.pseudo, 'Nino');
      expect(p.isSelf, isTrue);
      expect(p.melo, 1620);
      expect(p.meloRandom, 1480, reason: 'le mélo Random est séparé');
      expect(p.followers.single.online, isTrue);
      expect(p.following.single.melo, 1400);
      expect(p.blocked.single.melo, 1500, reason: 'mélo par défaut');
      expect(p.direct, (mine: 3, theirs: 1));
      expect(p.correspondence, (mine: 0, theirs: 2));
    });

    test('une réponse minimale ne casse rien', () {
      final p = Profile.fromJson({'pseudo': 'Ana'});

      expect(p.isSelf, isFalse);
      expect(p.melo, 1500);
      expect(p.email, '');
      expect(p.followers, isEmpty);
      expect(p.direct, (mine: 0, theirs: 0));
    });

    test('un mélo envoyé en texte est quand même lu', () {
      expect(Profile.fromJson({'melo': '1712'}).melo, 1712);
    });
  });

  group('Notifications', () {
    test('tout est allumé par défaut', () {
      const n = NotifPrefs();
      expect(n.mail, isTrue);
      expect(n['defi_corr'], isTrue);
    });

    test('le serveur ne coupe que ce qu il dit explicitement', () {
      final n = NotifPrefs.fromJson({'mail': false, 'msg': false});
      expect(n.mail, isFalse);
      expect(n.msg, isFalse);
      expect(n.turn, isTrue);
    });

    test('une bascule ne touche qu une clé', () {
      final n = const NotifPrefs().toggled('turn');
      expect(n.turn, isFalse);
      expect(n.msg, isTrue);
      expect(n.mail, isTrue);
    });

    test('les clés envoyées sont celles du serveur', () {
      expect(const NotifPrefs().toJson().keys, [
        'mail',
        'turn',
        'msg',
        'defi_corr',
        'defi_direct',
      ]);
    });
  });

  group('Photo de profil', () {
    test('une photo complète est lue', () {
      final p = parsePhoto('dragon|Garde|Noir');
      expect(p.theme, 'dragon');
      expect(p.piece, PieceType.garde);
      expect(p.camp, Camp.noir);
    });

    test('sans camp, la pièce est blanche', () {
      expect(parsePhoto('original|Nurse').camp, Camp.blanc);
    });

    test('n importe quoi retombe sur l Héritier blanc du thème original', () {
      for (final photo in ['', 'nawak', 'theme-inconnu|Roi']) {
        final p = parsePhoto(photo);
        expect(p.theme, 'original');
        expect(p.piece, PieceType.heritier);
        expect(p.camp, Camp.blanc);
      }
    });

    test('les logos de thème sont reconnus', () {
      expect(isLogoPhoto('logo|dragon'), isTrue);
      expect(logoThemeOf('logo|dragon'), 'dragon');
      expect(
        logoThemeOf('logo|inconnu'),
        'original',
        reason: 'un thème disparu ne doit pas faire de trou',
      );
      expect(isLogoPhoto('dragon|Nurse'), isFalse);
    });

    test('les logos au nom différent gardent leur fichier', () {
      // Kivy nomme ces trois-là autrement que leur thème.
      expect(logoAssetOf('medieval'), endsWith('logo_bataille.png'));
      expect(logoAssetOf('fleur'), endsWith('logo_fleurs.png'));
      expect(logoAssetOf('insectes'), endsWith('logo_foret.png'));
      expect(logoAssetOf('dragon'), endsWith('logo_dragon.png'));
    });
  });
}
