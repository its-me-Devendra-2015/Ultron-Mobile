import 'dart:convert';
import 'package:http/http.dart' as http;

class UltronApi {
  UltronApi({required this.baseUrl, required this.apiKey, required this.model});
  final String baseUrl;
  final String apiKey;
  final String model;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  Future<List<String>> listModels() async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/models');
    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server returned HTTP ${response.statusCode}: ${_error(response.body)}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'];
    if (data is! List) return [];
    return data.map((item) => (item as Map<String, dynamic>)['id'].toString()).toList();
  }

  Future<String> chat(List<Map<String, String>> messages) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final response = await http.post(uri, headers: _headers,
      body: jsonEncode({'model': model, 'messages': messages, 'stream': false}))
      .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server returned HTTP ${response.statusCode}: ${_error(response.body)}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = choices.first['message'];
      final content = message is Map ? message['content'] : null;
      if (content is String && content.trim().isNotEmpty) return content.trim();
    }
    throw Exception('The server response did not contain a chat reply.');
  }

  String _error(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        final error = decoded['error'];
        return error is Map ? (error['message']?.toString() ?? error.toString()) : error.toString();
      }
    } catch (_) {}
    return body.length > 240 ? '${body.substring(0, 240)}…' : body;
  }
}
