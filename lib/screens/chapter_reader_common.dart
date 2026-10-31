import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/last_read.dart';
import 'package:novel_app/services/reading_list.dart';

import '../config/api_config.dart';
import '../models/User.dart';
import '../offline/service/offline_entry_service.dart';
import '../offline/service/offline_mode_service.dart';
import '../services/app_preference.dart';
import '../services/chapter_fetcher.dart';
import '../services/story_fetcher.dart';
import '../widget/sequential_chapter_image.dart';

abstract class ChapterReaderScreenStateBase<T extends StatefulWidget>
    extends State<T> {
  final ScrollController scrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final PageController _pageController = PageController();

  final GlobalKey<ScaffoldState> _scaffoldKey =
  GlobalKey<ScaffoldState>();

  final GlobalKey _listViewKey = GlobalKey();
  final GlobalKey _readerViewportKey = GlobalKey();

  final FocusNode _keyboardFocusNode = FocusNode();

  final TransformationController transformController =
  TransformationController();

  // Windows continuous mode: toàn bộ chương được biến đổi như một canvas.
  final TransformationController _windowsCanvasController =
  TransformationController();
  final GlobalKey _windowsCanvasKey = GlobalKey();

  bool _mobileZoomed = false;

  final Set<int> _activePointers = <int>{};

  Size _mobileViewport = Size.zero;

  Map<String, dynamic>? chapter;

  List<dynamic> blocks = [];
  List<dynamic> chapters = [];
  List<dynamic> _allChapters = [];

  List<String> sources = [];

  late String currentSource;

  List<int> _imageIndexByBlockIndex = [];
  List<int> _imageBlockIndexes = [];

  List<GlobalKey> _imageKeys = [];

  final Set<int> _finishedInitialImageIndexes = {};

  bool _isCtrlZooming = false;

  late int currentChapterId;
  late double lastChapterNumber;
  late String lastStoryTitle;
  late String coverUrl;
  late int index;

  int? nextId;
  int? prevId;

  int totalPages = 0;
  int currentPage = 0;
  int initialImageCount = 0;

  bool allowRemainingImages = false;
  bool useOfflineImages = false;
  bool loading = true;

  double zoomScale = 1.0;
  double maxAllowedZoomScale = 2.5;
  double scrollSensitivity = 1.0;

  double lastAvailableWidth = 0.0;
  double lastBaseContentWidth = 0.0;

  static const double minZoomScale = 0.5;
  static const double maxZoomLimit = 3.5;
  static const double zoomStep = 0.1;

  int chapterId = 0;
  int storyId = 0;

  String source = '';

  bool usePageMode = false;

  bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get isMobile =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);

  bool get isOffline => OfflineModeService.isOffline.value;

  // ============================================================
  // CÀI ĐẶT
  // ============================================================

  Future<void> loadReaderSettings() async {
    try {
      final prefs = await AppPreferences.getInstance();

      final sensitivity =
          prefs.getDouble('reader_scroll_sensitivity') ?? 1.0;

      final pageMode =
          prefs.getBool('reader_page_mode') ?? false;

      if (!mounted) return;

      setState(() {
        scrollSensitivity =
            sensitivity.clamp(0.5, 10.0).toDouble();

        usePageMode = pageMode;
      });
    } catch (e) {
      debugPrint('Không thể tải thông tin cài đặt: $e');
    }
  }

  /// Chuyển chế độ đọc sang trạng thái được chỉ định.
  /// Giao diện được cập nhật ngay, không phải chờ lưu Preferences.
  Future<void> setReaderMode(bool nextMode) async {
    if (nextMode == usePageMode) return;

    if (!usePageMode) {
      updateReadingProgress();
    }

    if (!mounted) return;

    setState(() {
      usePageMode = nextMode;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || totalPages == 0) return;

      final targetPage =
      (currentPage - 1).clamp(0, totalPages - 1);

      if (nextMode) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(targetPage);
        }
      } else {
        _jumpToImage(targetPage);
      }
    });

    try {
      final prefs = await AppPreferences.getInstance();

      await prefs.setBool('reader_page_mode', nextMode);
    } catch (e) {
      debugPrint('Không thể lưu chế độ đọc: $e');
    }
  }

  /// Giữ lại hàm toggle để tương thích với các vị trí gọi hiện tại.
  Future<void> toggleReaderMode() async {
    await setReaderMode(!usePageMode);
  }

  /// Lưu độ nhạy cuộn.
  Future<void> _saveScrollSensitivity(double value) async {
    final normalizedValue =
    value.clamp(0.5, 10.0).toDouble();

    try {
      final prefs = await AppPreferences.getInstance();

      await prefs.setDouble(
        'reader_scroll_sensitivity',
        normalizedValue,
      );
    } catch (e) {
      debugPrint('Không thể lưu độ nhạy cuộn: $e');
    }
  }

  Future<void> showReaderSettingsDialog() async {
    var selectedPageMode = usePageMode;
    var selectedSensitivity = scrollSensitivity;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cài đặt đọc'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chế độ hiển thị',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Switch.adaptive(
                          value: selectedPageMode,
                          onChanged: (value) {
                            setDialogState(() {
                              selectedPageMode = value;
                            });

                            // Chuyển chế độ đọc ngay khi gạt công tắc.
                            setReaderMode(value);
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedPageMode
                                ? 'Đang ở chế độ từng trang'
                                : 'Đang ở chế độ cuộn',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (isWindows) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Độ nhạy cuộn',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${selectedSensitivity.toStringAsFixed(1)}x',
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: selectedSensitivity,
                              min: 0.5,
                              max: 10.0,
                              divisions: 95,
                              label:
                              '${selectedSensitivity.toStringAsFixed(1)}x',
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedSensitivity = value;
                                });

                                // Áp dụng độ nhạy ngay khi kéo.
                                if (mounted) {
                                  setState(() {
                                    scrollSensitivity = value
                                        .clamp(0.5, 10.0)
                                        .toDouble();
                                  });
                                }
                              },
                              onChangeEnd: (value) {
                                // Lưu sau khi người dùng kết thúc kéo.
                                _saveScrollSensitivity(value);
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 44,
                            child: TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  selectedSensitivity = 1.0;
                                });

                                // Đặt lại độ nhạy và áp dụng ngay.
                                if (mounted) {
                                  setState(() {
                                    scrollSensitivity = 1.0;
                                  });
                                }

                                // Lưu giá trị mặc định ngay lập tức.
                                _saveScrollSensitivity(1.0);
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(40, 36),
                              ),
                              child: const Text('1x'),
                            ),
                          ),
                        ],
                      ),
                      const Row(
                        mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Chậm',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Nhanh',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Áp dụng cho con lăn chuột, phím mũi tên lên/xuống '
                            'và nút cuộn.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // KHỞI TẠO TRUYỆN
  // ============================================================

  Future<void> initData() async {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }

    try {
      final storyData =
      await StoryFetcher().fetchStory(storyId);

      final allChapters = storyData['chapters'] is List
          ? List<dynamic>.from(storyData['chapters'])
          : <dynamic>[];

      final sourceSet = <String>{};

      for (final item in allChapters) {
        if (item is! Map) continue;

        final itemSource =
            item['createdBy']?.toString().trim() ?? '';

        if (itemSource.isNotEmpty) {
          sourceSet.add(itemSource);
        }
      }

      final sourceList = sourceSet.toList()
        ..sort(
              (a, b) =>
              a.toLowerCase().compareTo(b.toLowerCase()),
        );

      var initialSource = source;

      var initialChapters = getChaptersBySourceFrom(
        allChapters,
        initialSource,
      );

      if (initialChapters.isEmpty && allChapters.isNotEmpty) {
        dynamic initialChapter;

        for (final item in allChapters) {
          if (chapterIdOf(item) == chapterId) {
            initialChapter = item;
            break;
          }
        }

        if (initialChapter is Map) {
          initialSource =
              initialChapter['createdBy']?.toString().trim() ?? '';
        }

        if (initialSource.isEmpty && sourceList.isNotEmpty) {
          initialSource = sourceList.first;
        }

        initialChapters = getChaptersBySourceFrom(
          allChapters,
          initialSource,
        );
      }

      if (!mounted) return;

      setState(() {
        _allChapters = allChapters;
        sources = sourceList;
        currentSource = initialSource;
        chapters = initialChapters;

        lastStoryTitle =
            storyData['title']?.toString() ?? '';

        coverUrl =
            storyData['coverUrl']?.toString() ?? '';
      });

      var targetChapterId = chapterId;

      final chapterExists = chapters.any(
            (item) => chapterIdOf(item) == targetChapterId,
      );

      if (!chapterExists && chapters.isNotEmpty) {
        targetChapterId =
            chapterIdOf(chapters.first) ?? chapterId;
      }

      await fetchChapter(targetChapterId);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      debugPrint('Lỗi tải thông tin truyện: $e');

      showError('Không thể tải thông tin truyện: $e');
    }
  }

  int? chapterIdOf(dynamic item) {
    if (item is! Map) return null;

    final value = item['id'];

    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '');
  }

  double parseChapterNumber(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<dynamic> getChaptersBySourceFrom(
      List<dynamic> sourceChapters,
      String source,
      ) {
    final filtered = sourceChapters.where((item) {
      if (item is! Map) return false;

      return (item['createdBy']?.toString().trim() ?? '') ==
          source;
    }).toList();

    filtered.sort((a, b) {
      final numberA =
      parseChapterNumber(a['chapterNumber']);

      final numberB =
      parseChapterNumber(b['chapterNumber']);

      final comparison = numberA.compareTo(numberB);

      if (comparison != 0) return comparison;

      return (chapterIdOf(a) ?? 0)
          .compareTo(chapterIdOf(b) ?? 0);
    });

    return filtered;
  }

  List<dynamic> getChaptersBySource(String source) =>
      getChaptersBySourceFrom(_allChapters, source);

  // ============================================================
  // ĐỔI SOURCE
  // ============================================================

  Future<void> changeSource(String newSource) async {
    if (newSource == currentSource || loading) return;

    final filtered = getChaptersBySource(newSource);

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Source "$newSource" không có chapter.'),
        ),
      );

      return;
    }

    setState(() {
      currentSource = newSource;
      chapters = filtered;
    });

    updateNextPrev();
  }

  // ============================================================
  // TẢI CHƯƠNG
  // ============================================================

  Future<void> fetchChapter(
      int id, {
        bool openAtLastPage = false,
      }) async {
    if (!mounted) return;

    setState(() {
      loading = true;
    });

    try {
      final data = await ChapterFetcher().fetchChapter(
        id,
        storyId: storyId,
      );

      if (!mounted) return;

      final newBlocks =
      List<dynamic>.from(data['blocks'] ?? []);

      final imageIndexByBlockIndex = <int>[];
      final imageBlockIndexes = <int>[];

      var imageCount = 0;

      for (int i = 0; i < newBlocks.length; i++) {
        final block = newBlocks[i];

        if (block is Map && block['type'] == 'image') {
          imageIndexByBlockIndex.add(imageCount);
          imageBlockIndexes.add(i);
          imageCount++;
        } else {
          imageIndexByBlockIndex.add(-1);
        }
      }

      bool offlineImages = false;

      final storyAvailable =
      await OfflineEntryService.instance.isStoryAvailable(
        storyId,
      );

      if (storyAvailable) {
        offlineImages =
        await OfflineEntryService.instance.isChapterAvailable(
          storyId,
          id,
        );
      }

      final imageKeys = List<GlobalKey>.generate(
        imageCount,
            (_) => GlobalKey(),
      );

      currentChapterId = id;

      setState(() {
        chapter = data;

        blocks = newBlocks;

        _imageIndexByBlockIndex =
            imageIndexByBlockIndex;

        _imageBlockIndexes = imageBlockIndexes;

        _imageKeys = imageKeys;

        totalPages = imageCount;

        currentPage = imageCount > 0
            ? (openAtLastPage ? imageCount : 1)
            : 0;

        // Tất cả ảnh của chương được phép tải ngay, không chờ cuộn tới.
        initialImageCount = 0;
        _finishedInitialImageIndexes.clear();
        allowRemainingImages = true;

        useOfflineImages = offlineImages;

        zoomScale = 1.0;
        _isCtrlZooming = false;

        transformController.value = Matrix4.identity();
        _windowsCanvasController.value = Matrix4.identity();

        _mobileZoomed = false;
        _activePointers.clear();

        lastChapterNumber =
            parseChapterNumber(data['chapterNumber']);

        loading = false;
      });

      updateNextPrev();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || currentChapterId != id) return;

        // Preload toàn bộ ảnh ngay sau khi nhận dữ liệu chương.
        // Việc này đảm bảo ảnh ở các vị trí chưa được ListView/PageView
        // dựng lên cũng bắt đầu tải, không phải đợi người dùng cuộn tới.
        if (!useOfflineImages) {
          for (final block in newBlocks) {
            if (block is! Map || block['type'] != 'image') {
              continue;
            }

            final imageName = block['data']?.toString() ?? '';
            if (imageName.isEmpty) continue;

            final imageUrl = '${ApiConfig.chapterImage}/$imageName';

            precacheImage(
              CachedNetworkImageProvider(imageUrl),
              context,
            ).then<void>(
                  (_) {},
              onError: (Object error, StackTrace stackTrace) {
                debugPrint('Lỗi preload ảnh $imageName: $error');
              },
            );
          }
        }

        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }

        if (_horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(0);
        }

        if (_pageController.hasClients) {
          _pageController.jumpToPage(
            openAtLastPage && totalPages > 0 ? totalPages - 1 : 0,
          );
        }

        if (openAtLastPage &&
            !usePageMode &&
            scrollController.hasClients) {
          scrollController.jumpTo(
            scrollController.position.maxScrollExtent,
          );
        }

        _keyboardFocusNode.requestFocus();

        if (!openAtLastPage) {
          updateReadingProgress();
        }
      });

      await saveReadingHistory(id);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      debugPrint('Lỗi tải chương: $e');

      showError('Không thể tải chương: $e');
    }
  }

  Future<void> saveReadingHistory(int chapterId) async {
    try {
      final prefs = await AppPreferences.getInstance();

      final userString = prefs.getString('user');

      if (userString != null) {
        final user = User.fromJson(jsonDecode(userString));

        await LastRead().updateLastRead(
          user.id,
          storyId,
          chapterId,
          currentSource,
        );

        await ReadingList().save(
          user.id,
          storyId,
          chapterId,
        );
      } else {
        await saveLastRead(chapterId);
      }
    } catch (e) {
      debugPrint('Không thể lưu lịch sử đọc: $e');
    }
  }

  void showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void onInitialImageFinished(
      int chapterId,
      int imageIndex,
      ) {
    if (!mounted || chapterId != currentChapterId) return;

    if (imageIndex >= initialImageCount) return;

    if (!_finishedInitialImageIndexes.add(imageIndex)) {
      return;
    }

    if (_finishedInitialImageIndexes.length >=
        initialImageCount) {
      setState(() {
        allowRemainingImages = true;
      });
    }
  }

  // ============================================================
  // TIẾN ĐỘ ĐỌC
  // ============================================================

  void updateReadingProgress() {
    if (usePageMode || totalPages == 0) return;

    RenderBox? viewportObject;

    if (isWindows) {
      final object = _readerViewportKey.currentContext?.findRenderObject();
      if (object is RenderBox && object.hasSize) {
        viewportObject = object;
      }
    } else {
      if (!scrollController.hasClients) return;
      final object = _listViewKey.currentContext?.findRenderObject();
      if (object is RenderBox && object.hasSize) {
        viewportObject = object;
      }
    }

    if (viewportObject == null) return;

    final viewportTop = viewportObject.localToGlobal(Offset.zero).dy;
    int? lastPageStarted;
    int? firstAvailablePage;
    int? visiblePage;
    int? nearestFollowingPage;
    double nearestFollowingDistance = double.infinity;

    for (int i = 0; i < _imageKeys.length; i++) {
      final imageObject = _imageKeys[i].currentContext?.findRenderObject();
      if (imageObject is! RenderBox || !imageObject.hasSize) continue;

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

      if (imageTop > viewportTop) {
        final distance = imageTop - viewportTop;
        if (distance < nearestFollowingDistance) {
          nearestFollowingDistance = distance;
          nearestFollowingPage = i + 1;
        }
      }
    }

    final newPage = visiblePage ??
        lastPageStarted ??
        nearestFollowingPage ??
        firstAvailablePage ??
        1;

    if (newPage != currentPage && mounted) {
      setState(() => currentPage = newPage);
    }
  }

  void _scheduleReadingProgressUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || usePageMode || _isCtrlZooming) return;
      updateReadingProgress();
    });
  }

  void onPageChanged(int page) {
    if (!mounted) return;

    final newPage = page + 1;

    if (newPage == currentPage) return;

    setState(() {
      currentPage = newPage;
    });
  }

  @override
  void dispose() {
    scrollController.removeListener(updateReadingProgress);

    transformController.removeListener(onTransformChanged);

    scrollController.dispose();
    _horizontalScrollController.dispose();
    _pageController.dispose();

    _keyboardFocusNode.dispose();

    transformController.dispose();
    _windowsCanvasController.dispose();

    super.dispose();
  }

  // ============================================================
  // ĐIỀU HƯỚNG CHƯƠNG
  // ============================================================

  void updateNextPrev() {
    index = chapters.indexWhere(
          (item) => chapterIdOf(item) == currentChapterId,
    );

    if (index == -1) {
      nextId = null;
      prevId = null;
      return;
    }

    prevId =
    index > 0 ? chapterIdOf(chapters[index - 1]) : null;

    nextId = index < chapters.length - 1
        ? chapterIdOf(chapters[index + 1])
        : null;
  }

  Future<void> saveLastRead(int chapterId) async {
    final prefs = await AppPreferences.getInstance();

    await prefs.setInt('lastStoryId', storyId);

    await prefs.setInt('lastChapterId', chapterId);

    await prefs.setString(
      'lastReadCreatedById',
      currentSource,
    );
  }

  /// Nút điều hướng chương luôn chuyển chương, không phụ thuộc chế độ đọc.
  void goNext() {
    if (loading) return;

    if (nextId != null) {
      fetchChapter(nextId!);
    } else {
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text('Thông báo'),
          content: Text('Đây là chương cuối rồi'),
        ),
      );
    }
  }

  /// Chuyển về chương trước và mở tại ảnh cuối của chương đó.
  void goPrev() {
    if (loading) return;

    if (prevId != null) {
      fetchChapter(prevId!, openAtLastPage: true);
    }
  }

  /// Nhảy một trang/ảnh trong chương. Chỉ khi đã ở biên mới chuyển chương.
  void goNextPage() {
    if (loading || totalPages <= 0) return;

    if (currentPage < totalPages) {
      final targetIndex = currentPage; // currentPage là 1-based.
      if (usePageMode) {
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      } else {
        _jumpToImage(targetIndex, animate: true);
      }
      return;
    }

    goNext();
  }

  void goPrevPage() {
    if (loading || totalPages <= 0) return;

    if (currentPage > 1) {
      final targetIndex = currentPage - 2; // 0-based.
      if (usePageMode) {
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      } else {
        _jumpToImage(targetIndex, animate: true);
      }
      return;
    }

    goPrev();
  }

  void handleReaderTap(TapUpDetails details, double width) {
    if (loading || width <= 0) return;

    // Khi đang phóng to trên Android, ưu tiên thao tác pan/zoom.
    if (isMobile && _mobileZoomed) return;

    final tapX = details.localPosition.dx;
    final zoneWidth = width / 3;

    // 1/3 bên trái: Trang trước.
    if (tapX < zoneWidth) {
      goPrevPage();
      return;
    }

    // 1/3 bên phải: Trang tiếp theo.
    if (tapX > width - zoneWidth) {
      goNextPage();
      return;
    }

    // 1/3 chính giữa: Không thực hiện thao tác.
  }

  void _jumpToImage(int imageIndex, {bool animate = false}) {
    if (imageIndex < 0 || imageIndex >= _imageKeys.length) return;

    if (isWindows && !usePageMode) {
      final imageObject =
      _imageKeys[imageIndex].currentContext?.findRenderObject();
      final viewportObject =
      _readerViewportKey.currentContext?.findRenderObject();

      if (imageObject is RenderBox &&
          imageObject.hasSize &&
          viewportObject is RenderBox &&
          viewportObject.hasSize) {
        final imageTop = imageObject.localToGlobal(Offset.zero).dy;
        final viewportTop = viewportObject.localToGlobal(Offset.zero).dy;
        final matrix = _windowsCanvasController.value.clone();
        final translation = matrix.getTranslation();
        matrix.setTranslationRaw(
          translation.x,
          translation.y + viewportTop - imageTop,
          0,
        );
        _applyWindowsCanvasMatrix(matrix, updateScale: false);
      }
      return;
    }

    final imageContext = _imageKeys[imageIndex].currentContext;
    if (imageContext != null) {
      Scrollable.ensureVisible(
        imageContext,
        alignment: 0,
        duration: animate
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        curve: Curves.easeOut,
      );
      return;
    }

    // ListView.builder có thể chưa dựng widget ảnh ở xa. Trong trường hợp
    // đó cuộn gần một viewport để đưa ảnh kế tiếp vào vùng cache/dựng widget.
    if (scrollController.hasClients) {
      final position = scrollController.position;
      final direction = imageIndex + 1 > currentPage ? 1.0 : -1.0;
      final target = (position.pixels +
          direction * position.viewportDimension)
          .clamp(0.0, position.maxScrollExtent)
          .toDouble();

      if (animate) {
        scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        scrollController.jumpTo(target);
      }
    }
  }

  // ============================================================
  // CUỘN VÀ ZOOM WINDOWS
  // ============================================================

  // ============================================================
  // WINDOWS CANVAS: CUỘN VÀ ZOOM TOÀN BỘ CHƯƠNG
  // ============================================================

  Size _windowsCanvasViewportSize() {
    final object = _readerViewportKey.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize ? object.size : Size.zero;
  }

  Size _windowsCanvasContentSize() {
    final object = _windowsCanvasKey.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize ? object.size : Size.zero;
  }

  Matrix4 _clampWindowsCanvasMatrix(Matrix4 source) {
    final viewport = _windowsCanvasViewportSize();
    final content = _windowsCanvasContentSize();
    if (viewport.isEmpty || content.isEmpty) return source;

    final matrix = source.clone();
    final scale = matrix
        .getMaxScaleOnAxis()
        .clamp(minZoomScale, maxZoomLimit)
        .toDouble();
    final scaledWidth = content.width * scale;
    final scaledHeight = content.height * scale;
    final translation = matrix.getTranslation();

    final minX = scaledWidth <= viewport.width
        ? (viewport.width - scaledWidth) / 2
        : viewport.width - scaledWidth;
    final maxX = scaledWidth <= viewport.width ? minX : 0.0;
    final minY = scaledHeight <= viewport.height
        ? (viewport.height - scaledHeight) / 2
        : viewport.height - scaledHeight;
    final maxY = scaledHeight <= viewport.height ? minY : 0.0;

    matrix.setTranslationRaw(
      translation.x.clamp(minX, maxX).toDouble(),
      translation.y.clamp(minY, maxY).toDouble(),
      0,
    );
    return matrix;
  }

  void _applyWindowsCanvasMatrix(Matrix4 matrix, {bool updateScale = true}) {
    if (!isWindows || !mounted) return;

    final clamped = _clampWindowsCanvasMatrix(matrix);
    _windowsCanvasController.value = clamped;

    if (updateScale) {
      final nextScale = clamped
          .getMaxScaleOnAxis()
          .clamp(minZoomScale, maxZoomLimit)
          .toDouble();
      if ((nextScale - zoomScale).abs() > 0.0001) {
        setState(() => zoomScale = nextScale);
      }
    }

    _scheduleReadingProgressUpdate();
  }

  void _translateWindowsCanvas(double dx, double dy) {
    if (!isWindows || usePageMode) return;

    final matrix = _windowsCanvasController.value.clone();
    final translation = matrix.getTranslation();
    matrix.setTranslationRaw(
      translation.x + dx,
      translation.y + dy,
      0,
    );
    _applyWindowsCanvasMatrix(matrix, updateScale: false);
  }

  void scrollBy(double offset) {
    if (isWindows && !usePageMode) {
      _translateWindowsCanvas(0, -offset * scrollSensitivity);
      return;
    }

    if (!scrollController.hasClients) return;
    if (usePageMode && totalPages > 0) return;

    final position = scrollController.position;
    final adjustedOffset =
    isWindows ? offset * scrollSensitivity : offset;
    final target = (scrollController.offset + adjustedOffset)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();

    scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  void scrollByWheel(double delta) {
    if (!isWindows) return;

    if (!usePageMode) {
      _translateWindowsCanvas(0, -delta * scrollSensitivity);
      return;
    }

    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final target = (position.pixels + delta * scrollSensitivity)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() > 0.1) {
      scrollController.jumpTo(target);
    }
  }

  void scrollHorizontallyByWheel(double delta) {
    if (!isWindows) return;

    if (!usePageMode) {
      _translateWindowsCanvas(-delta * scrollSensitivity, 0);
      return;
    }

    if (!_horizontalScrollController.hasClients) return;
    final position = _horizontalScrollController.position;
    final target = (position.pixels + delta * scrollSensitivity)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() > 0.1) {
      _horizontalScrollController.jumpTo(target);
    }
  }

  void handlePointerSignal(PointerSignalEvent event) {
    if (!isWindows || event is! PointerScrollEvent) return;

    final delta = event.scrollDelta.dy;
    final horizontalDelta = event.scrollDelta.dx;
    final ctrlPressed = HardwareKeyboard.instance.isControlPressed;

    if (!ctrlPressed) {
      if (_isCtrlZooming && mounted) {
        setState(() => _isCtrlZooming = false);
        _scheduleReadingProgressUpdate();
      }

      final useHorizontalScroll =
          HardwareKeyboard.instance.isShiftPressed ||
              horizontalDelta.abs() > 0.0;
      if (useHorizontalScroll) {
        scrollHorizontallyByWheel(
          horizontalDelta.abs() > 0.0 ? horizontalDelta : delta,
        );
      } else {
        scrollByWheel(delta);
      }
      return;
    }

    if (!_isCtrlZooming && mounted) {
      setState(() => _isCtrlZooming = true);
    }

    final viewport = _windowsCanvasViewportSize();
    if (viewport.isEmpty) return;

    if (usePageMode) {
      // Chế độ từng trang vẫn giữ cơ chế zoom theo chiều rộng cũ.
      final oldScale = zoomScale;
      final nextScale = (oldScale * math.exp(-delta * 0.0008))
          .clamp(minZoomScale, maxZoomLimit)
          .toDouble();
      if ((nextScale - oldScale).abs() < 0.0001) return;

      final center = viewport.center(Offset.zero);
      final ratio = nextScale / oldScale;
      if (_horizontalScrollController.hasClients) {
        final position = _horizontalScrollController.position;
        final target = (position.pixels + center.dx) * ratio - center.dx;
        _horizontalScrollController.jumpTo(
          target.clamp(0.0, position.maxScrollExtent).toDouble(),
        );
      }
      setState(() => zoomScale = nextScale);
      return;
    }

    final oldMatrix = _windowsCanvasController.value.clone();
    final oldScale = oldMatrix.getMaxScaleOnAxis();
    final nextScale = (oldScale * math.exp(-delta * 0.0008))
        .clamp(minZoomScale, maxZoomLimit)
        .toDouble();
    if ((nextScale - oldScale).abs() < 0.0001) return;

    // Zoom toàn bộ canvas quanh tâm viewport, không theo từng ảnh và
    // không phụ thuộc vị trí con trỏ chuột.
    final center = viewport.center(Offset.zero);
    final ratio = nextScale / oldScale;
    final nextMatrix = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..scale(ratio)
      ..translate(-center.dx, -center.dy)
      ..multiply(oldMatrix);

    _applyWindowsCanvasMatrix(nextMatrix);
  }

  // ============================================================
  // ZOOM MOBILE
  // ============================================================

  void onTransformChanged() {
    final zoomed =
        transformController.value.getMaxScaleOnAxis() > 1.01;

    if (zoomed != _mobileZoomed && mounted) {
      setState(() {
        _mobileZoomed = zoomed;
      });
    }
  }

  void handleMobilePointerMove(PointerMoveEvent event) {
    if (!isMobile ||
        !_mobileZoomed ||
        _activePointers.length != 1) {
      return;
    }

    final size = _mobileViewport;

    if (size.isEmpty) return;

    final matrix = transformController.value.clone();

    final scale = matrix.getMaxScaleOnAxis();

    final translation = matrix.getTranslation();

    final minX = size.width - size.width * scale;

    final minY = size.height - size.height * scale;

    final newX =
    (translation.x + event.delta.dx)
        .clamp(minX, 0.0)
        .toDouble();

    final dy = event.delta.dy;

    final desiredY = translation.y + dy;

    final newY =
    desiredY.clamp(minY, 0.0).toDouble();

    final leftover = desiredY - newY;

    if (leftover != 0 && scrollController.hasClients) {
      final pos = scrollController.position;

      final target =
      (scrollController.offset - leftover / scale)
          .clamp(0.0, pos.maxScrollExtent)
          .toDouble();

      scrollController.jumpTo(target);
    }

    matrix.setTranslationRaw(newX, newY, 0);

    transformController.value = matrix;
  }

  // ============================================================
  // BÀN PHÍM
  // ============================================================

  KeyEventResult handleKeyboardEvent(
      FocusNode node,
      KeyEvent event,
      ) {
    if (isWindows &&
        (event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight)) {
      final isPressed =
          event is KeyDownEvent || event is KeyRepeatEvent;

      if (_isCtrlZooming != isPressed && mounted) {
        setState(() {
          _isCtrlZooming = isPressed;
        });
        if (!isPressed) {
          _scheduleReadingProgressUpdate();
        }
      }

      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent &&
        event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        scrollBy(-100);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        scrollBy(100);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft:
        if (event is KeyDownEvent) goPrev();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        if (event is KeyDownEvent) goNext();
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  void handleFocusChange(bool hasFocus) {
    if (hasFocus) return;

    if (_isCtrlZooming && mounted) {
      setState(() {
        _isCtrlZooming = false;
      });
      _scheduleReadingProgressUpdate();
    }
  }

  // ============================================================
  // SIDEBAR WINDOWS
  // ============================================================

  Widget buildWindowsSidebar() {
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
              onPressed: loading ? null : goPrev,
              icon: const Icon(Icons.skip_previous),
            ),

            IconButton(
              tooltip: 'Về trang chủ',
              onPressed: () {
                Navigator.popUntil(
                  context,
                      (route) => route.isFirst,
                );
              },
              icon: const Icon(Icons.home),
            ),

            IconButton(
              tooltip: 'Danh sách chương',
              onPressed: () =>
                  _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_book),
            ),

            const Divider(),

            const Spacer(),

            RotatedBox(
              quarterTurns: 3,
              child: Text(
                totalPages == 0
                    ? '0 / 0'
                    : '$currentPage / $totalPages',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),

            const SizedBox(height: 12),

            IconButton(
              tooltip: 'Chương tiếp theo (→)',
              onPressed: loading ? null : goNext,
              icon: const Icon(Icons.skip_next),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ẢNH BÌA
  // ============================================================

  Widget buildCoverImage() {
    if (isOffline) {
      return FutureBuilder<File?>(
        future: OfflineEntryService.instance.getImage(
          storyId,
          'cover/$coverUrl',
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const SizedBox(
              width: 80,
              height: 110,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final file = snapshot.data;

          if (file == null) return coverPlaceholder();

          return Image.file(
            file,
            width: 80,
            height: 110,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                coverPlaceholder(),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: '${ApiConfig.coverImage}/$coverUrl',
      width: 80,
      height: 110,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => coverPlaceholder(),
    );
  }

  Widget coverPlaceholder() {
    return const SizedBox(
      width: 80,
      height: 110,
      child: Icon(Icons.book),
    );
  }

  // ============================================================
  // NỘI DUNG BLOCK
  // ============================================================

  Widget buildBlock(
      dynamic block,
      int blockIndex,
      double effectiveZoom,
      double contentWidth, {
        bool pageMode = false,
        double pageHeight = 0,
      }) {
    if (block is! Map) {
      return const SizedBox.shrink();
    }

    if (block['type'] == 'text') {
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: 8,
          horizontal: 16 * effectiveZoom,
        ),
        child: Text(
          block['data']?.toString() ?? '',
          style: TextStyle(
            fontSize: 18 * effectiveZoom,
            height: 1.5,
          ),
        ),
      );
    }

    if (block['type'] == 'image') {
      final imageIndex =
      _imageIndexByBlockIndex[blockIndex];

      if (imageIndex < 0 ||
          imageIndex >= _imageKeys.length) {
        return const SizedBox.shrink();
      }

      final imageName =
          block['data']?.toString() ?? '';

      // Không trì hoãn tải ảnh theo vị trí cuộn/trang hiện tại.
      const shouldLoad = true;

      return _ReaderChapterImage(
        key: _imageKeys[imageIndex],
        storyId: storyId,
        imageName: imageName,
        imageUrl:
        '${ApiConfig.chapterImage}/$imageName',
        offline: useOfflineImages,
        shouldLoad: shouldLoad,
        width: contentWidth,
        pageMode: pageMode,
        fitToPage: effectiveZoom <= 1.0001,
        pageHeight: pageHeight,
        onLoadFinished: null,
      );
    }

    return const SizedBox.shrink();
  }

  // ============================================================
  // CHẾ ĐỘ CUỘN LIÊN TỤC
  // ============================================================

  Widget buildScrollContent(
      double availableWidth,
      double availableHeight,
      double contentWidth,
      double effectiveZoom,
      ) {
    return Center(
      child: SizedBox(
        width: contentWidth,
        height: availableHeight,
        child: Align(
          alignment: Alignment.topCenter,
          child: AbsorbPointer(
            // Chặn cuộn thông thường khi đang Ctrl + wheel trên Windows.
            // Trên Android, nhường gesture cho InteractiveViewer khi zoom/pinch.
            absorbing: (isWindows && _isCtrlZooming) ||
                (isMobile &&
                    (_mobileZoomed || _activePointers.length >= 2)),
            child: ListView.builder(
              key: _listViewKey,
              controller: scrollController,
              physics: (isWindows ||
                  (isMobile &&
                      (_mobileZoomed || _activePointers.length >= 2)))
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              cacheExtent: 500,
              itemCount: blocks.length,
              itemBuilder: (context, i) {
                return SizedBox(
                  width: contentWidth,
                  child: buildBlock(
                    blocks[i],
                    i,
                    effectiveZoom,
                    contentWidth,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CHẾ ĐỘ ĐỌC TỪNG TRANG
  // ============================================================

  Widget buildSinglePageContent(
      double contentWidth,
      double effectiveZoom,
      double availableHeight,
      ) {
    if (totalPages == 0) {
      return const Center(
        child: Text('Chương này không có ảnh.'),
      );
    }

    return SizedBox.expand(
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: totalPages,
        onPageChanged: onPageChanged,
        itemBuilder: (context, pageIndex) {
          final blockIndex =
          _imageBlockIndexes[pageIndex];

          return SizedBox.expand(
            child: Center(
              child: buildBlock(
                blocks[blockIndex],
                blockIndex,
                effectiveZoom,
                contentWidth,
                pageMode: true,
                pageHeight: availableHeight,
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // DỰNG NỘI DUNG CHƯƠNG
  // ============================================================

  Widget buildWindowsCanvas(
      double availableWidth,
      double availableHeight,
      double baseContentWidth,
      ) {
    return InteractiveViewer(
      transformationController: _windowsCanvasController,
      constrained: false,
      panEnabled: true,
      scaleEnabled: false,
      minScale: minZoomScale,
      maxScale: maxZoomLimit,
      boundaryMargin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      onInteractionUpdate: (_) => _scheduleReadingProgressUpdate(),
      child: SizedBox(
        key: _windowsCanvasKey,
        width: availableWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(blocks.length, (blockIndex) {
            return SizedBox(
              width: availableWidth,
              child: Center(
                child: SizedBox(
                  width: baseContentWidth,
                  child: buildBlock(
                    blocks[blockIndex],
                    blockIndex,
                    1.0,
                    baseContentWidth,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget buildChapterContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        final availableHeight = constraints.maxHeight;

        final desiredWidth = (availableHeight * 0.7)
            .clamp(320.0, 900.0)
            .toDouble();

        final baseContentWidth =
        desiredWidth < availableWidth
            ? desiredWidth
            : availableWidth;

        lastAvailableWidth = availableWidth;

        lastBaseContentWidth = baseContentWidth;

        final effectiveZoom =
        isWindows ? zoomScale : 1.0;

        if (isWindows) {
          // Không giới hạn zoom theo kích thước fit của cửa sổ.
          // Người đọc có thể phóng to đến maxZoomLimit trên mọi màn hình.
          maxAllowedZoomScale = maxZoomLimit;
        }

        if (isWindows && !usePageMode) {
          return SizedBox(
            width: availableWidth,
            height: availableHeight,
            child: buildWindowsCanvas(
              availableWidth,
              availableHeight,
              baseContentWidth,
            ),
          );
        }

        final contentWidth =
        (baseContentWidth * effectiveZoom)
            .clamp(1.0, 5000.0)
            .toDouble();

        return SizedBox(
          width: availableWidth,
          height: availableHeight,
          child: Center(
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: contentWidth,
                height: availableHeight,
                child: usePageMode
                    ? buildSinglePageContent(
                  contentWidth,
                  effectiveZoom,
                  availableHeight,
                )
                    : buildScrollContent(
                  availableWidth,
                  availableHeight,
                  contentWidth,
                  effectiveZoom,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // VÙNG ĐỌC THEO NỀN TẢNG
  // ============================================================

  Widget buildReaderBody() {
    final content = buildChapterContent();

    Widget addPageTapNavigation(Widget child) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) =>
                handleReaderTap(details, constraints.maxWidth),
            child: child,
          );
        },
      );
    }

    if (isWindows) {
      return Listener(
        key: _readerViewportKey,
        behavior: HitTestBehavior.translucent,
        onPointerSignal: handlePointerSignal,
        child: addPageTapNavigation(content),
      );
    }

    if (isMobile) {
      return LayoutBuilder(
        builder: (context, constraints) {
          _mobileViewport = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              final wasMultiTouch = _activePointers.length >= 2;
              _activePointers.add(e.pointer);

              // Khi ngón thứ hai chạm xuống, dừng ngay chuyển động cuộn
              // đang diễn ra để gesture pinch được ưu tiên.
              if (!wasMultiTouch && _activePointers.length >= 2) {
                if (scrollController.hasClients) {
                  scrollController.position.hold(() {});
                }
                if (mounted) setState(() {});
              }
            },
            onPointerUp: (e) {
              final wasMultiTouch = _activePointers.length >= 2;
              _activePointers.remove(e.pointer);
              if (wasMultiTouch &&
                  _activePointers.length < 2 &&
                  mounted) {
                setState(() {});
              }
            },
            onPointerCancel: (e) {
              final wasMultiTouch = _activePointers.length >= 2;
              _activePointers.remove(e.pointer);
              if (wasMultiTouch &&
                  _activePointers.length < 2 &&
                  mounted) {
                setState(() {});
              }
            },
            onPointerMove: handleMobilePointerMove,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) =>
                  handleReaderTap(details, constraints.maxWidth),
              child: InteractiveViewer(
                key: ValueKey(
                  'mobile-reader-$currentChapterId',
                ),
                transformationController:
                transformController,
                minScale: 1.0,
                maxScale: maxZoomLimit,
                scaleEnabled: true,
                // Khi giữ 2 ngón, bật pan mặc định để có thể vừa giữ pinch
                // vừa kéo ảnh theo kiểu ứng dụng xem ảnh trên điện thoại.
                // Khi chỉ còn 1 ngón, tắt pan mặc định để tránh pan hai lần;
                // handleMobilePointerMove sẽ xử lý pan và chuyển phần kéo dư
                // thành cuộn nội dung khi ảnh chạm biên.
                panEnabled: _activePointers.length >= 2,
                constrained: true,
                clipBehavior: Clip.hardEdge,
                boundaryMargin: EdgeInsets.zero,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: content,
                ),
              ),
            ),
          );
        },
      );
    }

    return addPageTapNavigation(content);
  }

  // ============================================================
  // THANH ĐIỀU HƯỚNG DƯỚI
  // ============================================================

  Widget buildBottomNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: loading ? null : goPrev,
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
            ),
            tooltip: 'Chương trước',
          ),

          IconButton(
            onPressed: () {
              Navigator.popUntil(
                context,
                    (route) => route.isFirst,
              );
            },
            icon: const Icon(
              Icons.home,
              color: Colors.white,
            ),
            tooltip: 'Về trang chủ',
          ),

          IconButton(
            onPressed: () =>
                _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(
              Icons.menu,
              color: Colors.white,
            ),
            tooltip: 'Danh sách chương',
          ),

          IconButton(
            onPressed: loading ? null : goNext,
            icon: const Icon(
              Icons.arrow_forward,
              color: Colors.white,
            ),
            tooltip: 'Chương tiếp theo',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CHỌN SOURCE
  // ============================================================

  Widget buildSourceSelector() {
    if (sources.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedSource =
    sources.contains(currentSource)
        ? currentSource
        : sources.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nguồn truyện',
            style: Theme.of(context).textTheme.titleSmall,
          ),

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
            items: sources.map((source) {
              final count =
                  getChaptersBySource(source).length;

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
                changeSource(source);
              }
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GIAO DIỆN
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (chapter == null) {
      return Scaffold(
        body: Center(
          child: loading
              ? const CircularProgressIndicator()
              : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 42,
              ),
              const SizedBox(height: 12),
              const Text(
                'Không thể mở chương truyện.',
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: initData,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
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
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius:
                      BorderRadius.circular(8),
                      child: buildCoverImage(),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StoryDetailScreen(
                                    storyId: storyId,
                                  ),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              lastStoryTitle,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow:
                              TextOverflow.ellipsis,
                            ),

                            const SizedBox(height: 6),

                            Text('Ch. $lastChapterNumber'),

                            const SizedBox(height: 4),

                            Text(
                              'Nguồn: $currentSource',
                              maxLines: 1,
                              overflow:
                              TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),

                            if (isOffline)
                              const Padding(
                                padding:
                                EdgeInsets.only(top: 4),
                                child: Text(
                                  'Đang đọc Offline',
                                  style:
                                  TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              buildSourceSelector(),

              if (loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),

              if (!loading && chapters.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Source này chưa có chapter.',
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics:
                  const NeverScrollableScrollPhysics(),
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: chapters.length,
                  itemBuilder: (context, chapterIndex) {
                    final c = chapters[chapterIndex];

                    final selectedChapterId =
                    chapterIdOf(c);

                    final isCurrent =
                        selectedChapterId == currentChapterId;

                    return Material(
                      color: isCurrent
                          ? Theme.of(context)
                          .colorScheme
                          .primary
                          : Theme.of(context).cardColor,
                      borderRadius:
                      BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius:
                        BorderRadius.circular(8),
                        onTap: loading ||
                            selectedChapterId == null
                            ? null
                            : () {
                          Navigator.pop(context);

                          fetchChapter(
                            selectedChapterId,
                          );
                        },
                        child: Center(
                          child: Padding(
                            padding:
                            const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            child: Text(
                              'Ch. ${c['chapterNumber']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrent
                                    ? Theme.of(context)
                                    .colorScheme
                                    .onPrimary
                                    : Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color,
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

        actions: [
          IconButton(
            tooltip: 'Cài đặt đọc',
            onPressed: showReaderSettingsDialog,
            icon: const Icon(Icons.settings),
          ),
        ],

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              10,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book,
                  size: 18,
                ),

                const SizedBox(width: 8),

                Text(
                  totalPages == 0
                      ? 'Không có trang ảnh'
                      : 'Trang $currentPage / $totalPages',
                  style: const TextStyle(fontSize: 13),
                ),

                const Spacer(),

                if (loading)
                  const Text(
                    'Đang tải chương...',
                    style: TextStyle(fontSize: 11),
                  )
                else if (!allowRemainingImages &&
                    initialImageCount > 0)
                  const Text(
                    'Đang tải ảnh đầu...',
                    style: TextStyle(fontSize: 11),
                  ),

                if (isWindows)
                  Text(
                    '  ${(zoomScale * 100).round()}%',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),

      body: loading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : Focus(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: handleKeyboardEvent,
        onFocusChange: handleFocusChange,
        child: Row(
          children: [
            if (isWindows)
              buildWindowsSidebar(),

            Expanded(
              child: buildReaderBody(),
            ),
          ],
        ),
      ),

      bottomNavigationBar:
      isWindows ? null : buildBottomNavigationBar(),
    );
  }
}

// ============================================================
// WIDGET ẢNH CHƯƠNG HỖ TRỢ OFFLINE
// ============================================================

class _ReaderChapterImage extends StatefulWidget {
  final int storyId;
  final String imageName;
  final String imageUrl;
  final bool offline;
  final bool shouldLoad;
  final double width;

  // Chỉ bật khi đọc từng trang.
  final bool pageMode;

  // Chỉ fit vào trang ở mức zoom gốc; khi phóng to phải giữ nguyên tỷ lệ pixel.
  final bool fitToPage;

  // Chiều cao vùng hiển thị một trang.
  final double pageHeight;

  final VoidCallback? onLoadFinished;

  const _ReaderChapterImage({
    super.key,
    required this.storyId,
    required this.imageName,
    required this.imageUrl,
    required this.offline,
    required this.shouldLoad,
    required this.width,
    this.pageMode = false,
    this.fitToPage = true,
    this.pageHeight = 0,
    this.onLoadFinished,
  });

  @override
  State<_ReaderChapterImage> createState() =>
      _ReaderChapterImageState();
}

class _ReaderChapterImageState
    extends State<_ReaderChapterImage> {
  File? _localFile;

  bool _loadingLocalFile = false;
  bool _localLoadStarted = false;
  bool _notifiedFinished = false;

  @override
  void didUpdateWidget(
      covariant _ReaderChapterImage oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.imageName != widget.imageName ||
        oldWidget.storyId != widget.storyId ||
        oldWidget.offline != widget.offline) {
      _localFile = null;
      _localLoadStarted = false;
      _loadingLocalFile = false;
      _notifiedFinished = false;
    }
  }

  void _notifyFinished() {
    if (_notifiedFinished) return;

    _notifiedFinished = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onLoadFinished?.call();
      }
    });
  }

  Future<void> _loadLocalFile() async {
    if (_localLoadStarted || !widget.shouldLoad) {
      return;
    }

    _localLoadStarted = true;
    _loadingLocalFile = true;

    try {
      final filename = widget.imageName
          .replaceAll('\\', '/')
          .split('/')
          .last;

      final file =
      await OfflineEntryService.instance.getImage(
        widget.storyId,
        'chapter/$filename',
      );

      if (!mounted) return;

      setState(() {
        _localFile = file;
        _loadingLocalFile = false;
      });

      _notifyFinished();
    } catch (e) {
      debugPrint('Lỗi đọc ảnh Offline: $e');

      if (!mounted) return;

      setState(() {
        _loadingLocalFile = false;
      });

      _notifyFinished();
    }
  }

  Widget _placeholder() {
    return SizedBox(
      width: widget.width,
      height: 220,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _errorWidget() {
    return SizedBox(
      width: widget.width,
      height: 160,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              size: 36,
              color: Colors.grey,
            ),

            Text(
              widget.offline
                  ? 'Ảnh chưa có trong package Offline'
                  : 'Không thể tải ảnh',
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),

            if (!widget.offline)
              TextButton(
                onPressed: () {
                  setState(() {
                    _notifiedFinished = false;
                  });
                },
                child: const Text('Thử tải lại'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (!widget.shouldLoad) {
      return _placeholder();
    }

    if (!widget.offline) {
      return SequentialChapterImage(
        imageUrl: widget.imageUrl,
        shouldLoad: true,
        width: widget.width,
        onLoadFinished: widget.onLoadFinished,
      );
    }

    if (!_localLoadStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadLocalFile();
        }
      });
    }

    if (_loadingLocalFile || !_localLoadStarted) {
      return _placeholder();
    }

    final file = _localFile;

    if (file == null) {
      return _errorWidget();
    }

    return Image.file(
      file,
      width: widget.width,
      fit: BoxFit.fitWidth,
      errorBuilder: (_, __, ___) => _errorWidget(),
      frameBuilder: (
          context,
          child,
          frame,
          wasSynchronouslyLoaded,
          ) {
        if (frame != null || wasSynchronouslyLoaded) {
          _notifyFinished();
        }

        return child;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _buildImageContent();

    // Chế độ cuộn: giữ nguyên cách hiển thị ảnh theo chiều rộng.
    if (!widget.pageMode) {
      return image;
    }

    // Ở zoom gốc, giữ hành vi fit ảnh vào khung trang như trước.
    if (widget.fitToPage) {
      return SizedBox(
        width: widget.width,
        height: widget.pageHeight,
        child: Center(
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: SizedBox(
                width: widget.width,
                child: image,
              ),
            ),
          ),
        ),
      );
    }

    // Khi zoom > 100%, tuyệt đối không dùng FittedBox/contain vì chúng sẽ
    // thu ảnh trở lại vừa khung. Cho ảnh giữ nguyên kích thước theo widget.width
    // và chỉ cắt phần nằm ngoài viewport; người đọc pan bằng thanh cuộn ngang.
    return SizedBox(
      width: widget.width,
      height: widget.pageHeight,
      child: ClipRect(
        child: Align(
          alignment: Alignment.center,
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: widget.width,
            maxWidth: widget.width,
            minHeight: 0,
            maxHeight: double.infinity,
            child: SizedBox(
              width: widget.width,
              child: image,
            ),
          ),
        ),
      ),
    );
  }
}