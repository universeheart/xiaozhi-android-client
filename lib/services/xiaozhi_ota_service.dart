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

    return XiaozhiOtaAuthorization(
      websocketUrl: websocketUrl,
      token: token,
    );
  }
}

class XiaozhiOtaService {
  static const String otaUrl = 'http://175.24.226.167:8002/xiaozhi/ota/';
  static const String clientId = '7b94d69a-9808-4c59-9c9b-704333b38aff';

  Future<XiaozhiOtaAuthorization> authorize({
    required String deviceId,
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
