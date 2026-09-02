import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/xiaozhi_websocket_manager.dart';

void main() {
  group('XiaozhiWebSocketManager authentication', () {
    test('does not add a default authorization credential', () {
      final headers = XiaozhiWebSocketManager.buildConnectionHeaders(
        deviceId: 'device-1',
        enableToken: false,
        token: '',
      );

      expect(headers, isNot(contains('Authorization')));
      expect(
        XiaozhiWebSocketManager.buildFallbackAuthMessage(
          enableToken: false,
          token: '',
        ),
        isNull,
      );
    });

    test('adds the configured token without changing it', () {
      const token = 'configured-token';
      final headers = XiaozhiWebSocketManager.buildConnectionHeaders(
        deviceId: 'device-1',
        enableToken: true,
        token: token,
      );

      expect(headers['Authorization'], 'Bearer $token');
      expect(
        XiaozhiWebSocketManager.buildFallbackAuthMessage(
          enableToken: true,
          token: token,
        ),
        'Authorization: Bearer $token',
      );
    });

    test('does not authenticate with an empty enabled token', () {
      final headers = XiaozhiWebSocketManager.buildConnectionHeaders(
        deviceId: 'device-1',
        enableToken: true,
        token: '',
      );

      expect(headers, isNot(contains('Authorization')));
      expect(
        XiaozhiWebSocketManager.buildFallbackAuthMessage(
          enableToken: true,
          token: '',
        ),
        isNull,
      );
    });
  });
}
