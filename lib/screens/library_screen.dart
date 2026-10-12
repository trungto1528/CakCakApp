import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/config/api_config.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/bookmark.dart';
import 'package:novel_app/services/story_fetcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/Story.dart';
import '../models/User.dart';
import '../route_observer.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with RouteAware {
  int? userId;
  bool loading = true;
  List<dynamic> library = [];
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
    _loadLibrary();
  }

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedUser = prefs.getString("user");

      if (storedUser == null) {
        if (!mounted) return;

        setState(() {
          userId = null;
          library = [];
          loading = false;
        });
        return;
      }

      final User user = User.fromJson(jsonDecode(storedUser));
      final int currentUserId = user.id;

      final List<int> data = List<int>.from(
        await Bookmark().getBookmark(currentUserId),
      );

      final List<Story> list = [];

      for (final int id in data) {
        final Map<String, dynamic> marked =
        await StoryFetcher().searchLittle(id);

        list.add(Story.fromJson(marked));
      }

      if (!mounted) return;

      setState(() {
        userId = currentUserId;
        library = list;
        loading = false;
      });
    } catch (e) {
      debugPrint('Lỗi tải thư viện: $e');

      if (!mounted) return;

      setState(() {
        library = [];
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể tải thư viện. Vui lòng thử lại.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Bookmarks")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Bookmarks")),
        body: Center(
          child: Text(
            "Bạn cần đăng nhập để xem truyện đã đánh dấu",
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (library.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Bookmarks")),
        body: Center(
          child: Text(
            "Bạn chưa lưu truyện nào",
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Bookmarks")),
      body: ListView.builder(
        itemCount: library.length,
        itemBuilder: (_, i) {
          final s = library[i];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryDetailScreen(storyId: s.id),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      width: 70,
                      height: 105,
                      fit: BoxFit.cover,
                      imageUrl:
                          "${ApiConfig.coverImage}/${s.coverUrl}",
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
