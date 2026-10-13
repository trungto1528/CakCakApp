import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class OfflineEntryService {
  OfflineEntryService._();

  static final OfflineEntryService instance = OfflineEntryService._();

  /// Thư mục gốc chứa tất cả truyện Offline.
  Future<Directory> _offlineStoriesDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/offline_stories');
  }

  /// Thư mục của một truyện nếu package đã được đánh dấu hoàn tất.
  Future<Directory?> _getStoryDirectory(int storyId) async {
    final root = await _offlineStoriesDirectory();
    final directory = Directory('${root.path}/$storyId');

    if (!await directory.exists()) return null;

    final marker = File('${directory.path}/complete.json');
    final metadata = File('${directory.path}/metadata.json');

    if (!await marker.exists() || !await metadata.exists()) {
      return null;
    }

    return directory;
  }

  /// Kiểm tra truyện đã có sẵn để đọc Offline.
  Future<bool> isStoryAvailable(int storyId) async {
    return await _getStoryDirectory(storyId) != null;
  }

  /// Lấy ID của tất cả truyện đã tải hoàn chỉnh.
  Future<List<int>> getDownloadedStoryIds() async {
    final root = await _offlineStoriesDirectory();

    if (!await root.exists()) return [];

    final storyIds = <int>[];

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;

      final segments = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .toList();

      if (segments.isEmpty) continue;

      final storyId = int.tryParse(segments.last);
      if (storyId == null) continue;

      if (await isStoryAvailable(storyId)) {
        storyIds.add(storyId);
      }
    }

    storyIds.sort();
    return storyIds;
  }

  /// Đọc metadata của một truyện Offline.
  Future<Map<String, dynamic>?> getStory(int storyId) async {
    final directory = await _getStoryDirectory(storyId);
    if (directory == null) return null;

    final file = File('${directory.path}/metadata.json');
    if (!await file.exists()) return null;

    final decoded = jsonDecode(await file.readAsString());

    if (decoded is! Map) return null;

    final metadata = Map<String, dynamic>.from(decoded);
    metadata['id'] ??= storyId;

    return metadata;
  }

  /// Lấy metadata của tất cả truyện đã tải hoàn chỉnh.
  Future<List<Map<String, dynamic>>> getDownloadedStories() async {
    final ids = await getDownloadedStoryIds();
    final stories = <Map<String, dynamic>>[];

    for (final id in ids) {
      try {
        final story = await getStory(id);
        if (story != null) {
          stories.add(story);
        }
      } catch (_) {
        // Bỏ qua metadata lỗi để không làm hỏng toàn bộ danh sách.
      }
    }

    return stories;
  }

  /// Tìm truyện Offline theo tên, tác giả hoặc mô tả.
  Future<List<Map<String, dynamic>>> searchStories(String keyword) async {
    final query = keyword.trim().toLowerCase();
    final stories = await getDownloadedStories();

    if (query.isEmpty) return stories;

    return stories.where((story) {
      final title = (story['title'] ?? '').toString().toLowerCase();
      final author = (story['author'] ?? '').toString().toLowerCase();
      final description = (story['description'] ?? '').toString().toLowerCase();

      return title.contains(query) ||
          author.contains(query) ||
          description.contains(query);
    }).toList();
  }

  /// Đọc nội dung một chương đã tải.
  Future<Map<String, dynamic>?> getChapter(int storyId, int chapterId) async {
    final directory = await _getStoryDirectory(storyId);
    if (directory == null) return null;

    final file = File('${directory.path}/chapters/$chapterId.json');
    if (!await file.exists()) return null;

    final decoded = jsonDecode(await file.readAsString());

    if (decoded is! Map) return null;

    return Map<String, dynamic>.from(decoded);
  }

  /// Lấy file ảnh cục bộ, ví dụ cover/abc.jpg hoặc chapter/xyz.webp.
  Future<File?> getImage(int storyId, String imagePath) async {
    final normalizedPath = imagePath.replaceAll('\\', '/');
    final parts = normalizedPath.split('/');

    // Chỉ chấp nhận ảnh nằm trong cover/ hoặc chapter/.
    if (parts.length != 2 ||
        (parts[0] != 'cover' && parts[0] != 'chapter') ||
        parts[1].isEmpty ||
        parts[1] == '.' ||
        parts[1] == '..' ||
        parts[1].contains(':')) {
      throw Exception('Đường dẫn ảnh không hợp lệ: $imagePath');
    }

    final directory = await _getStoryDirectory(storyId);
    if (directory == null) return null;

    final file = File('${directory.path}/$normalizedPath');

    if (!await file.exists() || await file.length() == 0) {
      return null;
    }

    return file;
  }

  /// Lấy ảnh bìa từ package Offline.
  Future<File?> getCoverImage(int storyId) async {
    final directory = await _getStoryDirectory(storyId);
    if (directory == null) return null;

    final marker = File('${directory.path}/complete.json');
    if (!await marker.exists()) return null;

    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map) return null;

      final images = decoded['images'];
      if (images is! List) return null;

      for (final item in images) {
        final path = item.toString().replaceAll('\\', '/');

        if (!path.startsWith('cover/')) continue;

        final file = await getImage(storyId, path);
        if (file != null) return file;
      }
    } catch (e) {
      // Package không hợp lệ hoặc không đọc được.
    }

    return null;
  }
}
