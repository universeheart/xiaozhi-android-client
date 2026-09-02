import 'dart:typed_data';

import 'package:ai_assistant/audio/turn_audio_queue.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _frame(int value) => Uint8List.fromList([value]);

void main() {
  group('TurnAudioQueue', () {
    test('rejects audio until a session and turn are active', () {
      final queue = TurnAudioQueue(maxFrames: 3);

      expect(
        queue.enqueue(
          sessionId: 'session-1',
          turnId: 'turn-1',
          data: _frame(1),
        ),
        TurnAudioEnqueueResult.noActiveTurn,
      );
      expect(queue.length, 0);
    });

    test('preserves FIFO order inside the current turn', () {
      final queue = TurnAudioQueue(maxFrames: 3)..startSession('session-1');
      final turn = queue.beginTurn();

      queue.enqueue(
        sessionId: turn.sessionId,
        turnId: turn.turnId,
        data: _frame(1),
      );
      queue.enqueue(
        sessionId: turn.sessionId,
        turnId: turn.turnId,
        data: _frame(2),
      );

      expect(queue.takeNext()!.data, _frame(1));
      expect(queue.takeNext()!.data, _frame(2));
      expect(queue.takeNext(), isNull);
    });

    test('a new session clears queued audio from the old session', () {
      final queue = TurnAudioQueue(maxFrames: 3)..startSession('session-1');
      final oldTurn = queue.beginTurn();
      queue.enqueue(
        sessionId: oldTurn.sessionId,
        turnId: oldTurn.turnId,
        data: _frame(1),
      );

      queue.startSession('session-2');

      expect(queue.length, 0);
      expect(queue.hasActiveTurn, isFalse);
      expect(
        queue.enqueue(
          sessionId: oldTurn.sessionId,
          turnId: oldTurn.turnId,
          data: _frame(2),
        ),
        TurnAudioEnqueueResult.noActiveTurn,
      );
    });

    test('rejects stale explicit turn identifiers', () {
      final queue = TurnAudioQueue(maxFrames: 3)..startSession('session-1');
      final turn = queue.beginTurn(turnId: 'turn-current');

      expect(
        queue.enqueue(
          sessionId: turn.sessionId,
          turnId: 'turn-old',
          data: _frame(1),
        ),
        TurnAudioEnqueueResult.staleTurn,
      );
      expect(queue.length, 0);
    });

    test('rejects audio tagged with another session', () {
      final queue = TurnAudioQueue(maxFrames: 3)..startSession('session-1');
      final turn = queue.beginTurn();

      expect(
        queue.enqueue(
          sessionId: 'session-old',
          turnId: turn.turnId,
          data: _frame(1),
        ),
        TurnAudioEnqueueResult.staleSession,
      );
      expect(queue.length, 0);
    });

    test('close rejects late audio but allows queued audio to drain', () {
      final queue = TurnAudioQueue(maxFrames: 3)..startSession('session-1');
      final turn = queue.beginTurn();
      queue.enqueue(
        sessionId: turn.sessionId,
        turnId: turn.turnId,
        data: _frame(1),
      );

      expect(queue.closeTurn(turn), isTrue);
      expect(
        queue.enqueue(
          sessionId: turn.sessionId,
          turnId: turn.turnId,
          data: _frame(2),
        ),
        TurnAudioEnqueueResult.noActiveTurn,
      );
      expect(queue.takeNext()!.data, _frame(1));
    });

    test('a new turn clears pending frames from the previous turn', () {
      final queue = TurnAudioQueue(maxFrames: 3)..startSession('session-1');
      final first = queue.beginTurn(turnId: 'turn-1');
      queue.enqueue(
        sessionId: first.sessionId,
        turnId: first.turnId,
        data: _frame(1),
      );

      final second = queue.beginTurn(turnId: 'turn-2');

      expect(queue.length, 0);
      expect(queue.isCurrent(second), isTrue);
      expect(queue.isCurrent(first), isFalse);
    });

    test('capacity is bounded and overflow drops the oldest frame', () {
      final queue = TurnAudioQueue(maxFrames: 2)..startSession('session-1');
      final turn = queue.beginTurn();

      queue.enqueue(
        sessionId: turn.sessionId,
        turnId: turn.turnId,
        data: _frame(1),
      );
      queue.enqueue(
        sessionId: turn.sessionId,
        turnId: turn.turnId,
        data: _frame(2),
      );
      expect(
        queue.enqueue(
          sessionId: turn.sessionId,
          turnId: turn.turnId,
          data: _frame(3),
        ),
        TurnAudioEnqueueResult.acceptedAfterDroppingOldest,
      );

      expect(queue.length, 2);
      expect(queue.droppedFrames, 1);
      expect(queue.takeNext()!.data, _frame(2));
      expect(queue.takeNext()!.data, _frame(3));
    });
  });
}
