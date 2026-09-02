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

  group('OTA URL resolution', () {
    test('uses an explicitly configured OTA URL', () {
      expect(
        XiaozhiOtaService.resolveOtaUrl(
          configuredOtaUrl: 'http://10.0.2.2:9000/custom/ota/',
          websocketUrl: 'ws://10.0.2.2:8000/xiaozhi/v1/',
        ),
        'http://10.0.2.2:9000/custom/ota/',
      );
    });

    test('derives local OTA port from a plain WebSocket URL', () {
      expect(
        XiaozhiOtaService.resolveOtaUrl(
          configuredOtaUrl: '',
          websocketUrl: 'ws://172.21.128.50:8000/xiaozhi/v1/',
        ),
        'http://172.21.128.50:8002/xiaozhi/ota/',
      );
    });

    test('derives HTTPS OTA URL from a secure WebSocket URL', () {
      expect(
        XiaozhiOtaService.resolveOtaUrl(
          configuredOtaUrl: '',
          websocketUrl: 'wss://xiaozhi.example.com/xiaozhi/v1/',
        ),
        'https://xiaozhi.example.com/xiaozhi/ota/',
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
    expect(config.otaUrl, isEmpty);
  });

  test('Xiaozhi config persists the configurable OTA URL', () {
    final config = XiaozhiConfig(
      id: '1',
      name: 'local',
      websocketUrl: 'ws://172.21.128.50:8000/xiaozhi/v1/',
      otaUrl: 'http://172.21.128.50:8002/xiaozhi/ota/',
      macAddress: 'fc:0c:70:20:83:a6',
      token: '',
      enableAutoAuth: true,
    );

    final restored = XiaozhiConfig.fromJson(config.toJson());
    expect(restored.otaUrl, config.otaUrl);
    expect(restored.enableAutoAuth, isTrue);
  });
}
