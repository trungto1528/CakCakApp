import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/last_read.dart';

import '../config/api_config.dart';
import '../models/User.dart';
import '../offline/service/offline_entry_service.dart';
import '../offline/service/offline_mode_service.dart';
import '../services/app_preference.dart';
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
  final ScrollController _horizontalScrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _listViewKey = GlobalKey();
  final FocusNode _keyboardFocusNode = FocusNode();

  // Mobile: điều khiển zoom/pan của InteractiveViewer.
  final TransformationController _transformController =
  TransformationController();
  bool _mobileZoomed = false;
  final Set<int> _activePointers = <int>{};
  Size _mobileViewport = Size.zero;

  Map<String, dynamic>? chapter;
  List<dynamic> blocks = [];
  List<dynamic> chapters = [];
  List<dynamic> _allChapters = [];
  List<String> _sources = [];

  late String currentSource;

  List<int> _imageIndexByBlockIndex = [];
  List<GlobalKey> _imageKeys = [];

  final Set<int> _finishedInitialImageIndexes = {};

  // Windows: trạng thái Ctrl dùng cho zoom bằng con lăn.
  bool _isCtrlZooming = false;

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

  // Chỉ sử dụng cho zoom trên Windows.
  double _zoomScale = 1.0;
  double _maxAllowedZoomScale = 2.5;
  double _scrollSensitivity = 1.0;

  double _lastAvailableWidth = 0.0;
  double _lastBaseContentWidth = 0.0;

  static const double _minZoomScale = 0.5;
  static const double _maxZoomLimit = 3.5;
  static const double _zoomStep = 0.1;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isMobile =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isOffline => OfflineModeService.isOffline.value;

  @override
  void initState() {
    super.initState();

    currentChapterId = widget.chapterId;
    currentSource = widget.source;

    _scrollController.addListener(_updateReadingProgress);
    _transformController.addListener(_onTransformChanged);

    _loadReaderSettings();
    _initData();
  }

  // ============================================================
  // CÀI ĐẶT ĐỘ NHẠY CUỘN WINDOWS
  // ============================================================

  Future<void> _loadReaderSettings() async {
    try {
      final prefs = await AppPreferences.getInstance();
      final sensitivity = prefs.getDouble('reader_scroll_sensitivity') ?? 1.0;

      if (!mounted) return;

      setState(() {
        _scrollSensitivity = sensitivity.clamp(0.5, 10.0).toDouble();
      });
    } catch (e) {
      debugPrint('Không thể tải cài đặt trình đọc: $e');
    }
  }

  Future<void> _showScrollSensitivityDialog() async {
    double selectedSensitivity = _scrollSensitivity;

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Độ nhạy cuộn'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${selectedSensitivity.toStringAsFixed(1)}x',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Slider(
                    value: selectedSensitivity,
                    min: 0.5,
                    max: 10.0,
                    divisions: 95,
                    label: '${selectedSensitivity.toStringAsFixed(1)}x',
                    onChanged: (value) {
                      setDialogState(() {
                        selectedSensitivity = value;
                      });
                    },
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text('Chậm'), Text('Nhanh')],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Áp dụng cho con lăn chuột, phím mũi tên lên/xuống '
                        'và nút cuộn trên Windows.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, selectedSensitivity),
                  child: const Text('Áp dụng'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      _scrollSensitivity = result;
    });

    try {
      final prefs = await AppPreferences.getInstance();
      await prefs.setDouble('reader_scroll_sensitivity', result);
    } catch (e) {
      debugPrint('Không thể lưu độ nhạy cuộn: $e');
    }
  }

  // ============================================================
  // KHỞI TẠO TRUYỆN
  // ============================================================

  Future<void> _initData() async {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }

    try {
      final storyData = await StoryFetcher().fetchStory(widget.storyId);

      final allChapters = storyData['chapters'] is List
          ? List<dynamic>.from(storyData['chapters'])
          : <dynamic>[];

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

      var initialChapters = _getChaptersBySourceFrom(
        allChapters,
        initialSource,
      );

      if (initialChapters.isEmpty && allChapters.isNotEmpty) {
        dynamic initialChapter;

        for (final item in allChapters) {
          if (_chapterIdOf(item) == widget.chapterId) {
            initialChapter = item;
            break;
          }
        }

        if (initialChapter is Map) {
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
      _showError('Không thể tải thông tin truyện: $e');
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

      return (item['createdBy']?.toString().trim() ?? '') == source;
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

  List<dynamic> _getChaptersBySource(String source) =>
      _getChaptersBySourceFrom(_allChapters, source);

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
    });

    _updateNextPrev();
  }

  // ============================================================
  // TẢI CHƯƠNG
  // ============================================================

  Future<void> _fetchChapter(int id) async {
    if (!mounted) return;

    setState(() {
      loading = true;
    });

    try {
      final data = await ChapterFetcher().fetchChapter(
        id,
        storyId: widget.storyId,
      );

      if (!mounted) return;

      final newBlocks = List<dynamic>.from(data['blocks'] ?? []);
      final imageIndexByBlockIndex = <int>[];

      var imageCount = 0;

      for (final block in newBlocks) {
        if (block is Map && block['type'] == 'image') {
          imageIndexByBlockIndex.add(imageCount++);
        } else {
          imageIndexByBlockIndex.add(-1);
        }
      }

      final imageKeys = List<GlobalKey>.generate(
        imageCount,
            (_) => GlobalKey(),
      );

      currentChapterId = id;

      setState(() {
        chapter = data;
        blocks = newBlocks;
        _imageIndexByBlockIndex = imageIndexByBlockIndex;
        _imageKeys = imageKeys;
        _totalPages = imageCount;
        _currentPage = imageCount > 0 ? 1 : 0;
        _initialImageCount = imageCount < 3 ? imageCount : 3;

        _finishedInitialImageIndexes.clear();
        _allowRemainingImages = imageCount == 0;

        // Reset zoom của Windows khi chuyển chương.
        _zoomScale = 1.0;
        _isCtrlZooming = false;

        // Reset zoom của mobile khi chuyển chương.
        _transformController.value = Matrix4.identity();
        _mobileZoomed = false;
        _activePointers.clear();

        lastChapterNumber = _parseChapterNumber(data['chapterNumber']);

        loading = false;
      });

      _updateNextPrev();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }

        if (_horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(0);
        }

        _keyboardFocusNode.requestFocus();
        _updateReadingProgress();
      });

      await _saveReadingHistory(id);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      debugPrint('Lỗi tải chương: $e');
      _showError('Không thể tải chương: $e');
    }
  }

  Future<void> _saveReadingHistory(int chapterId) async {
    try {
      final prefs = await AppPreferences.getInstance();
      final userString = prefs.getString('user');

      if (userString != null) {
        final user = User.fromJson(jsonDecode(userString));

        await LastRead().updateLastRead(
          user.id,
          widget.storyId,
          chapterId,
          currentSource,
        );
      } else {
        await _saveLastRead(chapterId);
      }
    } catch (e) {
      debugPrint('Không thể lưu lịch sử đọc: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
  // TIẾN ĐỘ ĐỌC
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
      final imageObject = _imageKeys[i].currentContext?.findRenderObject();

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
    _transformController.removeListener(_onTransformChanged);

    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _keyboardFocusNode.dispose();
    _transformController.dispose();

    super.dispose();
  }

  // ============================================================
  // ĐIỀU HƯỚNG CHƯƠNG
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
    final prefs = await AppPreferences.getInstance();

    await prefs.setInt('lastStoryId', widget.storyId);
    await prefs.setInt('lastChapterId', chapterId);
    await prefs.setString('lastReadCreatedById', currentSource);
  }

  void _goNext() {
    if (loading) return;

    if (nextId != null) {
      _fetchChapter(nextId!);
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

  void _goPrev() {
    if (loading) return;

    if (prevId != null) {
      _fetchChapter(prevId!);
    }
  }

  // ============================================================
  // CUỘN VÀ ZOOM WINDOWS
  // ============================================================

  void _scrollBy(double offset) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final adjustedOffset = _isWindows ? offset * _scrollSensitivity : offset;

    final target = (_scrollController.offset + adjustedOffset)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  // Cuộn chuột bình thường trên Windows.
  void _scrollByWheel(double delta) {
    if (!_isWindows || !_scrollController.hasClients) return;

    if (HardwareKeyboard.instance.isControlPressed) return;

    final position = _scrollController.position;
    final adjustedDelta = delta * _scrollSensitivity;

    final target = (_scrollController.offset + adjustedDelta)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
  }

  // Chỉ Ctrl + lăn chuột mới zoom trên Windows.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_isWindows || event is! PointerScrollEvent) return;

    final delta = event.scrollDelta.dy;
    if (delta == 0) return;

    final ctrlPressed = HardwareKeyboard.instance.isControlPressed;

    if (!ctrlPressed) {
      if (_isCtrlZooming && mounted) {
        setState(() {
          _isCtrlZooming = false;
        });
      }

      _scrollByWheel(delta);
      return;
    }

    if (!_isCtrlZooming && mounted) {
      setState(() {
        _isCtrlZooming = true;
      });
    }

    final change = delta < 0 ? _zoomStep : -_zoomStep;

    final oldZoomScale = _zoomScale;

    final newZoomScale = (_zoomScale + change)
        .clamp(_minZoomScale, _maxAllowedZoomScale)
        .toDouble();

    if (newZoomScale == oldZoomScale) return;

    setState(() {
      _zoomScale = newZoomScale;
    });

    _adjustZoomOffsets(oldZoomScale);
  }

  void _adjustZoomOffsets(double oldZoomScale) {
    if (_horizontalScrollController.hasClients) {
      final position = _horizontalScrollController.position;
      final newContentWidth = _lastBaseContentWidth * _zoomScale;

      final oldMax = position.maxScrollExtent;
      final newMax = newContentWidth - _lastAvailableWidth;
      final clampedNewMax = newMax > 0 ? newMax : 0.0;

      if (oldMax > 0 && clampedNewMax > 0) {
        final proportion = position.pixels / oldMax;
        final newOffset = proportion * clampedNewMax;

        _horizontalScrollController.jumpTo(
          newOffset.clamp(0.0, clampedNewMax).toDouble(),
        );
      } else if (oldMax > 0) {
        _horizontalScrollController.jumpTo(0.0);
      }
    }

    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      final oldMax = position.maxScrollExtent;

      final contentHeightFactor = blocks.length * 100.0;
      final newMaxVertical = contentHeightFactor * (_zoomScale / oldZoomScale);

      final clampedNewMax = newMaxVertical > oldMax ? newMaxVertical : oldMax;

      if (oldMax > 0 && clampedNewMax > oldMax) {
        final proportion = position.pixels / oldMax;
        final newOffset = proportion * clampedNewMax;

        _scrollController.jumpTo(
          newOffset.clamp(0.0, clampedNewMax).toDouble(),
        );
      }
    }
  }

  // ============================================================
  // ZOOM VÀ KÉO TỰ DO TRÊN MOBILE
  // ============================================================

  void _onTransformChanged() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.01;

    if (zoomed != _mobileZoomed && mounted) {
      setState(() => _mobileZoomed = zoomed);
    }
  }

  // Kéo 1 ngón khi đang zoom trên mobile: pan tự do cả 2 hướng.
  void _handleMobilePointerMove(PointerMoveEvent event) {
    if (!_isMobile || !_mobileZoomed || _activePointers.length != 1) return;

    final size = _mobileViewport;
    if (size.isEmpty) return;

    final matrix = _transformController.value.clone();
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();

    final minX = size.width - size.width * scale;
    final minY = size.height - size.height * scale;

    // Ngang: dịch khung nhìn.
    final newX = (translation.x + event.delta.dx).clamp(minX, 0.0).toDouble();

    // Dọc: dịch khung nhìn trước, phần dư thì cuộn danh sách.
    final dy = event.delta.dy;
    final desiredY = translation.y + dy;
    final newY = desiredY.clamp(minY, 0.0).toDouble();
    final leftover = desiredY - newY; // phần vượt biên

    if (leftover != 0 && _scrollController.hasClients) {
      final pos = _scrollController.position;
      final target = (_scrollController.offset - leftover / scale)
          .clamp(0.0, pos.maxScrollExtent)
          .toDouble();
      _scrollController.jumpTo(target);
    }

    matrix.setTranslationRaw(newX, newY, 0);
    _transformController.value = matrix;
  }

  // ============================================================
  // BÀN PHÍM WINDOWS
  // ============================================================

  KeyEventResult _handleKeyboardEvent(FocusNode node, KeyEvent event) {
    if (_isWindows &&
        (event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight)) {
      final isPressed = event is KeyDownEvent || event is KeyRepeatEvent;

      if (_isCtrlZooming != isPressed && mounted) {
        setState(() {
          _isCtrlZooming = isPressed;
        });
      }

      return KeyEventResult.handled;
    }

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
        if (event is KeyDownEvent) _goPrev();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        if (event is KeyDownEvent) _goNext();
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  void _handleFocusChange(bool hasFocus) {
    if (hasFocus) return;

    if (_isCtrlZooming && mounted) {
      setState(() {
        _isCtrlZooming = false;
      });
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
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_book),
            ),
            const Divider(),
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
  // ẢNH BÌA
  // ============================================================

  Widget _buildCoverImage() {
    if (_isOffline) {
      return FutureBuilder<File?>(
        future: OfflineEntryService.instance.getImage(
          widget.storyId,
          'cover/$coverUrl',
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 80,
              height: 110,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final file = snapshot.data;

          if (file == null) return _coverPlaceholder();

          return Image.file(
            file,
            width: 80,
            height: 110,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _coverPlaceholder(),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: '${ApiConfig.coverImage}/$coverUrl',
      width: 80,
      height: 110,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => _coverPlaceholder(),
    );
  }

  Widget _coverPlaceholder() {
    return const SizedBox(width: 80, height: 110, child: Icon(Icons.book));
  }

  // ============================================================
  // NỘI DUNG CHƯƠNG
  // ============================================================

  Widget buildBlock(
      dynamic block,
      int blockIndex,
      double zoomScale,
      double contentWidth,
      ) {
    if (block is! Map) return const SizedBox.shrink();

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

      if (imageIndex < 0 || imageIndex >= _imageKeys.length) {
        return const SizedBox.shrink();
      }

      final imageName = block['data']?.toString() ?? '';

      final shouldLoad =
          imageIndex < _initialImageCount || _allowRemainingImages;

      final image = _ReaderChapterImage(
        key: _imageKeys[imageIndex],
        storyId: widget.storyId,
        imageName: imageName,
        imageUrl: '${ApiConfig.chapterImage}/$imageName',
        offline: _isOffline,
        shouldLoad: shouldLoad,
        width: contentWidth,
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
        final availableHeight = constraints.maxHeight;

        final desiredWidth = (availableHeight * 0.7)
            .clamp(320.0, 900.0)
            .toDouble();

        final baseContentWidth = desiredWidth < availableWidth
            ? desiredWidth
            : availableWidth;

        _lastAvailableWidth = availableWidth;
        _lastBaseContentWidth = baseContentWidth;

        final effectiveZoom = _isWindows ? _zoomScale : 1.0;

        if (_isWindows) {
          _maxAllowedZoomScale =
              (baseContentWidth > 0 ? availableWidth / baseContentWidth : 1.0)
                  .clamp(1.0, _maxZoomLimit)
                  .toDouble();
        }

        final contentWidth = (baseContentWidth * effectiveZoom)
            .clamp(1.0, 2500.0)
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
                child: Align(
                  alignment: Alignment.topCenter,
                  child: IgnorePointer(
                    // Khi zoom trên mobile, danh sách không nhận touch nữa,
                    // việc kéo do Listener xử lý.
                    ignoring: _isMobile && _mobileZoomed,
                    child: ListView.builder(
                      key: _listViewKey,
                      controller: _scrollController,
                      // Khi đang zoom trên mobile, Listener lo việc kéo/cuộn.
                      // Windows: cuộn/zoom do _handlePointerSignal và phím mũi
                      // tên xử lý (animateTo vẫn hoạt động với physics này),
                      // nên tắt cuộn mặc định để Ctrl + lăn chuột chỉ zoom.
                      physics: (_isWindows || (_isMobile && _mobileZoomed))
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
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // VÙNG ĐỌC THEO NỀN TẢNG
  // ============================================================

  Widget _buildReaderBody() {
    final content = _buildChapterContent();

    if (_isWindows) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handlePointerSignal,
        child: content,
      );
    }

    if (_isMobile) {
      return LayoutBuilder(
        builder: (context, constraints) {
          _mobileViewport = Size(constraints.maxWidth, constraints.maxHeight);

          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _activePointers.add(e.pointer),
            onPointerUp: (e) => _activePointers.remove(e.pointer),
            onPointerCancel: (e) => _activePointers.remove(e.pointer),
            onPointerMove: _handleMobilePointerMove,
            child: InteractiveViewer(
              key: ValueKey('mobile-reader-$currentChapterId'),
              transformationController: _transformController,
              // Giữ 1.0 để phép tính clamp khi kéo luôn đúng.
              minScale: 1.0,
              maxScale: _maxZoomLimit,
              scaleEnabled: true,
              // Khi đã zoom, Listener lo việc pan để kéo tự do mọi hướng.
              panEnabled: !_mobileZoomed,
              constrained: true,
              clipBehavior: Clip.hardEdge,
              boundaryMargin: EdgeInsets.zero,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: content,
              ),
            ),
          );
        },
      );
    }

    return content;
  }

  // ============================================================
  // THANH ĐIỀU HƯỚNG DƯỚI
  // ============================================================

  Widget _buildBottomNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: loading ? null : _goPrev,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Chương trước',
          ),
          IconButton(
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            icon: const Icon(Icons.home, color: Colors.white),
            tooltip: 'Về trang chủ',
          ),
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Danh sách chương',
          ),
          IconButton(
            onPressed: loading ? null : _goNext,
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
            tooltip: 'Chương tiếp theo',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CHỌN SOURCE
  // ============================================================

  Widget _buildSourceSelector() {
    if (_sources.isEmpty) return const SizedBox.shrink();

    final selectedSource = _sources.contains(currentSource)
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
              if (source != null) _changeSource(source);
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
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              const Text('Không thể mở chương truyện.'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initData,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildCoverImage(),
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
                            if (_isOffline)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Đang đọc Offline',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
        actions: [
          if (_isWindows)
            IconButton(
              tooltip: 'Điều chỉnh độ nhạy cuộn',
              onPressed: _showScrollSensitivityDialog,
              icon: const Icon(Icons.tune),
            ),
        ],
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
        onFocusChange: _handleFocusChange,
        child: Row(
          children: [
            if (_isWindows) _buildWindowsSidebar(),
            Expanded(child: _buildReaderBody()),
          ],
        ),
      ),
      bottomNavigationBar: _isWindows ? null : _buildBottomNavigationBar(),
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
  final VoidCallback? onLoadFinished;

  const _ReaderChapterImage({
    super.key,
    required this.storyId,
    required this.imageName,
    required this.imageUrl,
    required this.offline,
    required this.shouldLoad,
    required this.width,
    this.onLoadFinished,
  });

  @override
  State<_ReaderChapterImage> createState() => _ReaderChapterImageState();
}

class _ReaderChapterImageState extends State<_ReaderChapterImage> {
  File? _localFile;
  bool _loadingLocalFile = false;
  bool _localLoadStarted = false;
  bool _notifiedFinished = false;

  @override
  void didUpdateWidget(covariant _ReaderChapterImage oldWidget) {
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
    if (_localLoadStarted || !widget.shouldLoad) return;

    _localLoadStarted = true;
    _loadingLocalFile = true;

    try {
      final filename = widget.imageName.replaceAll('\\', '/').split('/').last;

      final file = await OfflineEntryService.instance.getImage(
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
      child: const Center(child: CircularProgressIndicator()),
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
              style: const TextStyle(color: Colors.grey),
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

  @override
  Widget build(BuildContext context) {
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
        if (mounted) _loadLocalFile();
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
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null || wasSynchronouslyLoaded) {
          _notifyFinished();
        }

        return child;
      },
    );
  }
}