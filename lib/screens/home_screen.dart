
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/screens/chapter_reader_screen.dart';
import 'package:novel_app/screens/search_screen.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/chapter_fetcher.dart';
import 'package:novel_app/services/story_fetcher.dart';
import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';
import '../models/User.dart';
import '../offline/service/offline_mode_service.dart';
import '../route_observer.dart';
import '../services/app_preference.dart';
import '../services/auth.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  String? lastStoryTitle;
  double? lastChapterNumber;

  late Future<List<dynamic>> latestStoriesFuture;

  Timer? _debounce;
  String keyword = '';

  int? userId;
  int? lastStoryId;
  int? lastChapterId;
  String? lastReadCreatedBy;
  String? coverUrl;

  final TextEditingController _offlineSearchController =
  TextEditingController();

  List<Map<String, dynamic>> _downloadedStories = [];
  bool _loadingDownloadedStories = false;
  String _offlineKeyword = '';

  bool get isOffline => OfflineModeService.isOffline.value;

  @override
  void initState() {
    super.initState();

    OfflineModeService.isOffline.addListener(_onOfflineModeChanged);

    latestStoriesFuture = _loadLatestStories();
    _loadLastRead();

    if (isOffline) {
      _loadDownloadedStories();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _offlineSearchController.dispose();

    OfflineModeService.isOffline.removeListener(
      _onOfflineModeChanged,
    );

    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    if (!mounted) return;

    setState(() {
      latestStoriesFuture = _loadLatestStories();
    });

    _loadLastRead();

    if (isOffline) {
      _loadDownloadedStories();
    }
  }

  void _onOfflineModeChanged() {
    if (!mounted) return;

    setState(() {
      latestStoriesFuture = _loadLatestStories();

      lastStoryTitle = null;
      lastChapterNumber = null;
      lastStoryId = null;
      lastChapterId = null;
      lastReadCreatedBy = null;
      coverUrl = null;
    });

    _loadLastRead();

    if (isOffline) {
      _loadDownloadedStories();
    } else {
      setState(() {
        _downloadedStories = [];
      });
    }
  }

  Future<List<dynamic>> _loadLatestStories() async {
    if (OfflineModeService.isOffline.value) {
      return <dynamic>[];
    }

    return StoryFetcher().fetchLatestStories();
  }

  Future<void> _loadLastRead() async {
    try {
      final prefs = await AppPreferences.getInstance();

      final storedUser = prefs.getString('user');
      int? storedStoryId = prefs.getInt('lastStoryId');
      int? storedChapterId = prefs.getInt('lastChapterId');
      String? storedCreatedBy = prefs.getString('lastReadCreatedBy');

      String? storyTitle;
      String? cover;
      double? chapterNumber;
      int? uid;

      if (!OfflineModeService.isOffline.value && storedUser != null) {
        var currentUser = User.fromJson(jsonDecode(storedUser));
        uid = currentUser.id;

        try {
          final latestUserJson = await Auth().fetchUser(uid);
          currentUser = User.fromJson(jsonDecode(latestUserJson));

          if (currentUser.lastReadStoryId != -1 &&
              currentUser.lastReadChapterId != -1 &&
              currentUser.lastReadCreatedBy != 'na') {
            storedStoryId = currentUser.lastReadStoryId;
            storedChapterId = currentUser.lastReadChapterId;
            storedCreatedBy = currentUser.lastReadCreatedBy;
          }
        } catch (e) {
          debugPrint('Không thể đồng bộ lịch sử đọc: $e');
        }
      } else if (storedUser != null) {
        final currentUser = User.fromJson(jsonDecode(storedUser));
        uid = currentUser.id;
      }

      if (!OfflineModeService.isOffline.value &&
          storedStoryId != null &&
          storedChapterId != null &&
          storedCreatedBy != null) {
        try {
          final storyData =
          await StoryFetcher().fetchStory(storedStoryId);

          storyTitle = storyData['title']?.toString();
          cover = storyData['coverUrl']?.toString();

          final chapterData =
          await ChapterFetcher().fetchChapter(storedChapterId);

          final rawChapterNumber = chapterData['chapterNumber'];

          if (rawChapterNumber is num) {
            chapterNumber = rawChapterNumber.toDouble();
          } else {
            chapterNumber = double.tryParse(
              rawChapterNumber?.toString() ?? '',
            );
          }
        } catch (e) {
          debugPrint('Không thể tải thông tin đọc gần nhất: $e');
        }
      }

      if (!mounted) return;

      setState(() {
        userId = uid;
        lastStoryId = storedStoryId;
        lastChapterId = storedChapterId;
        lastReadCreatedBy = storedCreatedBy;
        lastStoryTitle = storyTitle;
        coverUrl = cover;
        lastChapterNumber = chapterNumber;
      });
    } catch (e) {
      debugPrint('Lỗi tải thông tin đọc gần nhất: $e');
    }
  }

  Widget _buildOfflineModeButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: OfflineModeService.isOffline,
      builder: (context, offline, _) {
        return IconButton(
          tooltip: offline
              ? 'Đang Offline — chuyển sang Online'
              : 'Đang Online — chuyển sang Offline',
          icon: Icon(
            offline ? Icons.cloud_off : Icons.cloud_done,
          ),
          onPressed: () async {
            await OfflineModeService.setOffline(!offline);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isOffline ? 'Truyện offline' : 'Cạk Cạk Cạk'),
        actions: [
          _buildOfflineModeButton(),
          if (!isOffline)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Tìm kiếm',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SearchScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: isOffline ? _buildOfflineHome() : buildHome(),
    );
  }

  // ==================== OFFLINE HOME ====================

  Future<void> _loadDownloadedStories() async {
    if (!mounted) return;

    setState(() {
      _loadingDownloadedStories = true;
    });

    try {
      final appDir = await getApplicationSupportDirectory();

      final storiesDir = Directory(
        '${appDir.path}${Platform.pathSeparator}offline_stories',
      );

      if (!await storiesDir.exists()) {
        if (!mounted) return;

        setState(() {
          _downloadedStories = [];
          _loadingDownloadedStories = false;
        });
        return;
      }

      final stories = <Map<String, dynamic>>[];

      await for (final entity in storiesDir.list()) {
        if (entity is! Directory) continue;

        final separator = Platform.pathSeparator;

        final completeFile = File(
          '${entity.path}${separator}complete.json',
        );

        final metadataFile = File(
          '${entity.path}${separator}metadata.json',
        );

        if (!await completeFile.exists() ||
            !await metadataFile.exists()) {
          continue;
        }

        try {
          final completeJson = jsonDecode(
            await completeFile.readAsString(),
          );

          final metadataJson = jsonDecode(
            await metadataFile.readAsString(),
          );

          if (completeJson is! Map || metadataJson is! Map) {
            continue;
          }

          final complete = Map<String, dynamic>.from(completeJson);
          final metadata = Map<String, dynamic>.from(metadataJson);

          final storyId = int.tryParse(
            (metadata['id'] ?? '').toString(),
          ) ??
              int.tryParse(
                (complete['storyId'] ?? '').toString(),
              ) ??
              int.tryParse(
                entity.uri.pathSegments.isNotEmpty
                    ? entity.uri.pathSegments.last
                    : '',
              );

          if (storyId == null) continue;

          stories.add({
            ...metadata,
            'id': storyId,
            'title': metadata['title'] ??
                complete['title'] ??
                'Truyện chưa có tên',
            'author': metadata['author'] ?? 'Chưa rõ tác giả',
            'coverUrl': metadata['coverUrl'] ?? '',
            'localPath': entity.path,
          });
        } catch (e) {
          debugPrint(
            'Không đọc được metadata ${entity.path}: $e',
          );
        }
      }

      stories.sort((a, b) {
        final titleA = (a['title'] ?? '').toString().toLowerCase();
        final titleB = (b['title'] ?? '').toString().toLowerCase();

        return titleA.compareTo(titleB);
      });

      if (!mounted) return;

      setState(() {
        _downloadedStories = stories;
        _loadingDownloadedStories = false;
      });
    } catch (e) {
      debugPrint('Lỗi đọc danh sách truyện offline: $e');

      if (!mounted) return;

      setState(() {
        _loadingDownloadedStories = false;
      });
    }
  }

  Widget _buildOfflineHome() {
    final search = _offlineKeyword.trim().toLowerCase();

    final filteredStories = _downloadedStories.where((story) {
      final title = (story['title'] ?? '').toString().toLowerCase();
      final author = (story['author'] ?? '').toString().toLowerCase();

      return title.contains(search) || author.contains(search);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _offlineSearchController,
            onChanged: (value) {
              setState(() {
                _offlineKeyword = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Tìm truyện đã tải...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _offlineKeyword.isNotEmpty
                  ? IconButton(
                tooltip: 'Xóa tìm kiếm',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _offlineSearchController.clear();

                  setState(() {
                    _offlineKeyword = '';
                  });
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Danh sách truyện',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text('${filteredStories.length} truyện'),
              IconButton(
                tooltip: 'Làm mới danh sách',
                onPressed: _loadDownloadedStories,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingDownloadedStories
              ? const Center(child: CircularProgressIndicator())
              : filteredStories.isEmpty
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.library_books_outlined,
                    size: 64,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _downloadedStories.isEmpty
                        ? 'Bạn chưa có truyện nào được tải hoàn tất.'
                        : 'Không tìm thấy truyện phù hợp.',
                    textAlign: TextAlign.center,
                  ),
                  if (_downloadedStories.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Hãy tải truyện khi Online để đọc '
                          'ở chế độ Offline.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          )
              : LayoutBuilder(
            builder: (context, constraints) {
              final isWindows = !kIsWeb &&
                  defaultTargetPlatform ==
                      TargetPlatform.windows;

              if (isWindows && constraints.maxWidth >= 650) {
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredStories.length,
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 145,
                  ),
                  itemBuilder: (context, index) {
                    return _buildOfflineStoryCard(
                      filteredStories[index],
                    );
                  },
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  4,
                  12,
                  12,
                ),
                itemCount: filteredStories.length,
                itemBuilder: (context, index) {
                  return _buildOfflineStoryCard(
                    filteredStories[index],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineStoryCard(
      Map<String, dynamic> story,
      ) {
    final title = (story['title'] ?? 'Chưa có tên').toString();
    final author = (story['author'] ?? 'Chưa rõ tác giả').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openStory(story),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _buildOfflineCover(story),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      author,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_done, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Đã tải xuống',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineCover(Map<String, dynamic> story) {
    final storyDir = story['localPath']?.toString();

    if (storyDir == null || storyDir.isEmpty) {
      return _offlineCoverPlaceholder();
    }

    final coverDir = Directory(
      '$storyDir${Platform.pathSeparator}cover',
    );

    return FutureBuilder<List<File>>(
      future: _loadOfflineCoverFiles(coverDir),
      builder: (context, snapshot) {
        final files = snapshot.data;

        if (files != null && files.isNotEmpty) {
          return Image.file(
            files.first,
            width: 70,
            height: 95,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _offlineCoverPlaceholder(),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 70,
            height: 95,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        return _offlineCoverPlaceholder();
      },
    );
  }

  Future<List<File>> _loadOfflineCoverFiles(
      Directory coverDir,
      ) async {
    if (!await coverDir.exists()) {
      debugPrint('Không tồn tại thư mục ảnh bìa: ${coverDir.path}');
      return [];
    }

    final files = <File>[];

    await for (final entity in coverDir.list()) {
      if (entity is! File) continue;

      final path = entity.path.toLowerCase();

      final isImage = path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.png') ||
          path.endsWith('.webp') ||
          path.endsWith('.gif') ||
          path.endsWith('.bmp');

      if (isImage && await entity.length() > 0) {
        files.add(entity);
      }
    }

    files.sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      debugPrint('Không tìm thấy ảnh bìa trong: ${coverDir.path}');
    }

    return files;
  }

  Widget _offlineCoverPlaceholder() {
    return const SizedBox(
      width: 70,
      height: 95,
      child: ColoredBox(
        color: Colors.black12,
        child: Center(
          child: Icon(Icons.book, size: 36),
        ),
      ),
    );
  }

  // ==================== ONLINE HOME ====================

  Widget buildHome() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (lastStoryId != null &&
            lastChapterId != null &&
            lastReadCreatedBy != null &&
            lastStoryTitle != null) ...[
          const Text(
            'Đọc tiếp',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChapterReaderScreen(
                      storyId: lastStoryId!,
                      chapterId: lastChapterId!,
                      source: lastReadCreatedBy!,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: '${ApiConfig.coverImage}/$coverUrl',
                        width: 80,
                        height: 110,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox(
                          width: 80,
                          height: 110,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => const SizedBox(
                          width: 80,
                          height: 110,
                          child: Icon(Icons.book, size: 40),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lastStoryTitle ?? '',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text('Chương ${lastChapterNumber ?? ''}'),
                        ],
                      ),
                    ),
                    const Icon(Icons.play_arrow),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Mới cập nhật',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<dynamic>>(
          future: latestStoriesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Không thể tải dữ liệu'),
                ),
              );
            }

            final stories = snapshot.data ?? [];

            if (stories.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa có truyện mới cập nhật'),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final isWindows = !kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.windows;

                final useGrid =
                    isWindows && constraints.maxWidth >= 650;

                if (!useGrid) {
                  return Column(
                    children: stories.map((story) {
                      return _buildStoryListItem(story);
                    }).toList(),
                  );
                }

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stories.length,
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 145,
                  ),
                  itemBuilder: (context, index) {
                    return _buildStoryGridItem(stories[index]);
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildStoryListItem(dynamic story) {
    final title = story['title']?.toString() ?? 'Chưa có tên';
    final author = story['author']?.toString() ?? 'Chưa rõ tác giả';
    final latestChapter = story['latestChapter']?.toString() ?? '?';
    final cover = story['coverUrl']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: '${ApiConfig.coverImage}/$cover',
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
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text('Chương $latestChapter'),
          ],
        ),
        onTap: () => _openStory(story),
      ),
    );
  }

  Widget _buildStoryGridItem(dynamic story) {
    final title = story['title']?.toString() ?? 'Chưa có tên';
    final author = story['author']?.toString() ?? 'Chưa rõ tác giả';
    final latestChapter = story['latestChapter']?.toString() ?? '?';
    final cover = story['coverUrl']?.toString() ?? '';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openStory(story),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: '${ApiConfig.coverImage}/$cover',
                  width: 80,
                  height: 110,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox(
                    width: 80,
                    height: 110,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => const SizedBox(
                    width: 80,
                    height: 110,
                    child: Icon(Icons.book, size: 40),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      author,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chương $latestChapter',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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

  void _openStory(dynamic story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryDetailScreen(
          storyId: story['id'],
        ),
      ),
    );
  }
}
