import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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

  Map<String, dynamic>? chapter;

  List<dynamic> blocks = [];
  List<dynamic> chapters = [];

  // Ánh xạ vị trí block sang số trang ảnh.
  // -1 nghĩa là block văn bản hoặc không phải ảnh.
  List<int> _imageIndexByBlockIndex = [];

  // Mỗi ảnh có một key để xác định trang đang nằm tại đầu vùng đọc.
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

  @override
  void initState() {
    super.initState();

    currentChapterId = widget.chapterId;

    _scrollController.addListener(_updateReadingProgress);

    _initData();
  }

  Future<void> _initData() async {
    try {
      final storyData = await StoryFetcher().fetchStory(widget.storyId);
      final raw = storyData["chapters"] as List;

      final filtered = raw.where((c) {
        return c["createdBy"] == widget.source;
      }).toList();

      filtered.sort(
            (a, b) => (a["chapterNumber"] as double)
            .compareTo(b["chapterNumber"] as double),
      );

      if (!mounted) return;

      setState(() {
        chapters = filtered;
        lastStoryTitle = storyData["title"];
        coverUrl = storyData["coverUrl"];
      });

      await _fetchChapter(currentChapterId);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      debugPrint('Lỗi tải thông tin truyện: $e');
    }
  }

  Future<void> _fetchChapter(int id) async {
    if (!mounted) return;

    setState(() {
      loading = true;
    });

    try {
      final data = await ChapterFetcher().fetchChapter(id);

      if (!mounted) return;

      final newBlocks = List<dynamic>.from(data["blocks"] ?? []);

      // Tạo danh sách trang ảnh và ánh xạ block -> trang.
      final imageIndexByBlockIndex = <int>[];
      int imageCount = 0;

      for (final block in newBlocks) {
        if (block["type"] == "image") {
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

        // Các ảnh còn lại chưa được phép tải.
        // Nếu chương không có ảnh thì không cần chờ.
        _allowRemainingImages = imageCount == 0;

        lastChapterNumber = data["chapterNumber"];
        loading = false;
      });

      // Đưa nội dung về đầu chương mới.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
          _updateReadingProgress();
        }
      });

      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString("user");

      if (userString != null) {
        final user = User.fromJson(jsonDecode(userString));

        await LastRead().updateLastRead(
          user.id,
          widget.storyId,
          currentChapterId,
          widget.source,
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

  /// Được gọi khi một trong 3 ảnh đầu tải xong hoặc tải lỗi.
  ///
  /// Chỉ khi cả 3 ảnh đầu hoàn tất, các ảnh còn lại mới được phép tải.
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

  /// Cập nhật số trang đang đọc dựa trên vị trí thực tế của ảnh.
  void _updateReadingProgress() {
    if (!_scrollController.hasClients || _totalPages == 0) return;

    final listContext = _listViewKey.currentContext;
    final listObject = listContext?.findRenderObject();

    if (listObject is! RenderBox || !listObject.hasSize) return;

    final viewportTop = listObject.localToGlobal(Offset.zero).dy;

    int? lastPageStarted;
    int? firstAvailablePage;
    int? visiblePage;

    for (int i = 0; i < _imageKeys.length; i++) {
      final imageContext = _imageKeys[i].currentContext;
      final imageObject = imageContext?.findRenderObject();

      if (imageObject is! RenderBox || !imageObject.hasSize) continue;

      final imageTop = imageObject.localToGlobal(Offset.zero).dy;
      final imageBottom = imageTop + imageObject.size.height;

      firstAvailablePage ??= i + 1;

      if (imageTop <= viewportTop) {
        lastPageStarted = i + 1;
      }

      // Nếu đầu vùng đọc đang nằm trong ảnh này, đây là trang hiện tại.
      if (imageTop <= viewportTop && imageBottom > viewportTop) {
        visiblePage = i + 1;
        break;
      }
    }

    final newPage =
        visiblePage ?? lastPageStarted ?? firstAvailablePage ?? 1;

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
    super.dispose();
  }

  void _updateNextPrev() {
    index = chapters.indexWhere((c) => c["id"] == currentChapterId);

    if (index == -1) {
      nextId = null;
      prevId = null;
      return;
    }

    prevId = index > 0 ? chapters[index - 1]["id"] : null;
    nextId = index < chapters.length - 1 ? chapters[index + 1]["id"] : null;
  }

  Future<void> _saveLastRead(int chapterId) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt("lastStoryId", widget.storyId);
    await prefs.setInt("lastChapterId", chapterId);
    await prefs.setString("lastReadCreatedById", widget.source);
  }

  void _goNext() {
    if (nextId != null) {
      _fetchChapter(nextId!);
    } else {
      showDialog(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text("Thông báo"),
          content: Text("Đây là chương cuối rồi"),
        ),
      );
    }
  }

  void _goPrev() {
    if (prevId != null) {
      _fetchChapter(prevId!);
    }
  }

  Widget buildBlock(dynamic block, int blockIndex) {
    if (block["type"] == "text") {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Text(
          block["data"] ?? "",
          style: const TextStyle(
            fontSize: 18,
            height: 1.5,
          ),
        ),
      );
    }

    if (block["type"] == "image") {
      final imageIndex = _imageIndexByBlockIndex[blockIndex];

      final shouldLoad =
          imageIndex < _initialImageCount || _allowRemainingImages;

      final image = SequentialChapterImage(
        key: _imageKeys[imageIndex],
        imageUrl: '${ApiConfig.chapterImage}/${block['data']}',
        shouldLoad: shouldLoad,
        onLoadFinished: imageIndex < _initialImageCount
            ? () => _onInitialImageFinished(
          currentChapterId,
          imageIndex,
        )
            : null,
      );

      final isFirstImage = imageIndex == 0;
      final isLastImage = imageIndex == _totalPages - 1;

      // Chỉ ảnh đầu và ảnh cuối có vùng chạm chuyển chương.
      if (!isFirstImage && !isLastImage) {
        return image;
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final edgeWidth = constraints.maxWidth * 0.2;

          return Stack(
            children: [
              image,

              // Rìa trái ảnh đầu: về chương trước.
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

              // Rìa phải ảnh cuối: sang chương sau.
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

  @override
  Widget build(BuildContext context) {
    if (loading || chapter == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: "${ApiConfig.coverImage}/$coverUrl",
                      width: 80,
                      height: 110,
                      fit: BoxFit.cover,
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
                          Text("Ch. $lastChapterNumber"),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.2,
                ),
                itemCount: chapters.length,
                itemBuilder: (context, index) {
                  final c = chapters[index];
                  final isCurrent = c["id"] == currentChapterId;

                  return Material(
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.pop(context);
                        _fetchChapter(c["id"]);
                      },
                      child: Center(
                        child: Text(
                          "Ch. ${c["chapterNumber"]}",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isCurrent
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color,
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("${chapter!["title"]}"),
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
                if (!_allowRemainingImages && _initialImageCount > 0)
                  const Text(
                    'Đang tải ảnh đầu...',
                    style: TextStyle(fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        key: _listViewKey,
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        cacheExtent: 500,
        children: [
          for (int i = 0; i < blocks.length; i++)
            buildBlock(blocks[i], i),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.black87,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: _goPrev,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            IconButton(
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              icon: const Icon(Icons.home, color: Colors.white),
            ),
            IconButton(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu, color: Colors.white),
            ),
            IconButton(
              onPressed: _goNext,
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}