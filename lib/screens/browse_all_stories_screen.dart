import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/config/api_config.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/story_fetcher.dart';
class BrowseAllStoriesScreen extends StatefulWidget {
  const BrowseAllStoriesScreen({super.key});
  @override
  State<BrowseAllStoriesScreen> createState() => _BrowseAllStoriesScreenState();
}
class _BrowseAllStoriesScreenState extends State<BrowseAllStoriesScreen> {
  final ScrollController _scrollController = ScrollController();
  final StoryFetcher _storyFetcher = StoryFetcher();
  static const int _pageSize = 20;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _initialLoading = true;
  String? _errorMessage;
  // Spring Data PageRequest đánh số trang từ 0.
  int _page = 0;
  int? _totalStories;
  final Set<int> _loadedStoryIds = {};
  final List<Map<String, dynamic>> _allStories = [];
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadStoriesPage(0);
  }
  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _isLoading) {
      return;
    }
    if (_scrollController.position.extentAfter < 200) {
      _loadStoriesPage(_page + 1);
    }
  }
  Future<void> _loadStoriesPage(int page) async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await _storyFetcher.fetchStoriesPage(page, _pageSize);
      if (!mounted) return;
      final stories = result['stories'] as List<Map<String, dynamic>>;
      final newStories = <Map<String, dynamic>>[];
      for (final story in stories) {
        final id = int.tryParse('${story['id']}');
        if (id != null && !_loadedStoryIds.add(id)) {
          continue;
        }
        newStories.add(story);
      }
      setState(() {
        _allStories.addAll(newStories);
        _page = (result['page'] as int?) ?? page;
        final total = result['totalElements'];
        if (total is num) {
          _totalStories = total.toInt();
        }
        _hasMore = result['hasNext'] == true;
        _initialLoading = false;
      });
    } catch (e) {
      debugPrint('Lỗi tải trang truyện $page: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể tải truyện. Vui lòng thử lại.';
        _initialLoading = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  void _retryLoading() {
    if (_isLoading) return;
    if (_allStories.isEmpty) {
      _hasMore = true;
      _loadStoriesPage(0);
    } else {
      _hasMore = true;
      _loadStoriesPage(_page + 1);
    }
  }
  void _onStoryTap(Map<String, dynamic> story) {
    final id = int.tryParse('${story['id']}');
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoryDetailScreen(storyId: id)),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tất cả truyện'),
            Text(
              _totalStories == null
                  ? 'Đang tải số lượng...'
                  : 'Tổng $_totalStories truyện',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }
  Widget _buildBody() {
    if (_initialLoading && _allStories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_allStories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage ?? 'Chưa có truyện nào'),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _retryLoading,
                  child: const Text('Thử lại'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _allStories.length + 1,
      itemBuilder: (context, index) {
        if (index < _allStories.length) {
          return _buildStoryItem(_allStories[index]);
        }
        if (_errorMessage != null && !_isLoading) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: _retryLoading,
                child: const Text('Tải thêm thất bại. Thử lại'),
              ),
            ),
          );
        }
        if (_isLoading) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!_hasMore && _allStories.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 28,
                  color: Colors.grey,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bạn đã xem hết danh sách truyện',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Đã tải ${_allStories.length}'
                  '${_totalStories != null ? ' / $_totalStories' : ''} truyện',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
  Widget _buildStoryItem(Map<String, dynamic> story) {
    final title = story['title']?.toString() ?? 'Chưa có tên';
    final rawCover = story['coverUrl']?.toString() ?? '';
    final cover = rawCover.trim();
    final imageUrl = cover.isEmpty
        ? ''
        : (cover.startsWith('http://') || cover.startsWith('https://')
              ? cover
              : '${ApiConfig.coverImage}/$cover');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: imageUrl.isEmpty
              ? const SizedBox(width: 60, height: 80, child: Icon(Icons.book))
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: 60,
                  height: 80,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox(
                    width: 60,
                    height: 80,
                    child: Icon(Icons.book),
                  ),
                ),
        ),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => _onStoryTap(story),
      ),
    );
  }
}
