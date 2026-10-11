import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class CrawlService {
  Future<Map<String, dynamic>> crawlStory(String url) async {
    final res = await http.post(
      Uri.parse("${ApiConfig.crawlerUrl}/story-info"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "url": url,
      }),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }

    throw Exception(
      "Crawl failed: ${res.body}",
    );
  }

  Future<List<String>> getSupportedWebsites() async {
    final res = await http.get(
      Uri.parse("${ApiConfig.crawlerUrl}/websites"),
    );

    if (res.statusCode != 200) {
      throw Exception("Không thể lấy danh sách website");
    }

    final decoded = jsonDecode(res.body) as List;

    return decoded
        .map((item) => item['name'].toString())
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchStories(
      String website,
      String keyword,
      ) async {
    final uri = Uri.parse(
      "${ApiConfig.crawlerUrl}/search",
    ).replace(
      queryParameters: {
        "website": website,
        "keyword": keyword.trim(),
      },
    );

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

  Future<Map<String, dynamic>> importStory(Map<String, dynamic> data,
      int userId,) async {
    final res = await http.post(
      Uri.parse(
        "${ApiConfig.crawlerUrl}/import-selected",
      ),
      headers: {
        "Content-Type":
        "application/json",
        "userId":
        userId.toString(),
      },
      body: jsonEncode(data),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }

    throw Exception(
      "Import failed: ${res.body}",
    );
  }

  Future<Map<String, dynamic>>
  getAllTasks() async {
    final res = await http.get(
      Uri.parse("${ApiConfig.crawlerUrl}/tasks"),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }

    throw Exception(
      "Failed to get tasks",
    );
  }

  Future<void> cancelTask(String taskId) async {
    final res = await http.post(
      Uri.parse(
        "${ApiConfig.crawlerUrl}/cancel/$taskId",
      ),
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Cancel failed",
      );
    }
  }
}