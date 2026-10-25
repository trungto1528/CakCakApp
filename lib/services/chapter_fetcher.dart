import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:novel_app/config/api_config.dart';
import 'package:novel_app/offline/service/offline_data_service.dart';
import 'package:novel_app/offline/service/offline_entry_service.dart';
import 'package:novel_app/offline/service/offline_mode_service.dart';
class ChapterFetcher {
  String _cacheKey(int chapterId) => 'chapter_$chapterId';
  /// Lấy nội dung chương.
  ///
  /// Offline: đọc chương từ package đã tải theo storyId.
  /// Online: lấy dữ liệu từ server và lưu cache JSON.
  Future<Map<String, dynamic>> fetchChapter(
      int chapterId, {
        int? storyId,
      }) async {
    final key = _cacheKey(chapterId);
    if (OfflineModeService.isOffline.value) {
      // Ưu tiên đọc chương trong package Offline.
      if (storyId != null) {
        final chapter = await OfflineEntryService.instance.getChapter(
          storyId,
          chapterId,
        );
        if (chapter != null) {
          return chapter;
        }
      }
      // Không dùng cache JSON chung để giả định rằng chương thuộc
      // package của truyện đang đọc.
      throw Exception(
        storyId == null
            ? 'Cần storyId để đọc chương trong package Offline.'
            : 'Chương này chưa có trong package Offline của truyện.',
      );
    }
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.api}/chapters/$chapterId'),
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Không thể tải chương. HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );
      if (decoded is! Map) {
        throw Exception('Dữ liệu chương không hợp lệ.');
      }
      final data = Map<String, dynamic>.from(decoded);
      // Lưu cache JSON thông thường để hỗ trợ đọc lại khi mất mạng.
      await OfflineDataService.saveJson(key, data);
      return data;
    } catch (_) {
      // Khi lỗi mạng lúc đang Online, thử dùng cache JSON thông thường.
      final cached = await OfflineDataService.readJson(key);
      if (cached is Map) {
        return Map<String, dynamic>.from(cached);
      }
      rethrow;
    }
  }
  /// Tạo chương mới.
  Future<bool> createChapter({
    required int storyId,
    required String title,
    required List<Map<String, String>> content,
    required int chapterNumber,
    required int userId,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.api}/chapters'),
      headers: {
        'Content-Type': 'application/json',
        'userId': userId.toString(),
      },
      body: jsonEncode({
        'storyId': storyId,
        'title': title,
        'blocks': content,
        'chapterNumber': chapterNumber,
      }),
    );
    return res.statusCode == 200 || res.statusCode == 201;
  }
  /// Duyệt chương.
  Future<void> approveChapter(int adminId, int chapterId) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.api}/chapters/$chapterId/approve'),
      headers: {'userId': adminId.toString()},
    );
    if (res.statusCode != 200) {
      throw Exception('Approve chapter failed');
    }
  }
  /// Từ chối chương.
  Future<void> rejectChapter(int adminId, int chapterId) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.api}/chapters/$chapterId/reject'),
      headers: {'userId': adminId.toString()},
    );
    if (res.statusCode != 200) {
      throw Exception('Reject chapter failed');
    }
  }
  /// Xóa chương.
  Future<void> deleteChapter(int chapterId, int userId) async {
    final res = await http.delete(
      Uri.parse('${ApiConfig.api}/chapters/$chapterId'),
      headers: {'userId': userId.toString()},
    );
    if (res.statusCode != 200) {
      throw Exception('Delete chapter failed');
    }
    await OfflineDataService.deleteData(_cacheKey(chapterId));
  }
  /// Upload ảnh minh họa.
  Future<String?> uploadIllustration(File file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.api}/illus/upload'),
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
      print('Upload illustration error: $e');
    }
    return null;
  }
  /// Lấy danh sách chương chờ duyệt.
  Future<List<dynamic>> getPendingChapters() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.api}/chapters/pending'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is List) return data;
    }
    throw Exception('Failed to load pending chapters');
  }
  /// Lấy danh sách chương của người dùng.
  Future<List<dynamic>> getMyChapter(int userId) async {
    final res = await http.get(
      Uri.parse(
        '${ApiConfig.api}/chapters/my-chapters?userId=$userId',
      ),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is List) return data;
    }
    throw Exception('Failed to load my chapters');
  }
}
