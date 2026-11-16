import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/ultron_protocol.dart';

void main() {
  test('creates and round-trips a shared protocol event', () {
    final event = UltronEventEnvelope.create(
      sessionId: 'session-123',
      eventType: 'assistant.state',
      source: 'mobile',
      payload: const {'state': 'listening'},
    );

    final decoded = UltronEventEnvelope.fromJson(event.toJson());
    expect(decoded.protocolVersion, '1.0');
    expect(decoded.sessionId, 'session-123');
    expect(decoded.payload['state'], 'listening');
    expect(decoded.eventId, isNotEmpty);
  });

  test('rejects unsupported event types', () {
    expect(
      () => UltronEventEnvelope.create(
        sessionId: 'session-123',
        eventType: 'unknown.event',
        source: 'mobile',
      ),
      throwsArgumentError,
    );
  });

  test('rejects malformed incoming events', () {
    expect(
      () => UltronEventEnvelope.fromJson(const {}),
      throwsFormatException,
    );
  });
}
