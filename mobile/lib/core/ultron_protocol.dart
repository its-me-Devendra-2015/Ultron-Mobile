import 'dart:math';

/// Transport-neutral event contract shared with ULTRON Desktop.
class UltronEventEnvelope {
  UltronEventEnvelope({
    required this.eventId,
    required this.sessionId,
    required this.eventType,
    required this.occurredAt,
    required this.source,
    required this.payload,
    this.requestId,
    this.protocolVersion = protocolVersionCurrent,
  });

  static const protocolVersionCurrent = '1.0';

  static const supportedSources = <String>{
    'desktop', 'mobile', 'backend', 'agent',
  };

  static const supportedEventTypes = <String>{
    'session.started', 'session.ended',
    'message.user', 'message.assistant',
    'assistant.state',
    'tool.started', 'tool.completed', 'tool.failed',
    'audio.state', 'system.status', 'error',
  };

  static const assistantStates = <String>{
    'idle', 'listening', 'thinking', 'speaking', 'acting', 'offline', 'error',
  };

  final String protocolVersion;
  final String eventId;
  final String sessionId;
  final String? requestId;
  final String eventType;
  final DateTime occurredAt;
  final String source;
  final Map<String, dynamic> payload;

  factory UltronEventEnvelope.create({
    required String sessionId,
    required String eventType,
    required String source,
    Map<String, dynamic> payload = const {},
    String? requestId,
    DateTime? occurredAt,
  }) {
    if (sessionId.trim().isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'Must not be empty');
    }
    if (!supportedEventTypes.contains(eventType)) {
      throw ArgumentError.value(eventType, 'eventType', 'Unsupported event type');
    }
    if (!supportedSources.contains(source)) {
      throw ArgumentError.value(source, 'source', 'Unsupported source');
    }
    if (requestId != null && requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Must not be empty');
    }
    return UltronEventEnvelope(
      eventId: _uuidV4(),
      sessionId: sessionId,
      eventType: eventType,
      occurredAt: occurredAt ?? DateTime.now().toUtc(),
      source: source,
      payload: Map<String, dynamic>.unmodifiable(payload),
      requestId: requestId,
    );
  }

  factory UltronEventEnvelope.fromJson(Map<String, dynamic> json) {
    final version = json['protocol_version'];
    final eventId = json['event_id'];
    final sessionId = json['session_id'];
    final eventType = json['event_type'];
    final source = json['source'];
    final timestamp = json['occurred_at'];
    final payload = json['payload'];
    final requestId = json['request_id'];

    if (version != protocolVersionCurrent) {
      throw const FormatException('Unsupported ULTRON protocol version');
    }
    if (eventId is! String || eventId.trim().isEmpty ||
        sessionId is! String || sessionId.trim().isEmpty) {
      throw const FormatException('Invalid ULTRON event or session ID');
    }
    if (eventType is! String || !supportedEventTypes.contains(eventType)) {
      throw const FormatException('Unsupported ULTRON event type');
    }
    if (source is! String || !supportedSources.contains(source)) {
      throw const FormatException('Unsupported ULTRON event source');
    }
    if (timestamp is! String) {
      throw const FormatException('Missing ULTRON event timestamp');
    }
    final date = DateTime.tryParse(timestamp);
    if (date == null) {
      throw const FormatException('Invalid ULTRON event timestamp');
    }
    if (payload is! Map) {
      throw const FormatException('ULTRON event payload must be an object');
    }
    if (requestId != null && (requestId is! String || requestId.trim().isEmpty)) {
      throw const FormatException('Invalid ULTRON request ID');
    }

    return UltronEventEnvelope(
      protocolVersion: version as String,
      eventId: eventId,
      sessionId: sessionId,
      requestId: requestId as String?,
      eventType: eventType,
      occurredAt: date.toUtc(),
      source: source,
      payload: Map<String, dynamic>.from(payload),
    );
  }

  Map<String, dynamic> toJson() => {
        'protocol_version': protocolVersion,
        'event_id': eventId,
        'session_id': sessionId,
        if (requestId != null) 'request_id': requestId,
        'event_type': eventType,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'source': source,
        'payload': payload,
      };

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
