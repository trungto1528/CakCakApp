import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class CrawlService {
  Future<Map<String, dynamic>> crawlStory(String url) async {
    final res = await http.post(
      Uri.parse("${ApiConfig.crawlerUrl}/story-info"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"url": url}),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }

    throw Exception("Crawl failed: ${res.body}");
  }

  Future<List<String>> getSupportedWebsites() async {
    final res = await http.get(Uri.parse("${ApiConfig.crawlerUrl}/websites"));

    if (res.statusCode != 200) {
      throw Exception("Không thể lấy danh sách website");
    }

    final decoded = jsonDecode(res.body) as List;

    return decoded.map((item) => item['name'].toString()).toList();
  }

  // Bắt đầu kiểm tra một truyện.
  Future<Map<String, dynamic>> checkStoryUpdates(int storyId) async {
    final res = await http.post(
      Uri.parse("${ApiConfig.crawlerUrl}/check-update/$storyId"),
    );

    if (res.statusCode == 202 || res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    }

    throw Exception("Không thể kiểm tra truyện: ${res.body}");
  }

  // Bắt đầu kiểm tra tất cả truyện.
  Future<Map<String, dynamic>> checkAllStoryUpdates() async {
    final res = await http.post(
      Uri.parse("${ApiConfig.crawlerUrl}/check-update"),
    );

    if (res.statusCode == 202 || res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    }

    throw Exception("Không thể kiểm tra tất cả truyện: ${res.body}");
  }

  // Lấy danh sách task kiểm tra cập nhật.
  Future<List<Map<String, dynamic>>> getUpdateCheckTasks() async {
    final res = await http.get(
      Uri.parse("${ApiConfig.crawlerUrl}/check-updates/tasks"),
    );

    if (res.statusCode != 200) {
      throw Exception("Không thể lấy danh sách task: ${res.body}");
    }

    final decoded = jsonDecode(res.body) as List;

    return decoded.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  // Lấy chi tiết tiến độ và kết quả của một task.
  Future<Map<String, dynamic>> getUpdateCheckTask(String taskId) async {
    final res = await http.get(
      Uri.parse(
        "${ApiConfig.crawlerUrl}/check-updates/tasks/"
        "${Uri.encodeComponent(taskId)}",
      ),
    );

    if (res.statusCode != 200) {
      throw Exception("Không thể lấy task $taskId: ${res.body}");
    }

    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  Map<String, dynamic> buildNewChaptersPayload(Map<String, dynamic> result) {
    final chapters = (result['chapters'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map(
          (chapter) => <String, dynamic>{
            'title': chapter['title'],
            'url': chapter['url'],
            'order': chapter['order'],
            'choosen': true,
          },
        )
        .toList();

    if (chapters.isEmpty) {
      throw Exception('Truyện không có chapter mới');
    }

    return {
      'title': result['storyTitle'],
      'sourceUrl': result['sourceUrl'],
      'selectedStoryId': result['storyId'],
      'chapters': chapters,
    };
  }

  Future<Map<String, dynamic>> crawlNewChapters(
    Map<String, dynamic> result,
    int userId,
  ) async {
    return importStory(buildNewChaptersPayload(result), userId);
  }

  Future<List<Map<String, dynamic>>> searchStories(
    String website,
    String keyword,
  ) async {
    final uri = Uri.parse(
      "${ApiConfig.crawlerUrl}/search",
    ).replace(queryParameters: {"website": website, "keyword": keyword.trim()});

    final res = await http.get(uri);

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);

      if (decoded is List) {
        return decoded
            .map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item),
            )
            .toList();
      }

      throw Exception("Dữ liệu tìm kiếm không hợp lệ");
    }

    throw Exception("Search failed: ${res.body}");
  }

  Future<Map<String, dynamic>> importStory(
    Map<String, dynamic> data,
    int userId,
  ) async {
    final res = await http.post(
      Uri.parse("${ApiConfig.crawlerUrl}/import-selected"),
      headers: {
        "Content-Type": "application/json",
        "userId": userId.toString(),
      },
      body: jsonEncode(data),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }

    throw Exception("Import failed: ${res.body}");
  }

  Future<Map<String, dynamic>> getAllTasks() async {
    final res = await http.get(Uri.parse("${ApiConfig.crawlerUrl}/tasks"));

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }

    throw Exception("Failed to get tasks");
  }

  Future<void> cancelTask(String taskId) async {
    final res = await http.post(
      Uri.parse("${ApiConfig.crawlerUrl}/cancel/$taskId"),
    );

    if (res.statusCode != 200) {
      throw Exception("Cancel failed");
    }
  }
}
