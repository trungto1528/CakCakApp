
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/screens/chapter_reader_screen.dart';
import 'package:novel_app/screens/search_screen.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/chapter_fetcher.dart';
import 'package:novel_app/services/story_fetcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/User.dart';
import '../route_observer.dart';
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

  @override
  void initState() {
    super.initState();
    _loadLastRead();
    latestStoriesFuture = StoryFetcher().fetchLatestStories();
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
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadLastRead();

    setState(() {
      latestStoriesFuture = StoryFetcher().fetchLatestStories();
    });
  }

  Future<void> _loadLastRead() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final storedUser = prefs.getString('user');
      int? storedStoryId = prefs.getInt('lastStoryId');
      int? storedChapterId = prefs.getInt('lastChapterId');
      String? storedCreatedBy = prefs.getString('lastReadCreatedBy');

      String? storyTitle;
      String? cover;
      double? chapterNumber;
      int? uid;

      if (storedUser != null) {
        var currentUser = User.fromJson(jsonDecode(storedUser));
        uid = currentUser.id;

        final latestUserJson = await Auth().fetchUser(uid);
        currentUser = User.fromJson(jsonDecode(latestUserJson));

        if (currentUser.lastReadStoryId != -1 &&
            currentUser.lastReadChapterId != -1 &&
            currentUser.lastReadCreatedBy != 'na') {
          storedStoryId = currentUser.lastReadStoryId;
          storedChapterId = currentUser.lastReadChapterId;
          storedCreatedBy = currentUser.lastReadCreatedBy;
        }
      }

      if (storedStoryId != null &&
          storedChapterId != null &&
          storedCreatedBy != null) {
        final storyData = await StoryFetcher().fetchStory(storedStoryId);

        storyTitle = storyData['title']?.toString();
        cover = storyData['coverUrl']?.toString();

        final chapterData =
        await ChapterFetcher().fetchChapter(storedChapterId);

        final rawChapterNumber = chapterData['chapterNumber'];

        if (rawChapterNumber is num) {
          chapterNumber = rawChapterNumber.toDouble();
        } else {
          chapterNumber =
              double.tryParse(rawChapterNumber?.toString() ?? '');
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

  void onSearchChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;

      setState(() {
        keyword = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cạk Cạk Cạk'),
        actions: [
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
      body: buildHome(),
    );
  }

  Widget buildHome() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (lastStoryId != null &&
            lastChapterId != null &&
            lastReadCreatedBy != null) ...[
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

                // Windows dùng 3 cột khi đủ rộng.
                // Android và các nền tảng khác vẫn dùng danh sách một cột.
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
