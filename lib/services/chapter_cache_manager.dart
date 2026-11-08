import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ChapterCacheManager {
  /// Số lượng ảnh tối đa được giữ lại trong cache đĩa.
  ///
  /// Đặt rất lớn để coi như không giới hạn; việc dọn dẹp thực tế do
  /// [Config.stalePeriod] quyết định (ảnh không được dùng quá 1 ngày).
  static const int _unlimitedCacheObjects = 1 << 30;

  static final CacheManager instance = CacheManager(
    Config(
      'chapterImageCache',
      // Giữ ảnh trong 1 ngày. Mỗi lần mở chương/prefetch sẽ "touch" lại
      // toàn bộ ảnh của chương nên ảnh đang đọc không bị dọn.
      stalePeriod: const Duration(days: 1),
      maxNrOfCacheObjects: _unlimitedCacheObjects,
    ),
  );
}
