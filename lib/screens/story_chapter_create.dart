import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../config/api_config.dart';
import '../models/User.dart';
import '../services/app_preference.dart';
import '../services/chapter_fetcher.dart';
import '../services/story_fetcher.dart';
class StoryChapterScreen extends StatefulWidget {
  const StoryChapterScreen({super.key});
  @override
  State<StoryChapterScreen> createState() => _StoryChapterScreenState();
}
class ContentBlock {
  String type;
  TextEditingController? controller;
  File? imageFile;
  String? fileName;
  ContentBlock.text({String content = ""})
    : type = "text",
      controller = TextEditingController(text: content);
  ContentBlock.image(this.imageFile, this.fileName) : type = "image";
}
class _StoryChapterScreenState extends State<StoryChapterScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  // STORY
  final _storyTitle = TextEditingController();
  final _author = TextEditingController();
  final _description = TextEditingController();
  File? _cover;
  // CHAPTER
  final _searchController = TextEditingController();
  final _chapterTitle = TextEditingController();
  final _chapterNo = TextEditingController(text: "1");
  int? _selectedStoryId;
  Map<String, dynamic>? _selectedStory;
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounce;
  final List<ContentBlock> _blocks = [ContentBlock.text()];
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
  // ================= SEARCH =================
  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (value.trim().isEmpty) {
        setState(() => _searchResults = []);
        return;
      }
      final results = await StoryFetcher().search(value);
      if (!mounted) return;
      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(results);
      });
    });
  }
  void _selectStory(Map<String, dynamic> story) {
    setState(() {
      _selectedStoryId = story['id'];
      _selectedStory = story;
      _searchController.text = story['title'];
      _searchResults = [];
    });
  }
  // ================= IMAGE =================
  Future<void> _pickCover() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() => _cover = File(img.path));
  }
  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() {
      _blocks.add(
        ContentBlock.image(
          File(img.path),
          "${const Uuid().v4()}${p.extension(img.path)}",
        ),
      );
      _blocks.add(ContentBlock.text());
    });
  }
  void _removeBlock(int i) {
    setState(() {
      _blocks.removeAt(i);
      if (_blocks.isEmpty) _blocks.add(ContentBlock.text());
    });
  }
  // ================= SUBMIT =================
  Future<void> _submitStory() async {
    if (_storyTitle.text.trim().isEmpty ||
        _author.text.trim().isEmpty ||
        _description.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Nhập đầy đủ thông tin")));
      return;
    }
    try {
      final prefs = await AppPreferences.getInstance();
      final user = User.fromJson(jsonDecode(prefs.getString("user")!));
      String coverUrl = "";
      if (_cover != null) {
        final uploaded = await StoryFetcher().uploadCover(_cover!);
        if (uploaded != null) coverUrl = uploaded;
      }
      final newStory = await StoryFetcher().createStory(
        title: _storyTitle.text.trim(),
        author: _author.text.trim(),
        description: _description.text.trim(),
        coverUrl: coverUrl,
        userId: user.id,
      );
      if (newStory == null) {
        throw Exception("Tạo truyện thất bại");
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Tạo truyện thành công")));
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
    }
  }
  Future<void> _submitChapter() async {
    if (_selectedStoryId == null) return;
    try {
      final prefs = await AppPreferences.getInstance();
      final user = User.fromJson(jsonDecode(prefs.getString("user")!));
      List<Map<String, String>> content = [];
      for (final b in _blocks) {
        if (b.type == "text" && b.controller!.text.trim().isNotEmpty) {
          content.add({"type": "text", "data": b.controller!.text.trim()});
        } else if (b.type == "image") {
          final url = await ChapterFetcher().uploadIllustration(b.imageFile!);
          if (url != null) {
            content.add({"type": "image", "data": url});
          }
        }
      }
      await ChapterFetcher().createChapter(
        storyId: _selectedStoryId!,
        title: _chapterTitle.text,
        chapterNumber: int.parse(_chapterNo.text),
        content: content,
        userId: user.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Đăng chương thành công")));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
    }
  }
  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tạo nội dung"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "TẠO TRUYỆN"),
            Tab(text: "TẠO CHƯƠNG"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildStoryTab(), _buildChapterTab()],
      ),
    );
  }
  // ================= TAB STORY =================
  Widget _buildStoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickCover,
                child: Container(
                  width: 90,
                  height: 130,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                  ),
                  child: _cover != null
                      ? Image.file(_cover!, fit: BoxFit.cover)
                      : const Icon(Icons.add_a_photo),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 130,
                  child: TextField(
                    controller: _storyTitle,
                    expands: true,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: "Tên truyện",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _author,
            decoration: const InputDecoration(
              labelText: "Tác giả",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: "Mô tả",
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitStory,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text("TẠO TRUYỆN"),
            ),
          ),
        ],
      ),
    );
  }
  // ================= TAB CHAPTER =================
  Widget _buildChapterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: "Nhập tên truyện...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          if (_searchResults.isNotEmpty)
            Container(
              height: 250,
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (_, i) {
                  final s = _searchResults[i];
                  return InkWell(
                    onTap: () => _selectStory(s),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          CachedNetworkImage(
                            width: 60,
                            height: 90,
                            fit: BoxFit.cover,
                            imageUrl: '${ApiConfig.coverImage}/${s['coverUrl'] ?? ''}',
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s['title'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s['createdByName'] ?? "",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
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
              ),
            ),
          const SizedBox(height: 16),
          // SELECTED STORY
          if (_selectedStory != null) ...[
            Row(
              children: [
                CachedNetworkImage(
                  width: 70,
                  height: 100,
                  fit: BoxFit.cover,
                  imageUrl: '${ApiConfig.coverImage}/${(_selectedStory!['coverUrl'] ?? "")}',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedStory!['title'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedStory!['createdByName'] ?? "",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // FORM
            Row(
              children: [
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _chapterNo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Chương số",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _chapterTitle,
                    decoration: const InputDecoration(
                      labelText: "Tiêu đề",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _blocks.length,
                    itemBuilder: (_, i) {
                      final b = _blocks[i];
                      if (b.type == "text") {
                        return TextField(
                          controller: b.controller,
                          maxLines: null,
                          decoration: const InputDecoration(
                            hintText: "Nhập nội dung...",
                            border: InputBorder.none,
                          ),
                        );
                      }
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(b.imageFile!, height: 200),
                          ),
                          Positioned(
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _removeBlock(i),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  InkWell(
                    onTap: _pickImage,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.image_outlined, color: Colors.grey),
                          SizedBox(width: 3),
                          Text(
                            "Thêm ảnh",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitChapter,
                child: const Text("Đăng chương"),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
