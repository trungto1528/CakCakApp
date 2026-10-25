import 'package:flutter/material.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import '../config/api_config.dart';
import '../services/chapter_fetcher.dart';
class MyStoriesScreen extends StatefulWidget {
  final int userId;
  const MyStoriesScreen({super.key, required this.userId});
  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}
class _MyStoriesScreenState extends State<MyStoriesScreen> {
  List stories = [];
  bool isLoading = true;
  int? expandedIndex;
  @override
  void initState() {
    super.initState();
    _loadStories();
  }
  Color _getStatusColor(String? status) {
    switch (status) {
      case "APPROVED":
        return Colors.green;
      case "PENDING":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  Future<void> _loadStories() async {
    try {
      final data = await ChapterFetcher().getMyChapter(widget.userId);
      setState(() {
        stories = data;
        isLoading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => isLoading = false);
    }
  }
  // ================= DELETE =================
  void _confirmDelete(int chapterId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Xoá chương"),
        content: const Text("Bạn có chắc muốn xoá chương này?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Huỷ"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteChapter(chapterId);
            },
            child: const Text(
              "Xoá",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
  Future<void> _deleteChapter(int chapterId) async {
    try {
      await ChapterFetcher().deleteChapter(chapterId, widget.userId);
      setState(() {
        for (var story in stories) {
          story['chapters']?.removeWhere((c) => c['id'] == chapterId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Đã xoá chương")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Xoá thất bại")),
      );
    }
  }
  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Truyện của tôi"),
          leading: Navigator.canPop(context)
              ? IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          )
              : null,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (stories.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Truyện của tôi"),
          leading: Navigator.canPop(context)
              ? IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          )
              : null,
        ),
        body: const Center(child: Text("Chưa có truyện nào")),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Truyện của tôi"),
        leading: Navigator.canPop(context)
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        )
            : null,
      ),
      body: ListView.builder(
        itemCount: stories.length,
        itemBuilder: (context, index) {
          final story = stories[index];
          final List chapters =
              (story['chapters'] as List?)?.toList() ?? [];
          chapters.sort((a, b) =>
              (a['chapterNumber'] ?? 0).compareTo(b['chapterNumber'] ?? 0));
          return ExpansionTile(
            initiallyExpanded: expandedIndex == index,
            onExpansionChanged: (v) {
              setState(() {
                expandedIndex = v ? index : null;
              });
            },
            // ===== COVER =====
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                '${ApiConfig.coverImage}/${story['coverUrl'] ?? ''}',
                width: 50,
                height: 75,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                const Icon(Icons.book, size: 50),
              ),
            ),
            // ===== TITLE =====
            title: Text(
              story['title'] ?? "Không có tên",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            // ===== SUBTITLE =====
            subtitle: Row(
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(story['status'])
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (story['status'] ?? "UNKNOWN").toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: _getStatusColor(story['status']),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "(${chapters.length} chương)",
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            // ===== CHAPTER LIST =====
            children: chapters.map<Widget>((c) {
              return ListTile(
                dense: true,
                title: Text(
                  "Chap ${c['chapterNumber']}: ${c['title']}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoryDetailScreen(
                        storyId: story['storyId'],
                      ),
                    ),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // STATUS
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getStatusColor(c['status'])
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        (c['status'] ?? "UNKNOWN").toString(),
                        style: TextStyle(
                          fontSize: 11,
                          color: _getStatusColor(c['status']),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // DELETE
                    IconButton(
                      icon: const Icon(Icons.delete,
                          size: 18, color: Colors.red),
                      onPressed: () => _confirmDelete(c['id']),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}