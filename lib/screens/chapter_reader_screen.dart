import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/last_read.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/User.dart';
import '../services/chapter_fetcher.dart';
import '../services/story_fetcher.dart';
import '../widget/sequential_chapter_image.dart';

class ChapterReaderScreen extends StatefulWidget {
  final int chapterId;
  final int storyId;
  final String source;

  const ChapterReaderScreen({
    super.key,
    required this.chapterId,
    required this.storyId,
    required this.source,
  });

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _listViewKey = GlobalKey();
  final FocusNode _keyboardFocusNode = FocusNode();

  Map<String, dynamic>? chapter;

  List<dynamic> blocks = [];

  // Danh sách chapter của source đang được chọn.
  List<dynamic> chapters = [];

  // Toàn bộ chapter lấy từ storyData['chapters'].
  List<dynamic> _allChapters = [];

  // Các source duy nhất được tìm thấy trong danh sách chapter.
  List<String> _sources = [];

  // Source đang đọc, có thể thay đổi khi người dùng chọn source khác.
  late String currentSource;

  // Ánh xạ vị trí block sang số trang ảnh.
  // -1 nghĩa là block văn bản hoặc không phải ảnh.
  List<int> _imageIndexByBlockIndex = [];

  // Mỗi ảnh có một key để xác định trang đang đọc.
  List<GlobalKey> _imageKeys = [];

  final Set<int> _finishedInitialImageIndexes = {};

  late int currentChapterId;
  late double lastChapterNumber;
  late String lastStoryTitle;
  late String coverUrl;
  late int index;

  int? nextId;
  int? prevId;

  int _totalPages = 0;
  int _currentPage = 0;
  int _initialImageCount = 0;

  bool _allowRemainingImages = false;
  bool loading = true;

  // Mức zoom chỉ áp dụng trên Windows.
  double _zoomScale = 1.0;
  double _maxAllowedZoomScale = 2.5;

  static const double _minZoomScale = 0.5;
  static const double _maxZoomLimit = 2.5;
  static const double _zoomStep = 0.1;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();

    currentChapterId = widget.chapterId;
    currentSource = widget.source;

    _scrollController.addListener(_updateReadingProgress);

    _initData();
  }

  // ============================================================
  // KHỞI TẠO DỮ LIỆU TRUYỆN VÀ DANH SÁCH SOURCE
  // ============================================================

  Future<void> _initData() async {
    try {
      final storyData = await StoryFetcher().fetchStory(widget.storyId);

      final allChapters = storyData['chapters'] as List? ?? [];

      // Lấy danh sách source duy nhất từ createdBy.
      final sourceSet = <String>{};

      for (final item in allChapters) {
        if (item is! Map) continue;

        final source = item['createdBy']?.toString().trim() ?? '';

        if (source.isNotEmpty) {
          sourceSet.add(source);
        }
      }

      final sources = sourceSet.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      var initialSource = widget.source;

      // Nếu source truyền vào không có chapter, thử xác định source
      // dựa trên chapterId ban đầu.
      var initialChapters = _getChaptersBySourceFrom(
        allChapters,
        initialSource,
      );

      if (initialChapters.isEmpty && allChapters.isNotEmpty) {
        final initialChapter = allChapters.cast<dynamic?>().firstWhere(
          (item) => _chapterIdOf(item) == widget.chapterId,
          orElse: () => null,
        );

        if (initialChapter != null) {
          initialSource = initialChapter['createdBy']?.toString().trim() ?? '';
        }

        if (initialSource.isEmpty && sources.isNotEmpty) {
          initialSource = sources.first;
        }

        initialChapters = _getChaptersBySourceFrom(allChapters, initialSource);
      }

      if (!mounted) return;

      setState(() {
        _allChapters = allChapters;
        _sources = sources;
        currentSource = initialSource;
        chapters = initialChapters;

        lastStoryTitle = storyData['title']?.toString() ?? '';
        coverUrl = storyData['coverUrl']?.toString() ?? '';
      });

      // Nếu chapterId không thuộc source được chọn, chọn chapter đầu
      // trong source đó để tránh danh sách chương không khớp nội dung.
      var targetChapterId = widget.chapterId;

      final chapterExists = chapters.any(
        (item) => _chapterIdOf(item) == targetChapterId,
      );

      if (!chapterExists && chapters.isNotEmpty) {
        targetChapterId = _chapterIdOf(chapters.first) ?? widget.chapterId;
      }

      await _fetchChapter(targetChapterId);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      debugPrint('Lỗi tải thông tin truyện: $e');
    }
  }

  int? _chapterIdOf(dynamic item) {
    if (item is! Map) return null;

    final value = item['id'];

    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '');
  }

  double _parseChapterNumber(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<dynamic> _getChaptersBySourceFrom(
    List<dynamic> sourceChapters,
    String source,
  ) {
    final filtered = sourceChapters.where((item) {
      if (item is! Map) return false;

      final createdBy = item['createdBy']?.toString().trim() ?? '';

      return createdBy == source;
    }).toList();

    filtered.sort((a, b) {
      final numberA = _parseChapterNumber(a['chapterNumber']);
      final numberB = _parseChapterNumber(b['chapterNumber']);

      final comparison = numberA.compareTo(numberB);

      if (comparison != 0) return comparison;

      return (_chapterIdOf(a) ?? 0).compareTo(_chapterIdOf(b) ?? 0);
    });

    return filtered;
  }

  List<dynamic> _getChaptersBySource(String source) {
    return _getChaptersBySourceFrom(_allChapters, source);
  }

  // ============================================================
  // ĐỔI SOURCE
  // ============================================================

  Future<void> _changeSource(String newSource) async {
    if (newSource == currentSource || loading) return;

    final filtered = _getChaptersBySource(newSource);

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Source "$newSource" không có chapter.')),
      );
      return;
    }

    setState(() {
      currentSource = newSource;
      chapters = filtered;

      // Không thay đổi currentChapterId.
      // Không fetch chapter mới.
    });

    _updateNextPrev();
  }

  // ============================================================
  // TẢI CHAPTER
  // ============================================================

  Future<void> _fetchChapter(int id) async {
    if (!mounted) return;

    setState(() {
      loading = true;
    });

    try {
      final data = await ChapterFetcher().fetchChapter(id);

      if (!mounted) return;

      final newBlocks = List<dynamic>.from(data['blocks'] ?? []);

      final imageIndexByBlockIndex = <int>[];
      var imageCount = 0;

      for (final block in newBlocks) {
        if (block is Map && block['type'] == 'image') {
          imageIndexByBlockIndex.add(imageCount);
          imageCount++;
        } else {
          imageIndexByBlockIndex.add(-1);
        }
      }

      final imageKeys = List<GlobalKey>.generate(
        imageCount,
        (_) => GlobalKey(),
      );

      currentChapterId = id;
      _updateNextPrev();

      setState(() {
        chapter = data;
        blocks = newBlocks;

        _imageIndexByBlockIndex = imageIndexByBlockIndex;
        _imageKeys = imageKeys;

        _totalPages = imageCount;
        _currentPage = imageCount > 0 ? 1 : 0;

        // Chỉ tải trước tối đa 3 ảnh đầu tiên.
        _initialImageCount = imageCount < 3 ? imageCount : 3;

        _finishedInitialImageIndexes.clear();
        _allowRemainingImages = imageCount == 0;

        lastChapterNumber = _parseChapterNumber(data['chapterNumber']);

        loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
          _keyboardFocusNode.requestFocus();
          _updateReadingProgress();
        }
      });

      // Lưu lịch sử đọc theo source hiện tại.
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');

      if (userString != null) {
        final user = User.fromJson(jsonDecode(userString));

        await LastRead().updateLastRead(
          user.id,
          widget.storyId,
          currentChapterId,
          currentSource,
        );
      } else {
        await _saveLastRead(id);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      debugPrint('Lỗi tải chương: $e');
    }
  }

  void _onInitialImageFinished(int chapterId, int imageIndex) {
    if (!mounted || chapterId != currentChapterId) return;
    if (imageIndex >= _initialImageCount) return;
    if (!_finishedInitialImageIndexes.add(imageIndex)) return;

    if (_finishedInitialImageIndexes.length >= _initialImageCount) {
      setState(() {
        _allowRemainingImages = true;
      });
    }
  }

  // ============================================================
  // THEO DÕI TIẾN ĐỘ ĐỌC
  // ============================================================

  void _updateReadingProgress() {
    if (!_scrollController.hasClients || _totalPages == 0) {
      return;
    }

    final listContext = _listViewKey.currentContext;
    final listObject = listContext?.findRenderObject();

    if (listObject is! RenderBox || !listObject.hasSize) {
      return;
    }

    final viewportTop = listObject.localToGlobal(Offset.zero).dy;

    int? lastPageStarted;
    int? firstAvailablePage;
    int? visiblePage;

    for (int i = 0; i < _imageKeys.length; i++) {
      final imageContext = _imageKeys[i].currentContext;
      final imageObject = imageContext?.findRenderObject();

      if (imageObject is! RenderBox || !imageObject.hasSize) {
        continue;
      }

      final imageTop = imageObject.localToGlobal(Offset.zero).dy;
      final imageBottom = imageTop + imageObject.size.height;

      firstAvailablePage ??= i + 1;

      if (imageTop <= viewportTop) {
        lastPageStarted = i + 1;
      }

      if (imageTop <= viewportTop && imageBottom > viewportTop) {
        visiblePage = i + 1;
        break;
      }
    }

    final newPage = visiblePage ?? lastPageStarted ?? firstAvailablePage ?? 1;

    if (newPage != _currentPage && mounted) {
      setState(() {
        _currentPage = newPage;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateReadingProgress);
    _scrollController.dispose();
    _keyboardFocusNode.dispose();

    super.dispose();
  }

  // ============================================================
  // CHAPTER TRƯỚC / SAU
  // ============================================================

  void _updateNextPrev() {
    index = chapters.indexWhere(
      (item) => _chapterIdOf(item) == currentChapterId,
    );

    if (index == -1) {
      nextId = null;
      prevId = null;
      return;
    }

    prevId = index > 0 ? _chapterIdOf(chapters[index - 1]) : null;

    nextId = index < chapters.length - 1
        ? _chapterIdOf(chapters[index + 1])
        : null;
  }

  Future<void> _saveLastRead(int chapterId) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('lastStoryId', widget.storyId);
    await prefs.setInt('lastChapterId', chapterId);
    await prefs.setString('lastReadCreatedById', currentSource);
  }

  void _goNext() {
    if (loading) return;

    if (nextId != null) {
      _fetchChapter(nextId!);
    } else {
      showDialog(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text('Thông báo'),
          content: Text('Đây là chương cuối rồi'),
        ),
      );
    }
  }

  void _goPrev() {
    if (loading) return;

    if (prevId != null) {
      _fetchChapter(prevId!);
    }
  }

  // ============================================================
  // CUỘN TRANG
  // ============================================================

  void _scrollBy(double offset) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;

    final target = (_scrollController.offset + offset)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  // Ctrl + lăn chuột trên Windows để phóng to hoặc thu nhỏ.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_isWindows || event is! PointerScrollEvent) {
      return;
    }

    if (!HardwareKeyboard.instance.isControlPressed) {
      return;
    }

    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      if (!mounted || resolvedEvent is! PointerScrollEvent) {
        return;
      }

      if (!HardwareKeyboard.instance.isControlPressed) {
        return;
      }

      final delta = resolvedEvent.scrollDelta.dy;

      if (delta == 0) return;

      setState(() {
        final change = delta < 0 ? _zoomStep : -_zoomStep;

        _zoomScale = (_zoomScale + change)
            .clamp(_minZoomScale, _maxAllowedZoomScale)
            .toDouble();
      });
    });
  }

  KeyEventResult _handleKeyboardEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _scrollBy(-100);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        _scrollBy(100);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft:
        if (event is KeyDownEvent) {
          _goPrev();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        if (event is KeyDownEvent) {
          _goNext();
        }
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  // ============================================================
  // SIDEBAR WINDOWS
  // ============================================================

  Widget _buildWindowsSidebar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 64,
      color: colorScheme.surfaceContainer,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            IconButton(
              tooltip: 'Chương trước (←)',
              onPressed: loading ? null : _goPrev,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              tooltip: 'Về trang chủ',
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              icon: const Icon(Icons.home),
            ),
            IconButton(
              tooltip: 'Danh sách chương',
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
              icon: const Icon(Icons.menu_book),
            ),
            const Divider(),
            IconButton(
              tooltip: 'Cuộn lên (↑)',
              onPressed: () => _scrollBy(-400),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: 'Cuộn xuống (↓)',
              onPressed: () => _scrollBy(400),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            const Spacer(),
            RotatedBox(
              quarterTurns: 3,
              child: Text(
                _totalPages == 0 ? '0 / 0' : '$_currentPage / $_totalPages',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const SizedBox(height: 12),
            IconButton(
              tooltip: 'Chương tiếp theo (→)',
              onPressed: loading ? null : _goNext,
              icon: const Icon(Icons.skip_next),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HIỂN THỊ NỘI DUNG CHAPTER
  // ============================================================

  Widget buildBlock(dynamic block, int blockIndex, double zoomScale) {
    if (block is! Map) {
      return const SizedBox.shrink();
    }

    if (block['type'] == 'text') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16 * zoomScale),
        child: Text(
          block['data']?.toString() ?? '',
          style: TextStyle(fontSize: 18 * zoomScale, height: 1.5),
        ),
      );
    }

    if (block['type'] == 'image') {
      final imageIndex = _imageIndexByBlockIndex[blockIndex];

      final shouldLoad =
          imageIndex < _initialImageCount || _allowRemainingImages;

      final image = SequentialChapterImage(
        key: _imageKeys[imageIndex],
        imageUrl: '${ApiConfig.chapterImage}/${block['data']}',
        shouldLoad: shouldLoad,
        onLoadFinished: imageIndex < _initialImageCount
            ? () => _onInitialImageFinished(currentChapterId, imageIndex)
            : null,
      );

      final isFirstImage = imageIndex == 0;
      final isLastImage = imageIndex == _totalPages - 1;

      if (!isFirstImage && !isLastImage) {
        return image;
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final edgeWidth = constraints.maxWidth * 0.2;

          return Stack(
            children: [
              image,
              if (isFirstImage)
                Positioned(
                  top: 0,
                  left: 0,
                  bottom: 0,
                  width: edgeWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _goPrev,
                    child: const SizedBox.expand(),
                  ),
                ),
              if (isLastImage)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: edgeWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _goNext,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          );
        },
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildChapterContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        final desiredWidth = (constraints.maxHeight * 0.7)
            .clamp(320.0, 900.0)
            .toDouble();

        // Chiều rộng cơ sở không vượt quá vùng đọc hiện có.
        final baseContentWidth = desiredWidth < availableWidth
            ? desiredWidth
            : availableWidth;

        // Giới hạn zoom theo chiều ngang khả dụng.
        final maxZoomByWidth = baseContentWidth > 0
            ? availableWidth / baseContentWidth
            : 1.0;

        _maxAllowedZoomScale = maxZoomByWidth
            .clamp(1.0, _maxZoomLimit)
            .toDouble();

        final effectiveZoom = _zoomScale
            .clamp(_minZoomScale, _maxAllowedZoomScale)
            .toDouble();

        final contentWidth = (baseContentWidth * effectiveZoom)
            .clamp(0.0, availableWidth)
            .toDouble();

        // ListView chiếm toàn bộ chiều rộng vùng đọc.
        return SizedBox(
          width: availableWidth,
          height: constraints.maxHeight,
          child: ListView(
            key: _listViewKey,
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            cacheExtent: 500,
            children: [
              for (int i = 0; i < blocks.length; i++)
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: _handlePointerSignal,
                  child: SizedBox(
                    width: availableWidth,
                    child: Center(
                      child: SizedBox(
                        width: contentWidth,
                        child: buildBlock(blocks[i], i, effectiveZoom),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // THANH ĐIỀU HƯỚNG PHÍA DƯỚI
  // ============================================================

  Widget _buildBottomNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Chương trước',
            onPressed: loading ? null : _goPrev,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Về trang chủ',
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            icon: const Icon(Icons.home, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Danh sách chương',
            onPressed: () {
              _scaffoldKey.currentState?.openDrawer();
            },
            icon: const Icon(Icons.menu, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Chương tiếp theo',
            onPressed: loading ? null : _goNext,
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DROPDOWN CHỌN SOURCE
  // ============================================================

  Widget _buildSourceSelector() {
    if (_sources.isEmpty) {
      return const SizedBox.shrink();
    }

    final availableSources = _sources.toSet();

    // Bảo đảm giá trị hiện tại luôn hợp lệ với DropdownButton.
    final selectedSource = availableSources.contains(currentSource)
        ? currentSource
        : _sources.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nguồn truyện', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(selectedSource),
            initialValue: selectedSource,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: _sources.map((source) {
              final count = _getChaptersBySource(source).length;

              return DropdownMenuItem<String>(
                value: source,
                child: Text(
                  '$source ($count chương)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: loading
                ? null
                : (source) {
                    if (source != null) {
                      _changeSource(source);
                    }
                  },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GIAO DIỆN CHÍNH
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // Chỉ hiển thị màn hình chờ riêng khi chưa có chapter đầu tiên.
    // Khi chuyển source, giữ Scaffold và Drawer để không mất danh sách.
    if (chapter == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: '${ApiConfig.coverImage}/$coverUrl',
                        width: 80,
                        height: 110,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) {
                          return const SizedBox(
                            width: 80,
                            height: 110,
                            child: Icon(Icons.book),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StoryDetailScreen(storyId: widget.storyId),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lastStoryTitle,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text('Ch. $lastChapterNumber'),
                            const SizedBox(height: 4),
                            Text(
                              'Nguồn: $currentSource',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Chọn source và lọc lại danh sách chapter.
              _buildSourceSelector(),

              if (loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),

              if (!loading && chapters.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Source này chưa có chapter.'),
                ),

              // Danh sách chapter thuộc source hiện tại.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: chapters.length,
                  itemBuilder: (context, chapterIndex) {
                    final c = chapters[chapterIndex];
                    final chapterId = _chapterIdOf(c);
                    final isCurrent = chapterId == currentChapterId;

                    return Material(
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: loading || chapterId == null
                            ? null
                            : () {
                                // Đóng Drawer rồi tải chapter được chọn.
                                Navigator.pop(context);
                                _fetchChapter(chapterId);
                              },
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'Ch. ${c['chapterNumber']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrent
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${chapter!['title']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              currentSource,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.menu_book, size: 18),
                const SizedBox(width: 8),
                Text(
                  _totalPages == 0
                      ? 'Không có trang ảnh'
                      : 'Trang $_currentPage / $_totalPages',
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                if (loading)
                  const Text(
                    'Đang tải chương...',
                    style: TextStyle(fontSize: 11),
                  )
                else if (!_allowRemainingImages && _initialImageCount > 0)
                  const Text(
                    'Đang tải ảnh đầu...',
                    style: TextStyle(fontSize: 11),
                  ),
                if (_isWindows)
                  Text(
                    '  ${(_zoomScale * 100).round()}%',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Focus(
              focusNode: _keyboardFocusNode,
              autofocus: true,
              onKeyEvent: _handleKeyboardEvent,
              child: Row(
                children: [
                  // Sidebar nằm ngoài vùng nhận sự kiện cuộn và zoom.
                  if (_isWindows) _buildWindowsSidebar(),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerSignal: _handlePointerSignal,
                      child: _buildChapterContent(),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _isWindows ? null : _buildBottomNavigationBar(),
    );
  }
}
