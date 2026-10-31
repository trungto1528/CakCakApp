import 'package:flutter/material.dart';
import 'chapter_reader_common.dart';

class ChapterReaderAndroidScreen extends StatefulWidget {
  final int chapterId;
  final int storyId;
  final String source;

  const ChapterReaderAndroidScreen({
    super.key,
    required this.chapterId,
    required this.storyId,
    required this.source,
  });

  @override
  State<ChapterReaderAndroidScreen> createState() =>
      _ChapterReaderAndroidScreenState();
}

class _ChapterReaderAndroidScreenState
    extends ChapterReaderScreenStateBase<ChapterReaderAndroidScreen> {
  @override
  void initState() {
    super.initState();

    chapterId = widget.chapterId;
    storyId = widget.storyId;
    source = widget.source;
    currentChapterId = widget.chapterId;
    currentSource = widget.source;

    scrollController.addListener(updateReadingProgress);
    transformController.addListener(onTransformChanged);

    _initializeReader();
  }

  Future<void> _initializeReader() async {
    await loadReaderSettings();
    if (!mounted) return;
    await initData();
  }
}
