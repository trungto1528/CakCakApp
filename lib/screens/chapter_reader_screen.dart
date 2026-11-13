import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'chapter_reader_android.dart';
import 'chapter_reader_windows.dart';

/// Entry point tương thích với các màn hình/route cũ.
/// Tự chọn màn hình đọc phù hợp với nền tảng đang chạy.
class ChapterReaderScreen extends StatelessWidget {
  final int chapterId;
  final int storyId;
  final String source;
  final int? startPage;

  const ChapterReaderScreen({
    super.key,
    required this.chapterId,
    required this.storyId,
    required this.source,
    this.startPage,
  });

  @override
  Widget build(BuildContext context) {
    final isWindows = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows;

    if (isWindows) {
      return ChapterReaderWindowsScreen(
        chapterId: chapterId,
        storyId: storyId,
        source: source,
        startPage: startPage,
      );
    }

    return ChapterReaderAndroidScreen(
      chapterId: chapterId,
      storyId: storyId,
      source: source,
      startPage: startPage,
    );
  }
}
