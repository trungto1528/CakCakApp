import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
class Bookmark {
  Future<void> saveStory(int userId, int storyId) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.api}/bookmarks/save'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "storyId": storyId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception("Lưu truyện thất bại");
    }
  }
  Future<void> unsaveStory(int userId, int storyId) async {
    final res = await http.delete(
      Uri.parse('${ApiConfig.api}/bookmarks/unsave'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "storyId": storyId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception("Bỏ lưu thất bại");
    }
  }
  Future<bool> isSavedApi(int userId, int storyId) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.api}/bookmarks/check?userId=$userId&storyId=$storyId'),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      throw Exception("Check bookmark thất bại");
    }
  }
  Future<List> getBookmark(int userId) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.api}/bookmarks/user/$userId'),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      throw Exception("Lấy danh sách bookmark thất bại");
    }
  }
}