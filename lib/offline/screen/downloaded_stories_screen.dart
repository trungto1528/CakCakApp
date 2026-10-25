import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:novel_app/offline/service/story_download_service.dart';
import 'package:path_provider/path_provider.dart';
class DownloadedStory {
  final int id;
  final String title;
  final String author;
  final String directoryPath;
  final String? coverPath;
  final int imageCount;
  final int sizeBytes;
  final DateTime? downloadedAt;
  const DownloadedStory({
    required this.id,
    required this.title,
    required this.author,
    required this.directoryPath,
    required this.coverPath,
    required this.imageCount,
    required this.sizeBytes,
    required this.downloadedAt,
  });
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}
class DownloadedStoriesScreen extends StatefulWidget {
  const DownloadedStoriesScreen({super.key});
  @override
  State<DownloadedStoriesScreen> createState() =>
      _DownloadedStoriesScreenState();
}
class _DownloadedStoriesScreenState extends State<DownloadedStoriesScreen> {
  List<DownloadedStory> _stories = [];
  bool _loading = true;
  String? _error;
  int _totalSize = 0;
  @override
  void initState() {
    super.initState();
    _loadDownloadedStories();
  }
  Future<Directory> _getOfflineRoot() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/offline_stories');
  }
  Future<int> _calculateDirectorySize(Directory directory) async {
    var total = 0;
    if (!await directory.exists()) return total;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // Bỏ qua file không thể đọc.
        }
      }
    }
    return total;
  }
  Future<List<DownloadedStory>> _scanDownloadedStories() async {
    final root = await _getOfflineRoot();
    if (!await root.exists()) {
      return [];
    }
    final result = <DownloadedStory>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final storyId = int.tryParse(
        entity.path.split(Platform.pathSeparator).last,
      );
      if (storyId == null) continue;
      final completeFile = File('${entity.path}/complete.json');
      final metadataFile = File('${entity.path}/metadata.json');
      // Chỉ hiển thị truyện đã có marker hoàn tất.
      if (!await completeFile.exists() ||
          !await metadataFile.exists()) {
        continue;
      }
      try {
        final manifestJson = jsonDecode(
          await completeFile.readAsString(),
        );
        final metadataJson = jsonDecode(
          await metadataFile.readAsString(),
        );
        if (manifestJson is! Map || metadataJson is! Map) {
          continue;
        }
        if (manifestJson['storyId'] != null &&
            int.tryParse(manifestJson['storyId'].toString()) != storyId) {
          continue;
        }
        final title = metadataJson['title']?.toString().trim();
        final author = metadataJson['author']?.toString().trim() ?? '';
        final images = manifestJson['images'] is List
            ? List<String>.from(
          (manifestJson['images'] as List).map(
                (item) => item.toString(),
          ),
        )
            : <String>[];
        String? coverPath;
        for (final image in images) {
          if (image.replaceAll('\\', '/').startsWith('cover/')) {
            final normalized = image.replaceAll(
              '/',
              Platform.pathSeparator,
            );
            final file = File('${entity.path}/$normalized');
            if (await file.exists() && await file.length() > 0) {
              coverPath = file.path;
              break;
            }
          }
        }
        final downloadedAtText =
        manifestJson['downloadedAt']?.toString();
        final downloadedAt = downloadedAtText == null
            ? null
            : DateTime.tryParse(downloadedAtText);
        final size = await _calculateDirectorySize(entity);
        result.add(
          DownloadedStory(
            id: storyId,
            title: title == null || title.isEmpty
                ? 'Truyện #$storyId'
                : title,
            author: author,
            directoryPath: entity.path,
            coverPath: coverPath,
            imageCount: images.length,
            sizeBytes: size,
            downloadedAt: downloadedAt,
          ),
        );
      } catch (e) {
        debugPrint('Không đọc được dữ liệu truyện $storyId: $e');
      }
    }
    result.sort((a, b) {
      final dateA = a.downloadedAt;
      final dateB = b.downloadedAt;
      if (dateA == null && dateB == null) {
        return a.title.compareTo(b.title);
      }
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA);
    });
    return result;
  }
  Future<void> _loadDownloadedStories() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final stories = await _scanDownloadedStories();
      if (!mounted) return;
      setState(() {
        _stories = stories;
        _totalSize = stories.fold<int>(
          0,
              (total, story) => total + story.sizeBytes,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  String _formatDate(DateTime? date) {
    if (date == null) return 'Không rõ ngày tải';
    final local = date.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/'
        '${local.year} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
  Future<void> _deleteStory(DownloadedStory story) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa truyện đã tải?'),
        content: Text(
          'Bạn có chắc muốn xóa "${story.title}" khỏi thiết bị?\n\n'
              'Dung lượng sẽ được giải phóng: ${story.formattedSize}.',
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
      await StoryDownloadService.instance.deleteDownloadedStory(
        story.id,
      );
      await _loadDownloadedStories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xóa "${story.title}"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể xóa truyện: $e')),
      );
    }
  }
  Future<void> _deleteAllStories() async {
    if (_stories.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa tất cả truyện offline?'),
        content: Text(
          'Sẽ xóa ${_stories.length} truyện, giải phóng khoảng '
              '${_formatSize(_totalSize)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa tất cả'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var deletedCount = 0;
    final errors = <String>[];
    for (final story in List<DownloadedStory>.from(_stories)) {
      try {
        await StoryDownloadService.instance.deleteDownloadedStory(
          story.id,
        );
        deletedCount++;
      } catch (e) {
        errors.add('${story.title}: $e');
      }
    }
    await _loadDownloadedStories();
    if (!mounted) return;
    final message = errors.isEmpty
        ? 'Đã xóa $deletedCount truyện'
        : 'Đã xóa $deletedCount truyện; còn ${errors.length} truyện chưa xóa được';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  Widget _buildCover(DownloadedStory story) {
    final path = story.coverPath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
      );
    }
    return _buildCoverPlaceholder();
  }
  Widget _buildCoverPlaceholder() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.menu_book_rounded, size: 38),
      ),
    );
  }
  Widget _buildSummary() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.storage_outlined, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_stories.length} truyện đã tải',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đang sử dụng ${_formatSize(_totalSize)} bộ nhớ',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (_stories.isNotEmpty)
              IconButton(
                tooltip: 'Xóa tất cả',
                onPressed: _deleteAllStories,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ],
        ),
      ),
    );
  }
  Widget _buildStoryCard(DownloadedStory story) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 84,
                height: 116,
                child: _buildCover(story),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (story.author.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Tác giả: ${story.author}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 7),
                  Text('${story.imageCount} ảnh'),
                  Text(story.formattedSize),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(story.downloadedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Xóa bản tải',
              onPressed: () => _deleteStory(story),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('Không thể đọc danh sách truyện đã tải'),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadDownloadedStories,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_stories.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadDownloadedStories,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.download_for_offline_outlined, size: 72),
            SizedBox(height: 16),
            Center(
              child: Text(
                'Chưa có truyện nào được tải',
                style: TextStyle(fontSize: 16),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                'Những truyện tải hoàn tất sẽ xuất hiện tại đây.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadDownloadedStories,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _buildSummary(),
          ..._stories.map(_buildStoryCard),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Truyện đã tải'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loadDownloadedStories,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
