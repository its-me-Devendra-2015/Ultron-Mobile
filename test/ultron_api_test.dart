import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/ultron_api.dart';

void main() {
  test('API client can be constructed with a configured server', () {
    final api = UltronApi(
      baseUrl: 'http://localhost:20128/v1',
      apiKey: 'test-key',
      model: 'gemma3',
    );
    expect(api.baseUrl, contains('/v1'));
    expect(api.model, 'gemma3');
  });
}
