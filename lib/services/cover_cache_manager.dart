import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CoverCacheManager {
  static const int _unlimitedCacheObjects = 1 << 30;

  static final CacheManager instance = CacheManager(
    Config(
      'coverImageCache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: _unlimitedCacheObjects,
    ),
  );
}
