import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/services/xiaozhi_ota_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XiaozhiOtaAuthorization', () {
    test('parses websocket URL and token', () {
      final authorization = XiaozhiOtaAuthorization.fromJson({
        'websocket': {
          'url': 'ws://example.com/xiaozhi/v1/',
          'token': 'dynamic-token',
        },
      });

      expect(authorization.websocketUrl, 'ws://example.com/xiaozhi/v1/');
      expect(authorization.token, 'dynamic-token');
    });

    test('rejects a response without a token', () {
      expect(
        () => XiaozhiOtaAuthorization.fromJson({
          'websocket': {'url': 'ws://example.com/xiaozhi/v1/', 'token': ''},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('legacy Xiaozhi config keeps automatic authorization disabled', () {
    final config = XiaozhiConfig.fromJson({
      'id': '1',
      'name': 'legacy',
      'websocketUrl': 'ws://example.com',
      'macAddress': 'fc:0c:70:20:83:a6',
      'token': 'legacy-token',
    });

    expect(config.enableAutoAuth, isFalse);
  });
}
