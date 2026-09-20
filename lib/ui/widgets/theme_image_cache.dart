/// Chargement des images de thème.
///
/// Un `CustomPainter` dessine de façon synchrone : il lui faut des `ui.Image`
/// déjà décodées. On les charge donc une fois, à l'ouverture, puis on peint.
/// Tant qu'elles ne sont pas prêtes, le rendu géométrique sert de repli — le
/// plateau s'affiche tout de suite plutôt que de rester blanc.
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import '../../engine/piece.dart';
import '../../theme/theme_assets.dart';

/// Images décodées d'un thème.
final class LoadedThemeImages {
  const LoadedThemeImages({
    this.background,
    this.board,
    this.pieces = const {},
    this.cornerRadius = 0,
  });

  final ui.Image? background;
  final ui.Image? board;
  final Map<(PieceType, Camp), ui.Image> pieces;

  /// Arrondi des coins, en fraction du côté (masque un filigrane d'angle).
  final double cornerRadius;

  bool get hasPieceImages => pieces.isNotEmpty;

  ui.Image? pieceFor(Piece p) => pieces[(p.type, p.camp)];

  static const LoadedThemeImages none = LoadedThemeImages();
}

/// Charge et retient les images de thème.
///
/// Le cache est global et ne se vide pas : un joueur ne change pas de thème
/// assez souvent pour que la mémoire pose problème, et recharger à chaque
/// partie ferait clignoter le plateau.
abstract final class ThemeImageCache {
  static final Map<String, LoadedThemeImages> _loaded = {};
  static final Map<String, Future<LoadedThemeImages>> _loading = {};

  /// Images déjà chargées pour ce thème, ou `null` si elles ne le sont pas.
  ///
  /// Synchrone : c'est ce que le peintre appelle.
  static LoadedThemeImages? ready(String theme) => _loaded[theme];

  /// Charge les images d'un thème. Plusieurs appels simultanés partagent le
  /// même chargement.
  static Future<LoadedThemeImages> load(String theme) {
    final done = _loaded[theme];
    if (done != null) return Future.value(done);
    return _loading[theme] ??= _loadNow(theme);
  }

  static Future<LoadedThemeImages> _loadNow(String theme) async {
    final spec = imagesFor(theme);
    if (spec == null) {
      _loaded[theme] = LoadedThemeImages.none;
      _loading.remove(theme);
      return LoadedThemeImages.none;
    }

    // Tout est décodé de front : à la chaîne, ouvrir un thème complet
    // attendrait une quinzaine de décodages l'un après l'autre.
    final keys = spec.pieces.keys.toList(growable: false);
    final decoded = await Future.wait([
      _decode(spec.background),
      _decode(spec.board),
      for (final key in keys) _decode(spec.pieces[key]),
    ]);

    final background = decoded[0];
    final board = decoded[1];
    final pieces = <(PieceType, Camp), ui.Image>{};
    for (var i = 0; i < keys.length; i++) {
      final image = decoded[i + 2];
      if (image != null) pieces[keys[i]] = image;
    }

    final result = LoadedThemeImages(
      background: background,
      board: board,
      pieces: pieces,
      cornerRadius: spec.cornerRadius,
    );
    _loaded[theme] = result;
    _loading.remove(theme);
    return result;
  }

  /// Décode une image. Une image manquante ou illisible ne doit pas empêcher
  /// le thème de s'afficher : on retombe sur le rendu géométrique pour elle.
  static Future<ui.Image?> _decode(String? asset) async {
    if (asset == null) return null;
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// Vide le cache — pour les tests.
  static void clear() {
    _loaded.clear();
    _loading.clear();
  }
}
