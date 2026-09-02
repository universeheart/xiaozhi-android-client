import 'dart:async';
import 'dart:convert';

enum XiaozhiConnectionState { connecting, handshaking, ready, offline }

typedef CancelHandshakeTimer = void Function();
typedef HandshakeTimerFactory =
    CancelHandshakeTimer Function(Duration duration, void Function() callback);

CancelHandshakeTimer _defaultTimerFactory(
  Duration duration,
  void Function() callback,
) {
  final timer = Timer(duration, callback);
  return timer.cancel;
}

class XiaozhiConnectionStateMachine {
  XiaozhiConnectionStateMachine({
    this.handshakeTimeout = const Duration(seconds: 10),
    HandshakeTimerFactory? timerFactory,
    this.onStateChanged,
    this.onHandshakeTimeout,
  }) : _timerFactory = timerFactory ?? _defaultTimerFactory;

  final Duration handshakeTimeout;
  final HandshakeTimerFactory _timerFactory;
  final void Function(XiaozhiConnectionState state)? onStateChanged;
  final void Function()? onHandshakeTimeout;

  XiaozhiConnectionState _state = XiaozhiConnectionState.offline;
  CancelHandshakeTimer? _cancelHandshakeTimer;

  XiaozhiConnectionState get state => _state;

  void beginConnecting() {
    _cancelTimeout();
    _transitionTo(XiaozhiConnectionState.connecting);
  }

  void beginHandshake() {
    if (_state != XiaozhiConnectionState.connecting) {
      throw StateError('Handshake can only start while connecting');
    }

    _transitionTo(XiaozhiConnectionState.handshaking);
    _cancelHandshakeTimer = _timerFactory(handshakeTimeout, () {
      if (_state != XiaozhiConnectionState.handshaking) {
        return;
      }
      _cancelHandshakeTimer = null;
      _transitionTo(XiaozhiConnectionState.offline);
      onHandshakeTimeout?.call();
    });
  }

  bool acceptServerText(String message) {
    if (_state != XiaozhiConnectionState.handshaking) {
      return false;
    }

    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic> || decoded['type'] != 'hello') {
        return false;
      }
    } on FormatException {
      return false;
    }

    _cancelTimeout();
    _transitionTo(XiaozhiConnectionState.ready);
    return true;
  }

  void goOffline() {
    _cancelTimeout();
    _transitionTo(XiaozhiConnectionState.offline);
  }

  void _cancelTimeout() {
    _cancelHandshakeTimer?.call();
    _cancelHandshakeTimer = null;
  }

  void _transitionTo(XiaozhiConnectionState nextState) {
    if (_state == nextState) {
      return;
    }
    _state = nextState;
    onStateChanged?.call(nextState);
  }
}
