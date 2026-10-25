import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:novel_app/services/crawl_service.dart';

import '../config/api_config.dart';
import '../services/chapter_fetcher.dart';
import '../services/story_fetcher.dart';

class AdminStoryManagerScreen extends StatefulWidget {
  final int adminId;

  const AdminStoryManagerScreen({super.key, required this.adminId});

  @override
  State<AdminStoryManagerScreen> createState() =>
      _AdminStoryManagerScreenState();
}

class _AdminStoryManagerScreenState extends State<AdminStoryManagerScreen> {
  List stories = [];
  final Map<int, List> storyChapters = {};

  bool isLoading = true;
  bool isCheckingAll = false;
  bool isLoadingTasks = false;

  List<Map<String, dynamic>> updateTasks = [];

  Timer? _taskRefreshTimer;

  // Lưu nguồn đang chọn riêng cho từng truyện.
  final Map<int, String> _selectedSourcesByStory = {};

  @override
  void initState() {
    super.initState();
    _loadStories();
    _loadUpdateTasks();

    _taskRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshRunningTasks(),
    );
  }

  @override
  void dispose() {
    _taskRefreshTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // LOAD STORIES
  // ============================================================

  Future<void> _loadStories() async {
    try {
      final data = await StoryFetcher().getAllStories(widget.adminId);

      data.sort((a, b) {
        if (a['status'] == 'PENDING' && b['status'] != 'PENDING') {
          return -1;
        }
        if (a['status'] != 'PENDING' && b['status'] == 'PENDING') {
          return 1;
        }
        return 0;
      });

      if (!mounted) return;

      setState(() {
        stories = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoading = false);
      _showMessage('Không thể tải danh sách truyện: $e');
    }
  }

  Future<void> _loadChapters(int storyId) async {
    try {
      final data = await StoryFetcher().fetchStoryAdmin(
        storyId,
        widget.adminId,
      );

      if (!mounted) return;

      final rawChapters = data?['chapters'];
      final chapters = rawChapters is List
          ? rawChapters
                .whereType<Map>()
                .map((chapter) => Map<String, dynamic>.from(chapter))
                .toList()
          : <Map<String, dynamic>>[];

      chapters.sort((a, b) {
        if (a['status'] == 'PENDING' && b['status'] != 'PENDING') {
          return -1;
        }
        if (a['status'] != 'PENDING' && b['status'] == 'PENDING') {
          return 1;
        }

        final aNumber = double.tryParse('${a['chapterNumber']}') ?? 0;
        final bNumber = double.tryParse('${b['chapterNumber']}') ?? 0;
        return aNumber.compareTo(bNumber);
      });

      final sources = <String>{};
      for (final chapter in chapters) {
        final source = '${chapter['createdBy'] ?? ''}'.trim();
        sources.add(source.isEmpty ? 'Không rõ nguồn' : source);
      }

      final sortedSources = sources.toList()..sort();

      setState(() {
        storyChapters[storyId] = chapters;

        final selectedSource = _selectedSourcesByStory[storyId];

        if (sortedSources.isEmpty) {
          _selectedSourcesByStory.remove(storyId);
        } else if (selectedSource == null ||
            !sortedSources.contains(selectedSource)) {
          // Mặc định chọn nguồn đầu tiên khi mở truyện lần đầu.
          _selectedSourcesByStory[storyId] = sortedSources.first;
        }
      });
    } catch (e) {
      debugPrint('Không thể tải chapter của truyện $storyId: $e');
    }
  }

  // ============================================================
  // UPDATE CHECK API
  // ============================================================

  Future<void> _checkStoryUpdates(int storyId) async {
    try {
      final response = await CrawlService().checkStoryUpdates(storyId);
      final taskId = response['taskId']?.toString();

      if (taskId == null || taskId.isEmpty) {
        throw Exception('Backend không trả về taskId');
      }

      await _loadUpdateTasks();

      if (!mounted) return;

      _showMessage('Đã bắt đầu kiểm tra truyện #$storyId.');
      _showTaskDetails(taskId);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Không thể kiểm tra cập nhật: $e');
    }
  }

  Future<void> _checkAllUpdates() async {
    if (isCheckingAll) return;

    setState(() => isCheckingAll = true);

    try {
      final response = await CrawlService().checkAllStoryUpdates();
      final taskId = response['taskId']?.toString();

      if (taskId == null || taskId.isEmpty) {
        throw Exception('Backend không trả về taskId');
      }

      await _loadUpdateTasks();

      if (!mounted) return;

      _showMessage('Đã bắt đầu kiểm tra tất cả truyện.');
      _showTaskDetails(taskId);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Không thể kiểm tra tất cả truyện: $e');
    } finally {
      if (mounted) {
        setState(() => isCheckingAll = false);
      }
    }
  }

  Future<void> _loadUpdateTasks() async {
    if (isLoadingTasks) return;

    isLoadingTasks = true;

    try {
      final response = await CrawlService().getUpdateCheckTasks();

      response.sort((a, b) {
        final aTime = DateTime.tryParse('${a['createdAt'] ?? ''}');
        final bTime = DateTime.tryParse('${b['createdAt'] ?? ''}');

        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;

      setState(() => updateTasks = response);
    } catch (e) {
      debugPrint('Không thể tải danh sách task: $e');
    } finally {
      isLoadingTasks = false;
    }
  }

  Future<void> _refreshRunningTasks() async {
    if (!mounted || isLoadingTasks) return;

    final hasRunningTask = updateTasks.any(
      (task) => _isRunning(task['status']),
    );

    if (hasRunningTask) {
      await _loadUpdateTasks();
    }
  }

  Future<Map<String, dynamic>> _getTaskDetails(String taskId) async {
    return CrawlService().getUpdateCheckTask(taskId);
  }

  bool _isRunning(dynamic status) {
    final value = '${status ?? ''}'.toUpperCase();
    return value == 'RUNNING' || value == 'PENDING' || value == 'QUEUED';
  }

  String _responseMessage(http.Response response) {
    final body = response.body.trim();

    if (body.isEmpty) return 'HTTP ${response.statusCode}';

    try {
      final decoded = jsonDecode(body);

      if (decoded is String) return decoded;
      if (decoded is Map) {
        return '${decoded['message'] ?? decoded['error'] ?? body}';
      }
    } catch (_) {}

    return body;
  }

  // ============================================================
  // TASK LIST
  // ============================================================

  void _showTaskList() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(child: Text('Task kiểm tra cập nhật')),
                  IconButton(
                    tooltip: 'Làm mới',
                    onPressed: () async {
                      await _loadUpdateTasks();
                      if (dialogContext.mounted) {
                        setDialogState(() {});
                      }
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              content: SizedBox(
                width: 700,
                height: 500,
                child: isLoadingTasks && updateTasks.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : updateTasks.isEmpty
                    ? const Center(child: Text('Chưa có task nào'))
                    : ListView.separated(
                        itemCount: updateTasks.length,
                        separatorBuilder: (_, __) => const Divider(height: 20),
                        itemBuilder: (context, index) {
                          final task = updateTasks[index];

                          return _buildTaskCard(
                            task,
                            onTap: () {
                              final taskId = task['taskId']?.toString();

                              if (taskId != null && taskId.isNotEmpty) {
                                Navigator.pop(dialogContext);
                                _showTaskDetails(taskId);
                              }
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, {VoidCallback? onTap}) {
    final taskId = '${task['taskId'] ?? 'Không rõ'}';
    final status = '${task['status'] ?? 'UNKNOWN'}';
    final processed = _asInt(task['processed']);
    final total = _asInt(task['total']);
    final progress = total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;

    final storyId = task['storyId'];
    final message = '${task['message'] ?? 'Không có thông báo'}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Task ID: $taskId',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  _buildTaskStatus(status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                storyId == null
                    ? 'Phạm vi: Tất cả truyện'
                    : 'Truyện ID: $storyId',
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 6),
              Text('Tiến độ: $processed/$total nguồn'),
              const SizedBox(height: 4),
              Text(message),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Nhấn để xem kết quả',
                  style: TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskStatus(String status) {
    final normalized = status.toUpperCase();

    Color color;
    switch (normalized) {
      case 'COMPLETED':
        color = Colors.green;
        break;
      case 'FAILED':
      case 'ERROR':
        color = Colors.red;
        break;
      case 'CANCELLED':
        color = Colors.grey;
        break;
      default:
        color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        normalized,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  void _showTaskDetails(String taskId) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 760,
          height: 650,
          child: _TaskDetailsDialog(
            taskId: taskId,
            adminId: widget.adminId,
            loadTask: _getTaskDetails,
            onRefreshTasks: _loadUpdateTasks,
            isRunning: _isRunning,
            asInt: _asInt,
          ),
        ),
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  List<DropdownMenuItem<String>> _buildSourceDropdownItems(int storyId) {
    final chapters = storyChapters[storyId] ?? [];
    final sources = <String>{};

    for (final chapter in chapters) {
      final source = '${chapter['createdBy'] ?? ''}'.trim();
      sources.add(source.isEmpty ? 'Không rõ nguồn' : source);
    }

    final sortedSources = sources.toList()..sort();

    return sortedSources.map((source) {
      return DropdownMenuItem<String>(
        value: source,
        child: Text(source, overflow: TextOverflow.ellipsis),
      );
    }).toList();
  }

  Widget _buildDeleteSourceButton(int storyId) {
    final selectedSource = _selectedSourcesByStory[storyId];

    if (selectedSource == null || selectedSource.isEmpty) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: const Icon(Icons.delete, color: Colors.red),
      tooltip: 'Xóa chapter của nguồn $selectedSource trong truyện này',
      onPressed: () => _confirmDeleteSourceChapters(storyId, selectedSource),
    );
  }

  void _confirmDeleteSourceChapters(int storyId, String sourceName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa chapter của nguồn'),
        content: Text(
          'Bạn có chắc muốn xóa tất cả chapter của nguồn '
          '$sourceName trong truyện ID $storyId?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteChaptersOfSource(storyId, sourceName);
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChaptersOfSource(int storyId, String sourceName) async {
    final chapters = List<Map<String, dynamic>>.from(
      storyChapters[storyId] ?? [],
    );

    final targets = chapters.where((chapter) {
      final source = '${chapter['createdBy'] ?? ''}'.trim();
      final normalizedSource = source.isEmpty ? 'Không rõ nguồn' : source;

      return normalizedSource == sourceName;
    }).toList();

    var deleted = 0;
    var failed = 0;

    for (final chapter in targets) {
      final chapterId = _asInt(chapter['id']);

      if (chapterId <= 0) {
        failed++;
        continue;
      }

      try {
        await ChapterFetcher().deleteChapter(chapterId, widget.adminId);
        deleted++;
      } catch (e) {
        failed++;
        debugPrint('Lỗi xóa chapter $chapterId: $e');
      }
    }

    if (!mounted) return;

    await _loadChapters(storyId);

    if (!mounted) return;

    _showMessage(
      'Đã xóa $deleted chapter của nguồn $sourceName'
      '${failed > 0 ? ', lỗi $failed chapter' : ''}.',
    );
  }

  // ============================================================
  // CHAPTER DETAIL
  // ============================================================

  Future<void> _viewChapter(int chapterId) async {
    try {
      final chapter = await ChapterFetcher().fetchChapter(chapterId);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'Chương ${chapter['chapterNumber']}: ${chapter['title']}',
          ),
          content: SizedBox(
            width: 700,
            height: 500,
            child: ListView(
              children:
                  ((chapter['blocks'] is List)
                          ? chapter['blocks'] as List
                          : <dynamic>[])
                      .map<Widget>((block) {
                        if (block is Map && block['type'] == 'text') {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text('${block['data'] ?? ''}'),
                          );
                        }

                        if (block is Map && block['type'] == 'image') {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: CachedNetworkImage(
                              imageUrl:
                                  '${ApiConfig.chapterImage}/${block['data']}',
                            ),
                          );
                        }

                        return const SizedBox.shrink();
                      })
                      .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('$e');
    }
  }

  // ============================================================
  // STORY / CHAPTER ACTIONS
  // ============================================================

  Future<void> _approveStory(int id) async {
    try {
      await StoryFetcher().approveStory(widget.adminId, id);
      await _loadStories();
    } catch (e) {
      _showMessage('$e');
    }
  }

  Future<void> _rejectStory(int id) async {
    try {
      await StoryFetcher().rejectStory(widget.adminId, id);
      await _loadStories();
    } catch (e) {
      _showMessage('$e');
    }
  }

  Future<void> _deleteStory(int id) async {
    try {
      await StoryFetcher().deleteStory(id, widget.adminId);
      await _loadStories();
    } catch (e) {
      _showMessage('$e');
    }
  }

  Future<void> _deleteChapter(int storyId, int chapterId) async {
    try {
      await ChapterFetcher().deleteChapter(chapterId, widget.adminId);
      await _loadChapters(storyId);

      if (!mounted) return;
      _showMessage('Đã xoá chương');
    } catch (e) {
      if (!mounted) return;
      _showMessage('$e');
    }
  }

  Future<void> _approveChapter(int storyId, int chapterId) async {
    try {
      await ChapterFetcher().approveChapter(widget.adminId, chapterId);
      await _loadChapters(storyId);
    } catch (e) {
      _showMessage('$e');
    }
  }

  Future<void> _rejectChapter(int storyId, int chapterId) async {
    try {
      await ChapterFetcher().rejectChapter(widget.adminId, chapterId);
      await _loadChapters(storyId);
    } catch (e) {
      _showMessage('$e');
    }
  }

  void _confirmDeleteChapter(int storyId, int chapterId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá chương'),
        content: const Text('Bạn có chắc muốn xoá chương này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteChapter(storyId, chapterId);
            },
            child: const Text('Xoá', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteStory(int id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá truyện'),
        content: const Text('Bạn có chắc muốn xoá truyện này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteStory(id);
            },
            child: const Text('Xoá', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmRejectStory(int id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Từ chối truyện'),
        content: const Text('Bạn có chắc muốn từ chối truyện này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _rejectStory(id);
            },
            child: const Text(
              'Từ chối',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // MAIN UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý truyện'),
        actions: [
          IconButton(
            tooltip: 'Task kiểm tra cập nhật',
            onPressed: _showTaskList,
            icon: const Icon(Icons.task_alt),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: FilledButton.icon(
                onPressed: isCheckingAll ? null : _checkAllUpdates,
                icon: isCheckingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Kiểm tra tất cả'),
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadStories,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: stories.length,
                      itemBuilder: (context, index) {
                        final story = stories[index];
                        final id = _asInt(story['id']);
                        final title = '${story['title'] ?? ''}';

                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.all(10),
                            title: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    width: 60,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    imageUrl:
                                        '${ApiConfig.coverImage}/${story['coverUrl'] ?? ''}',
                                    placeholder: (_, __) => const SizedBox(
                                      width: 60,
                                      height: 90,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => const SizedBox(
                                      width: 60,
                                      height: 90,
                                      child: Icon(Icons.image, size: 40),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'ID: $id',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        'Tạo bởi: ${story['createdBy'] ?? 'Unknown'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      _buildStoryStatus(
                                        '${story['status'] ?? 'UNKNOWN'}',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onExpansionChanged: (expanded) {
                              if (expanded && !storyChapters.containsKey(id)) {
                                _loadChapters(id);
                              }
                            },
                            trailing: SizedBox(
                              width: 100,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Kiểm tra cập nhật',
                                    onPressed: () => _checkStoryUpdates(id),
                                    icon: const Icon(
                                      Icons.sync,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  if (story['status'] == 'PENDING') ...[
                                    IconButton(
                                      tooltip: 'Duyệt truyện',
                                      onPressed: () => _approveStory(id),
                                      icon: const Icon(
                                        Icons.check,
                                        color: Colors.green,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Từ chối truyện',
                                      onPressed: () => _confirmRejectStory(id),
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ],
                                  IconButton(
                                    tooltip: 'Xoá truyện',
                                    onPressed: () => _confirmDeleteStory(id),
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            children: _buildChapters(id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ============================================================
  // CHAPTER LIST
  // ============================================================

  List<Widget> _buildChapters(int storyId) {
    final chapters = storyChapters[storyId];

    if (chapters == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (chapters.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(12),
          child: Text('Truyện chưa có chapter nào'),
        ),
      ];
    }

    final sourceItems = _buildSourceDropdownItems(storyId);
    final sources = sourceItems
        .map((item) => item.value)
        .whereType<String>()
        .toList();

    if (sources.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(12),
          child: Text('Không tìm thấy nguồn của chapter'),
        ),
      ];
    }

    final storedSource = _selectedSourcesByStory[storyId];
    final selectedSource =
        storedSource != null && sources.contains(storedSource)
        ? storedSource
        : sources.first;

    final filteredChapters = chapters.where((chapter) {
      final source = '${chapter['createdBy'] ?? ''}'.trim();
      final normalizedSource = source.isEmpty ? 'Không rõ nguồn' : source;

      return normalizedSource == selectedSource;
    }).toList();

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            const Text(
              'Nguồn:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                value: selectedSource,
                isExpanded: true,
                items: sourceItems,
                onChanged: (String? newValue) {
                  if (newValue == null) return;

                  setState(() {
                    _selectedSourcesByStory[storyId] = newValue;
                  });
                },
              ),
            ),
            _buildDeleteSourceButton(storyId),
          ],
        ),
      ),
      if (filteredChapters.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Nguồn này chưa có chapter nào'),
        )
      else
        ...filteredChapters.map((chapter) {
          final chapterId = _asInt(chapter['id']);
          final status = '${chapter['status'] ?? 'UNKNOWN'}';

          return ListTile(
            title: Text(
              'Chương ${chapter['chapterNumber']}: ${chapter['title'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text('${chapter['createdBy'] ?? 'Không rõ nguồn'}'),
            trailing: Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildStoryStatus(status),
                if (status == 'PENDING') ...[
                  IconButton(
                    tooltip: 'Duyệt chapter',
                    onPressed: () => _approveChapter(storyId, chapterId),
                    icon: const Icon(Icons.check, color: Colors.green),
                  ),
                  IconButton(
                    tooltip: 'Từ chối chapter',
                    onPressed: () => _rejectChapter(storyId, chapterId),
                    icon: const Icon(Icons.close, color: Colors.orange),
                  ),
                ],
                IconButton(
                  tooltip: 'Xóa chapter',
                  onPressed: () => _confirmDeleteChapter(storyId, chapterId),
                  icon: const Icon(Icons.delete, color: Colors.red),
                ),
              ],
            ),
          );
        }),
    ];
  }

  // ============================================================
  // SOURCE MANAGEMENT
  // ============================================================

  // ============================================================
  // STATUS
  // ============================================================

  Widget _buildStoryStatus(String status) {
    final color = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'APPROVED':
      case 'COMPLETED':
        return Colors.green;
      case 'PENDING':
        return Colors.orange;
      case 'REJECTED':
      case 'FAILED':
      case 'ERROR':
        return Colors.red;
      case 'RUNNING':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

// ================================================================
// TASK DETAILS DIALOG
// ================================================================

class _TaskDetailsDialog extends StatefulWidget {
  final String taskId;
  final int adminId;
  final Future<Map<String, dynamic>> Function(String) loadTask;
  final Future<void> Function() onRefreshTasks;
  final bool Function(dynamic) isRunning;
  final int Function(dynamic) asInt;

  const _TaskDetailsDialog({
    required this.taskId,
    required this.adminId,
    required this.loadTask,
    required this.onRefreshTasks,
    required this.isRunning,
    required this.asInt,
  });

  @override
  State<_TaskDetailsDialog> createState() => _TaskDetailsDialogState();
}

class _TaskDetailsDialogState extends State<_TaskDetailsDialog> {
  Map<String, dynamic>? task;
  String? error;
  bool isLoading = true;
  bool isCrawlingAll = false;

  final Set<String> crawlingSources = <String>{};

  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();

    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (task == null || widget.isRunning(task!['status'])) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await widget.loadTask(widget.taskId);

      if (!mounted) return;

      setState(() {
        task = result;
        error = null;
        isLoading = false;
      });

      await widget.onRefreshTasks();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = '$e';
        isLoading = false;
      });
    }
  }

  // ============================================================
  // CRAWL NEW CHAPTERS
  // ============================================================

  String _sourceKey(Map<String, dynamic> result) {
    final sourceUrl = '${result['sourceUrl'] ?? ''}'.trim();
    if (sourceUrl.isNotEmpty) return sourceUrl;

    return '${result['sourceId'] ?? result['sourceName'] ?? result['storyTitle']}';
  }

  /// Chuẩn bị payload theo API /import-selected.
  Map<String, dynamic> _buildImportPayload(Map<String, dynamic> result) {
    final sourceUrl = '${result['sourceUrl'] ?? ''}'.trim();

    if (sourceUrl.isEmpty) {
      throw Exception('Nguồn không có sourceUrl');
    }

    final rawStoryId = result['storyId'];
    final storyId = widget.asInt(rawStoryId);

    if (rawStoryId == null || storyId <= 0) {
      throw Exception(
        'Kết quả không có storyId hợp lệ. '
        'Backend cần trả storyId trong mỗi kết quả kiểm tra.',
      );
    }

    final rawChapters = result['chapters'];
    final chapters = rawChapters is List ? rawChapters : <dynamic>[];

    final selectedChapters = <Map<String, dynamic>>[];

    for (final rawChapter in chapters) {
      if (rawChapter is! Map) continue;

      final chapter = Map<String, dynamic>.from(rawChapter);
      final url = '${chapter['url'] ?? ''}'.trim();

      if (url.isEmpty) continue;

      selectedChapters.add({
        'title': '${chapter['title'] ?? 'Chapter mới'}',
        'url': url,
        'order': chapter['order'],
        'choosen': true,
        'crawled': false,
      });
    }

    if (selectedChapters.isEmpty) {
      throw Exception('Nguồn này không có chapter hợp lệ để crawl');
    }

    return {
      'title': '${result['storyTitle'] ?? 'Truyện chưa có tên'}',
      'sourceUrl': sourceUrl,
      'selectedStoryId': storyId,
      'chapters': selectedChapters,
    };
  }

  /// Gửi một nguồn đến backend.
  /// Thành công ở đây nghĩa là API đã tiếp nhận yêu cầu,
  /// không khẳng định toàn bộ chapter đã lưu xong.
  Future<void> _crawlResult(Map<String, dynamic> result) async {
    final sourceKey = _sourceKey(result);

    if (crawlingSources.contains(sourceKey)) return;

    setState(() {
      crawlingSources.add(sourceKey);
    });

    try {
      final payload = _buildImportPayload(result);

      final response = await CrawlService().importStory(
        payload,
        widget.adminId,
      );

      if (!mounted) return;

      final taskId = response['taskId']?.toString();
      final message = response['message']?.toString();

      _showDialogMessage(
        message != null && message.isNotEmpty
            ? message
            : taskId != null && taskId.isNotEmpty
            ? 'Đã gửi yêu cầu crawl. Task: $taskId'
            : 'Backend đã tiếp nhận yêu cầu crawl.',
      );
    } catch (e) {
      if (!mounted) return;
      _showDialogMessage('Không thể crawl nguồn này: $e');
    } finally {
      if (mounted) {
        setState(() => crawlingSources.remove(sourceKey));
      }
    }
  }

  /// Crawl tuần tự từng nguồn có chapter mới.
  Future<void> _crawlAllResults(List<Map<String, dynamic>> results) async {
    if (isCrawlingAll) return;

    final candidates = results.where((result) {
      final chapters = result['chapters'];
      return chapters is List && chapters.isNotEmpty;
    }).toList();

    if (candidates.isEmpty) {
      _showDialogMessage('Không có nguồn nào có chapter mới để crawl.');
      return;
    }

    setState(() => isCrawlingAll = true);

    var succeeded = 0;
    var failed = 0;

    try {
      for (final result in candidates) {
        if (!mounted) return;

        final sourceKey = _sourceKey(result);

        if (crawlingSources.contains(sourceKey)) {
          continue;
        }

        setState(() => crawlingSources.add(sourceKey));

        try {
          final payload = _buildImportPayload(result);

          await CrawlService().importStory(payload, widget.adminId);

          succeeded++;
        } catch (e) {
          failed++;
          debugPrint('Crawl lỗi nguồn ${result['sourceUrl']}: $e');
        } finally {
          if (mounted) {
            setState(() => crawlingSources.remove(sourceKey));
          }
        }
      }

      if (!mounted) return;

      _showDialogMessage(
        'Đã gửi crawl tuần tự: $succeeded nguồn thành công, '
        '$failed nguồn lỗi.',
      );
    } finally {
      if (mounted) {
        setState(() => isCrawlingAll = false);
      }
    }
  }

  void _showDialogMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // COVER IMAGE
  // ============================================================

  Widget _buildCover(dynamic coverUrl) {
    final cover = '${coverUrl ?? ''}'.trim();

    if (cover.isEmpty || cover.toLowerCase() == 'null') {
      return _coverPlaceholder();
    }

    final String imageUrl;

    if (cover.startsWith('https://') || cover.startsWith('http://')) {
      imageUrl = cover;
    } else {
      final baseUrl = ApiConfig.coverImage.replaceAll(RegExp(r'/+$'), '');
      final path = cover.replaceAll(RegExp(r'^/+'), '');
      imageUrl = '$baseUrl/$path';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 50,
        height: 70,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 50,
          height: 70,
          color: Colors.grey.withValues(alpha: 0.1),
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _coverPlaceholder(),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      width: 50,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.image_not_supported_outlined, size: 24),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final current = task;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Chi tiết task kiểm tra',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Làm mới',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Đóng',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isLoading && current == null
              ? const Center(child: CircularProgressIndicator())
              : error != null && current == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(error!),
                  ),
                )
              : current == null
              ? const Center(child: Text('Không có dữ liệu task'))
              : _buildContent(current),
        ),
      ],
    );
  }

  Widget _buildContent(Map<String, dynamic> current) {
    final status = '${current['status'] ?? 'UNKNOWN'}';
    final processed = widget.asInt(current['processed']);
    final total = widget.asInt(current['total']);
    final progress = total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;

    final results = current['results'] is List
        ? (current['results'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];

    final errors = current['errors'] is List
        ? current['errors'] as List
        : <dynamic>[];

    Color statusColor;

    switch (status.toUpperCase()) {
      case 'COMPLETED':
        statusColor = Colors.green;
        break;
      case 'FAILED':
      case 'ERROR':
        statusColor = Colors.red;
        break;
      case 'CANCELLED':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.orange;
    }

    final crawlableResults = results.where((result) {
      final chapters = result['chapters'];
      return chapters is List && chapters.isNotEmpty;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // TASK OVERVIEW
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.task_alt, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tổng quan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Task ID: ${current['taskId'] ?? widget.taskId}'),
                const SizedBox(height: 6),
                Text(
                  current['storyId'] == null
                      ? 'Phạm vi: Tất cả truyện'
                      : 'Truyện ID: ${current['storyId']}',
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tiến độ'),
                    Text(
                      '$processed / $total nguồn',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: progress, minHeight: 8),
                ),
                const SizedBox(height: 10),
                Text(
                  '${current['message'] ?? 'Đang xử lý...'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // RESULTS HEADER AND CRAWL ALL BUTTON
        Row(
          children: [
            const Icon(Icons.library_books_outlined, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Kết quả kiểm tra',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            _countBadge(results.length, Colors.blue),
          ],
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isCrawlingAll || crawlableResults.isEmpty
                ? null
                : () => _crawlAllResults(crawlableResults),
            icon: isCrawlingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(
              isCrawlingAll
                  ? 'Đang gửi yêu cầu crawl...'
                  : 'Crawl tất cả nguồn có chapter mới '
                        '(${crawlableResults.length})',
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          _emptyTaskMessage('Chưa có kết quả kiểm tra.')
        else
          ...results.map<Widget>((result) {
            final chapters = result['chapters'] is List
                ? result['chapters'] as List
                : <dynamic>[];

            final chapterCount = widget.asInt(
              result['newChapterCount'] ?? chapters.length,
            );

            final sourceKey = _sourceKey(result);
            final isCrawling = crawlingSources.contains(sourceKey);

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                leading: _buildCover(result['coverUrl']),
                title: Text(
                  '${result['storyTitle'] ?? 'Không rõ truyện'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '${result['sourceName'] ?? 'Không rõ nguồn'}'
                    ' • $chapterCount chapter mới',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                children: [
                  if (result['sourceUrl'] != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        'Nguồn: ${result['sourceUrl']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // CRAWL THIS SOURCE
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: chapters.isEmpty || isCrawling || isCrawlingAll
                          ? null
                          : () => _crawlResult(result),
                      icon: isCrawling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(
                        isCrawling ? 'Đang gửi yêu cầu...' : 'Crawl nguồn này',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (chapters.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Không có chapter mới.',
                        style: TextStyle(fontSize: 13),
                      ),
                    )
                  else
                    ...chapters.map<Widget>((rawChapter) {
                      final chapter = rawChapter is Map
                          ? Map<String, dynamic>.from(rawChapter)
                          : <String, dynamic>{};

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.fiber_new,
                              size: 20,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${chapter['title'] ?? 'Chapter mới'}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Thứ tự: ${chapter['order'] ?? '?'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (chapter['url'] != null)
                                    SelectableText(
                                      '${chapter['url']}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            );
          }),

        const SizedBox(height: 16),

        // ERRORS
        Row(
          children: [
            const Icon(Icons.error_outline, size: 20, color: Colors.red),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Nguồn gặp lỗi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            _countBadge(errors.length, Colors.red),
          ],
        ),
        const SizedBox(height: 8),

        if (errors.isEmpty)
          _emptyTaskMessage('Không có nguồn lỗi được ghi nhận.')
        else
          ...errors.map<Widget>((rawError) {
            final item = rawError is Map
                ? Map<String, dynamic>.from(rawError)
                : <String, dynamic>{};

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: Colors.red.withValues(alpha: 0.04),
              child: ListTile(
                leading: _buildCover(item['coverUrl']),
                title: Text(
                  '${item['storyTitle'] ?? item['sourceName'] ?? 'Nguồn không rõ'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['error'] ?? 'Lỗi không xác định'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (item['sourceUrl'] != null) ...[
                        const SizedBox(height: 4),
                        SelectableText(
                          '${item['sourceUrl']}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),

        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  Widget _countBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _emptyTaskMessage(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
