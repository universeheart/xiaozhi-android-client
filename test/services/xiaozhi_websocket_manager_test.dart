import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_assistant/services/xiaozhi_websocket_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports connected only after authenticated server hello', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestCompleter = Completer<HttpRequest>();
    final serverSubscription = server.listen((request) async {
      requestCompleter.complete(request);
      final socket = await WebSocketTransformer.upgrade(request);
      final hello = jsonDecode(await socket.first as String);
      expect(hello['type'], 'hello');
      socket.add(jsonEncode({'type': 'hello', 'session_id': 'session-1'}));
    });

    final connected = Completer<void>();
    final manager = XiaozhiWebSocketManager(
      deviceId: 'fc:0c:70:20:83:a6',
      clientId: 'client-id',
      enableToken: true,
    );
    manager.addListener((event) {
      if (event.type == XiaozhiEventType.connected && !connected.isCompleted) {
        connected.complete();
      }
    });

    await manager.connect(
      'ws://${server.address.address}:${server.port}/xiaozhi/v1/',
      'dynamic-token',
    );
    await manager.waitUntilReady();
    await connected.future;

    final request = await requestCompleter.future;
    expect(request.headers.value('Device-Id'), 'fc:0c:70:20:83:a6');
    expect(request.headers.value('Client-Id'), 'client-id');
    expect(request.headers.value('Protocol-Version'), '1');
    expect(request.headers.value('Authorization'), 'Bearer dynamic-token');
    expect(manager.isConnected, isTrue);

    await manager.disconnect();
    await serverSubscription.cancel();
    await server.close(force: true);
  });

  test(
    'handshake timeout closes the stale channel and schedules retry',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final firstConnection = Completer<void>();
      final secondConnection = Completer<void>();
      var connectionCount = 0;
      final serverSubscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        connectionCount++;
        if (connectionCount == 1) {
          firstConnection.complete();
        } else if (!secondConnection.isCompleted) {
          secondConnection.complete();
        }
        socket.listen((_) {}, onError: (_) {});
      });

      late void Function() fireHandshakeTimeout;
      late void Function() fireReconnect;
      final manager = XiaozhiWebSocketManager(
        deviceId: 'fc:0c:70:20:83:a6',
        handshakeTimerFactory: (_, callback) {
          fireHandshakeTimeout = callback;
          return () {};
        },
        reconnectTimerFactory: (_, callback) {
          fireReconnect = callback;
          return () {};
        },
      );

      await manager.connect(
        'ws://${server.address.address}:${server.port}/xiaozhi/v1/',
        '',
      );
      await firstConnection.future;

      fireHandshakeTimeout();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      fireReconnect();
      await secondConnection.future.timeout(const Duration(seconds: 2));

      expect(connectionCount, 2);

      await manager.disconnect();
      for (final socket in sockets) {
        await socket.close();
      }
      await serverSubscription.cancel();
      await server.close(force: true);
    },
  );
}
