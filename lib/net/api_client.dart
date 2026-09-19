/// Client HTTP du serveur La Fuga.
///
/// Toutes les routes sont des POST JSON répondant `{"ok": bool, ...}` ou
/// `{"error": "..."}`. Le protocole est **celui du client Kivy** : ne rien
/// changer ici sans changer `server.py`, qui reste inchangé.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// URL par défaut du serveur (VPS OVH, HTTPS via le domaine).
/// Surchargeable par la clé `server_url` de la configuration.
const String kDefaultServerUrl = 'https://fuga-online.fr';

/// Résultat d'un appel : soit une réponse, soit une erreur lisible.
final class ApiResult {
  const ApiResult.ok(this.data) : error = null, isNetworkError = false;

  const ApiResult.failure(this.error, {this.isNetworkError = false})
    : data = null;

  final Map<String, dynamic>? data;
  final String? error;

  /// Vrai quand l'échec vient du réseau, pas d'un refus du serveur.
  ///
  /// La distinction compte pour la reconnexion automatique : un token reste
  /// valide si le serveur est seulement injoignable, il ne faut donc pas
  /// déconnecter le joueur sur une simple coupure.
  final bool isNetworkError;

  bool get isOk => data != null && data!['ok'] == true;

  /// Message d'erreur renvoyé par le serveur, le cas échéant.
  String? get serverError => data?['error'] as String?;

  T? get<T>(String key) => data?[key] as T?;
}

/// Client HTTP bas niveau.
class ApiClient {
  ApiClient({http.Client? client, String serverUrl = kDefaultServerUrl})
    : _client = client ?? http.Client(),
      _serverUrl = serverUrl;

  final http.Client _client;
  String _serverUrl;

  static const Duration _timeout = Duration(seconds: 15);

  String get serverUrl => _serverUrl;
  set serverUrl(String value) =>
      _serverUrl = value.replaceAll(RegExp(r'/+$'), '');

  /// POST JSON sur `path`.
  ///
  /// Un code HTTP d'erreur accompagné d'un corps JSON n'est **pas** traité
  /// comme une panne : le serveur répond `{"error": ...}` avec un statut non
  /// 200, et ce message doit remonter tel quel à l'utilisateur.
  Future<ApiResult> post(String path, Map<String, dynamic> payload) async {
    final uri = Uri.parse('$_serverUrl$path');
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.body.isEmpty) return const ApiResult.ok({});
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        return const ApiResult.failure('Réponse inattendue du serveur');
      }
      return ApiResult.ok(Map<String, dynamic>.from(decoded));
    } on TimeoutException {
      return const ApiResult.failure(
        'Le serveur ne répond pas',
        isNetworkError: true,
      );
    } on FormatException {
      return const ApiResult.failure('Réponse illisible du serveur');
    } catch (e) {
      return ApiResult.failure('Erreur réseau : $e', isNetworkError: true);
    }
  }

  void close() => _client.close();
}
