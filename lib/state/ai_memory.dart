/// Ce que Deep Grey garde d'une partie à l'autre : ses poids appris et son
/// livre d'ouvertures — portage de `dg_weights.json` et `dg_openings.json`.
///
/// Kivy range ces deux fichiers à côté du script ; ici, dans le dossier de
/// documents de l'application. Le format JSON est le même, à l'identique.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../engine/ai/opening_book.dart';
import '../engine/ai/weights.dart';

/// Mémoire persistante de l'IA.
///
/// Les lectures sont mises en cache : une partie ne relit pas le livre à
/// chaque coup. Une écriture qui échoue est ignorée — perdre un apprentissage
/// est un moindre mal comparé à interrompre une partie.
class AiMemory {
  AiMemory({Directory? directory}) : _override = directory;

  static const String weightsFile = 'dg_weights.json';
  static const String openingsFile = 'dg_openings.json';

  final Directory? _override;
  Directory? _dir;

  DeepGreyWeights? _weights;
  OpeningBook? _book;

  Future<Directory> _directory() async =>
      _dir ??= _override ?? await getApplicationDocumentsDirectory();

  Future<String?> _read(String name) async {
    try {
      final f = File('${(await _directory()).path}/$name');
      return f.existsSync() ? f.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String name, String content) async {
    try {
      File('${(await _directory()).path}/$name').writeAsStringSync(content);
    } catch (_) {
      // Rien à faire : l'IA jouera sans cet apprentissage.
    }
  }

  /// Poids appris, ou les poids par défaut si rien n'a encore été enregistré.
  Future<DeepGreyWeights> weights() async => _weights ??=
      DeepGreyWeights.fromJsonString(await _read(weightsFile) ?? '');

  /// Livre d'ouvertures, vide au premier lancement.
  Future<OpeningBook> book() async =>
      _book ??= OpeningBook.fromJsonString(await _read(openingsFile) ?? '');

  Future<void> saveWeights(DeepGreyWeights w) async {
    _weights = w;
    await _write(weightsFile, w.toJsonString());
  }

  Future<void> saveBook(OpeningBook b) async {
    _book = b;
    await _write(openingsFile, b.toJsonString());
  }
}
