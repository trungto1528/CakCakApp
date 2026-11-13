import 'package:flutter/material.dart';
import 'chapter_reader_common.dart';

class ChapterReaderWindowsScreen extends StatefulWidget {
  final int chapterId;
  final int storyId;
  final String source;
  final int? startPage;

  const ChapterReaderWindowsScreen({
    super.key,
    required this.chapterId,
    required this.storyId,
    required this.source,
    this.startPage,
  });

  @override
  State<ChapterReaderWindowsScreen> createState() =>
      _ChapterReaderWindowsScreenState();
}

class _ChapterReaderWindowsScreenState
    extends ChapterReaderScreenStateBase<ChapterReaderWindowsScreen> {
  @override
  void initState() {
    super.initState();

    chapterId = widget.chapterId;
    storyId = widget.storyId;
    source = widget.source;
    currentChapterId = widget.chapterId;
    currentSource = widget.source;
    startPage = widget.startPage;

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
