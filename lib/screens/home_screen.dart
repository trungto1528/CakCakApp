import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
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
  late List storyList;
  late Future<List<dynamic>> latestStoriesFuture;
  bool isSearching = false;
  String keyword = "";
  Timer? _debounce;
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

    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadLastRead();
  }

  int? userId;
  int? lastStoryId;
  int? lastChapterId;
  String? lastReadCreatedBy;

  Future<void> _loadLastRead() async {
    final prefs = await SharedPreferences.getInstance();

    var storedUser = prefs.getString('user');
    int? storedStoryId = prefs.getInt("lastStoryId");
    int? storedChapterId = prefs.getInt("lastChapterId");
    String? storedCreatedBy = prefs.getString('lastReadCreatedBy');

    String? storyTitle;
    String? cover;
    double? chapterNumber;

    int? uid;

    if (storedUser != null) {
      var user = User.fromJson(jsonDecode(storedUser));
      uid = user.id;
      storedUser = await Auth().fetchUser(uid);
      user = User.fromJson(jsonDecode(storedUser));
      if (user.lastReadStoryId != -1 &&
          user.lastReadChapterId != -1 &&
          user.lastReadCreatedBy != "na") {
        storedStoryId = user.lastReadStoryId;
        storedChapterId = user.lastReadChapterId;
        storedCreatedBy = user.lastReadCreatedBy;
      }
    }
    if (storedStoryId != null &&
        storedChapterId != null &&
        storedCreatedBy != null) {
      final storyData = await StoryFetcher().fetchStory(storedStoryId);
      storyTitle = storyData['title'];
      cover = storyData['coverUrl'];

      final chapterData = await ChapterFetcher().fetchChapter(storedChapterId);
      chapterNumber = chapterData['chapterNumber'];
    }

    setState(() {
      userId = uid;
      lastStoryId = storedStoryId;
      lastChapterId = storedChapterId;
      lastReadCreatedBy = storedCreatedBy;
      lastStoryTitle = storyTitle;
      coverUrl = cover;
      lastChapterNumber = chapterNumber;
    });
  }

  void onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        keyword = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cạk Cạk Cạk"),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
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
          const SizedBox(width: 8),
          Text(
            "Đọc tiếp",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),
          Row(
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
                        builder: (_) => ChapterReaderScreen(
                          storyId: lastStoryId!,
                          chapterId: lastChapterId!,
                          source: lastReadCreatedBy!,
                        ),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lastStoryTitle ?? "",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text("Chương $lastChapterNumber"),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text(
          "Mới cập nhật",
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
              return const Text("Không thể tải dữ liệu");
            }

            final stories = snapshot.data ?? [];

            return Column(
              children: stories.map((story) {

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(8),

                    leading: CachedNetworkImage(
                      imageUrl:
                      "${ApiConfig.coverImage}/${story['coverUrl']}",
                      width: 60,
                      fit: BoxFit.cover,
                    ),

                    title: Text(
                      story['title'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    subtitle: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(story['author']),
                        Text(
                          "Chương ${story['latestChapter']}",
                        ),
                      ],
                    ),

                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StoryDetailScreen(storyId: story['id']),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
