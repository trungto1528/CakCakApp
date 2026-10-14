
import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
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

  String? _currentStoryUrl;

  int? _selectedStoryId;
  bool _createNewStory = true;

  bool loading = false;
  bool searching = false;
  bool importing = false;
  bool loadingWebsites = false;

  Timer? _progressTimer;

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

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
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

  List<Map<String, dynamic>> get similarStories {
    final raw = data?['similarStories'] as List? ?? [];

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
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

      final match = RegExp(
        r'^(\d+)\s*(?:-\s*(\d+))?$',
      ).firstMatch(part);

      if (match == null) {
        throw FormatException(
          'Khoảng "$part" không hợp lệ. '
              'Ví dụ: 1-20,30-50,60',
        );
      }

      final start = int.parse(match.group(1)!);
      final end = match.group(2) == null
          ? start
          : int.parse(match.group(2)!);

      if (start < 1 || end < 1) {
        throw FormatException(
          'Số thứ tự chương phải bắt đầu từ 1: "$part"',
        );
      }

      ranges.add((
      start <= end ? start : end,
      start <= end ? end : start,
      ));
    }

    return ranges.isEmpty ? null : ranges;
  }

  /// Áp dụng khoảng theo vị trí của chương trong danh sách.
  ///
  /// Ví dụ:
  /// Danh sách có 100 chương:
  /// - Nhập 1-20: chọn 20 chương đầu.
  /// - Nhập 30-50,60: chọn chương thứ tự 30 đến 50
  ///   và chương thứ tự 60.
  ///
  /// Chương đã crawl luôn bị bỏ chọn.
  void applyChapterRanges() {
    if (data == null) return;

    try {
      final ranges = _parseChapterRanges(
        chapterRangeController.text,
      );

      if (ranges == null) {
        _showSnackBar(
          'Vui lòng nhập khoảng chương, ví dụ: 1-20,30-50',
        );
        return;
      }

      int selectedCount = 0;
      int crawledCount = 0;

      setState(() {
        for (int i = 0; i < chapters.length; i++) {
          final chapter = chapters[i] as Map;

          // Số thứ tự dựa trên vị trí trong danh sách.
          // Không phụ thuộc title, chapterNumber hay order.
          final chapterOrder = i + 1;

          if (_isCrawled(chapter)) {
            chapter['choosen'] = false;
            crawledCount++;
            continue;
          }

          final matched = ranges.any(
                (range) =>
            chapterOrder >= range.$1 &&
                chapterOrder <= range.$2,
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
    if (mounted) setState(() {});
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
      _currentStoryUrl = null;
      _selectedStoryId = null;
      _createNewStory = true;
      chapterRangeController.clear();
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
      _showSnackBar('Không có URL truyện');
      return;
    }

    if (loading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      loading = true;
      data = null;
      _currentStoryUrl = url;
      _selectedStoryId = null;
      _createNewStory = true;
      chapterRangeController.clear();
    });

    try {
      final resultData = await crawlService.crawlStory(url);

      if (!mounted) return;

      final normalizedData = Map<String, dynamic>.from(resultData);
      final rawChapters = normalizedData['chapters'] as List? ?? [];

      normalizedData['url'] ??= url;

      normalizedData['chapters'] = rawChapters.map((rawChapter) {
        final chapter = Map<String, dynamic>.from(rawChapter as Map);
        final isCrawled = _isCrawled(chapter);

        chapter['crawled'] = isCrawled;
        chapter['choosen'] = !isCrawled;

        return chapter;
      }).toList();

      final initialStoryId = _readStoryId(
        normalizedData['selectedStoryId'],
      );

      setState(() {
        data = normalizedData;
        _selectedStoryId = initialStoryId;
        _createNewStory = initialStoryId == null;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Lỗi lấy thông tin truyện: $e');
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // =========================================================
  // STORY MATCHING SELECTION
  // =========================================================

  void _chooseCreateNewStory() {
    setState(() {
      _createNewStory = true;
      _selectedStoryId = null;

      if (data != null) {
        data!['selectedStoryId'] = null;
      }
    });
  }

  void _chooseExistingStory(Map<String, dynamic> story) {
    final storyId = _readStoryId(story['storyId']);

    if (storyId == null) {
      _showSnackBar('Truyện tương tự không có storyId hợp lệ');
      return;
    }

    setState(() {
      _createNewStory = false;
      _selectedStoryId = storyId;

      if (data != null) {
        data!['selectedStoryId'] = storyId;
      }
    });
  }

  // =========================================================
  // BACK TO SEARCH
  // =========================================================

  void backToSearch() {
    setState(() {
      data = null;
      searchResults = [];
      _currentStoryUrl = null;
      _selectedStoryId = null;
      _createNewStory = true;
      chapterRangeController.clear();
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
      return const Expanded(
        child: Center(child: CircularProgressIndicator()),
      );
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
                  errorBuilder: (_, __, ___) =>
                      _searchCoverPlaceholder(),
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
                  helperText:
                  'Khoảng được tính theo số thứ tự trong danh sách',
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
              value: selectedWebsite,
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
                  _currentStoryUrl = null;
                  _selectedStoryId = null;
                  _createNewStory = true;
                  chapterRangeController.clear();
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
                  _buildSimilarStories(),
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

  // =========================================================
  // STORY HEADER
  // =========================================================

  Widget _buildStoryHeader() {
    final chapterList = chapters;
    final cover = data!['cover']?.toString() ?? '';

    final storyUrl =
        _currentStoryUrl ??
            data!['url']?.toString() ??
            data!['cleanedUrl']?.toString() ??
            '';

    return Padding(
      padding: const EdgeInsets.all(16),
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
                  headers: _imageHeaders(storyUrl),
                  width: 100,
                  height: 140,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverPlaceholder(),
                )
                    : _coverPlaceholder(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data!['title']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tác giả: '
                          '${data!['author']?.toString().isNotEmpty == true ? data!['author'] : 'Ẩn danh'}',
                    ),
                    const SizedBox(height: 4),
                    Text('Tổng chương: ${chapterList.length}'),
                    Text('Đã chọn: ${selectedChapters.length}'),
                    Text(
                      'Đã crawl: '
                          '${chapterList.where((c) => _isCrawled(c as Map)).length}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDescription(),
        ],
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      width: 100,
      height: 140,
      color: Colors.grey[300],
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }

  // =========================================================
  // SIMILAR STORIES / MERGE SOURCE
  // =========================================================

  Widget _buildSimilarStories() {
    final matches = similarStories;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.library_books_outlined),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Truyện đã có trong hệ thống?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Chọn truyện đúng để gộp nguồn. Nếu không chắc chắn, '
                    'hãy tạo truyện mới.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const Divider(height: 20),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: true,
                groupValue: _createNewStory,
                onChanged: importing ? null : (_) => _chooseCreateNewStory(),
                title: const Text(
                  'Tạo truyện mới',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Không gộp với bất kỳ truyện nào đang có.',
                ),
                secondary: const Icon(Icons.add_circle_outline),
              ),
              if (matches.isEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Backend không trả về truyện tương tự. '
                        'Bạn có thể tiếp tục tạo truyện mới.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Các truyện có khả năng trùng (${matches.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...matches.map(_buildSimilarStoryTile),
              ],
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: !_createNewStory
                        ? Colors.blue.withValues(alpha: 0.5)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _createNewStory ? Icons.add_circle_outline : Icons.link,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _createNewStory
                            ? 'Lựa chọn hiện tại: tạo truyện mới.'
                            : 'Lựa chọn hiện tại: gộp nguồn vào truyện ID '
                            '$_selectedStoryId.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimilarStoryTile(Map<String, dynamic> story) {
    final storyId = _readStoryId(story['storyId']);
    final title = story['title']?.toString() ?? 'Không có tiêu đề';
    final author = story['author']?.toString() ?? '';
    final cover = story['coverUrl']?.toString() ?? '';
    final similarity = _asDouble(story['similarity']);

    final isSelected =
        !_createNewStory && storyId != null && storyId == _selectedStoryId;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey.withValues(alpha: 0.3),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: RadioListTile<int>(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        value: storyId ?? -1,
        groupValue: _createNewStory ? null : _selectedStoryId,
        onChanged: importing || storyId == null
            ? null
            : (_) => _chooseExistingStory(story),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (author.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                'Tác giả: $author',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 3),
            Text('ID truyện: ${storyId ?? 'Không hợp lệ'}'),
            if (story['similarity'] != null)
              Text(
                'Độ tương đồng: '
                    '${(similarity * 100).toStringAsFixed(1)}%',
              ),
          ],
        ),
        secondary: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: cover.isNotEmpty
              ? Image.network(
            '${ApiConfig.coverImage}/$cover',
            width: 48,
            height: 68,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _similarCoverPlaceholder(),
          )
              : _similarCoverPlaceholder(),
        ),
      ),
    );
  }

  Widget _similarCoverPlaceholder() {
    return Container(
      width: 48,
      height: 68,
      color: Colors.grey[300],
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.grey,
        size: 20,
      ),
    );
  }

  // =========================================================
  // DESCRIPTION
  // =========================================================

  Widget _buildDescription() {
    final description = data!['description']?.toString() ?? '';

    if (description.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text(
        'Mô tả truyện',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(description),
        ),
      ],
    );
  }

  // =========================================================
  // INFORMATION
  // =========================================================

  Widget _buildInformation() {
    final information = data!['information'] as List? ?? [];

    if (information.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        child: ExpansionTile(
          initiallyExpanded: false,
          title: const Text(
            'Thông tin truyện',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: information.map<Widget>((item) {
                  final info = Map<String, dynamic>.from(item as Map);

                  final label = info['label']?.toString() ?? '';
                  final value = info['value']?.toString() ?? '';

                  if (label.isEmpty && value.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return _buildInfoRow(label, value);
                }).toList(),
              ),
            ),
          ],
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
            style: TextStyle(
              color: isCrawled ? Colors.grey[600] : null,
            ),
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

    _timer = Timer.periodic(
      const Duration(seconds: 2),
          (_) => _refreshTask(),
    );
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
                      child: Text(
                        _canceling ? 'Đang hủy...' : 'Hủy cào',
                      ),
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
