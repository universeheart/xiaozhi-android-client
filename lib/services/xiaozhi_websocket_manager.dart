import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'xiaozhi_connection_state_machine.dart';
import 'xiaozhi_reconnect_controller.dart';
// 尝试导入io.dart，但在web平台会抛出异常
import 'package:web_socket_channel/io.dart'
    if (dart.library.html) 'package:web_socket_channel/html.dart';

/// 小智WebSocket事件类型
enum XiaozhiEventType {
  connected,
  disconnected,
  stateChanged,
  message,
  error,
  binaryMessage,
}

/// 小智WebSocket事件
class XiaozhiEvent {
  final XiaozhiEventType type;
  final dynamic data;

  XiaozhiEvent({required this.type, this.data});
}

/// 小智WebSocket监听器接口
typedef XiaozhiWebSocketListener = void Function(XiaozhiEvent event);

/// 小智WebSocket管理器
class XiaozhiWebSocketManager {
  static const String TAG = "XiaozhiWebSocket";

  WebSocketChannel? _channel;
  String? _serverUrl;
  String? _deviceId;
  String? _clientId;
  String? _token;
  bool _enableToken;
  final Connectivity _connectivity;

  final List<XiaozhiWebSocketListener> _listeners = [];
  StreamSubscription? _streamSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _connectInProgress = false;
  int _connectionGeneration = 0;
  late final XiaozhiConnectionStateMachine _connectionStateMachine;
  late final XiaozhiReconnectController _reconnectController;

  /// 构造函数
  XiaozhiWebSocketManager({
    required String deviceId,
    String? clientId,
    bool enableToken = false,
    Duration handshakeTimeout = const Duration(seconds: 10),
    HandshakeTimerFactory? handshakeTimerFactory,
    ReconnectTimerFactory? reconnectTimerFactory,
    double Function()? reconnectRandomUnit,
    Connectivity? connectivity,
  }) : _deviceId = deviceId,
       _clientId = clientId ?? deviceId,
       _enableToken = enableToken,
       _connectivity = connectivity ?? Connectivity() {
    _reconnectController = XiaozhiReconnectController(
      timerFactory: reconnectTimerFactory,
      randomUnit: reconnectRandomUnit,
      onReconnect: () => unawaited(_connectWithSavedParameters()),
    );
    _connectionStateMachine = XiaozhiConnectionStateMachine(
      handshakeTimeout: handshakeTimeout,
      timerFactory: handshakeTimerFactory,
      onStateChanged: (state) {
        _dispatchEvent(
          XiaozhiEvent(type: XiaozhiEventType.stateChanged, data: state),
        );
        if (state == XiaozhiConnectionState.ready) {
          _reconnectController.markReady();
          _dispatchEvent(
            XiaozhiEvent(type: XiaozhiEventType.connected, data: null),
          );
        }
      },
      onHandshakeTimeout: () => unawaited(_onHandshakeTimeout()),
    );
  }

  @visibleForTesting
  static Map<String, dynamic> buildConnectionHeaders({
    required String deviceId,
    String? clientId,
    required bool enableToken,
    required String token,
  }) {
    final headers = <String, dynamic>{
      'device-id': deviceId,
      'client-id': clientId ?? deviceId,
      'protocol-version': '1',
    };

    if (enableToken && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  @visibleForTesting
  static String? buildFallbackAuthMessage({
    required bool enableToken,
    required String token,
  }) {
    if (!enableToken || token.isEmpty) {
      return null;
    }
    return 'Authorization: Bearer $token';
  }

  /// 添加事件监听器
  void addListener(XiaozhiWebSocketListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除事件监听器
  void removeListener(XiaozhiWebSocketListener listener) {
    _listeners.remove(listener);
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(XiaozhiEvent event) {
    for (final listener in List<XiaozhiWebSocketListener>.of(_listeners)) {
      listener(event);
    }
  }

  /// 连接到WebSocket服务器
  Future<void> connect(String url, String token) async {
    if (url.isEmpty) {
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.error, data: "WebSocket地址不能为空"),
      );
      return;
    }

    // 保存连接参数
    _serverUrl = url;
    _token = token;
    _reconnectController.start();
    _reconnectController.resetBackoff();
    await _ensureConnectivityMonitoring();

    if (!_reconnectController.networkAvailable) {
      _connectionStateMachine.goOffline();
      return;
    }

    await _connectWithSavedParameters();
  }

  Future<void> reconnect() async {
    if (_serverUrl == null || _token == null) {
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.error, data: '没有可用的重连参数'),
      );
      return;
    }

    _reconnectController.start();
    await _ensureConnectivityMonitoring();
    _reconnectController.resetBackoff();
    await _connectWithSavedParameters();
  }

  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (isConnected) {
      return;
    }

    final completer = Completer<void>();
    late XiaozhiWebSocketListener listener;
    Timer? timeoutTimer;

    void cleanup() {
      timeoutTimer?.cancel();
      removeListener(listener);
    }

    listener = (event) {
      if (event.type == XiaozhiEventType.connected && !completer.isCompleted) {
        cleanup();
        completer.complete();
      }
    };
    addListener(listener);

    if (isConnected) {
      cleanup();
      return;
    }

    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        cleanup();
        completer.completeError(
          TimeoutException('等待 WebSocket 服务就绪超时', timeout),
        );
      }
    });

    await completer.future;
  }

  Future<void> _connectWithSavedParameters() async {
    if (_connectInProgress ||
        !_reconnectController.isActive ||
        !_reconnectController.networkAvailable ||
        _serverUrl == null ||
        _token == null) {
      return;
    }

    _connectInProgress = true;
    try {
      await _connectInternal(_serverUrl!, _token!);
    } finally {
      _connectInProgress = false;
    }
  }

  Future<void> _connectInternal(String url, String token) async {
    await _closeCurrentChannel(status.normalClosure);
    if (!_reconnectController.isActive ||
        !_reconnectController.networkAvailable) {
      return;
    }
    final generation = _connectionGeneration;

    _connectionStateMachine.beginConnecting();

    try {
      // 创建WebSocket连接
      Uri uri = Uri.parse(url);

      print('$TAG: 正在连接 $url');
      print('$TAG: Token启用: $_enableToken');

      // 尝试使用headers (这在非Web平台上有效)
      try {
        final headers = buildConnectionHeaders(
          deviceId: _deviceId ?? '',
          clientId: _clientId,
          enableToken: _enableToken,
          token: token,
        );

        // 使用IOWebSocketChannel并传递headers
        _channel = IOWebSocketChannel.connect(uri, headers: headers);

        print('$TAG: 使用headers方式连接WebSocket成功');
      } catch (e) {
        // 如果不支持IOWebSocketChannel（web平台），则回退到使用基本连接
        print('$TAG: 不支持使用headers方式，回退到基本连接: $e');

        // 创建基本连接
        _channel = WebSocketChannel.connect(uri);

        // 在连接成功后作为第一条消息发送认证信息
        Timer(Duration(milliseconds: 100), () {
          if (generation == _connectionGeneration &&
              _channel != null &&
              _connectionStateMachine.state ==
                  XiaozhiConnectionState.handshaking) {
            final authMessage = buildFallbackAuthMessage(
              enableToken: _enableToken,
              token: token,
            );
            if (authMessage != null) {
              _sendRawMessage(authMessage);
              print('$TAG: 已发送认证消息');
            }

            // 发送设备ID信息
            String deviceIdMessage = 'Device-ID: $_deviceId';
            _sendRawMessage(deviceIdMessage);
            print('$TAG: 已发送设备ID消息');
          }
        });
      }

      // 监听WebSocket事件
      _streamSubscription = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: _onError,
        cancelOnError: false,
      );

      // 通道创建只代表可以开始协议握手；收到服务端 hello 后才 READY。
      _connectionStateMachine.beginHandshake();

      // 在发送认证信息之后发送Hello消息
      Timer(Duration(milliseconds: 200), () {
        if (generation == _connectionGeneration) {
          _sendHelloMessage();
        }
      });

      print('$TAG: 已连接到 $uri');
    } catch (e) {
      print('$TAG: 连接失败: $e');
      _connectionStateMachine.goOffline();
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.error, data: "创建WebSocket失败: $e"),
      );
      _reconnectController.scheduleAfterFailure();
    }
  }

  /// 断开WebSocket连接
  Future<void> disconnect() async {
    _reconnectController.stop();
    _connectionStateMachine.goOffline();
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _closeCurrentChannel(status.normalClosure);
  }

  Future<void> _closeCurrentChannel(int closeCode) async {
    _connectionGeneration++;
    final subscription = _streamSubscription;
    _streamSubscription = null;
    final channel = _channel;
    _channel = null;

    try {
      await subscription?.cancel().timeout(const Duration(seconds: 2));
    } catch (error) {
      print('$TAG: 取消旧连接监听超时或失败: $error');
    }

    if (channel != null) {
      try {
        await channel.sink.close(closeCode).timeout(const Duration(seconds: 2));
      } catch (error) {
        print('$TAG: 关闭旧连接超时或失败: $error');
      }
      print('$TAG: 连接已断开');
    }
  }

  /// 发送Hello消息
  void _sendHelloMessage() {
    final hello = {
      "type": "hello",
      "version": 1,
      "transport": "websocket",
      "audio_params": {
        "format": "opus",
        "sample_rate": 16000,
        "channels": 1,
        "frame_duration": 60,
      },
    };

    _sendRawMessage(jsonEncode(hello));
  }

  void _sendRawMessage(dynamic message) {
    if (_channel != null &&
        _connectionStateMachine.state != XiaozhiConnectionState.offline) {
      _channel!.sink.add(message);
    }
  }

  /// 发送文本消息
  void sendMessage(String message) {
    if (_channel != null && isConnected) {
      _channel!.sink.add(message);
    } else {
      print('$TAG: 发送失败，连接未建立');
    }
  }

  /// 发送二进制数据
  void sendBinaryMessage(List<int> data) {
    if (_channel != null && isConnected) {
      try {
        _channel!.sink.add(data);
      } catch (e) {
        print('$TAG: 二进制数据发送失败: $e');
      }
    } else {
      print('$TAG: 发送失败，连接未建立');
    }
  }

  /// 发送文本请求
  void sendTextRequest(String text) {
    if (!isConnected) {
      print('$TAG: 发送失败，连接未建立');
      return;
    }

    try {
      // 构造消息格式，与Java实现保持一致
      final jsonMessage = {
        "type": "listen",
        "state": "detect",
        "text": text,
        "source": "text",
      };

      print('$TAG: 发送文本请求');
      sendMessage(jsonEncode(jsonMessage));
    } catch (e) {
      print('$TAG: 发送文本请求失败: $e');
    }
  }

  /// 处理收到的消息
  void _onMessage(dynamic message) {
    if (message is String) {
      _connectionStateMachine.acceptServerText(message);
      // 文本消息
      print('$TAG: 收到文本消息');
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.message, data: message),
      );
    } else if (message is List<int>) {
      // 二进制消息
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.binaryMessage, data: message),
      );
    }
  }

  Future<void> _ensureConnectivityMonitoring() async {
    if (_connectivitySubscription != null) {
      return;
    }

    try {
      final initial = await _connectivity.checkConnectivity();
      _reconnectController.setNetworkAvailable(_hasNetwork(initial));
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        (results) => unawaited(_handleNetworkChange(results)),
        onError: (Object error) {
          print('$TAG: 网络状态监听失败: $error');
        },
      );
    } catch (error) {
      // 桌面测试或未注册 connectivity_plus 插件的平台仍可直接连接；
      // 网络失败将由 WebSocket 自身的错误与退避重连处理。
      print('$TAG: 无法启用网络状态监听，继续直接连接: $error');
      _reconnectController.setNetworkAvailable(true);
    }
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> _handleNetworkChange(List<ConnectivityResult> results) async {
    final available = _hasNetwork(results);
    if (available == _reconnectController.networkAvailable) {
      return;
    }

    if (!available) {
      final wasOnline =
          _connectionStateMachine.state != XiaozhiConnectionState.offline;
      _reconnectController.setNetworkAvailable(false);
      _connectionStateMachine.goOffline();
      await _closeCurrentChannel(status.goingAway);
      if (wasOnline) {
        _dispatchEvent(
          XiaozhiEvent(type: XiaozhiEventType.disconnected, data: null),
        );
      }
      return;
    }

    // 网络恢复会取消旧退避、重置失败次数并立即尝试一次连接。
    _reconnectController.setNetworkAvailable(true);
  }

  /// 处理断开连接事件
  void _onDisconnected() {
    print('$TAG: 连接已断开');
    _streamSubscription = null;
    _channel = null;
    _connectionStateMachine.goOffline();
    _dispatchEvent(
      XiaozhiEvent(type: XiaozhiEventType.disconnected, data: null),
    );

    _reconnectController.scheduleAfterFailure();
  }

  /// 处理错误事件
  void _onError(error) {
    print('$TAG: 错误: $error');
    _connectionStateMachine.goOffline();
    _dispatchEvent(
      XiaozhiEvent(type: XiaozhiEventType.error, data: error.toString()),
    );
    _reconnectController.scheduleAfterFailure();
  }

  /// 判断是否已连接
  bool get isConnected {
    return _connectionStateMachine.state == XiaozhiConnectionState.ready;
  }

  XiaozhiConnectionState get connectionState => _connectionStateMachine.state;

  Future<void> _onHandshakeTimeout() async {
    print('$TAG: WebSocket握手超时');
    _dispatchEvent(
      XiaozhiEvent(type: XiaozhiEventType.error, data: 'WebSocket握手超时'),
    );
    await _closeCurrentChannel(status.goingAway);
    _reconnectController.scheduleAfterFailure();
  }
}
