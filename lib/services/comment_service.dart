import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../services/app_preference.dart';

class CommentService {
  /// Lấy userId đã lưu từ SharedPreferences / Windows preferences.
  static Future<int?> _getUserId() async {
    final prefs = await AppPreferences.getInstance();
    final userStr = prefs.getString('user');
    if (userStr == null) return null;
    try {
      final decoded = jsonDecode(userStr);
      if (decoded is Map) {
        final id = decoded['id'];
        if (id is num) return id.toInt();
      }
    } catch (_) {}
    return null;
  }

  /// Tạo bình luận hoặc trả lời (parentId != null là trả lời).
  Future<Map<String, dynamic>> createComment({
    required int chapterId,
    required String content,
    int? parentId,
  }) async {
    final userId = await _getUserId();
    if (userId == null) {
      throw Exception('Bạn cần đăng nhập để bình luận');
    }

    final res = await http.post(
      Uri.parse('${ApiConfig.api}/comments'),
      headers: {
        'Content-Type': 'application/json',
        'userId': userId.toString(),
      },
      body: jsonEncode({
        'chapterId': chapterId,
        'content': content,
        if (parentId != null) 'parentId': parentId,
      }),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw Exception('Phản hồi bình luận không hợp lệ');
    }
    throw Exception(res.body.isNotEmpty ? res.body : 'Bình luận thất bại');
  }

  /// Lấy danh sách bình luận của chapter (gốc + trả lời), phân trang.
  Future<List<Map<String, dynamic>>> getComments({
    required int chapterId,
    int page = 0,
    int limit = 20,
  }) async {
    final uri = Uri.parse('${ApiConfig.api}/comments/chapter/$chapterId')
        .replace(queryParameters: {
          'page': page.toString(),
          'limit': limit.toString(),
        });
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) {
        final content = decoded['content'];
        if (content is List) {
          return List<Map<String, dynamic>>.from(
            content.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
          );
        }
      }
      return <Map<String, dynamic>>[];
    }
    throw Exception('Không thể tải bình luận');
  }

  /// Chỉnh sửa bình luận của chính mình.
  Future<void> updateComment({
    required int commentId,
    required String newContent,
  }) async {
    final userId = await _getUserId();
    if (userId == null) {
      throw Exception('Bạn cần đăng nhập để chỉnh sửa');
    }

    final res = await http.put(
      Uri.parse('${ApiConfig.api}/comments/$commentId'),
      headers: {
        'Content-Type': 'application/json',
        'userId': userId.toString(),
      },
      body: jsonEncode({
        'content': newContent,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Chỉnh sửa thất bại');
    }
  }

  /// Xóa bình luận của chính mình.
  Future<void> deleteComment(int commentId) async {
    final userId = await _getUserId();
    if (userId == null) {
      throw Exception('Bạn cần đăng nhập để xóa');
    }

    final res = await http.delete(
      Uri.parse('${ApiConfig.api}/comments/$commentId'),
      headers: {'userId': userId.toString()},
    );

    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Xóa thất bại');
    }
  }
}
