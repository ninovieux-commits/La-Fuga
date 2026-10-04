// Branche un VRAI client Socket.IO — celui de l'application — sur un serveur
// La Fuga, et raconte ce qui se passe.
//
//     dart run tool/sonde_socket.dart <url> <pseudo>
//
// Les tests Flutter ne peuvent pas ouvrir de connexion réseau : le temps réel
// de l'application n'a donc jamais été éprouvé autrement qu'à la main. Cette
// sonde comble le trou — même paquet, mêmes options, même suite d'événements
// que `SocketClient.connect`.
//
// N'écrit rien, ne touche à rien : elle se connecte, s'authentifie, cherche
// une partie, et imprime tout ce qu'elle reçoit.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lafuga/net/socket_client.dart' show optionsSocket;
import 'package:socket_io_client/socket_io_client.dart' as io;

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

void main(List<String> args) async {
  final base = args.isNotEmpty ? args[0] : 'http://127.0.0.1:5300';
  final pseudo = args.length > 1 ? args[1] : 'SondeA';
  // Troisieme argument : les transports a essayer, separes par une virgule.
  // Par defaut « app » : ceux de l'application.
  final mode = args.length > 2 ? args[2] : 'app';

  stdout.writeln('→ serveur : $base');
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
    stdout.writeln('✗ pas de jeton : $r');
    exit(1);
  }
  stdout.writeln('→ jeton obtenu');

  // Les options de l'application elles-mêmes — pas une copie, qui dériverait.
  final options = optionsSocket();
  if (mode != 'app') options['transports'] = mode.split(',');
  stdout.writeln('→ transports : ${options['transports']}');
  final socket = io.io(base, options);

  final recus = <String>[];
  for (final ev in [
    'auth_ok',
    'auth_erreur',
    'recherche_en_cours',
    'partie_trouvee',
    'recherche_timeout',
  ]) {
    socket.on(ev, (data) {
      recus.add(ev);
      stdout.writeln('   ← $ev  $data');
    });
  }

  socket.onConnect((_) {
    stdout.writeln(
      '→ CONNECTÉ (transport : ${socket.io.engine?.transport?.name})',
    );
    socket.emit('auth', {'token': token});
    socket.emit('chercher_partie', {
      'objectif': 'partie',
      'cadence': '5',
      'random': false,
    });
  });
  socket.onConnectError((e) => stdout.writeln('✗ erreur de connexion : $e'));
  socket.onError((e) => stdout.writeln('✗ erreur : $e'));
  socket.onDisconnect((_) => stdout.writeln('→ déconnecté'));
  // Les événements bruts du moteur : c'est là que se voient les refus de
  // poignée de main, invisibles au niveau Socket.IO.
  for (final ev in [
    'connect_error',
    'connect_timeout',
    'reconnect_error',
    'reconnect_failed',
    'error',
  ]) {
    socket.on(ev, (d) => stdout.writeln('   ⚠ $ev : $d'));
    socket.io.on(ev, (d) => stdout.writeln('   ⚠ manager.$ev : $d'));
  }
  socket.io.on('open', (_) => stdout.writeln('   · manager ouvert'));
  socket.io.on('close', (d) => stdout.writeln('   · manager fermé : $d'));

  socket.connect();

  await Future<void>.delayed(const Duration(seconds: 12));
  stdout.writeln('\nconnecté : ${socket.connected}');
  stdout.writeln('reçus    : $recus');
  final ok = recus.contains('auth_ok') && recus.contains('recherche_en_cours');
  stdout.writeln(
    ok
        ? '✓ la socket marche : authentifié ET dans la file'
        : '✗ LA SOCKET NE MARCHE PAS',
  );
  socket.dispose();
  exit(ok ? 0 : 1);
}
