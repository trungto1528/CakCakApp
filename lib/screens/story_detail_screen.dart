import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/config/api_config.dart';
import 'package:novel_app/offline/service/offline_entry_service.dart';
import 'package:novel_app/offline/service/offline_mode_service.dart';
import 'package:novel_app/offline/service/story_download_service.dart';
import 'package:novel_app/screens/chapter_reader_screen.dart';
import 'package:novel_app/services/bookmark.dart';
import 'package:novel_app/services/story_fetcher.dart';
import 'package:novel_app/widget/expand_text.dart';
import 'package:path_provider/path_provider.dart';
import '../models/User.dart';
import '../services/app_preference.dart';
import 'login_screen.dart';
class StoryDetailScreen extends StatefulWidget {
  final int storyId;
  const StoryDetailScreen({super.key, required this.storyId});
  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}
class _StoryDetailScreenState extends State<StoryDetailScreen> {
  Map<String, dynamic> story = {};
  User? user;
  bool storyLoading = true;
  bool bookmarkLoading = false;
  bool isSaved = false;
  bool downloadLoading = false;
  bool isDownloaded = false;
  bool downloadActionLoading = false;
  double downloadProgress = 0;
  String downloadStatus = '';
  File? _offlineCover;
  late final ValueNotifier<StoryDownloadProgress> _downloadNotifier;
  List<dynamic> chapters = [];
  static const int _pageSize = 20;
  int _currentPage = 0;
  bool get _isOffline => OfflineModeService.isOffline.value;
  bool get _isDownloadPaused {
    final progress = _downloadNotifier.value;
    return progress.isPaused ||
        StoryDownloadService.instance.isPaused(widget.storyId);
  }
  @override
  void initState() {
    super.initState();
    _downloadNotifier = StoryDownloadService.instance.progressFor(
      widget.storyId,
    );
    _downloadNotifier.addListener(_onDownloadProgressChanged);
    _syncDownloadProgress();
    init();
  }
  @override
  void dispose() {
    _downloadNotifier.removeListener(_onDownloadProgressChanged);
    super.dispose();
  }
  void _onDownloadProgressChanged() {
    if (mounted) {
      _syncDownloadProgress();
    }
  }
  void _syncDownloadProgress() {
    if (!mounted) return;
    final progress = _downloadNotifier.value;
    setState(() {
      downloadLoading = progress.isDownloading;
      downloadProgress = progress.progress;
      downloadStatus = progress.status;
      if (progress.isCompleted) {
        isDownloaded = true;
      } else if (progress.isCancelled) {
        isDownloaded = false;
      }
    });
  }
  Future<void> init() async {
    await _loadUser();
    if (!mounted) return;
    await _loadStory();
    if (!mounted) return;
    await _loadSaved();
    if (!mounted) return;
    await _checkDownloaded();
  }
  // ============================================================
  // OFFLINE FILES
  // ============================================================
  Future<Directory> _getOfflineStoryDirectory() async {
    final appDirectory = await getApplicationSupportDirectory();
    return Directory(
      '${appDirectory.path}${Platform.pathSeparator}'
      'offline_stories${Platform.pathSeparator}'
      '${widget.storyId}',
    );
  }
  Future<Map<String, dynamic>> _readOfflineMetadata() async {
    final directory = await _getOfflineStoryDirectory();
    final completeFile = File(
      '${directory.path}${Platform.pathSeparator}complete.json',
    );
    final metadataFile = File(
      '${directory.path}${Platform.pathSeparator}metadata.json',
    );
    if (!await directory.exists()) {
      throw Exception('Không tìm thấy thư mục truyện offline.');
    }
    if (!await completeFile.exists()) {
      throw Exception('Bản tải chưa hoàn tất hoặc thiếu complete.json.');
    }
    if (!await metadataFile.exists()) {
      throw Exception('Không tìm thấy metadata.json.');
    }
    final metadataJson = jsonDecode(await metadataFile.readAsString());
    if (metadataJson is! Map) {
      throw Exception('Dữ liệu metadata không hợp lệ.');
    }
    return Map<String, dynamic>.from(metadataJson);
  }
  Future<File?> _findOfflineCover() async {
    final directory = await _getOfflineStoryDirectory();
    final possibleDirectories = [
      Directory(
        '${directory.path}${Platform.pathSeparator}'
        'images${Platform.pathSeparator}cover',
      ),
      Directory('${directory.path}${Platform.pathSeparator}cover'),
    ];
    const extensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
    for (final imageDirectory in possibleDirectories) {
      if (!await imageDirectory.exists()) continue;
      final files = await imageDirectory
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final extension = _fileExtension(file.path);
        if (extensions.contains(extension) &&
            await file.exists() &&
            await file.length() > 0) {
          return file;
        }
      }
    }
    return null;
  }
  String _fileExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0) return '';
    return name.substring(dotIndex).toLowerCase();
  }
  Future<void> _loadOfflineStory() async {
    final data = await _readOfflineMetadata();
    final rawChapters = data['chapters'];
    if (rawChapters is! List) {
      throw Exception('metadata.json không chứa danh sách chapters hợp lệ.');
    }
    final localCover = await _findOfflineCover();
    if (!mounted) return;
    setState(() {
      story = data;
      chapters = List<dynamic>.from(rawChapters);
      _offlineCover = localCover;
      _currentPage = 0;
      storyLoading = false;
    });
  }
  // ============================================================
  // LOAD STORY
  // ============================================================
  Future<void> _loadStory() async {
    try {
      if (_isOffline) {
        await _loadOfflineStory();
        return;
      }
      final data = await StoryFetcher().fetchStory(widget.storyId);
      if (!mounted) return;
      setState(() {
        story = Map<String, dynamic>.from(data);
        chapters = data['chapters'] is List
            ? List<dynamic>.from(data['chapters'])
            : <dynamic>[];
        _offlineCover = null;
        _currentPage = 0;
        storyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        storyLoading = false;
      });
      debugPrint('Lỗi tải dữ liệu truyện: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isOffline ? 'Không thể đọc truyện offline: $e' : 'Lỗi tải truyện.',
          ),
        ),
      );
    }
  }
  // ============================================================
  // USER AND BOOKMARK
  // ============================================================
  Future<void> _loadUser() async {
    final prefs = await AppPreferences.getInstance();
    final userString = prefs.getString('user');
    if (!mounted) return;
    if (userString == null) {
      setState(() => user = null);
      return;
    }
    try {
      final decoded = jsonDecode(userString);
      setState(() {
        user = User.fromJson(decoded);
      });
    } catch (_) {
      setState(() => user = null);
    }
  }
  Future<void> _loadSaved() async {
    if (_isOffline || user == null) {
      if (!mounted) return;
      setState(() {
        isSaved = false;
        bookmarkLoading = false;
      });
      return;
    }
    setState(() => bookmarkLoading = true);
    try {
      final result = await Bookmark().isSavedApi(user!.id, widget.storyId);
      if (!mounted) return;
      setState(() {
        isSaved = result;
        bookmarkLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => bookmarkLoading = false);
      debugPrint('Lỗi kiểm tra bookmark: $e');
    }
  }
  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yêu cầu đăng nhập'),
        content: const Text('Bạn cần đăng nhập để lưu truyện.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final loginResult = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LoginScreen()),
              );
              if (!mounted) return;
              if (loginResult == true) {
                await _loadUser();
                if (!mounted) return;
                await _loadSaved();
              }
            },
            child: const Text('Đăng nhập'),
          ),
        ],
      ),
    );
  }
  Future<void> _toggleBookmark() async {
    if (_isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chức năng yêu thích cần kết nối mạng.')),
      );
      return;
    }
    if (user == null) {
      _showLoginRequiredDialog();
      return;
    }
    if (bookmarkLoading) return;
    setState(() => bookmarkLoading = true);
    try {
      if (isSaved) {
        await Bookmark().unsaveStory(user!.id, widget.storyId);
      } else {
        await Bookmark().saveStory(user!.id, widget.storyId);
      }
      if (!mounted) return;
      setState(() {
        isSaved = !isSaved;
        bookmarkLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => bookmarkLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể cập nhật danh sách yêu thích.'),
        ),
      );
      debugPrint('Lỗi cập nhật bookmark: $e');
    }
  }
  // ============================================================
  // DOWNLOAD, PAUSE, RESUME, CANCEL AND DELETE
  // ============================================================
  Future<void> _checkDownloaded() async {
    try {
      final available = await OfflineEntryService.instance.isStoryAvailable(
        widget.storyId,
      );
      if (!mounted) return;
      final progress = _downloadNotifier.value;
      setState(() {
        isDownloaded = available || progress.isCompleted;
        downloadLoading = progress.isDownloading;
        downloadProgress = progress.progress;
        downloadStatus = progress.status;
      });
    } catch (e) {
      debugPrint('Lỗi kiểm tra truyện đã tải: $e');
    }
  }
  Future<void> _downloadStory() async {
    if (_isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể tải truyện mới khi đang ở chế độ offline.'),
        ),
      );
      return;
    }
    final service = StoryDownloadService.instance;
    final progress = service.progressFor(widget.storyId).value;
    if (progress.isPaused || service.isPaused(widget.storyId)) {
      service.resumeDownload(widget.storyId);
      return;
    }
    if (service.isDownloading(widget.storyId)) {
      _syncDownloadProgress();
      return;
    }
    if (downloadActionLoading) return;
    // Không bật downloadActionLoading trong toàn bộ thời gian tải.
    // Nếu bật, nút Hủy tải sẽ bị vô hiệu hóa cho đến khi tải kết thúc.
    try {
      await service.downloadStory(
        widget.storyId,
        onProgress: (completed, total, current) {},
        onStatus: (message) {},
      );
      if (!mounted) return;
      final latest = service.progressFor(widget.storyId).value;
      if (latest.isCancelled) {
        await _checkDownloaded();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã hủy tải truyện.')));
        return;
      }
      if (latest.isCompleted) {
        setState(() {
          isDownloaded = true;
          downloadProgress = 1;
          downloadStatus = 'Đã tải xong';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tải truyện hoàn tất.')));
      } else if (latest.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải truyện: ${latest.error}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi tải truyện: $e')));
    } finally {
      if (mounted) {
        _syncDownloadProgress();
        await _checkDownloaded();
      }
    }
  }
  void _pauseDownload() {
    if (_isOffline) return;
    StoryDownloadService.instance.pauseDownload(widget.storyId);
  }
  void _resumeDownload() {
    if (_isOffline) return;
    StoryDownloadService.instance.resumeDownload(widget.storyId);
  }
  Future<void> _cancelDownload() async {
    if (_isOffline || downloadActionLoading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hủy tải truyện?'),
        content: const Text(
          'Tác vụ tải sẽ dừng. Những ảnh đã tải thành công được giữ lại '
          'để có thể tiếp tục tải sau này. Bản tải chưa hoàn tất sẽ '
          'không được dùng để đọc offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Tiếp tục tải'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hủy tải'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      downloadActionLoading = true;
    });
    try {
      await StoryDownloadService.instance.cancelDownload(widget.storyId);
      if (!mounted) return;
      await _checkDownloaded();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy tải. Dữ liệu đã tải thành công được giữ lại.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể hủy tải: $e')));
    } finally {
      if (mounted) {
        setState(() {
          downloadActionLoading = false;
        });
        _syncDownloadProgress();
      }
    }
  }
  Future<void> _showDeleteDownloadDialog() async {
    if (_isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hãy tắt chế độ offline trước khi xóa bản tải.'),
        ),
      );
      return;
    }
    if (StoryDownloadService.instance.isDownloading(widget.storyId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không thể xóa khi truyện đang tải hoặc đang tạm dừng. '
            'Hãy hủy tải trước.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa bản tải?'),
        content: const Text(
          'Truyện sẽ bị xóa khỏi thiết bị và không thể đọc offline '
          'cho đến khi tải lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await StoryDownloadService.instance.deleteDownloadedStory(widget.storyId);
      if (!mounted) return;
      setState(() {
        isDownloaded = false;
        downloadProgress = 0;
        downloadStatus = '';
        downloadLoading = false;
        _offlineCover = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xóa bản tải.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể xóa bản tải: $e')));
    }
  }
  // ============================================================
  // CHAPTERS
  // ============================================================
  double? _parseChapterNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final number = value.toDouble();
      return number.isFinite ? number : null;
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final number = double.tryParse(text);
    if (number == null || !number.isFinite) return null;
    return number;
  }
  String _formatChapterNumber(double number) {
    if (number == number.truncateToDouble()) {
      return number.toInt().toString();
    }
    return number.toString();
  }
  Map<double, List<dynamic>> get groupedChapters {
    final Map<double, List<dynamic>> result = {};
    for (final chapter in chapters) {
      if (chapter is! Map) continue;
      final number = _parseChapterNumber(chapter['chapterNumber']);
      if (number == null) {
        debugPrint(
          'Bỏ qua chapter không có chapterNumber hợp lệ: '
          '${chapter['title']} - ${chapter['chapterNumber']}',
        );
        continue;
      }
      // Nhóm theo phần nguyên của số chapter (1, 1.1, 1.2 cùng nhóm là 1)
      // và (0, 000.1, 000.2 cùng nhóm là 0)
      final groupKey = number.truncateToDouble();
      result.putIfAbsent(groupKey, () => []);
      result[groupKey]!.add(chapter);
    }
    final keys = result.keys.toList()..sort();
    return {for (final number in keys) number: result[number]!};
  }
  int get _totalPages => (groupedChapters.length / _pageSize).ceil();
  Map<double, List<dynamic>> get paginatedChapters {
    final entries = groupedChapters.entries.toList();
    final start = _currentPage * _pageSize;
    if (start >= entries.length) return {};
    final end = (start + _pageSize).clamp(0, entries.length);
    return Map<double, List<dynamic>>.fromEntries(entries.sublist(start, end));
  }
  void _goToPage(int page) {
    if (page < 0 || page >= _totalPages) return;
    setState(() => _currentPage = page);
  }
  void _openChapter(Map chapter) {
    final chapterId = chapter['id'];
    if (chapterId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chương này không có ID hợp lệ.')),
      );
      return;
    }
    final source = chapter['createdBy']?.toString() ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChapterReaderScreen(
          chapterId: chapterId,
          storyId: widget.storyId,
          source: source,
        ),
      ),
    );
  }
  // ============================================================
  // STORY INFORMATION
  // ============================================================
  Widget _buildStoryCover() {
    if (_isOffline) {
      final file = _offlineCover;
      if (file == null) {
        return const SizedBox(
          width: 120,
          height: 180,
          child: Icon(Icons.book, size: 48),
        );
      }
      return Image.file(
        file,
        width: 120,
        height: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          width: 120,
          height: 180,
          child: Icon(Icons.book, size: 48),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: '${ApiConfig.coverImage}/${story['coverUrl'] ?? ''}',
      height: 180,
      width: 120,
      fit: BoxFit.cover,
      placeholder: (_, __) => const SizedBox(
        width: 120,
        height: 180,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, __, ___) => const SizedBox(
        width: 120,
        height: 180,
        child: Icon(Icons.book, size: 48),
      ),
    );
  }
  Widget _buildInformation() {
    final information = story['information'] is List
        ? story['information'] as List
        : <dynamic>[];
    if (information.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text(
              'Thông tin thêm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${information.length} thông tin',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            children: [
              ...information.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                if (item is! Map) {
                  return const SizedBox.shrink();
                }
                final label = item['label']?.toString() ?? '';
                final value = item['value']?.toString() ?? '';
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              value,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index != information.length - 1)
                      Divider(height: 1, color: Colors.grey.shade200),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildStoryInformationContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildStoryCover(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story['title']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Tác giả: ${story['author'] ?? ''}'),
                    const SizedBox(height: 6),
                    Text('Tạo bởi: ${story['createdByName'] ?? ''}'),
                    if (_isOffline) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Đang đọc bản offline',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ExpandableText(text: story['description']?.toString() ?? ''),
        ),
        _buildInformation(),
      ],
    );
  }
  // ============================================================
  // CHAPTER LIST UI
  // ============================================================
  Widget _buildPagination() {
    if (_totalPages <= 1) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Trang đầu',
            onPressed: _currentPage > 0 ? () => _goToPage(0) : null,
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: 'Trang trước',
            onPressed: _currentPage > 0
                ? () => _goToPage(_currentPage - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 100),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Trang ${_currentPage + 1} / $_totalPages',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Trang sau',
            onPressed: _currentPage < _totalPages - 1
                ? () => _goToPage(_currentPage + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Trang cuối',
            onPressed: _currentPage < _totalPages - 1
                ? () => _goToPage(_totalPages - 1)
                : null,
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
    );
  }
  Widget _buildChaptersContent() {
    final grouped = groupedChapters;
    final paginated = paginatedChapters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Danh sách chương',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${grouped.length} chương · '
            '${_totalPages == 0 ? 0 : _currentPage + 1}/$_totalPages trang',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
        if (grouped.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Chưa có chương nào')),
          ),
        ...paginated.entries.map((entry) {
          final chapterNumber = entry.key;
          final chapterList = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Ch. ${_formatChapterNumber(chapterNumber)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              ...chapterList.map((chapter) {
                if (chapter is! Map) {
                  return const SizedBox.shrink();
                }
                final source = chapter['createdBy']?.toString() ?? '';
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.blue,
                    ),
                    title: Text(
                      chapter['title']?.toString() ?? 'Không có tiêu đề',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Source: ${source.isEmpty ? 'Không rõ' : source}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                    ),
                    onTap: () => _openChapter(chapter),
                  ),
                );
              }),
            ],
          );
        }),
        _buildPagination(),
        const SizedBox(height: 20),
      ],
    );
  }
  // ============================================================
  // RESPONSIVE LAYOUT
  // ============================================================
  Widget _buildWindowsLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: init,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [_buildStoryInformationContent()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          flex: 5,
          child: RefreshIndicator(
            onRefresh: init,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [_buildChaptersContent()],
            ),
          ),
        ),
      ],
    );
  }
  Widget _buildMobileLayout() {
    return RefreshIndicator(
      onRefresh: init,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Divider(),
          _buildStoryInformationContent(),
          _buildChaptersContent(),
        ],
      ),
    );
  }
  // ============================================================
  // DOWNLOAD BUTTON AND PROGRESS
  // ============================================================
  Widget _buildDownloadButton() {
    final progress = _downloadNotifier.value;
    final service = StoryDownloadService.instance;
    final active = service.isDownloading(widget.storyId);
    final paused = progress.isPaused || service.isPaused(widget.storyId);
    if (active || progress.isDownloading || paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!paused)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 2.5,
                      value: downloadProgress > 0 ? downloadProgress : null,
                    ),
                    if (progress.total > 0)
                      Text(
                        '${progress.percent}',
                        style: const TextStyle(fontSize: 8),
                      ),
                  ],
                ),
              ),
            ),
          IconButton(
            tooltip: paused ? 'Tiếp tục tải' : 'Tạm dừng tải',
            onPressed: _isOffline
                ? null
                : paused
                ? _resumeDownload
                : _pauseDownload,
            icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          ),
          IconButton(
            tooltip: 'Hủy tải',
            onPressed: _isOffline || downloadActionLoading
                ? null
                : _cancelDownload,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isDownloaded && !_isOffline)
          IconButton(
            tooltip: 'Cập nhật truyện offline',
            onPressed: downloadActionLoading ? null : _downloadStory,
            icon: const Icon(Icons.refresh),
          ),
        IconButton(
          tooltip: _isOffline
              ? 'Đang ở chế độ offline'
              : isDownloaded
              ? 'Xóa bản tải offline'
              : 'Tải truyện offline',
          onPressed: _isOffline || downloadActionLoading
              ? null
              : isDownloaded
              ? _showDeleteDownloadDialog
              : _downloadStory,
          icon: downloadActionLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isDownloaded ? Icons.download_done : Icons.download_outlined,
                  color: isDownloaded ? Colors.green : null,
                ),
        ),
      ],
    );
  }
  Widget _buildDownloadProgressBanner() {
    final progress = _downloadNotifier.value;
    final active = StoryDownloadService.instance.isDownloading(widget.storyId);
    final paused = progress.isPaused || _isDownloadPaused;
    final hasStatus = downloadStatus.isNotEmpty;
    if (!active && !downloadLoading && !hasStatus) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    paused
                        ? 'Đã tạm dừng tải'
                        : downloadStatus.isEmpty
                        ? 'Đang tải truyện...'
                        : downloadStatus,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!paused && active && progress.total > 0)
                  Text('${progress.completed}/${progress.total}'),
                if (!paused && active && progress.total > 0)
                  const SizedBox(width: 8),
                if (!paused && active && progress.total > 0)
                  Text('${progress.percent}%'),
              ],
            ),
            if (active && !paused) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.total > 0 ? progress.progress : null,
              ),
            ],
            if (active && !paused && progress.current.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Đang xử lý: ${progress.current}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (progress.isCancelled) ...[
              const SizedBox(height: 4),
              const Text('Tác vụ tải đã bị hủy.'),
            ],
            if (progress.error != null) ...[
              const SizedBox(height: 4),
              Text(
                progress.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (storyLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (story.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chi tiết truyện')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book, size: 48),
              const SizedBox(height: 12),
              const Text('Không thể tải dữ liệu truyện.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    storyLoading = true;
                  });
                  init();
                },
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(story['title']?.toString() ?? ''),
        actions: [
          _buildDownloadButton(),
          IconButton(
            tooltip: _isOffline
                ? 'Yêu thích cần kết nối mạng'
                : isSaved
                ? 'Bỏ yêu thích'
                : 'Thêm vào yêu thích',
            icon: bookmarkLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isSaved ? Icons.favorite : Icons.favorite_border,
                    color: isSaved ? Colors.red : null,
                  ),
            onPressed: bookmarkLoading ? null : _toggleBookmark,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDownloadProgressBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWindows =
                    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
                final useTwoColumns = isWindows && constraints.maxWidth >= 900;
                if (useTwoColumns) {
                  return _buildWindowsLayout();
                }
                return _buildMobileLayout();
              },
            ),
          ),
        ],
      ),
    );
  }
}
