import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;

/// Requests short-lived credentials from the ULTRON backend and joins a
/// LiveKit room. The LiveKit API secret is never shipped in the app.
class UltronLiveKitVoiceService {
  UltronLiveKitVoiceService({
    required this.tokenEndpoint,
    this.sessionEndpoint,
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
  })  : _auth = firebaseAuth ?? FirebaseAuth.instance,
        _http = httpClient ?? http.Client();

  final Uri tokenEndpoint;
  final Uri? sessionEndpoint;
  final FirebaseAuth _auth;
  final http.Client _http;

  lk.Room? _room;
  String? _sessionId;
  lk.Room? get room => _room;

  Future<lk.Room> connect({String? sessionId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before starting an ULTRON voice session.');
    }

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Could not obtain a Firebase sign-in token.');
    }

    final activeSessionId = sessionId ?? _newSessionId();
    final response = await _http.post(
      tokenEndpoint,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'session_id': activeSessionId,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('ULTRON token service rejected the request '
          '(${response.statusCode}): ${response.body}');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final serverUrl = payload['server_url'] as String?;
    final participantToken = payload['participant_token'] as String?;
    if (serverUrl == null || participantToken == null) {
      throw const FormatException('Token service response is incomplete.');
    }

    final room = lk.Room();
    await room.connect(serverUrl, participantToken);
    await room.localParticipant?.setMicrophoneEnabled(true);
    _room = room;
    _sessionId = activeSessionId;
    await _recordSessionEvent('session.started', {'transport': 'livekit'});
    return room;
  }

  Future<void> disconnect() async {
    final activeRoom = _room;
    await _recordSessionEvent('session.ended', {'transport': 'livekit'});
    _sessionId = null;
    _room = null;
    if (activeRoom != null) {
      await activeRoom.disconnect();
      await activeRoom.dispose();
    }
  }

  Future<void> _recordSessionEvent(String eventType, Map<String, dynamic> payload) async {
    final endpoint = sessionEndpoint;
    final session = _sessionId;
    final user = _auth.currentUser;
    if (endpoint == null || session == null || user == null) return;
    try {
      final idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) return;
      final headers = {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'};
      if (eventType == 'session.started') {
        final created = await _http.post(
          endpoint.resolve('/api/sessions'),
          headers: headers,
          body: jsonEncode({'session_id': session, 'title': 'ULTRON Voice Session'}),
        );
        if (created.statusCode != 200) return;
      }
      await _http.post(
        endpoint.resolve('/api/sessions/$session/events'),
        headers: headers,
        body: jsonEncode({
          'protocol_version': '1.0',
          'event_id': _newSessionId(),
          'session_id': session,
          'event_type': eventType,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'source': 'mobile',
          'payload': payload,
        }),
      );
    } catch (_) {
      // Session sync is best-effort and must never break the existing LiveKit call.
    }
  }

  void dispose() {
    _http.close();
  }

  String _newSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // UUID version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
