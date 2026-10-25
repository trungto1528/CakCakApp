import 'package:flutter_cache_manager/flutter_cache_manager.dart';
class ChapterCacheManager {
  static final CacheManager instance = CacheManager(
    Config(
      'chapterImageCache',
      stalePeriod: const Duration(minutes: 10),
      maxNrOfCacheObjects: 100,
    ),
  );
}