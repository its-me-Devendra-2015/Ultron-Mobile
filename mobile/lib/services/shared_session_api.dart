import 'dart:convert';

import 'package:http/http.dart' as http;

/// Supplies a fresh Firebase ID token for every API request.
typedef FirebaseIdTokenProvider = Future<String?> Function();

/// Authenticated client for ULTRON's owner-scoped shared-session API.
class SharedSessionApi {
  SharedSessionApi({
    required this.baseUri,
    required this.tokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client() {
    final host = baseUri.host.toLowerCase();
    final isLoopback = const {'localhost', '127.0.0.1', '::1'}.contains(host);
    if (baseUri.scheme != 'https' &&
        !(baseUri.scheme == 'http' && isLoopback)) {
      throw ArgumentError(
        'ULTRON_SESSION_ENDPOINT must use HTTPS (HTTP is allowed only for loopback development).',
      );
    }
  }

  final Uri baseUri;
  final FirebaseIdTokenProvider tokenProvider;
  final http.Client _http;

  Uri _uri(String path) => baseUri.resolve(path);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in before accessing ULTRON shared sessions.');
    }

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    late final http.Response response;
    if (method == 'GET') {
      response = await _http.get(_uri(path), headers: headers);
    } else if (method == 'DELETE') {
      response = await _http.delete(_uri(path), headers: headers);
    } else {
      response = await _http.post(
        _uri(path),
        headers: headers,
        body: jsonEncode(body ?? const <String, dynamic>{}),
      );
    }

    Map<String, dynamic> data = <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // The status code below remains the source of truth for non-JSON errors.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['detail']?.toString() ?? 'ULTRON session API HTTP ${response.statusCode}',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> createPairingCode() => _request(
        'POST',
        '/api/devices/pairing-code',
        body: const {'device_label': 'ULTRON Desktop'},
      );

  Future<List<Map<String, dynamic>>> listDevices() async {
    final data = await _request('GET', '/api/devices');
    final values = data['devices'];
    if (values is! List) return const [];
    return values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> revokeDevice(String deviceId) {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must not be empty');
    }
    return _request('DELETE', '/api/devices/${Uri.encodeComponent(deviceId)}');
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final data = await _request('GET', '/api/sessions');
    final values = data['sessions'];
    if (values is! List) return const [];
    return values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> readEvents(
    String sessionId, {
    int limit = 200,
  }) async {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 500');
    }
    final encodedId = Uri.encodeComponent(sessionId);
    final data = await _request(
      'GET',
      '/api/sessions/$encodedId/events?limit=$limit',
    );
    final values = data['events'];
    if (values is! List) return const [];
    return values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
  }

  void dispose() => _http.close();
}
