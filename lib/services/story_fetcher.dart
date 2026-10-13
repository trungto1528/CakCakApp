
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:novel_app/config/api_config.dart';
import 'package:novel_app/offline/service/offline_data_service.dart';
import 'package:novel_app/offline/service/offline_entry_service.dart';
import 'package:novel_app/offline/service/offline_mode_service.dart';

class StoryFetcher {
  String _storyCacheKey(int storyId) => 'story_$storyId';

  static const String _latestStoriesCacheKey = 'latest_stories';

  /// Đọc metadata truyện từ đầu mối Offline.
  Future<Map<String, dynamic>?> _readOfflineStory(int storyId) async {
    final story = await OfflineEntryService.instance.getStory(storyId);

    if (story == null) return null;

    final result = Map<String, dynamic>.from(story);

    if (result['chapters'] is! List) {
      result['chapters'] = <dynamic>[];
    }

    return result;
  }

  /// Lấy thông tin chi tiết truyện.
  Future<Map<String, dynamic>> fetchStory(int storyId) async {
    if (OfflineModeService.isOffline.value) {
      final story = await _readOfflineStory(storyId);

      if (story != null) return story;

      throw Exception('Truyện chưa được tải đầy đủ để đọc Offline.');
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.api}/stories/fetch/$storyId'),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch story: HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map) {
        throw Exception('Dữ liệu truyện không hợp lệ.');
      }

      final data = Map<String, dynamic>.from(decoded);

      await OfflineDataService.saveJson(_storyCacheKey(storyId), data);

      return data;
    } catch (_) {
      // Khi lỗi mạng, ưu tiên package Offline đã tải.
      final offlineStory = await _readOfflineStory(storyId);

      if (offlineStory != null) return offlineStory;

      // Cuối cùng mới dùng cache JSON thông thường.
      final cached = await OfflineDataService.readJson(
        _storyCacheKey(storyId),
      );

      if (cached is Map) {
        return Map<String, dynamic>.from(cached);
      }

      rethrow;
    }
  }

  /// Lấy thông tin truyện dành cho quản trị viên.
  Future<Map<String, dynamic>?> fetchStoryAdmin(
      int storyId,
      int adminId,
      ) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.api}/stories/$storyId/admin'),
      headers: {'userId': adminId.toString()},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));

      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    }

    return null;
  }

  /// Lấy tất cả truyện dành cho quản trị viên.
  Future<List> getAllStories(int adminId) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.api}/stories/all'),
      headers: {'userId': adminId.toString()},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));

      if (data is List) return data;

      throw Exception('Dữ liệu danh sách truyện không hợp lệ.');
    }

    throw Exception('Failed to load stories');
  }

  /// Tìm kiếm truyện.
  ///
  /// Offline: chỉ tìm trong các truyện đã tải hoàn chỉnh.
  /// Online: tìm kiếm trên server.
  Future<List> search(String keyword) async {
    if (OfflineModeService.isOffline.value) {
      return OfflineEntryService.instance.searchStories(keyword);
    }

    final uri = Uri.parse('${ApiConfig.api}/stories/search').replace(
      queryParameters: {'keyword': keyword},
    );

    final res = await http.get(uri);

    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));

      if (data is List) return data;

      throw Exception('Dữ liệu tìm kiếm không hợp lệ.');
    }

    throw Exception('Search failed');
  }

  /// Lấy thông tin rút gọn của truyện.
  Future<Map<String, dynamic>> searchLittle(int storyId) async {
    if (OfflineModeService.isOffline.value) {
      final story = await _readOfflineStory(storyId);

      if (story != null) return story;

      throw Exception('Truyện chưa được tải để đọc Offline.');
    }

    final res = await http.get(
      Uri.parse('${ApiConfig.api}/stories/little?storyId=$storyId'),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));

      if (data is List && data.isNotEmpty && data.first is Map) {
        return Map<String, dynamic>.from(data.first);
      }

      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    }

    throw Exception('No story found');
  }

  /// Tạo truyện.
  Future<Map<String, dynamic>?> createStory({
    required String title,
    required String description,
    required String author,
    required String coverUrl,
    required int userId,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.api}/stories'),
      headers: {
        'Content-Type': 'application/json',
        'userId': userId.toString(),
      },
      body: jsonEncode({
        'title': title,
        'description': description,
        'author': author,
        'coverUrl': coverUrl,
      }),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));

      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    }

    return null;
  }

  /// Duyệt truyện.
  Future<void> approveStory(int adminId, int storyId) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.api}/stories/$storyId/approve'),
      headers: {'userId': adminId.toString()},
    );

    if (res.statusCode != 200) {
      throw Exception('Approve failed');
    }
  }

  /// Từ chối truyện.
  Future<void> rejectStory(int adminId, int storyId) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.api}/stories/$storyId/reject'),
      headers: {'userId': adminId.toString()},
    );

    if (res.statusCode != 200) {
      throw Exception('Reject failed');
    }
  }

  /// Xóa truyện trên server và xóa cache JSON thông thường.
  Future<void> deleteStory(int storyId, int userId) async {
    final res = await http.delete(
      Uri.parse('${ApiConfig.api}/stories/$storyId'),
      headers: {'userId': userId.toString()},
    );

    if (res.statusCode != 200) {
      throw Exception('Delete failed');
    }

    await OfflineDataService.deleteData(_storyCacheKey(storyId));
  }

  /// Upload ảnh bìa.
  Future<String?> uploadCover(File file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.api}/stories/upload-cover'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final response = await request.send();
      final result = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return result;
      }
    } catch (e) {
      print('Upload cover error: $e');
    }

    return null;
  }

  /// Lấy danh sách truyện cập nhật gần đây.
  ///
  /// Khi Offline, dùng cache danh sách đã lưu trước đó.
  /// Đây là danh sách cache chung, không phải danh sách package đã tải.
  Future<List<dynamic>> fetchLatestStories() async {
    if (OfflineModeService.isOffline.value) {
      final cached = await OfflineDataService.readJson(
        _latestStoriesCacheKey,
      );

      if (cached is List) {
        return List<dynamic>.from(cached);
      }

      throw Exception(
        'Danh sách truyện chưa được lưu để xem Offline.',
      );
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.api}/stories/latest-updated'),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load latest stories: HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! List) {
        throw Exception('Danh sách truyện không hợp lệ.');
      }

      await OfflineDataService.saveJson(
        _latestStoriesCacheKey,
        decoded,
      );

      return List<dynamic>.from(decoded);
    } catch (_) {
      final cached = await OfflineDataService.readJson(
        _latestStoriesCacheKey,
      );

      if (cached is List) {
        return List<dynamic>.from(cached);
      }

      rethrow;
    }
  }
}
