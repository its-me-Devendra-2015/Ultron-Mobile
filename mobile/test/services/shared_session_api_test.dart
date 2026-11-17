import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ultron_mobile/services/shared_session_api.dart';

void main() {
  test('pairing code request uses Firebase auth and returns a shared session', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/devices/pairing-code');
      expect(request.headers['authorization'], 'Bearer firebase-test');
      expect(jsonDecode(request.body), {'device_label': 'ULTRON Desktop'});
      return http.Response(jsonEncode({
        'code': 'ABCD1234',
        'session_id': '11111111-1111-4111-8111-111111111111',
        'expires_in_seconds': 300,
      }), 200);
    });
    final api = SharedSessionApi(
      baseUri: Uri.parse('https://example.test'),
      tokenProvider: () async => 'firebase-test',
      httpClient: client,
    );

    final result = await api.createPairingCode();
    expect(result['code'], 'ABCD1234');
    expect(result['session_id'], '11111111-1111-4111-8111-111111111111');
    api.dispose();
  });

  test('shared session event reads are owner-authenticated and bounded', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/sessions/11111111-1111-4111-8111-111111111111/events');
      expect(request.url.queryParameters['limit'], '200');
      expect(request.headers['authorization'], 'Bearer firebase-test');
      return http.Response(jsonEncode({
        'events': [
          {'event_type': 'message.assistant', 'payload': {'text': 'Hello from desktop'}},
        ],
      }), 200);
    });
    final api = SharedSessionApi(
      baseUri: Uri.parse('https://example.test'),
      tokenProvider: () async => 'firebase-test',
      httpClient: client,
    );

    final events = await api.readEvents('11111111-1111-4111-8111-111111111111');
    expect(events.single['payload']['text'], 'Hello from desktop');
    await expectLater(api.readEvents('session', limit: 501), throwsArgumentError);
    api.dispose();
  });

  test('session API refuses requests without a Firebase token', () async {
    final api = SharedSessionApi(
      baseUri: Uri.parse('https://example.test'),
      tokenProvider: () async => null,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(api.listSessions(), throwsA(isA<StateError>()));
    api.dispose();
  });
}
