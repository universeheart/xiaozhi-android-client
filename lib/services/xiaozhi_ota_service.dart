import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class XiaozhiOtaAuthorization {
  final String websocketUrl;
  final String token;

  const XiaozhiOtaAuthorization({
    required this.websocketUrl,
    required this.token,
  });

  factory XiaozhiOtaAuthorization.fromJson(Map<String, dynamic> json) {
    final websocket = json['websocket'];
    if (websocket is! Map<String, dynamic>) {
      throw const FormatException('OTA 响应缺少 websocket 配置');
    }

    final websocketUrl = websocket['url'];
    final token = websocket['token'];
    if (websocketUrl is! String || websocketUrl.isEmpty) {
      throw const FormatException('OTA 响应缺少 WebSocket 地址');
    }
    if (token is! String || token.isEmpty) {
      throw const FormatException('OTA 响应未下发有效 token');
    }

    return XiaozhiOtaAuthorization(websocketUrl: websocketUrl, token: token);
  }
}

class XiaozhiOtaService {
  static const String clientId = '7b94d69a-9808-4c59-9c9b-704333b38aff';

  static String resolveOtaUrl({
    required String configuredOtaUrl,
    required String websocketUrl,
  }) {
    final configured = configuredOtaUrl.trim();
    if (configured.isNotEmpty) {
      return configured;
    }

    final websocket = Uri.parse(websocketUrl);
    if (websocket.scheme != 'ws' && websocket.scheme != 'wss') {
      throw const FormatException('WebSocket 地址必须以 ws:// 或 wss:// 开头');
    }
    if (websocket.host.isEmpty) {
      throw const FormatException('WebSocket 地址缺少主机名或 IP');
    }

    final otaScheme = websocket.scheme == 'wss' ? 'https' : 'http';
    final otaPort =
        websocket.hasPort && websocket.port == 8000
            ? 8002
            : (websocket.hasPort ? websocket.port : null);
    return Uri(
      scheme: otaScheme,
      host: websocket.host,
      port: otaPort,
      path: '/xiaozhi/ota/',
    ).toString();
  }

  Future<XiaozhiOtaAuthorization> authorize({
    required String deviceId,
    required String otaUrl,
  }) async {
    final response = await http
        .post(
          Uri.parse(otaUrl),
          headers: {
            'Content-Type': 'application/json; charset=UTF-8',
            'Client-Id': clientId,
            'Device-Id': deviceId,
          },
          body: jsonEncode({
            'board': {'type': 'esp32', 'mac': deviceId},
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('OTA 自动授权失败：HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('OTA 响应格式无效');
    }
    return XiaozhiOtaAuthorization.fromJson(decoded);
  }
}
