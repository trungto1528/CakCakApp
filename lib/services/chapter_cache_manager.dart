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
      // Giữ ảnh trong 5 phút. Trong cùng một lần đọc chương (<5 phút),
      // ảnh đã tải sẽ được phục vụ lại từ đĩa khi lùi lại, không tải lại mạng.
      stalePeriod: const Duration(minutes: 5),
      maxNrOfCacheObjects: _unlimitedCacheObjects,
    ),
  );
}
