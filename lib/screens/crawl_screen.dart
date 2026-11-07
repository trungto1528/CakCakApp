import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/metadata_provider.dart';
import '../services/crawl_service.dart';

class CrawlScreen extends StatefulWidget {
  final int userId;

  const CrawlScreen({super.key, required this.userId});

  @override
  State<CrawlScreen> createState() => _CrawlScreenState();
}

class _CrawlScreenState extends State<CrawlScreen> {
  final TextEditingController searchController = TextEditingController();
  final TextEditingController chapterRangeController = TextEditingController();

  final CrawlService crawlService = CrawlService();

  Map<String, dynamic>? data;

  List<Map<String, dynamic>> searchResults = [];
  List<String> websites = [];

  String? selectedWebsite;
  int? _selectedStoryId;

  bool _createNewStory = true;
  bool loading = false;
  bool searching = false;
  bool importing = false;
  bool loadingWebsites = false;

  Timer? _progressTimer;

  MetadataProvider? _metaProvider;

  String? _crawlUrlPending;

  // TruyenGGVN: ten goc va trang thai dung alternative name de hien thi tren UI.
  String? _crawlOriginalTitle;
  bool _crawlUsedAlternative = false;

  @override
  void initState() {
    super.initState();
    loadWebsites();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    searchController.dispose();
    chapterRangeController.dispose();
    super.dispose();
  }

  // =========================================================
  // HELPERS
  // =========================================================

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isCrawled(Map chapter) {
    return chapter['crawled'] == true ||
        chapter['crawled']?.toString().toLowerCase() == 'true' ||
        chapter['isCrawled'] == true ||
        chapter['isCrawled']?.toString().toLowerCase() == 'true';
  }

  bool _isTaskDone(String message) {
    final lower = message.toLowerCase();

    return message.contains('Hoàn thành') ||
        message.contains('Lỗi') ||
        lower.contains('hủy') ||
        lower.contains('huỷ');
  }

  List<dynamic> get chapters {
    return data?['chapters'] as List? ?? [];
  }

  List<Map<String, dynamic>> get selectedChapters {
    return chapters
        .where((chapter) {
          final map = chapter as Map;
          return !_isCrawled(map) && map['choosen'] == true;
        })
        .map<Map<String, dynamic>>((chapter) {
          return Map<String, dynamic>.from(chapter as Map);
        })
        .toList();
  }

  String _getWebsiteReferer(String? url) {
    if (url == null || url.trim().isEmpty) {
      return 'https://www.mangahere.cc/';
    }

    final uri = Uri.tryParse(url.trim());

    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'https://www.mangahere.cc/';
    }

    return '${uri.scheme}://${uri.authority}/';
  }

  Map<String, String> _imageHeaders(String? storyUrl) {
    return {
      'Referer': _getWebsiteReferer(storyUrl),
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/146.0.0.0 Safari/537.36',
    };
  }

  String _getResultUrl(Map<String, dynamic> result) {
    return result['url']?.toString().trim() ??
        result['storyUrl']?.toString().trim() ??
        '';
  }

  int? _readStoryId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  List<String> _parseAllTitles(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value.whereType<String>().toList();
    }
    if (value is String) {
      if (value.isEmpty) return const [];
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.whereType<String>().toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  Map<String, List<String>> _parseAllTitlesByLocale(dynamic value) {
    final result = <String, List<String>>{};
    if (value == null) return result;
    if (value is Map) {
      value.forEach((k, v) {
        final locale = k.toString();
        if (v is List) {
          result[locale] = v.whereType<String>().toList();
        } else if (v is String) {
          result[locale] = [v];
        }
      });
    }
    if (value is String) {
      if (value.isEmpty) return result;
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final locale = k.toString();
            if (v is List) {
              result[locale] = v.whereType<String>().toList();
            } else if (v is String) {
              result[locale] = [v];
            }
          });
        }
      } catch (_) {}
    }
    return result;
  }

  String _localeLabel(String locale) {
    switch (locale) {
      case 'vi':
        return 'Tên (vi)';
      case 'en':
        return 'Tên (en)';
      case 'ja':
        return 'Tên (ja)';
      case 'ja-ro':
        return 'Tên (ja-ro)';
      case 'zh':
        return 'Tên (zh)';
      case 'zh-ro':
        return 'Tên (zh-ro)';
      case 'ko':
        return 'Tên (ko)';
      default:
        return 'Tên ($locale)';
    }
  }

  // =========================================================
  // CHAPTER RANGE SELECTION
  // =========================================================

  /// Phân tích khoảng theo số thứ tự trong danh sách.
  ///
  /// Ví dụ:
  /// 1-20
  /// 1-20,30-50
  /// 1-10,15,20-25
  /// 30-10
  ///
  /// Không đọc số chương từ title hoặc chapterNumber.
  /// Số thứ tự được xác định bằng vị trí trong danh sách,
  /// bắt đầu từ 1.
  ///
  /// Dấu phẩy và dấu chấm phẩy đều được hỗ trợ.
  List<(int, int)>? _parseChapterRanges(String input) {
    final text = input.trim();

    if (text.isEmpty) return null;

    final parts = text.split(RegExp(r'[,;，；]'));
    final ranges = <(int, int)>[];

    for (final rawPart in parts) {
      final part = rawPart.trim();

      if (part.isEmpty) {
        throw FormatException(
          'Có khoảng chương bị bỏ trống. '
          'Ví dụ hợp lệ: 1-20,30-50',
        );
      }

      final match = RegExp(r'^(\d+)\s*(?:-\s*(\d+))?$').firstMatch(part);

      if (match == null) {
        throw FormatException(
          'Khoảng "$part" không hợp lệ. '
          'Ví dụ: 1-20,30-50,60',
        );
      }

      final start = int.parse(match.group(1)!);
      final end = match.group(2) == null ? start : int.parse(match.group(2)!);

      if (start < 1 || end < 1) {
        throw FormatException('Số thứ tự chương phải bắt đầu từ 1: "$part"');
      }

      ranges.add((start <= end ? start : end, start <= end ? end : start));
    }

    return ranges.isEmpty ? null : ranges;
  }

  /// Áp dụng khoảng theo vị trí của chương trong danh sách.
  ///
  /// Chương đã crawl luôn bị bỏ chọn.
  void applyChapterRanges() {
    if (data == null) return;

    try {
      final ranges = _parseChapterRanges(chapterRangeController.text);

      if (ranges == null) {
        _showSnackBar('Vui lòng nhập khoảng chương, ví dụ: 1-20,30-50');
        return;
      }

      int selectedCount = 0;
      int crawledCount = 0;

      setState(() {
        for (int i = 0; i < chapters.length; i++) {
          final chapter = chapters[i] as Map;
          final chapterOrder = i + 1;

          if (_isCrawled(chapter)) {
            chapter['choosen'] = false;
            crawledCount++;
            continue;
          }

          final matched = ranges.any(
            (range) => chapterOrder >= range.$1 && chapterOrder <= range.$2,
          );

          chapter['choosen'] = matched;

          if (matched) {
            selectedCount++;
          }
        }
      });

      var message = 'Đã chọn $selectedCount chương theo số thứ tự';

      if (crawledCount > 0) {
        message += ', bỏ qua $crawledCount chương đã crawl';
      }

      _showSnackBar(message);
    } on FormatException catch (e) {
      _showSnackBar(e.message);
    } catch (e) {
      _showSnackBar('Lỗi xử lý khoảng chương: $e');
    }
  }

  void _clearChapterRanges() {
    chapterRangeController.clear();

    if (mounted) {
      setState(() {});
    }
  }

  // =========================================================
  // LOAD WEBSITES
  // =========================================================

  Future<void> loadWebsites() async {
    setState(() {
      loadingWebsites = true;
    });

    try {
      final results = await crawlService.getSupportedWebsites();

      if (!mounted) return;

      setState(() {
        websites = results.where((name) => name.isNotEmpty).toSet().toList();

        if (!websites.contains(selectedWebsite)) {
          selectedWebsite = websites.isNotEmpty ? websites.first : null;
        }
      });

      if (websites.isEmpty) {
        _showSnackBar('Backend chưa đăng ký website cào nào');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Lỗi tải danh sách website: $e');
    } finally {
      if (mounted) {
        setState(() {
          loadingWebsites = false;
        });
      }
    }
  }

  // =========================================================
  // SEARCH
  // =========================================================

  Future<void> searchStories() async {
    final keyword = searchController.text.trim();
    final website = selectedWebsite;

    if (website == null || website.isEmpty) {
      _showSnackBar('Vui lòng chọn website');
      return;
    }

    if (keyword.isEmpty) {
      _showSnackBar('Vui lòng nhập tên truyện');
      return;
    }

    if (searching) return;

    FocusScope.of(context).unfocus();

    setState(() {
      searching = true;
      searchResults = [];
      data = null;
      _selectedStoryId = null;
      _createNewStory = true;
      chapterRangeController.clear();
      _crawlUrlPending = null;
    });

    try {
      final results = await crawlService.searchStories(website, keyword);

      if (!mounted) return;

      setState(() {
        searchResults = results;
      });

      if (results.isEmpty) {
        _showSnackBar('Không tìm thấy truyện trên $website');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Lỗi tìm truyện: $e');
    } finally {
      if (mounted) {
        setState(() {
          searching = false;
        });
      }
    }
  }

  // =========================================================
  // SELECT SEARCH RESULT
  // =========================================================
  Future<void> selectSearchResult(Map<String, dynamic> result) async {
    final url = _getResultUrl(result);

    if (url.isEmpty) {
      print('[CrawlScreen][selectSearchResult] Khong co URL truyen');
      _showSnackBar('Khong co URL truyen');
      return;
    }

    print(
      '[CrawlScreen][selectSearchResult] url=$url title=${result['title']}',
    );

    if (loading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      loading = true;
      data = null;
      _selectedStoryId = null;
      _createNewStory = true;
      chapterRangeController.clear();
      _metaProvider = null;
      _crawlOriginalTitle = null;
      _crawlUsedAlternative = false;
    });

    _crawlUrlPending = url;

    Map<String, dynamic>? preCrawledData;
    String? alternativeName;
    bool alternativeUsed = false;
    String? originalTitle;

    try {
      final title = result['title']?.toString().trim() ?? '';
      final isTruyenGGVN = selectedWebsite == 'TruyenGGVN';

      // TruyenGGVN: crawl truoc de lay alternative name (ten khac) neu can.
      if (isTruyenGGVN) {
        print(
          '[CrawlScreen][selectSearchResult] TruyenGGVN: crawl lay thong tin truoc url=$url',
        );
        preCrawledData = await crawlService.crawlStory(url);
        if (!mounted) return;
        alternativeName = _extractAlternativeName(preCrawledData);
        print(
          '[CrawlScreen][selectSearchResult] TruyenGGVN alternativeName=$alternativeName',
        );
      }

      print(
        '[CrawlScreen][selectSearchResult] goi searchMangaDex title="$title"',
      );
      final mdResult = await crawlService.searchMangaDex(title);
      if (!mounted) return;

      final mdStatus = mdResult['status']?.toString() ?? '';
      print(
        '[CrawlScreen][selectSearchResult] MangaDex status=$mdStatus mangaDexId=${mdResult['mangaDexId']} resultsCount=${(mdResult['results'] as List?)?.length ?? 0}',
      );

      // MangaDex la chinh.
      if (mdStatus == 'DIRECT_MATCH') {
        final mangaDexId = mdResult['mangaDexId']?.toString();
        print(
          '[CrawlScreen][selectSearchResult] MangaDex DIRECT_MATCH mangaDexId=$mangaDexId',
        );
        if (mangaDexId != null && mangaDexId.isNotEmpty) {
          _metaProvider = MetadataProvider.mangaDex;
          await _loadMangaDexDetail(
            mangaDexId,
            preCrawledData: preCrawledData,
            originalTitle: originalTitle,
          );
          if (!mounted) return;
          return;
        }
      } else if (mdStatus == 'MULTIPLE_RESULTS') {
        final results = mdResult['results'] as List?;
        final resultsCount = results?.length ?? 0;
        print(
          '[CrawlScreen][selectSearchResult] MangaDex MULTIPLE_RESULTS resultsCount=$resultsCount',
        );
        if (results != null && results.isNotEmpty) {
          final candidates = results
              .map<Map<String, dynamic>>(
                (item) => Map<String, dynamic>.from(item as Map),
              )
              .toList();

          setState(() {
            _metaProvider = MetadataProvider.mangaDex;
          });
        }
      } else {
        print(
          '[CrawlScreen][selectSearchResult] MangaDex status khac ($mdStatus)',
        );
      }

      // Neu MangaDex khong co ket qua hoac loi, fetch chapters bang website data.
      print(
        '[CrawlScreen][selectSearchResult] MangaDex khong co DIRECT_MATCH -> fetchChapters',
      );
      await _fetchChapters(
        url,
        preCrawledData: preCrawledData,
        originalTitle: originalTitle,
      );
    } catch (e) {
      if (!mounted) return;
      print('[CrawlScreen][selectSearchResult] Loi: $e');
      _showSnackBar('Loi tim: $e');
      await _fetchChapters(
        url,
        preCrawledData: preCrawledData,
        originalTitle: originalTitle,
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _fetchChapters(
    String url, {
    Map<String, dynamic>? preCrawledData,
    String? originalTitle,
    Map<String, dynamic>? mangaDexInfo,
    String? mangaDexId,
  }) async {
    print(
      '[CrawlScreen][_fetchChapters] bat dau url=$url preCrawled=${preCrawledData != null}',
    );
    try {
      Map<String, dynamic> normalizedData;
      if (preCrawledData != null) {
        normalizedData = Map<String, dynamic>.from(preCrawledData);
        print(
          '[CrawlScreen][_fetchChapters] su du lieu da crawl truoc chaptersCount=${(normalizedData['chapters'] as List?)?.length ?? 0}',
        );
      } else {
        final resultData = await crawlService.crawlStory(url);
        if (!mounted) return;
        normalizedData = Map<String, dynamic>.from(resultData);
        print(
          '[CrawlScreen][_fetchChapters] crawlStory xong chaptersCount=${(normalizedData['chapters'] as List?)?.length ?? 0} url=${normalizedData['url']} cover=${normalizedData['cover']} coverUrl=${normalizedData['coverUrl']}',
        );
      }
      normalizedData['url'] ??= url;
      final rawCover = normalizedData['cover']?.toString().trim();
      if (rawCover == null || rawCover.isEmpty) {
        normalizedData['cover'] =
            normalizedData['coverUrl']?.toString().trim() ?? '';
      }

      normalizedData['chapters'] = (normalizedData['chapters'] as List? ?? [])
          .map((rawChapter) {
            final chapter = Map<String, dynamic>.from(rawChapter as Map);
            final isCrawled = _isCrawled(chapter);
            chapter['crawled'] = isCrawled;
            chapter['choosen'] = !isCrawled;
            return chapter;
          })
          .toList();

      final initialStoryId = _readStoryId(normalizedData['selectedStoryId']);

      if (mangaDexId != null && mangaDexId.isNotEmpty && mangaDexInfo != null) {
        final mdInfo = MetadataInfo.fromMangaDex(mangaDexInfo);
        _mergeMetadata(normalizedData, mdInfo);
        normalizedData['mangaDexId'] = mangaDexId;
        normalizedData['mangaDexInfo'] = mangaDexInfo;
        normalizedData['provider'] = 'MangaDex';
      }

      if (!mounted) return;
      setState(() {
        data = normalizedData;
        _selectedStoryId = initialStoryId;
        _createNewStory = initialStoryId == null;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Loi lay chuong tu website: $e');
    }
  }

  /// Gộp metadata từ provider vào payload crawl.
  void _mergeMetadata(Map<String, dynamic> data, MetadataInfo info) {
    data['provider'] = info.provider.label;

    if (info.provider == MetadataProvider.mangaDex) {
      data['mangaDexId'] = info.providerId;
    }

    data['title'] = info.title;

    // Giữ nguyên cover từ source crawler, không ghi đè bằng cover MangaDex.
    data['description'] = info.synopsis;
    data['author'] = info.authors;
  }

  /// Trich xuat alternative name tu thong tin website da crawl.
  String? _extractAlternativeName(Map<String, dynamic> data) {
    final information = data['information'];
    if (information is List) {
      for (final item in information) {
        if (item is Map) {
          final label = item['label']?.toString().trim();
          if (label == 'Alternative Name') {
            final value = item['value'];
            if (value != null && value.toString().trim().isNotEmpty) {
              return value.toString().trim();
            }
          }
        }
      }
    }
    return null;
  }

  Future<void> _loadMangaDexDetail(
    String mangaDexId, {
    Map<String, dynamic>? preCrawledData,
    String? originalTitle,
  }) async {
    print(
      '[CrawlScreen][_loadMangaDexDetail] bat dau mangaDexId=$mangaDexId pendingUrl=$_crawlUrlPending',
    );
    setState(() {
      _metaProvider = MetadataProvider.mangaDex;
    });
    try {
      final detail = await crawlService.getMangaDexDetail(mangaDexId);
      if (!mounted) return;

      print(
        '[CrawlScreen][_loadMangaDexDetail] detail nhan duoc mangaDexId=${detail['mangaDexId']} title=${detail['title']} keys=${detail.keys.toList()}',
      );

      final pendingUrl = _crawlUrlPending;
      print('[CrawlScreen][_loadMangaDexDetail] pendingUrl=$pendingUrl');
      if (pendingUrl != null && mounted) {
        _crawlUrlPending = null;
        await _fetchChapters(
          pendingUrl,
          mangaDexInfo: detail,
          mangaDexId: mangaDexId,
          preCrawledData: preCrawledData,
          originalTitle: originalTitle,
        );
      }
    } catch (e) {
      if (!mounted) return;
      print('[CrawlScreen][_loadMangaDexDetail] Loi lay chi tiet MangaDex: $e');
      _showSnackBar('Loi lay chi tiet MangaDex: $e');
      final pendingUrl = _crawlUrlPending;
      if (pendingUrl != null && mounted) {
        _crawlUrlPending = null;
        await _fetchChapters(
          pendingUrl,
          mangaDexInfo: null,
          mangaDexId: null,
          preCrawledData: preCrawledData,
          originalTitle: originalTitle,
        );
      }
    }
  }

  void backToSearch() {
    setState(() {
      data = null;
      searchResults = [];
      _selectedStoryId = null;
      _createNewStory = true;
      chapterRangeController.clear();

      _crawlUrlPending = null;
      _crawlOriginalTitle = null;
      _crawlUsedAlternative = false;
      _metaProvider = null;
    });
  }

  // =========================================================
  // CHAPTER SELECTION
  // =========================================================

  void selectAll(bool value) {
    if (data == null) return;

    setState(() {
      for (final rawChapter in chapters) {
        final chapter = rawChapter as Map;

        if (_isCrawled(chapter)) {
          chapter['choosen'] = false;
        } else {
          chapter['choosen'] = value;
        }
      }
    });
  }

  void toggle(Map chapter, bool value) {
    if (_isCrawled(chapter)) return;

    setState(() {
      chapter['choosen'] = value;
    });
  }

  // =========================================================
  // IMPORT
  // =========================================================

  Future<void> submit() async {
    if (data == null || selectedChapters.isEmpty) {
      _showSnackBar('Vui lòng chọn ít nhất 1 chương chưa crawl');
      return;
    }

    if (!_createNewStory && _selectedStoryId == null) {
      _showSnackBar('Vui lòng chọn truyện cần gộp hoặc tạo truyện mới');
      return;
    }

    if (importing) return;

    setState(() {
      importing = true;
    });

    try {
      final payload = Map<String, dynamic>.from(data!);

      // MangaDex co uu tien cao nhat.
      if (payload['mangaDexInfo'] != null && payload['mangaDexInfo'] is Map) {
        final completeMdInfo = Map<String, dynamic>.from(
          payload['mangaDexInfo'] as Map,
        );

        payload['mangaDexInfo'] = completeMdInfo;
        payload['mangaDexId'] =
            completeMdInfo['mangaDexId'] ??
            completeMdInfo['id'] ??
            payload['mangaDexId'];

        // Khi co MangaDex, CHI dung thong tin cua MangaDex, khong gop voi website.
        payload['title'] =
            completeMdInfo['title']?.toString() ?? completeMdInfo['title'];

        // Giu nguyen cover tu source crawler, khong ghi de boi cover MangaDex.

        payload['description'] =
            completeMdInfo['synopsis']?.toString() ??
            completeMdInfo['synopsis'];

        payload['author'] =
            completeMdInfo['authors']?.toString() ?? completeMdInfo['authors'];

        // Khong them field MangaDex vao payload['information'].
        // MangaDex da duoc luu day du trong payload['mangaDexInfo'].
        // information chi giu lai thong tin do website crawler tra ve.
      }

      payload['chapters'] = selectedChapters;

      payload['selectedStoryId'] = _createNewStory ? null : _selectedStoryId;

      final res = await crawlService.importStory(payload, widget.userId);

      final taskId = res['taskId']?.toString();

      if (taskId == null || taskId.isEmpty || taskId == 'null') {
        _showSnackBar('Không nhận được taskId từ server');
        return;
      }

      if (!mounted) return;

      _showProgressSheet(taskId);
    } catch (e) {
      if (mounted) {
        _showSnackBar('Lỗi Import: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          importing = false;
        });
      }
    }
  }

  // =========================================================
  // SNACKBAR
  // =========================================================

  void _showSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // =========================================================
  // TASK LIST
  // =========================================================

  void _showAllTasksSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.75,
          child: FutureBuilder<Map<String, dynamic>>(
            future: crawlService.getAllTasks(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Lỗi: ${snapshot.error}'));
              }

              final tasks = snapshot.data ?? {};

              if (tasks.isEmpty) {
                return const Center(child: Text('Không có tiến trình nào'));
              }

              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Danh sách tiến độ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final taskId = tasks.keys.elementAt(index);

                        final task = Map<String, dynamic>.from(
                          tasks[taskId] as Map,
                        );

                        final processed = _asInt(task['processed']);
                        final total = _asInt(task['total']);

                        final double progress = total > 0
                            ? (processed / total).clamp(0.0, 1.0)
                            : 0.0;

                        final message = task['message']?.toString() ?? '';

                        final isDone = _isTaskDone(message);

                        return ListTile(
                          title: Text(
                            task['title']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: progress),
                              const SizedBox(height: 4),
                              Text('$processed/$total - $message'),
                            ],
                          ),
                          trailing: isDone
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.stop_circle_outlined,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Hủy task',
                                  onPressed: () async {
                                    try {
                                      await crawlService.cancelTask(
                                        taskId.toString(),
                                      );

                                      if (!sheetContext.mounted) return;

                                      Navigator.pop(sheetContext);
                                      _showAllTasksSheet();
                                    } catch (e) {
                                      _showSnackBar('Lỗi hủy task: $e');
                                    }
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                      },
                      child: const Text('Đóng'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // =========================================================
  // PROGRESS
  // =========================================================

  void _showProgressSheet(String taskId) {
    _progressTimer?.cancel();

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _ProgressSheetContent(
          taskId: taskId,
          crawlService: crawlService,
          onCancel: () async {
            try {
              await crawlService.cancelTask(taskId);

              _progressTimer?.cancel();

              if (!sheetContext.mounted) return;

              Navigator.pop(sheetContext);
              _showSnackBar('Đã gửi yêu cầu dừng.');
            } catch (e) {
              _showSnackBar('Lỗi hủy task: $e');
            }
          },
          onClose: () {
            _progressTimer?.cancel();

            if (sheetContext.mounted) {
              Navigator.pop(sheetContext);
            }
          },
        );
      },
    ).whenComplete(() {
      _progressTimer?.cancel();
      _progressTimer = null;
    });
  }

  // =========================================================
  // SEARCH RESULTS
  // =========================================================

  Widget _buildSearchResults() {
    if (searching || loadingWebsites) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    if (websites.isEmpty) {
      return const Expanded(
        child: Center(child: Text('Không có website được hỗ trợ')),
      );
    }

    if (searchResults.isEmpty) {
      return const Expanded(
        child: Center(child: Text('Nhập tên truyện để tìm kiếm')),
      );
    }

    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: searchResults.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final result = searchResults[index];

          final title = result['title']?.toString() ?? '';
          final cover = result['cover']?.toString() ?? '';
          final storyUrl = _getResultUrl(result);

          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.all(8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: cover.isNotEmpty
                    ? Image.network(
                        cover,
                        headers: _imageHeaders(storyUrl),
                        width: 60,
                        height: 85,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return _searchCoverPlaceholder();
                        },
                      )
                    : _searchCoverPlaceholder(),
              ),
              title: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(selectedWebsite ?? 'Chưa chọn website'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: loading ? null : () => selectSearchResult(result),
            ),
          );
        },
      ),
    );
  }

  Widget _searchCoverPlaceholder() {
    return Container(
      width: 60,
      height: 85,
      color: Colors.grey[300],
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }

  // =========================================================
  // CHAPTER RANGE UI
  // =========================================================

  Widget _buildChapterRangeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.filter_list),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chọn chương theo khoảng',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: chapterRangeController,
                enabled: !importing,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!importing && !loading) {
                    applyChapterRanges();
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Ví dụ: 1-20,30-50,60',
                  helperText: 'Khoảng được tính theo số thứ tự trong danh sách',
                  prefixIcon: const Icon(Icons.format_list_numbered),
                  suffixIcon: IconButton(
                    tooltip: 'Xóa nội dung',
                    onPressed: importing ? null : _clearChapterRanges,
                    icon: const Icon(Icons.clear),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: importing || loading ? null : applyChapterRanges,
                  icon: const Icon(Icons.checklist),
                  label: const Text('Áp dụng khoảng chương'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Đã chọn ${selectedChapters.length}/${chapters.length} chương',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final chapterList = chapters;

    print(
      '[CrawlScreen][build] data null=${data == null} loading=$loading searching=$searching',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cào truyện'),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined),
            tooltip: 'Tiến độ cào',
            onPressed: _showAllTasksSheet,
          ),
          if (data != null)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Tìm truyện khác',
              onPressed: loading ? null : backToSearch,
            ),
        ],
      ),
      floatingActionButton: data == null
          ? null
          : FloatingActionButton.extended(
              onPressed: importing ? null : submit,
              icon: importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download),
              label: Text(
                importing
                    ? 'Đang import...'
                    : 'Import (${selectedChapters.length})',
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<String>(
              initialValue: selectedWebsite,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Website cần cào',
                prefixIcon: const Icon(Icons.language),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              hint: const Text('Chọn website'),
              items: websites.map((website) {
                return DropdownMenuItem<String>(
                  value: website,
                  child: Text(website),
                );
              }).toList(),
              onChanged: loadingWebsites || loading || importing
                  ? null
                  : (value) {
                      setState(() {
                        selectedWebsite = value;
                        searchResults = [];
                        data = null;
                        _selectedStoryId = null;
                        _createNewStory = true;
                        chapterRangeController.clear();
                        _crawlUrlPending = null;
                      });
                    },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Nhập tên truyện',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: searching || loadingWebsites || loading
                      ? null
                      : searchStories,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) {
                if (!searching && !loadingWebsites && !loading) {
                  searchStories();
                }
              },
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (data == null) _buildSearchResults(),
          if (data != null)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  _buildStoryHeader(),
                  _buildMalInfo(),
                  _buildInformation(),
                  _buildChapterRangeSelector(),
                  _buildActionButtons(),
                  _buildChapterList(chapterList),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _malCoverPlaceholder() {
    return Container(
      width: 90,
      height: 130,
      color: Colors.grey[300],
      child: const Icon(
        Icons.image_not_supported,
        size: 30,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildMalInfo() {
    final mangaDexInfo = data?['mangaDexInfo'];
    if (mangaDexInfo == null) {
      return const SizedBox.shrink();
    }

    final title = mangaDexInfo['title']?.toString() ?? '';
    final japaneseTitle = mangaDexInfo['japaneseTitle']?.toString() ?? '';
    final authors = mangaDexInfo['authors']?.toString() ?? '';
    final type = mangaDexInfo['type']?.toString() ?? '';
    final status = mangaDexInfo['status']?.toString() ?? '';
    final cover = data?['cover']?.toString() ??
        mangaDexInfo['cover']?.toString() ?? '';
    final isMangaDexCover = cover.contains('mangadex.org');
    print(
      '[CrawlScreen][_buildMalInfo] cover value="$cover" isMangaDex=$isMangaDexCover',
    );
    final score = mangaDexInfo['score']?.toString() ?? '';
    final genresRaw = mangaDexInfo['genres'];
    final genres = genresRaw is List
        ? genresRaw.whereType<String>().toList()
        : (genresRaw?.toString() ?? '')
              .split(',')
              .where((s) => s.isNotEmpty)
              .toList();
    final crawlOriginalTitle = _crawlUsedAlternative
        ? _crawlOriginalTitle
        : null;
    final mangaDexId = mangaDexInfo['mangaDexId']?.toString() ?? '';
    final allTitlesRaw = mangaDexInfo['allTitles'];
    final allTitlesByLocale = _parseAllTitlesByLocale(allTitlesRaw);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: cover + main title.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StoryCoverWidget(
                    coverUrl: cover,
                    isMangaDex: isMangaDexCover,
                    storyUrl: mangaDexInfo['url']?.toString() ?? '',
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'MangaDex',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (score.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star,
                                    color: Colors.amber,
                                    size: 17,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    score,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title.isEmpty ? 'Chưa có tiêu đề' : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Japanese title.
              if (japaneseTitle.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildMalMetadataRow(
                  icon: Icons.translate,
                  label: 'Japanese Title',
                  value: japaneseTitle,
                ),
              ],

              // TruyenGGVN ten goc (luu thanh Alternative Name).
              if (crawlOriginalTitle != null &&
                  crawlOriginalTitle.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildMalMetadataRow(
                  icon: Icons.title_outlined,
                  label: 'Tên gốc',
                  value: crawlOriginalTitle,
                ),
              ],

              // Authors.
              if (authors.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildMalMetadataRow(
                  icon: Icons.person_outline,
                  label: 'Authors',
                  value: authors,
                ),
              ],

              // Type and status.
              if (type.isNotEmpty || status.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (type.isNotEmpty)
                      _buildMalBadge(icon: Icons.category_outlined, text: type),
                    if (status.isNotEmpty)
                      _buildMalBadge(
                        icon: Icons.check_circle_outline,
                        text: status,
                        color: status.toLowerCase() == 'finished'
                            ? Colors.green
                            : null,
                      ),
                  ],
                ),
              ],

              // Genres.
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildMalSectionTitle(
                  icon: Icons.local_offer_outlined,
                  title: 'Genres',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: genres.map((genre) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        genre,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Provider ID and URL.
              if (mangaDexId.isNotEmpty ||
                  mangaDexInfo['url']?.toString().isNotEmpty == true) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (mangaDexId.isNotEmpty)
                      Expanded(
                        child: Text(
                          'MangaDex ID: $mangaDexId',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (mangaDexInfo['url']?.toString().isNotEmpty == true)
                      TextButton.icon(
                        onPressed: () {
                          final url = mangaDexInfo['url']?.toString() ?? '';

                          _showSnackBar('MangaDex URL: $url');
                        },
                        icon: const Icon(Icons.link, size: 15),
                        label: Text('MangaDex'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ],

              // All title variants grouped by locale, hien thi label: value.
              if (allTitlesByLocale.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildMalSectionTitle(icon: Icons.title, title: 'Tất cả tên'),
                const SizedBox(height: 8),
                ...allTitlesByLocale.entries.expand((entry) {
                  final locale = entry.key;
                  final titles = entry.value;
                  final label = _localeLabel(locale);
                  return <Widget>[
                    ...titles.map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        child: _buildMalMetadataRow(
                          icon: Icons.title,
                          label: label,
                          value: t,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ];
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // STORY HEADER (WEBSITE FALLBACK)
  // =========================================================

  /// Hiển thị tiêu đề và bìa từ website khi không có MangaDex.
  Widget _buildStoryHeader() {
    if (data?['mangaDexInfo'] != null) return const SizedBox.shrink();

    final title = data?['title']?.toString().trim() ?? '';
    final coverFromData = data?['cover']?.toString().trim() ?? '';
    final coverFromUrl = data?['coverUrl']?.toString().trim() ?? '';
    final cover = coverFromData.isNotEmpty ? coverFromData : coverFromUrl;

    if (title.isEmpty && cover.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: cover.isNotEmpty
                        ? Image.network(
                            cover,
                            headers: _imageHeaders(data?['url']),
                            width: 90,
                            height: 130,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) {
                              return _storyCoverPlaceholder();
                            },
                          )
                        : _storyCoverPlaceholder(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title.isEmpty ? 'Không có tiêu đề' : title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storyCoverPlaceholder() {
    return Container(
      width: 90,
      height: 130,
      color: Colors.grey[300],
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.grey,
        size: 30,
      ),
    );
  }

  Widget _buildMalMetadataRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Colors.grey[600]),
        const SizedBox(width: 8),
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMalBadge({
    required IconData icon,
    required String text,
    Color? color,
  }) {
    final badgeColor = color ?? Colors.grey[700]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: badgeColor),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: badgeColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMalSectionTitle({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // =========================================================
  // DESCRIPTION
  // =========================================================

  // =========================================================
  // INFORMATION
  // =========================================================

  String _formatMalValue(dynamic value) {
    if (value == null) return '';

    if (value is String) {
      return value.trim();
    }

    if (value is num || value is bool) {
      return value.toString();
    }

    if (value is List) {
      return value
          .map((item) => _formatMalValue(item))
          .where((item) => item.isNotEmpty)
          .join(', ');
    }

    if (value is Map) {
      return value.entries
          .map((entry) {
            final key = entry.key.toString().trim();
            final content = _formatMalValue(entry.value);

            if (key.isEmpty || content.isEmpty) return '';

            return '$key: $content';
          })
          .where((item) => item.isNotEmpty)
          .join('\n');
    }

    return value.toString();
  }

  Widget _buildInformation() {
    // Khi đã có MangaDex, không hiển thị thêm thông tin từ website source.
    if (data?['mangaDexInfo'] != null) {
      return const SizedBox.shrink();
    }

    final rawWebsiteInfo = data?['information'];
    final Map<String, String> infoMap = {};

    if (rawWebsiteInfo is List) {
      for (final item in rawWebsiteInfo) {
        if (item is Map) {
          final label = item['label']?.toString().trim();
          final value = _formatMalValue(item['value']);
          if (label != null && label.isNotEmpty && value.isNotEmpty) {
            infoMap[label] = value;
          }
        }
      }
    } else if (rawWebsiteInfo is Map) {
      for (final entry in rawWebsiteInfo.entries) {
        final label = entry.key.toString().trim();
        final value = _formatMalValue(entry.value);
        if (label.isNotEmpty && value.isNotEmpty) {
          infoMap[label] = value;
        }
      }
    }

    final genres = infoMap['Genres'];

    // Tìm tác giả theo key chứa "author" (không phân biệt hoa thường).
    String? authors;
    for (final entry in infoMap.entries) {
      if (entry.key.toLowerCase().contains('author')) {
        authors = entry.value.trim();
        break;
      }
    }

    // TruyenGGVN dùng "Đang Cập Nhật" làm placeholder cho tác giả → bỏ qua.
    final showAuthors =
        authors != null &&
        authors.isNotEmpty &&
        authors.toLowerCase() != 'đang cập nhật';

    // Các label vô nghĩa, bỏ hoàn toàn (Views, Likes, Follows, Status).
    final skippedLabels = {'Views', 'Likes', 'Follows', 'Status'};

    // Các field đã được đưa ra ngoài (genre, author) thì không còn hiển thị trong dropdown.
    final remainingKeys = infoMap.keys
        .where(
          (k) =>
              !skippedLabels.contains(k) &&
              k != 'Genres' &&
              !k.toLowerCase().contains('author'),
        )
        .toList();

    if ((genres == null || genres.isEmpty) &&
        !showAuthors &&
        remainingKeys.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Genres hiển thị thành chip (giống MAL).
              if (genres != null && genres.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildMalSectionTitle(
                  icon: Icons.local_offer_outlined,
                  title: 'Thể loại',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: genres.split(RegExp(r'[,;，；]')).map((g) {
                    final trimmed = g.trim();
                    if (trimmed.isEmpty) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        trimmed,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Tác giả (bỏ qua nếu là "Đang Cập Nhật").
              if (showAuthors) ...[
                const SizedBox(height: 16),
                _buildMalSectionTitle(
                  icon: Icons.info_outline,
                  title: 'Thông tin từ website',
                ),
                const SizedBox(height: 10),
                _buildMalMetadataRow(
                  icon: Icons.person_outline,
                  label: 'Tác giả',
                  value: authors!,
                ),
              ],

              // Các field còn lại giữ trong dropdown.
              if (remainingKeys.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    title: Text(
                      'Thông tin từ website (${remainingKeys.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          children: remainingKeys.map<Widget>((label) {
                            return _buildInfoRow(label, infoMap[label]!);
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // =========================================================
  // CHAPTER ACTIONS
  // =========================================================

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: importing ? null : () => selectAll(true),
            icon: const Icon(Icons.check_box),
            label: const Text('Tất cả'),
          ),
          TextButton.icon(
            onPressed: importing ? null : () => selectAll(false),
            icon: const Icon(Icons.check_box_outline_blank),
            label: const Text('Bỏ chọn'),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CHAPTER LIST
  // =========================================================

  Widget _buildChapterList(List chapterList) {
    if (chapterList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Truyện chưa có chương nào')),
      );
    }

    return Column(
      children: List.generate(chapterList.length, (index) {
        final chapterOrder = index + 1;
        final chapter = chapterList[index] as Map;

        final title = chapter['title']?.toString() ?? '';
        final isCrawled = _isCrawled(chapter);

        return ListTile(
          dense: true,
          leading: SizedBox(
            width: 40,
            height: 48,
            child: Center(
              child: isCrawled
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 24,
                    )
                  : Checkbox(
                      value: chapter['choosen'] == true,
                      activeColor: Colors.blue,
                      onChanged: importing
                          ? null
                          : (value) {
                              toggle(chapter, value ?? false);
                            },
                    ),
            ),
          ),
          title: Text(
            '$chapterOrder. $title',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isCrawled ? Colors.grey[600] : null),
          ),
          subtitle: Text(
            isCrawled ? 'Đã crawl' : 'Thứ tự $chapterOrder',
            style: TextStyle(
              color: isCrawled ? Colors.green : Colors.grey[600],
              fontSize: 12,
            ),
          ),
          onTap: isCrawled || importing
              ? null
              : () {
                  toggle(chapter, chapter['choosen'] != true);
                },
        );
      }),
    );
  }
}

// =============================================================
// MANGADEX IMAGE CACHE + RATE LIMIT GUARD
// =============================================================

/// Chặn request lặp lại khi MangaDex trả HTTP 429.
/// Cache thành công do CachedNetworkImage quản lý; cooldown này chỉ quản lý lỗi.
class _MangaDexCachedImage extends StatefulWidget {
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;

  const _MangaDexCachedImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<_MangaDexCachedImage> createState() => _MangaDexCachedImageState();
}

class _MangaDexCachedImageState extends State<_MangaDexCachedImage> {
  // MangaDex rate limit thường áp dụng theo host/IP, không chỉ từng URL.
  static final Map<String, DateTime> _hostBlockedUntil = {};

  // Lỗi mạng thông thường chỉ cooldown riêng URL để không ảnh hưởng ảnh khác.
  static final Map<String, DateTime> _urlFailedUntil = {};

  static const Duration _rateLimitCooldown = Duration(minutes: 10);
  static const Duration _networkErrorCooldown = Duration(minutes: 2);

  int _retryCount = 0;
  static const int _maxRetries = 3;
  late Key _imageKey;

  @override
  void initState() {
    super.initState();
    _imageKey = ValueKey('${widget.imageUrl}_$_retryCount');
  }

  String get _host {
    return Uri.tryParse(widget.imageUrl)?.host.toLowerCase() ?? '';
  }

  bool get _isCoolingDown {
    final now = DateTime.now();
    final hostUntil = _hostBlockedUntil[_host];
    final urlUntil = _urlFailedUntil[widget.imageUrl];

    if (hostUntil != null && now.isBefore(hostUntil)) return true;
    if (urlUntil != null && now.isBefore(urlUntil)) return true;

    if (hostUntil != null && !now.isBefore(hostUntil)) {
      _hostBlockedUntil.remove(_host);
    }
    if (urlUntil != null && !now.isBefore(urlUntil)) {
      _urlFailedUntil.remove(widget.imageUrl);
    }

    return false;
  }

  void _handleImageError(Object error) {
    final message = error.toString().toLowerCase();
    final isNetworkError =
        message.contains('socket') ||
        message.contains('connection') ||
        message.contains('reset') ||
        message.contains('timeout');
    final isRateLimited =
        message.contains('429') || message.contains('too many requests');

    final now = DateTime.now();

    if (isRateLimited) {
      final current = _hostBlockedUntil[_host];
      if (current == null || !now.isBefore(current)) {
        _hostBlockedUntil[_host] = now.add(_rateLimitCooldown);
        debugPrint(
          '[MangaDexImage] HTTP 429: block host=$_host '
          'for ${_rateLimitCooldown.inMinutes} minutes',
        );
      }
    } else if (isNetworkError && _retryCount < _maxRetries) {
      _retryCount++;
      debugPrint(
        '[MangaDexImage] Retry $_retryCount/$_maxRetries after network error: '
        '${widget.imageUrl}; error=$error',
      );
      Future.delayed(Duration(seconds: _retryCount * 2), () {
        if (!mounted) return;
        setState(() {
          _imageKey = ValueKey('${widget.imageUrl}_$_retryCount');
        });
      });
    } else {
      final current = _urlFailedUntil[widget.imageUrl];
      if (current == null || !now.isBefore(current)) {
        _urlFailedUntil[widget.imageUrl] = now.add(_networkErrorCooldown);
        debugPrint(
          '[MangaDexImage] Image failed; cooldown URL for '
          '${_networkErrorCooldown.inMinutes} minutes: ${widget.imageUrl}; '
          'error=$error',
        );
      }
    }
  }

  Widget _placeholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.grey,
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.isEmpty || _isCoolingDown) {
      return _placeholder();
    }

    return CachedNetworkImage(
      key: _imageKey,
      imageUrl: widget.imageUrl,
      cacheKey: widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, error) {
        _handleImageError(error);
        return _placeholder();
      },
    );
  }
}

// =============================================================
// STORY COVER WIDGET
// =============================================================

class _StoryCoverWidget extends StatefulWidget {
  final String coverUrl;
  final bool isMangaDex;
  final String storyUrl;

  _StoryCoverWidget({
    required this.coverUrl,
    required this.isMangaDex,
    required this.storyUrl,
  }) : super(key: ValueKey(coverUrl));

  @override
  State<_StoryCoverWidget> createState() => _StoryCoverWidgetState();
}

class _StoryCoverWidgetState extends State<_StoryCoverWidget> {
  String _coverUrl = ''; // bắt đầu rỗng → hiển thị placeholder, load chậm sau
  bool _coverLoaded = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[CrawlScreen][_StoryCoverWidget] initState coverUrl=${widget.coverUrl}',
    );
    // Đợi render xong nội dung khác mới load cover (tránh rate limit MangaDex)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() {
          _coverUrl = widget.coverUrl;
          _coverLoaded = true;
        });
      });
    });
  }

  @override
  void didUpdateWidget(covariant _StoryCoverWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint(
      '[CrawlScreen][_StoryCoverWidget] didUpdateWidget '
      'old=${oldWidget.coverUrl} new=${widget.coverUrl}',
    );
    // Nếu coverUrl thay đổi (user chọn truyện khác), reset để load lại sau delay
    if (oldWidget.coverUrl != widget.coverUrl && _coverLoaded) {
      setState(() {
        _coverUrl = '';
        _coverLoaded = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          setState(() {
            _coverUrl = widget.coverUrl;
            _coverLoaded = true;
          });
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayUrl = _coverUrl;
    if (displayUrl.isEmpty) {
      return _placeholder();
    }

    if (widget.isMangaDex) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _MangaDexCachedImage(
          imageUrl: displayUrl,
          width: 90,
          height: 130,
        ),
      );
    }

    final coverUri = Uri.tryParse(displayUrl);
    final referer = coverUri != null && coverUri.host.isNotEmpty
        ? '${coverUri.scheme}://${coverUri.authority}/'
        : 'https://www.mangahere.com/';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: displayUrl,
        cacheKey: displayUrl,
        httpHeaders: {
          'Referer': referer,
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/146.0.0.0 Safari/537.36',
        },
        width: 90,
        height: 130,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, error) {
          debugPrint(
            '[CrawlScreen][_StoryCoverWidget] ERROR '
            'url=$displayUrl error=$error',
          );
          return _placeholder();
        },
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 90,
      height: 130,
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.grey,
        size: 30,
      ),
    );
  }
}

// =============================================================
// PROGRESS SHEET
// =============================================================

class _ProgressSheetContent extends StatefulWidget {
  final String taskId;
  final CrawlService crawlService;
  final Future<void> Function() onCancel;
  final VoidCallback onClose;

  const _ProgressSheetContent({
    required this.taskId,
    required this.crawlService,
    required this.onCancel,
    required this.onClose,
  });

  @override
  State<_ProgressSheetContent> createState() => _ProgressSheetContentState();
}

class _ProgressSheetContentState extends State<_ProgressSheetContent> {
  Timer? _timer;

  Map<String, dynamic>? _task;
  Object? _error;

  bool _loading = true;
  bool _canceling = false;

  @override
  void initState() {
    super.initState();

    _refreshTask();

    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshTask());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isDone(String message) {
    final lower = message.toLowerCase();

    return message.contains('Hoàn thành') ||
        message.contains('Lỗi') ||
        lower.contains('hủy') ||
        lower.contains('huỷ');
  }

  Future<void> _refreshTask() async {
    try {
      final allTasks = await widget.crawlService.getAllTasks();

      if (!mounted) return;

      final rawTask = allTasks[widget.taskId];

      setState(() {
        _task = rawTask == null
            ? null
            : Map<String, dynamic>.from(rawTask as Map);

        _error = null;
        _loading = false;
      });

      final message = _task?['message']?.toString() ?? '';

      if (_isDone(message)) {
        _timer?.cancel();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _task == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _task == null) {
      return SizedBox(
        height: 220,
        child: Center(child: Text('Lỗi tải tiến độ: $_error')),
      );
    }

    if (_task == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('Không tìm thấy task')),
      );
    }

    final processed = _asInt(_task!['processed']);
    final total = _asInt(_task!['total']);

    final double progress = total > 0
        ? (processed / total).clamp(0.0, 1.0)
        : 0.0;

    final message = _task!['message']?.toString() ?? '';
    final isDone = _isDone(message);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _task!['title']?.toString() ?? '',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 15),
            Text('Tiến độ: $processed / $total chương'),
            const SizedBox(height: 4),
            Text(
              'Trạng thái: $message',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDone
                    ? (message.contains('Hoàn thành')
                          ? Colors.green
                          : Colors.red)
                    : Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                if (!isDone)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _canceling
                          ? null
                          : () async {
                              setState(() {
                                _canceling = true;
                              });

                              try {
                                await widget.onCancel();
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _canceling = false;
                                  });
                                }
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: Text(_canceling ? 'Đang hủy...' : 'Hủy cào'),
                    ),
                  ),
                if (!isDone) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onClose,
                    child: Text(isDone ? 'Xong' : 'Chạy ngầm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
