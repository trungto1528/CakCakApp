import 'package:flutter/material.dart';
import '../services/story_fetcher.dart';
import '../services/chapter_fetcher.dart';
class AdminApproveScreen extends StatefulWidget {
  final int adminId;
  const AdminApproveScreen({super.key, required this.adminId});
  @override
  State<AdminApproveScreen> createState() => _AdminApproveScreenState();
}
class _AdminApproveScreenState extends State<AdminApproveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List stories = [];
  List chapters = [];
  bool loadingStories = true;
  bool loadingChapters = true;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }
  Future<void> _loadData() async {
    await Future.wait([
      _loadStories(),
      _loadChapters(),
    ]);
  }
  Future<void> _loadStories() async {
    setState(() => loadingStories = true);
    try {
      final data = await StoryFetcher().getAllStories(widget.adminId);
      setState(() {
        stories = data;
        loadingStories = false;
      });
    } catch (e) {
      setState(() => loadingStories = false);
    }
  }
  Future<void> _loadChapters() async {
    setState(() => loadingChapters = true);
    try {
      final data = await ChapterFetcher().getPendingChapters();
      setState(() {
        chapters = data;
        loadingChapters = false;
      });
    } catch (e) {
      setState(() => loadingChapters = false);
    }
  }
  Future<void> _approveStory(int id) async {
    await StoryFetcher().approveStory(widget.adminId, id);
    await _loadStories();
  }
  Future<void> _approveChapter(int id) async {
    await ChapterFetcher().approveChapter(widget.adminId, id);
    await _loadChapters();
  }
  Color _statusColor(String? status) {
    switch (status) {
      case "APPROVED":
        return Colors.green;
      case "PENDING":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  Widget _statusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: _statusColor(status),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Approve"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Stories"),
            Tab(text: "Chapters"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ================= STORIES =================
          loadingStories
              ? const Center(child: CircularProgressIndicator())
              : stories.isEmpty
              ? const Center(child: Text("No stories"))
              : ListView.builder(
            itemCount: stories.length,
            itemBuilder: (context, i) {
              final s = stories[i];
              final status = s["status"] ?? "UNKNOWN";
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(s["title"] ?? "No title"),
                  subtitle: _statusBadge(status),
                  trailing: status == "PENDING"
                      ? IconButton(
                    icon: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    onPressed: () => _approveStory(s["id"]),
                  )
                      : const Icon(
                    Icons.verified,
                    color: Colors.grey,
                  ),
                ),
              );
            },
          ),
          // ================= CHAPTERS =================
          loadingChapters
              ? const Center(child: CircularProgressIndicator())
              : chapters.isEmpty
              ? const Center(child: Text("No pending chapters"))
              : ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (context, i) {
              final c = chapters[i];
              final status = c["status"] ?? "UNKNOWN";
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(
                    "Chap ${c["chapterNumber"] ?? ""}: ${c["title"] ?? ""}",
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Story: ${c["storyTitle"] ?? ""}"),
                      _statusBadge(status),
                    ],
                  ),
                  trailing: status == "PENDING"
                      ? IconButton(
                    icon: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    onPressed: () => _approveChapter(c["id"]),
                  )
                      : const Icon(
                    Icons.verified,
                    color: Colors.grey,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}