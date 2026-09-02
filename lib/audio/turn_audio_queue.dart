import 'dart:collection';
import 'dart:typed_data';

enum TurnAudioEnqueueResult {
  accepted,
  acceptedAfterDroppingOldest,
  noActiveTurn,
  staleSession,
  staleTurn,
}

class TurnKey {
  const TurnKey({required this.sessionId, required this.turnId});

  final String sessionId;
  final String turnId;
}

class TurnAudioFrame {
  TurnAudioFrame({required this.turn, required Uint8List data})
    : data = Uint8List.fromList(data);

  final TurnKey turn;
  final Uint8List data;
}

class TurnAudioQueue {
  TurnAudioQueue({required this.maxFrames}) {
    if (maxFrames <= 0) {
      throw ArgumentError.value(maxFrames, 'maxFrames', 'must be positive');
    }
  }

  final int maxFrames;
  final ListQueue<TurnAudioFrame> _frames = ListQueue<TurnAudioFrame>();

  String? _sessionId;
  TurnKey? _currentTurn;
  bool _acceptingAudio = false;
  int _localTurnSequence = 0;
  int _droppedFrames = 0;

  int get length => _frames.length;
  int get droppedFrames => _droppedFrames;
  bool get hasActiveTurn => _acceptingAudio && _currentTurn != null;
  String? get sessionId => _sessionId;
  TurnKey? get currentTurn => _currentTurn;

  void startSession(String sessionId) {
    if (sessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    _sessionId = sessionId;
    _currentTurn = null;
    _acceptingAudio = false;
    _localTurnSequence = 0;
    _frames.clear();
  }

  TurnKey beginTurn({String? turnId}) {
    final session = _sessionId;
    if (session == null) {
      throw StateError('A session must be started before a turn');
    }

    final current = _currentTurn;
    if (_acceptingAudio &&
        current != null &&
        (turnId == null || turnId == current.turnId)) {
      return current;
    }

    final resolvedTurnId =
        turnId?.trim().isNotEmpty == true
            ? turnId!.trim()
            : 'local-${++_localTurnSequence}';
    final next = TurnKey(sessionId: session, turnId: resolvedTurnId);
    _frames.clear();
    _currentTurn = next;
    _acceptingAudio = true;
    return next;
  }

  bool closeTurn(TurnKey turn) {
    if (!isCurrent(turn)) {
      return false;
    }
    _acceptingAudio = false;
    return true;
  }

  void abortActiveTurn() {
    _acceptingAudio = false;
    _frames.clear();
  }

  TurnAudioEnqueueResult enqueue({
    required String sessionId,
    required String turnId,
    required Uint8List data,
  }) {
    final current = _currentTurn;
    if (!_acceptingAudio || current == null) {
      return TurnAudioEnqueueResult.noActiveTurn;
    }
    if (sessionId != current.sessionId) {
      return TurnAudioEnqueueResult.staleSession;
    }
    if (turnId != current.turnId) {
      return TurnAudioEnqueueResult.staleTurn;
    }

    var result = TurnAudioEnqueueResult.accepted;
    if (_frames.length == maxFrames) {
      _frames.removeFirst();
      _droppedFrames++;
      result = TurnAudioEnqueueResult.acceptedAfterDroppingOldest;
    }
    _frames.addLast(TurnAudioFrame(turn: current, data: data));
    return result;
  }

  TurnAudioFrame? takeNext() {
    return _frames.isEmpty ? null : _frames.removeFirst();
  }

  bool isCurrent(TurnKey turn) {
    final current = _currentTurn;
    return current != null &&
        current.sessionId == turn.sessionId &&
        current.turnId == turn.turnId;
  }
}
