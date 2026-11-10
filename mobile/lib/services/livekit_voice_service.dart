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
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
  })  : _auth = firebaseAuth ?? FirebaseAuth.instance,
        _http = httpClient ?? http.Client();

  final Uri tokenEndpoint;
  final FirebaseAuth _auth;
  final http.Client _http;

  lk.Room? _room;
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

    final response = await _http.post(
      tokenEndpoint,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'session_id': sessionId ?? _newSessionId(),
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
    return room;
  }

  Future<void> disconnect() async {
    final activeRoom = _room;
    _room = null;
    if (activeRoom != null) {
      await activeRoom.disconnect();
      await activeRoom.dispose();
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
