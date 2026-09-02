import 'package:ai_assistant/services/xiaozhi_reconnect_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScheduledReconnect {
  _ScheduledReconnect(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) {
      callback();
    }
  }
}

class _ManualReconnectScheduler {
  final List<_ScheduledReconnect> scheduled = [];

  CancelReconnectTimer schedule(Duration delay, void Function() callback) {
    final item = _ScheduledReconnect(delay, callback);
    scheduled.add(item);
    return () => item.cancelled = true;
  }
}

void main() {
  group('XiaozhiReconnectController', () {
    test('uses capped exponential delays and ignores duplicate scheduling', () {
      final scheduler = _ManualReconnectScheduler();
      final controller = XiaozhiReconnectController(
        timerFactory: scheduler.schedule,
        randomUnit: () => 0.5,
        onReconnect: () {},
      )..start();

      const expectedSeconds = [1, 2, 4, 8, 16, 30, 30];
      for (final seconds in expectedSeconds) {
        controller.scheduleAfterFailure();
        controller.scheduleAfterFailure();
        expect(scheduler.scheduled.last.delay, Duration(seconds: seconds));
        scheduler.scheduled.last.fire();
      }

      expect(scheduler.scheduled, hasLength(expectedSeconds.length));
    });

    test('applies bounded twenty percent jitter', () {
      final lowScheduler = _ManualReconnectScheduler();
      final low = XiaozhiReconnectController(
        timerFactory: lowScheduler.schedule,
        randomUnit: () => 0,
        onReconnect: () {},
      )..start();
      low.scheduleAfterFailure();

      final highScheduler = _ManualReconnectScheduler();
      final high = XiaozhiReconnectController(
        timerFactory: highScheduler.schedule,
        randomUnit: () => 1,
        onReconnect: () {},
      )..start();
      high.scheduleAfterFailure();

      expect(
        lowScheduler.scheduled.single.delay,
        const Duration(milliseconds: 800),
      );
      expect(
        highScheduler.scheduled.single.delay,
        const Duration(milliseconds: 1200),
      );

      for (var attempt = 0; attempt < 6; attempt++) {
        highScheduler.scheduled.last.fire();
        high.scheduleAfterFailure();
      }
      expect(highScheduler.scheduled.last.delay, const Duration(seconds: 30));
    });

    test('a ready connection resets the next delay to the base', () {
      final scheduler = _ManualReconnectScheduler();
      final controller = XiaozhiReconnectController(
        timerFactory: scheduler.schedule,
        randomUnit: () => 0.5,
        onReconnect: () {},
      )..start();

      controller.scheduleAfterFailure();
      scheduler.scheduled.last.fire();
      controller.scheduleAfterFailure();
      expect(scheduler.scheduled.last.delay, const Duration(seconds: 2));

      controller.markReady();
      controller.scheduleAfterFailure();
      expect(scheduler.scheduled.last.delay, const Duration(seconds: 1));
    });

    test('offline cancels waiting and recovery reconnects immediately', () {
      final scheduler = _ManualReconnectScheduler();
      var reconnects = 0;
      final controller = XiaozhiReconnectController(
        timerFactory: scheduler.schedule,
        randomUnit: () => 0.5,
        onReconnect: () => reconnects++,
      )..start();

      controller.scheduleAfterFailure();
      final pending = scheduler.scheduled.single;
      controller.setNetworkAvailable(false);
      pending.fire();

      expect(pending.cancelled, isTrue);
      expect(reconnects, 0);
      expect(controller.hasScheduledReconnect, isFalse);

      controller.setNetworkAvailable(true);
      expect(reconnects, 1);
    });

    test(
      'explicit reconnect cancels waiting, reconnects now, and resets delay',
      () {
        final scheduler = _ManualReconnectScheduler();
        var reconnects = 0;
        final controller = XiaozhiReconnectController(
          timerFactory: scheduler.schedule,
          randomUnit: () => 0.5,
          onReconnect: () => reconnects++,
        )..start();

        controller.scheduleAfterFailure();
        final pending = scheduler.scheduled.single;
        controller.requestImmediateReconnect();

        expect(pending.cancelled, isTrue);
        expect(reconnects, 1);

        controller.scheduleAfterFailure();
        expect(scheduler.scheduled.last.delay, const Duration(seconds: 1));
      },
    );

    test('stop prevents automatic and network recovery reconnects', () {
      final scheduler = _ManualReconnectScheduler();
      var reconnects = 0;
      final controller = XiaozhiReconnectController(
        timerFactory: scheduler.schedule,
        onReconnect: () => reconnects++,
      )..start();

      controller.scheduleAfterFailure();
      final pending = scheduler.scheduled.single;
      controller.stop();
      controller.setNetworkAvailable(false);
      controller.setNetworkAvailable(true);
      pending.fire();

      expect(reconnects, 0);
      expect(controller.isActive, isFalse);
    });
  });
}
