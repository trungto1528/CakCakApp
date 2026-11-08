import 'package:flutter/foundation.dart';

import 'chapter_cache_manager.dart';

/// Tải trước toàn bộ ảnh của một chương vào cache đĩa dùng chung với
/// [ChapterCacheManager] (cache mà các widget đọc truyện đang sử dụng).
class ChapterImagePrefetcher {
  const ChapterImagePrefetcher._();

  static Future<void> prefetchChapterImages(
    Iterable<String> urls, {
    int concurrency = 3,
    bool Function()? isCancelled,
  }) async {
    final pending = <String>[];
    final seen = <String>{};

    for (final url in urls) {
      if (url.isEmpty) continue;
      if (seen.add(url)) {
        pending.add(url);
      }
    }

    if (pending.isEmpty) return;

    var nextIndex = 0;

    bool cancelled() => isCancelled?.call() ?? false;

    Future<void> worker() async {
      while (true) {
        if (cancelled()) return;

        final current = nextIndex++;
        if (current >= pending.length) return;

        final url = pending[current];

        try {
          // File còn hạn thì trả về ngay, chưa có/mới hết hạn mới tải.
          await ChapterCacheManager.instance.getSingleFile(url);
        } catch (error) {
          debugPrint('Không thể tải trước ảnh $url: $error');
        }
      }
    }

    final workerCount = concurrency < 1
        ? 1
        : (concurrency > pending.length ? pending.length : concurrency);

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
  }
}
