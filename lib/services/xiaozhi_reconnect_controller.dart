import 'dart:async';
import 'dart:math';

typedef CancelReconnectTimer = void Function();
typedef ReconnectTimerFactory =
    CancelReconnectTimer Function(Duration delay, void Function() callback);

CancelReconnectTimer _defaultTimerFactory(
  Duration delay,
  void Function() callback,
) {
  final timer = Timer(delay, callback);
  return timer.cancel;
}

class XiaozhiReconnectController {
  XiaozhiReconnectController({
    required this.onReconnect,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.jitterRatio = 0.2,
    ReconnectTimerFactory? timerFactory,
    double Function()? randomUnit,
  }) : _timerFactory = timerFactory ?? _defaultTimerFactory,
       _randomUnit = randomUnit ?? Random().nextDouble {
    if (baseDelay <= Duration.zero) {
      throw ArgumentError.value(baseDelay, 'baseDelay', 'must be positive');
    }
    if (maxDelay < baseDelay) {
      throw ArgumentError.value(
        maxDelay,
        'maxDelay',
        'must not be shorter than baseDelay',
      );
    }
    if (jitterRatio < 0 || jitterRatio > 1) {
      throw ArgumentError.value(jitterRatio, 'jitterRatio', 'must be 0..1');
    }
  }

  final void Function() onReconnect;
  final Duration baseDelay;
  final Duration maxDelay;
  final double jitterRatio;
  final ReconnectTimerFactory _timerFactory;
  final double Function() _randomUnit;

  bool _isActive = false;
  bool _networkAvailable = true;
  int _failureCount = 0;
  CancelReconnectTimer? _cancelReconnectTimer;

  bool get isActive => _isActive;
  bool get networkAvailable => _networkAvailable;
  bool get hasScheduledReconnect => _cancelReconnectTimer != null;
  int get failureCount => _failureCount;

  void start() {
    _isActive = true;
  }

  void stop() {
    _isActive = false;
    _failureCount = 0;
    _cancelPending();
  }

  Duration? scheduleAfterFailure() {
    if (!_isActive || !_networkAvailable || hasScheduledReconnect) {
      return null;
    }

    final cappedMilliseconds =
        min(
          baseDelay.inMilliseconds * pow(2, _failureCount),
          maxDelay.inMilliseconds,
        ).toDouble();
    final random = _randomUnit().clamp(0.0, 1.0);
    final jitterMultiplier = 1 - jitterRatio + (2 * jitterRatio * random);
    final delay = Duration(
      milliseconds: min(
        (cappedMilliseconds * jitterMultiplier).round(),
        maxDelay.inMilliseconds,
      ),
    );

    _failureCount++;
    _cancelReconnectTimer = _timerFactory(delay, () {
      _cancelReconnectTimer = null;
      if (_isActive && _networkAvailable) {
        onReconnect();
      }
    });
    return delay;
  }

  void markReady() {
    resetBackoff();
  }

  void resetBackoff() {
    _failureCount = 0;
    _cancelPending();
  }

  void setNetworkAvailable(bool available) {
    if (_networkAvailable == available) {
      return;
    }

    _networkAvailable = available;
    _cancelPending();
    if (!available) {
      return;
    }

    _failureCount = 0;
    if (_isActive) {
      onReconnect();
    }
  }

  void requestImmediateReconnect() {
    _cancelPending();
    _failureCount = 0;
    if (_isActive && _networkAvailable) {
      onReconnect();
    }
  }

  void _cancelPending() {
    _cancelReconnectTimer?.call();
    _cancelReconnectTimer = null;
  }
}
