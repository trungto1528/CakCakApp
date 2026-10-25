import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/config/api_config.dart';
import 'package:novel_app/offline/service/offline_mode_service.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/reading_list.dart';
import 'package:novel_app/services/story_fetcher.dart';
import '../models/Story.dart';
import '../models/User.dart';
import '../services/app_preference.dart';
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}
class _LibraryPageState extends State<LibraryPage> {
  int? userId;
  bool loading = true;
  Map<int, Map<String, dynamic>> readingList = {};
  bool get _isOffline => OfflineModeService.isOffline.value;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }
  Future<void> _loadLibrary() async {
    try {
      final prefs = await AppPreferences.getInstance();
      final storedUser = prefs.getString("user");
      if (storedUser == null) {
        if (!mounted) return;
        setState(() {
          userId = null;
          readingList = {};
          loading = false;
        });
        return;
      }
      final User user = User.fromJson(jsonDecode(storedUser));
      final int currentUserId = user.id;
      final Map<int, Map<String, dynamic>> data = await ReadingList().getUser(currentUserId);
      if (!mounted) return;
      setState(() {
        userId = currentUserId;
        readingList = data;
        loading = false;
      });
    } catch (e) {
      debugPrint('Lỗi tải thư viện đọc: $e');
      if (!mounted) return;
      setState(() {
        readingList = {};
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể tải thư viện đọc. Vui lòng thử lại.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  Future<Map<String, dynamic>> _fetchStory(int storyId) async {
    final marked = await StoryFetcher().searchLittle(storyId);
    return Map<String, dynamic>.from(marked);
  }
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Library')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Library')),
        body: Center(
          child: Text(
            "Bạn cần đăng nhập để xem lịch sử đọc",
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (readingList.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Library')),
        body: Center(
          child: Text(
            "Bạn chưa đọc truyện nào",
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }
    final entries = readingList.entries.toList()..sort(
          (a, b) {
            final aNum = (a.value['chapterNumber'] as num?)?.toDouble() ?? 0;
            final bNum = (b.value['chapterNumber'] as num?)?.toDouble() ?? 0;
            return bNum.compareTo(aNum);
          },
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade100,
              child: Text(
                'Lịch sử đọc sẽ không được lưu khi ở chế độ offline.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (_, i) {
            final entry = entries[i];
            final storyId = entry.key;
            final chapterInfo = entry.value;
            final highestChapter = chapterInfo['chapterNumber']?.toString() ?? '-';
          return FutureBuilder<Map<String, dynamic>>(
            future: _fetchStory(storyId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const ListTile(
                  leading: SizedBox(
                    width: 70,
                    height: 105,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  title: Text('Đang tải...'),
                );
              }
              final data = snapshot.data!;
              final s = Story.fromJson(data);
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Chương đọc cuối: $highestChapter',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  ],
  ),
);
  }
}
