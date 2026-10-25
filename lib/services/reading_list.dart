import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ReadingList {
  Future<void> save(int userId, int storyId, int chapterId) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.api}/reading-list/save'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "storyId": storyId,
        "chapterId": chapterId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception("Lưu tiến độ đọc thất bại");
    }
  }

  Future<void> remove(int userId, int storyId) async {
    final res = await http.delete(
      Uri.parse('${ApiConfig.api}/reading-list/remove'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "storyId": storyId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception("Xóa tiến độ đọc thất bại");
    }
  }

  Future<int?> check(int userId, int storyId) async {
    final res = await http.get(
      Uri.parse(
        '${ApiConfig.api}/reading-list/check?userId=$userId&storyId=$storyId',
      ),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (body == null) return null;
      return int.tryParse(body.toString());
    } else {
      throw Exception("Kiểm tra tiến độ đọc thất bại");
    }
  }

  Future<Map<int, Map<String, dynamic>>> getUser(int userId) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.api}/reading-list/user/$userId'),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (body == null) return <int, Map<String, dynamic>>{};
      final map = Map<String, dynamic>.from(body);
      return map.map(
        (key, value) => MapEntry(
          int.parse(key),
          Map<String, dynamic>.from(value as Map),
        ),
      );
    } else {
      throw Exception("Lấy danh sách đọc thất bại");
    }
  }
}
