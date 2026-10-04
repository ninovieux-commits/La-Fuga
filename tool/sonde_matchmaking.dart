// Deux VRAIS clients — la classe `FugaSocket` de l'application, pas une
// imitation — cherchent une partie aux mêmes critères. Se trouvent-ils ?
//
//     dart run tool/sonde_matchmaking.dart <url> [transports]
//
// C'est la plainte de Nino reproduite telle quelle : « On est deux à attendre
// en 15min mais ça ne trouve jamais l'autre. » Les tests Flutter ne pouvant
// pas ouvrir de connexion réseau, c'est le seul endroit où l'appariement est
// éprouvé de bout en bout, client compris.
//
// Chaque joueur tourne dans SON processus : `io()` partage sinon un même
// manager entre deux clients du même programme, ce qui ne ressemblerait plus
// à deux téléphones. Le processus père relance donc ce fichier deux fois.
//
// Deux scénarios, parce que l'application fait les deux :
//   « posé »   — on cherche une fois connecté ;
//   « hâtif »  — on cherche aussitôt, sans attendre connexion ni `auth`,
//                comme le fait l'écran du menu.
//
// Sortie 0 si les deux scénarios apparient. N'écrit rien sur le serveur hors
// les comptes de sonde.
import 'dart:convert';
import 'dart:io';

import 'package:lafuga/net/socket_client.dart';

Future<Map<String, dynamic>> post(
  String base,
  String path,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();
  final req = await client.postUrl(Uri.parse('$base$path'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  final texte = await res.transform(utf8.decoder).join();
  client.close();
  return jsonDecode(texte) as Map<String, dynamic>;
}

/// Un joueur : connexion et recherche par le client de l'application.
Future<int> joueur(
  String base,
  String pseudo,
  bool hatif,
  List<String>? transportsForces,
) async {
  var r = await post(base, '/register', {
    'pseudo': pseudo,
    'password': 'motdepasse',
  });
  if (r['ok'] != true) {
    r = await post(base, '/login', {
      'pseudo': pseudo,
      'password': 'motdepasse',
    });
  }
  final token = r['token'] as String?;
  if (token == null) {
    stdout.writeln('   $pseudo : pas de jeton — $r');
    return 1;
  }

  final client = FugaSocket(serverUrl: base, transports: transportsForces);
  var trouve = false;
  for (final ev in [
    'auth_ok',
    'auth_erreur',
    'recherche_en_cours',
    'partie_trouvee',
    'recherche_timeout',
  ]) {
    client.on(ev, (d) {
      stdout.writeln('   $pseudo ← $ev');
      if (ev == 'partie_trouvee') trouve = true;
    });
  }

  void chercher() =>
      client.chercherPartie(objectif: 'partie', cadence: '5', random: false);

  if (hatif) {
    // Sans `await` : on cherche pendant que la connexion se fait, comme
    // l'écran du menu, qui émet dès que la socket existe.
    unawaited(client.connect(token));
    chercher();
  } else {
    await client.connect(token);
    await Future<void>.delayed(const Duration(seconds: 3));
    chercher();
  }

  for (var i = 0; i < 100 && !trouve; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  client.disconnect();
  stdout.writeln(trouve ? '   $pseudo : TROUVÉ' : '   $pseudo : rien');
  return trouve ? 0 : 1;
}

void unawaited(Future<void> f) {
  f.catchError((Object e) => stdout.writeln('   (connexion : $e)'));
}

Future<bool> duel(
  String base,
  String mode,
  String etiquette,
  bool hatif,
  int n,
) async {
  stdout.writeln('\n→ $etiquette');
  final procs = await Future.wait([
    for (final r in ['A', 'B'])
      Process.start(Platform.executable, [
        Platform.script.toFilePath(),
        base,
        mode,
        '--joueur=Mm$etiquette$n$r',
        if (hatif) '--hatif',
      ]),
  ]);
  for (final p in procs) {
    p.stdout.transform(utf8.decoder).listen(stdout.write);
    p.stderr.drain<void>();
  }
  final codes = await Future.wait(procs.map((p) => p.exitCode));
  final ok = codes.every((c) => c == 0);
  stdout.writeln(ok ? '✓ appariés' : '✗ PAS appariés ($codes)');
  return ok;
}

void main(List<String> args) async {
  final base = args.isNotEmpty ? args[0] : 'http://127.0.0.1:5300';
  final mode = args.length > 1 ? args[1] : 'app';
  final forces = mode == 'app' ? null : mode.split(',');

  final role = args.firstWhere(
    (a) => a.startsWith('--joueur='),
    orElse: () => '',
  );
  if (role.isNotEmpty) {
    exit(
      await joueur(base, role.split('=')[1], args.contains('--hatif'), forces),
    );
  }

  stdout.writeln('→ serveur : $base   transports : $mode');
  final n = DateTime.now().millisecondsSinceEpoch % 100000;
  final pose = await duel(base, mode, 'Pose', false, n);
  final hatif = await duel(base, mode, 'Hatif', true, n);

  stdout.writeln(
    pose && hatif
        ? '\n✓ LE MATCHMAKING MARCHE (posé ET hâtif)'
        : '\n✗ posé=$pose hâtif=$hatif — c\'est « on attend sans fin »',
  );
  exit(pose && hatif ? 0 : 1);
}
