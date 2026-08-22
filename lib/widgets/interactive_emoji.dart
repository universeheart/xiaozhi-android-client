import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

enum InteractiveEmojiState { waiting, thinking, speaking }

class InteractiveEmoji extends StatelessWidget {
  const InteractiveEmoji({super.key, required this.state, this.size = 280});

  final InteractiveEmojiState state;
  final double size;

  String get _assetPath => switch (state) {
    InteractiveEmojiState.waiting =>
      'assets/emoji/slightly_smiling_face_animated.webp',
    InteractiveEmojiState.thinking =>
      'assets/emoji/thinking_face_animated.webp',
    InteractiveEmojiState.speaking =>
      'assets/emoji/grinning_face_with_smiling_eyes_animated.webp',
  };

  String get _semanticLabel => switch (state) {
    InteractiveEmojiState.waiting => '正在等待你的输入',
    InteractiveEmojiState.thinking => '正在思考',
    InteractiveEmojiState.speaking => '正在回答',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel,
      image: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: Image.asset(
          _assetPath,
          key: ValueKey(_assetPath),
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

Widget _previewFrame(InteractiveEmojiState state, String label) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFFF8F7F3),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveEmoji(state: state),
            const SizedBox(height: 20),
            Text(label, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: '等待', group: '互动大表情', size: Size(360, 520))
Widget interactiveEmojiWaitingPreview() =>
    _previewFrame(InteractiveEmojiState.waiting, '等你和我说话');

@Preview(name: '思考', group: '互动大表情', size: Size(360, 520))
Widget interactiveEmojiThinkingPreview() =>
    _previewFrame(InteractiveEmojiState.thinking, '让我想一想');

@Preview(name: '说话', group: '互动大表情', size: Size(360, 520))
Widget interactiveEmojiSpeakingPreview() =>
    _previewFrame(InteractiveEmojiState.speaking, '正在回答');
