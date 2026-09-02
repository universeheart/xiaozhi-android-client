import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_assistant/utils/audio_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opus_dart/opus_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const samplesPerFrame = 960;
  const frameBytes = samplesPerFrame * 2;

  setUpAll(() async {
    if (!Platform.isWindows) {
      return;
    }
    final packageConfigFile = File('.dart_tool/package_config.json');
    final packageConfig =
        jsonDecode(await packageConfigFile.readAsString())
            as Map<String, dynamic>;
    final packages = packageConfig['packages'] as List<dynamic>;
    final opusPackage = packages.cast<Map<String, dynamic>>().singleWhere(
      (package) => package['name'] == 'opus_flutter_windows',
    );
    final packageRootUri = packageConfigFile.uri.resolve(
      opusPackage['rootUri'] as String,
    );
    final packageRoot = Directory.fromUri(packageRootUri);
    final libraryName =
        Platform.version.contains('x64')
            ? 'libopus_x64.dll.blob'
            : 'libopus_x86.dll.blob';
    initOpus(DynamicLibrary.open('${packageRoot.path}/assets/$libraryName'));
  });

  test('encodes and decodes one fixed 60 ms PCM16 vector', () async {
    final pcmBytes = Uint8List(frameBytes);
    final view = ByteData.view(pcmBytes.buffer);
    for (var index = 0; index < samplesPerFrame; index++) {
      view.setInt16(index * 2, (index % 401) - 200, Endian.little);
    }

    final encoded = await AudioUtil.encodeToOpus(pcmBytes);

    expect(encoded, isNotNull);
    expect(encoded, isNotEmpty);
    final decoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);
    addTearDown(decoder.destroy);
    final decoded = decoder.decode(input: encoded!);
    expect(decoded, hasLength(samplesPerFrame));
  }, skip: !Platform.isWindows);

  test(
    'rejects a partial frame instead of padding silence',
    () async {
      final encoded = await AudioUtil.encodeToOpus(Uint8List(frameBytes - 2));

      expect(encoded, isNull);
    },
    skip: !Platform.isWindows,
  );

  test(
    'rejects multiple frames instead of dropping later samples',
    () async {
      final encoded = await AudioUtil.encodeToOpus(Uint8List(frameBytes * 2));

      expect(encoded, isNull);
    },
    skip: !Platform.isWindows,
  );
}
