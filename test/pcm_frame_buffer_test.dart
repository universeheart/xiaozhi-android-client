import 'dart:math';
import 'dart:typed_data';

import 'package:ai_assistant/audio/pcm_frame_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const samplesPerFrame = 960;
  const bytesPerSample = 2;
  const frameBytes = samplesPerFrame * bytesPerSample;

  Uint8List sequence(int length) =>
      Uint8List.fromList(List<int>.generate(length, (index) => index % 251));

  group('PcmFrameBuffer', () {
    test('emits one exact PCM16 frame', () {
      final buffer = PcmFrameBuffer(frameBytes: frameBytes);
      final input = sequence(frameBytes);

      final frames = buffer.add(input);

      expect(frames, hasLength(1));
      expect(frames.single, orderedEquals(input));
      expect(buffer.pendingBytes, 0);
    });

    test('retains a short chunk without padding silence', () {
      final buffer = PcmFrameBuffer(frameBytes: frameBytes);
      final input = sequence(317);

      expect(buffer.add(input), isEmpty);
      expect(buffer.pendingBytes, input.length);
      expect(buffer.pendingData, orderedEquals(input));
    });

    test('emits every full frame and retains only the tail', () {
      final buffer = PcmFrameBuffer(frameBytes: frameBytes);
      final input = sequence(frameBytes * 3 + 127);

      final frames = buffer.add(input);

      expect(frames, hasLength(3));
      expect(
        frames.expand((frame) => frame),
        orderedEquals(input.sublist(0, frameBytes * 3)),
      );
      expect(buffer.pendingData, orderedEquals(input.sublist(frameBytes * 3)));
    });

    test('random recorder chunk sizes conserve every byte in order', () {
      final random = Random(20260828);
      final input = sequence(frameBytes * 19 + 911);
      final buffer = PcmFrameBuffer(frameBytes: frameBytes);
      final emitted = <int>[];
      var offset = 0;

      while (offset < input.length) {
        final chunkLength = min(
          1 + random.nextInt(3000),
          input.length - offset,
        );
        final chunk = Uint8List.sublistView(
          input,
          offset,
          offset + chunkLength,
        );
        for (final frame in buffer.add(chunk)) {
          emitted.addAll(frame);
        }
        offset += chunkLength;
      }

      expect(emitted.length % frameBytes, 0);
      expect(<int>[...emitted, ...buffer.pendingData], orderedEquals(input));
    });

    test('reset discards the previous recording tail', () {
      final buffer = PcmFrameBuffer(frameBytes: frameBytes);
      buffer.add(sequence(501));

      buffer.reset();

      expect(buffer.pendingBytes, 0);
      expect(buffer.pendingData, isEmpty);
    });
  });
}
