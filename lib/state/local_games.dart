/// Parties enregistrées sur l'appareil — portage de `get_parties_dir`,
/// `list_local_parties` et `erase_local_parties` (main.py).
///
/// Kivy range les `.nmc` dans un dossier `parties/` à côté du script. Ici,
/// c'est le dossier de documents de l'application.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../game/nmc.dart';

/// Une partie trouvée sur l'appareil.
final class LocalGame {
  const LocalGame(this.file, this.meta);

  final File file;
  final NmcMeta meta;

  String get name => file.uri.pathSegments.last;
}

/// Accès aux parties locales.
class LocalGamesStore {
  LocalGamesStore({Directory? directory}) : _override = directory;

  final Directory? _override;
  Directory? _dir;

  /// Dossier des parties, créé au besoin.
  Future<Directory> directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = _override ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/parties');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  /// Parties enregistrées, de la plus récente à la plus ancienne.
  ///
  /// Un fichier illisible est ignoré plutôt que de faire échouer la liste :
  /// une partie corrompue ne doit pas cacher toutes les autres.
  Future<List<LocalGame>> list() async {
    final dir = await directory();
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.nmc'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));

    final out = <LocalGame>[];
    for (final f in files) {
      try {
        out.add(LocalGame(f, parseNmc(f.readAsStringSync()).meta));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  /// Enregistre une partie. Le nom porte la date, pour que le tri par nom
  /// range naturellement de la plus récente à la plus ancienne.
  Future<File> save(NmcMeta meta, List<String> moves, {String? name}) async {
    final dir = await directory();
    // Même nom qu'en Kivy : `2026-09-19_14-03-22.nmc`.
    final t = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${t.year}-${p(t.month)}-${p(t.day)}_'
        '${p(t.hour)}-${p(t.minute)}-${p(t.second)}';
    final file = File('${dir.path}/${name ?? stamp}.nmc');
    file.writeAsStringSync(buildNmc(meta, moves));
    return file;
  }

  Future<String?> read(File file) async {
    try {
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(File file) async {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Un fichier qu'on n'arrive pas à supprimer ne doit pas planter l'écran.
    }
  }

  /// Efface toutes les parties locales.
  ///
  /// Kivy fait cela à la connexion : le jeu est pensé pour être connecté, et
  /// l'historique vient alors du compte.
  Future<void> clear() async {
    final dir = await directory();
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.nmc')) continue;
      try {
        f.deleteSync();
      } catch (_) {
        continue;
      }
    }
  }
}
