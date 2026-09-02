import 'dart:typed_data';

/// Accumulates arbitrary PCM byte chunks and emits fixed-size frames in order.
class PcmFrameBuffer {
  PcmFrameBuffer({required this.frameBytes}) {
    if (frameBytes <= 0) {
      throw ArgumentError.value(frameBytes, 'frameBytes', 'must be positive');
    }
  }

  final int frameBytes;
  Uint8List _pending = Uint8List(0);

  int get pendingBytes => _pending.length;

  Uint8List get pendingData => Uint8List.fromList(_pending);

  List<Uint8List> add(Uint8List chunk) {
    if (chunk.isEmpty) {
      return const [];
    }

    final combined =
        Uint8List(_pending.length + chunk.length)
          ..setRange(0, _pending.length, _pending)
          ..setRange(_pending.length, _pending.length + chunk.length, chunk);
    final frameCount = combined.length ~/ frameBytes;
    final frames = List<Uint8List>.generate(
      frameCount,
      (index) => Uint8List.fromList(
        combined.sublist(index * frameBytes, (index + 1) * frameBytes),
      ),
      growable: false,
    );
    final consumedBytes = frameCount * frameBytes;
    _pending = Uint8List.fromList(combined.sublist(consumedBytes));

    return frames;
  }

  void reset() {
    _pending = Uint8List(0);
  }
}
