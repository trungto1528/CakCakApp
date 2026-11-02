
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class CrawlService {
  String get _baseUrl => ApiConfig.crawlerUrl;

  Map<String, dynamic> _decodeMap(
      String body, {
        String errorMessage = 'Dữ liệu trả về không hợp lệ',
      }) {
    final decoded = jsonDecode(body);

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    throw FormatException(errorMessage);
  }

  List<dynamic> _decodeList(
      String body, {
        String errorMessage = 'Dữ liệu trả về không hợp lệ',
      }) {
    final decoded = jsonDecode(body);

    if (decoded is List) {
      return decoded;
    }

    throw FormatException(errorMessage);
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    throw const FormatException('Phần tử JSON không phải object');
  }

  Exception _httpError(String message, http.Response response) {
    String detail = response.body;

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map) {
        detail = decoded['message']?.toString() ??
            decoded['error']?.toString() ??
            response.body;
      }
    } catch (_) {
      // Giữ nguyên response body nếu không phải JSON.
    }

    return Exception(
      '$message (HTTP ${response.statusCode}): $detail',
    );
  }

  // ============================================================
  // CRAWL STORY
  // ============================================================

  Future<Map<String, dynamic>> crawlStory(String url) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/story-info'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': url}),
    );

    if (res.statusCode == 200) {
      return _decodeMap(
        res.body,
        errorMessage: 'Dữ liệu crawl truyện không hợp lệ',
      );
    }

    throw _httpError('Crawl failed', res);
  }

  // ============================================================
  // MYANIMELIST
  // ============================================================

  Future<Map<String, dynamic>> searchMal(String title) async {
    final trimmed = title.trim();
    print('[MAL][searchMal] title="$trimmed" url=$_baseUrl/mal/search');

    final res = await http.post(
      Uri.parse('$_baseUrl/mal/search'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'title': trimmed}),
    );

    final bodyPreview = res.body.length > 500
        ? '${res.body.substring(0, 500)}...'
        : res.body;
    print('[MAL][searchMal] statusCode=${res.statusCode} body=$bodyPreview');

    if (res.statusCode == 200) {
      final decoded = _decodeMap(
        res.body,
        errorMessage: 'Dữ liệu tìm kiếm MAL không hợp lệ',
      );
      final status = decoded['status']?.toString() ?? '';
      final malId = decoded['malId']?.toString() ?? '';
      final resultsCount = (decoded['results'] as List?)?.length ?? 0;
      print(
        '[MAL][searchMal] parsed status=$status malId=$malId resultsCount=$resultsCount',
      );
      return decoded;
    }

    throw _httpError('MAL search failed', res);
  }

  Future<Map<String, dynamic>> getMalDetail(int malId) async {
    print('[MAL][getMalDetail] malId=$malId url=$_baseUrl/mal/detail/$malId');
    final res = await http.get(
      Uri.parse('$_baseUrl/mal/detail/$malId'),
    );

    if (res.statusCode == 200) {
      return _decodeMap(
        res.body,
        errorMessage: 'Dữ liệu chi tiết MAL không hợp lệ',
      );
    }

    throw _httpError('MAL detail failed', res);
  }

  // ============================================================
  // SUPPORTED WEBSITES
  // ============================================================

  Future<List<String>> getSupportedWebsites() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/websites'),
    );

    if (res.statusCode != 200) {
      throw _httpError('Không thể lấy danh sách website', res);
    }

    final decoded = _decodeList(
      res.body,
      errorMessage: 'Danh sách website không hợp lệ',
    );

    return decoded.map((item) {
      if (item is Map) {
        return item['name']?.toString() ?? '';
      }

      return item.toString();
    }).where((name) => name.isNotEmpty).toList();
  }

  // ============================================================
  // CHECK STORY UPDATES
  // ============================================================

  // Bắt đầu kiểm tra một truyện.
  Future<Map<String, dynamic>> checkStoryUpdates(int storyId) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/check-update/$storyId'),
    );

    if (res.statusCode == 202 || res.statusCode == 200) {
      return _decodeMap(
        res.body,
        errorMessage: 'Dữ liệu kiểm tra cập nhật không hợp lệ',
      );
    }

    throw _httpError('Không thể kiểm tra truyện', res);
  }

  // Bắt đầu kiểm tra tất cả truyện.
  Future<Map<String, dynamic>> checkAllStoryUpdates() async {
    final res = await http.post(
      Uri.parse('$_baseUrl/check-update'),
    );

    if (res.statusCode == 202 || res.statusCode == 200) {
      return _decodeMap(
        res.body,
        errorMessage: 'Dữ liệu kiểm tra cập nhật không hợp lệ',
      );
    }

    throw _httpError('Không thể kiểm tra tất cả truyện', res);
  }

  // Lấy danh sách task kiểm tra cập nhật.
  Future<List<Map<String, dynamic>>> getUpdateCheckTasks() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/check-updates/tasks'),
    );

    if (res.statusCode != 200) {
      throw _httpError('Không thể lấy danh sách task', res);
    }

    final decoded = _decodeList(
      res.body,
      errorMessage: 'Danh sách task không hợp lệ',
    );

    return decoded.map(_toMap).toList();
  }

  // Lấy chi tiết tiến độ và kết quả của một task.
  Future<Map<String, dynamic>> getUpdateCheckTask(String taskId) async {
    final res = await http.get(
      Uri.parse(
        '$_baseUrl/check-updates/tasks/'
            '${Uri.encodeComponent(taskId)}',
      ),
    );

    if (res.statusCode != 200) {
      throw _httpError('Không thể lấy task $taskId', res);
    }

    return _decodeMap(
      res.body,
      errorMessage: 'Dữ liệu task không hợp lệ',
    );
  }

  // ============================================================
  // BUILD NEW CHAPTERS PAYLOAD
  // ============================================================

  Map<String, dynamic> buildNewChaptersPayload(
      Map<String, dynamic> result,
      ) {
    final rawChapters = result['chapters'];

    if (rawChapters != null && rawChapters is! List) {
      throw const FormatException(
        'Dữ liệu chapters phải là một danh sách',
      );
    }

    final chapters = (rawChapters as List? ?? [])
        .map((item) {
      final chapter = _toMap(item);

      return <String, dynamic>{
        // Giữ nguyên tất cả thông tin chapter từ backend.
        ...chapter,

        // Đảm bảo các chapter mới được chọn.
        'choosen': true,
      };
    })
        .toList();

    if (chapters.isEmpty) {
      throw Exception('Truyện không có chapter mới');
    }

    return <String, dynamic>{
      // Giữ nguyên toàn bộ thông tin truyện do crawler trả về.
      ...result,

      // Các trường tương thích với API import hiện tại.
      'title': result['storyTitle'] ?? result['title'],
      'sourceUrl': result['sourceUrl'],
      'selectedStoryId': result['storyId'] ?? result['selectedStoryId'],
      'chapters': chapters,
    };
  }

  // ============================================================
  // CRAWL NEW CHAPTERS
  // ============================================================

  Future<Map<String, dynamic>> crawlNewChapters(
      Map<String, dynamic> result,
      int userId,
      ) async {
    return importStory(
      buildNewChaptersPayload(result),
      userId,
    );
  }

  // ============================================================
  // SEARCH STORIES
  // ============================================================

  Future<List<Map<String, dynamic>>> searchStories(
      String website,
      String keyword,
      ) async {
    final uri = Uri.parse(
      '$_baseUrl/search',
    ).replace(
      queryParameters: {
        'website': website,
        'keyword': keyword.trim(),
      },
    );

    final res = await http.get(uri);

    if (res.statusCode == 200) {
      final decoded = _decodeList(
        res.body,
        errorMessage: 'Dữ liệu tìm kiếm không hợp lệ',
      );

      return decoded.map(_toMap).toList();
    }

    throw _httpError('Search failed', res);
  }

  // ============================================================
  // IMPORT STORY
  // ============================================================

  Future<Map<String, dynamic>> importStory(
      Map<String, dynamic> data,
      int userId,
      ) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/import-selected'),
      headers: {
        'Content-Type': 'application/json',
        'userId': userId.toString(),
      },
      body: jsonEncode(data),
    );

    if (res.statusCode == 200) {
      return _decodeMap(
        res.body,
        errorMessage: 'Dữ liệu import không hợp lệ',
      );
    }

    throw _httpError('Import failed', res);
  }

  // ============================================================
  // GENERAL TASKS
  // ============================================================

  Future<Map<String, dynamic>> getAllTasks() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/tasks'),
    );

    if (res.statusCode == 200) {
      return _decodeMap(
        res.body,
        errorMessage: 'Dữ liệu tasks không hợp lệ',
      );
    }

    throw _httpError('Failed to get tasks', res);
  }

  Future<void> cancelTask(String taskId) async {
    final res = await http.post(
      Uri.parse(
        '$_baseUrl/cancel/${Uri.encodeComponent(taskId)}',
      ),
    );

    if (res.statusCode != 200) {
      throw _httpError('Cancel failed', res);
    }
  }
}
