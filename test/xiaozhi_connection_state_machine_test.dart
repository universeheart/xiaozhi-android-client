import 'package:ai_assistant/services/xiaozhi_connection_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

class _ManualHandshakeTimer {
  void Function()? _callback;
  bool _cancelled = false;

  CancelHandshakeTimer schedule(Duration duration, void Function() callback) {
    _callback = callback;
    return () => _cancelled = true;
  }

  void fire() {
    if (!_cancelled) {
      _callback?.call();
    }
  }
}

void main() {
  group('XiaozhiConnectionStateMachine', () {
    test('does not become ready before a server hello', () {
      final timer = _ManualHandshakeTimer();
      final states = <XiaozhiConnectionState>[];
      final machine = XiaozhiConnectionStateMachine(
        timerFactory: timer.schedule,
        onStateChanged: states.add,
      );

      machine.beginConnecting();
      machine.beginHandshake();

      expect(machine.state, XiaozhiConnectionState.handshaking);
      expect(states, [
        XiaozhiConnectionState.connecting,
        XiaozhiConnectionState.handshaking,
      ]);
    });

    test('a valid server hello completes the handshake', () {
      final timer = _ManualHandshakeTimer();
      final machine = XiaozhiConnectionStateMachine(
        timerFactory: timer.schedule,
      );

      machine.beginConnecting();
      machine.beginHandshake();

      expect(
        machine.acceptServerText(
          '{"type":"hello","transport":"websocket","session_id":"s1"}',
        ),
        isTrue,
      );
      expect(machine.state, XiaozhiConnectionState.ready);

      timer.fire();
      expect(machine.state, XiaozhiConnectionState.ready);
    });

    test('invalid and unrelated messages cannot complete the handshake', () {
      final timer = _ManualHandshakeTimer();
      final machine = XiaozhiConnectionStateMachine(
        timerFactory: timer.schedule,
      );

      machine.beginConnecting();
      machine.beginHandshake();

      expect(machine.acceptServerText('not-json'), isFalse);
      expect(machine.acceptServerText('{"type":"stt"}'), isFalse);
      expect(machine.state, XiaozhiConnectionState.handshaking);
    });

    test('handshake timeout deterministically moves offline', () {
      final timer = _ManualHandshakeTimer();
      var timeoutCount = 0;
      final machine = XiaozhiConnectionStateMachine(
        timerFactory: timer.schedule,
        onHandshakeTimeout: () => timeoutCount++,
      );

      machine.beginConnecting();
      machine.beginHandshake();
      timer.fire();

      expect(machine.state, XiaozhiConnectionState.offline);
      expect(timeoutCount, 1);
      expect(
        machine.acceptServerText('{"type":"hello","transport":"websocket"}'),
        isFalse,
      );
      expect(machine.state, XiaozhiConnectionState.offline);
    });

    test('explicit offline cancels the pending handshake timeout', () {
      final timer = _ManualHandshakeTimer();
      var timeoutCount = 0;
      final machine = XiaozhiConnectionStateMachine(
        timerFactory: timer.schedule,
        onHandshakeTimeout: () => timeoutCount++,
      );

      machine.beginConnecting();
      machine.beginHandshake();
      machine.goOffline();
      timer.fire();

      expect(machine.state, XiaozhiConnectionState.offline);
      expect(timeoutCount, 0);
    });
  });
}
