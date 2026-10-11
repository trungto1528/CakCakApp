import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/config/api_config.dart';
import 'package:novel_app/screens/chapter_reader_screen.dart';
import 'package:novel_app/services/bookmark.dart';
import 'package:novel_app/services/story_fetcher.dart';
import 'package:novel_app/widget/expand_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/User.dart';
import 'login_screen.dart';

class StoryDetailScreen extends StatefulWidget {
  final int storyId;

  const StoryDetailScreen({super.key, required this.storyId});

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  late Map<String, dynamic> story;

  User? user;

  bool storyLoading = true;
  bool bookmarkLoading = false;
  bool isSaved = false;

  List chapters = [];

  static const int _pageSize = 20;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await _loadUser();
    if (!mounted) return;

    await _loadStory();
    if (!mounted) return;

    await _loadSaved();
  }

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Yêu cầu đăng nhập'),
        content: const Text('Bạn cần đăng nhập để lưu truyện'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              final loginResult = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LoginScreen()),
              );

              if (!mounted) return;

              if (loginResult == true) {
                await _loadUser();
                if (!mounted) return;

                await _loadSaved();
              }
            },
            child: const Text('Đăng nhập'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString('user');

    if (!mounted) return;

    if (userStr == null) {
      setState(() => user = null);
      return;
    }

    try {
      final json = jsonDecode(userStr);

      setState(() {
        user = User.fromJson(json);
      });
    } catch (_) {
      setState(() => user = null);
    }
  }

  Future<void> _loadSaved() async {
    if (user == null) {
      if (!mounted) return;

      setState(() {
        isSaved = false;
        bookmarkLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() => bookmarkLoading = true);
    }

    try {
      final result = await Bookmark().isSavedApi(user!.id, widget.storyId);

      if (!mounted) return;

      setState(() {
        isSaved = result;
        bookmarkLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => bookmarkLoading = false);
      debugPrint('Lỗi kiểm tra bookmark: $e');
    }
  }

  Future<void> _loadStory() async {
    try {
      final data = await StoryFetcher().fetchStory(widget.storyId);

      if (!mounted) return;

      setState(() {
        story = data;
        chapters = data['chapters'] ?? [];
        _currentPage = 0;
        storyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => storyLoading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lỗi tải truyện')));

      debugPrint('Lỗi tải truyện: $e');
    }
  }

  // Chuyển chapterNumber thành số để xử lý.
  // Hỗ trợ API trả về int, double hoặc String.
  double? _parseChapterNumber(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      final number = value.toDouble();
      return number.isFinite ? number : null;
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final number = double.tryParse(text);
    if (number == null || !number.isFinite) return null;

    return number;
  }

  // Hiển thị số chapter gọn gàng:
  // 1.0 -> 1, 1.5 -> 1.5, 10.0 -> 10.
  String _formatChapterNumber(double number) {
    if (number == number.truncateToDouble()) {
      return number.toInt().toString();
    }

    return number.toString();
  }

  // Gom các chương có cùng chapterNumber.
  Map<double, List<dynamic>> get groupedChapters {
    final Map<double, List<dynamic>> map = {};

    for (final c in chapters) {
      if (c is! Map) continue;

      final number = _parseChapterNumber(c['chapterNumber']);

      // Bỏ qua dữ liệu không có số chương hợp lệ,
      // tránh gom tất cả vào Ch. 0.
      if (number == null) {
        debugPrint(
          'Bỏ qua chapter không có chapterNumber hợp lệ: '
          '${c['title']} - ${c['chapterNumber']}',
        );
        continue;
      }

      map.putIfAbsent(number, () => []);
      map[number]!.add(c);
    }

    final sortedKeys = map.keys.toList()..sort();

    return {for (final number in sortedKeys) number: map[number]!};
  }

  int get _totalPages {
    return (groupedChapters.length / _pageSize).ceil();
  }

  Map<double, List<dynamic>> get paginatedChapters {
    final entries = groupedChapters.entries.toList();
    final start = _currentPage * _pageSize;

    if (start >= entries.length) {
      return {};
    }

    final end = (start + _pageSize).clamp(0, entries.length);

    return Map<double, List<dynamic>>.fromEntries(entries.sublist(start, end));
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _totalPages) return;

    setState(() {
      _currentPage = page;
    });
  }

  Widget _buildInformation() {
    final List information = story['information'] ?? [];

    if (information.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text(
              'Thông tin thêm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${information.length} thông tin',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            children: [
              ...information.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;

                final label = item['label']?.toString() ?? '';
                final value = item['value']?.toString() ?? '';

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              value,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index != information.length - 1)
                      Divider(height: 1, color: Colors.grey.shade200),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    if (_totalPages <= 1) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Trang đầu',
            onPressed: _currentPage > 0 ? () => _goToPage(0) : null,
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: 'Trang trước',
            onPressed: _currentPage > 0
                ? () => _goToPage(_currentPage - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 100),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Trang ${_currentPage + 1} / $_totalPages',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Trang sau',
            onPressed: _currentPage < _totalPages - 1
                ? () => _goToPage(_currentPage + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Trang cuối',
            onPressed: _currentPage < _totalPages - 1
                ? () => _goToPage(_totalPages - 1)
                : null,
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (storyLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(story['title']?.toString() ?? ''),
        actions: [
          IconButton(
            icon: bookmarkLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isSaved ? Icons.favorite : Icons.favorite_border,
                    color: isSaved ? Colors.red : null,
                  ),
            onPressed: bookmarkLoading
                ? null
                : () async {
                    if (user == null) {
                      _showLoginRequiredDialog();
                      return;
                    }

                    setState(() {
                      bookmarkLoading = true;
                    });

                    try {
                      if (isSaved) {
                        await Bookmark().unsaveStory(user!.id, widget.storyId);
                      } else {
                        await Bookmark().saveStory(user!.id, widget.storyId);
                      }

                      if (!mounted) return;

                      setState(() {
                        isSaved = !isSaved;
                        bookmarkLoading = false;
                      });
                    } catch (e) {
                      if (!mounted) return;

                      setState(() {
                        bookmarkLoading = false;
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Không thể cập nhật danh sách yêu thích',
                          ),
                        ),
                      );

                      debugPrint('Lỗi cập nhật bookmark: $e');
                    }
                  },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: init,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Divider(),

            // Thông tin đầu truyện.
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl:
                          '${ApiConfig.coverImage}/${story['coverUrl'] ?? ''}',
                      height: 180,
                      width: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story['title']?.toString() ?? '',
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(height: 6),
                        Text('Tác giả: ${story['author'] ?? ''}'),
                        Text('Tạo bởi: ${story['createdByName'] ?? ''}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Mô tả truyện.
            Padding(
              padding: const EdgeInsets.all(16),
              child: ExpandableText(
                text: story['description']?.toString() ?? '',
              ),
            ),

            _buildInformation(),

            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Danh sách chương',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${groupedChapters.length} chương · '
                '${_totalPages == 0 ? 0 : _currentPage + 1}/$_totalPages trang',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),

            // Danh sách chương của trang hiện tại.
            ...paginatedChapters.entries.map((entry) {
              final chapterNumber = entry.key;
              final list = entry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Ch. ${_formatChapterNumber(chapterNumber)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),

                  // Các bản dịch/nguồn của cùng chương.
                  ...list.map((c) {
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.blue,
                        ),
                        title: Text(
                          c['title']?.toString() ?? 'Không có tiêu đề',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Source: ${c['createdBy'] ?? 'Không rõ'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChapterReaderScreen(
                                chapterId: c['id'],
                                storyId: widget.storyId,
                                source: c['createdBy'],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ],
              );
            }),

            _buildPagination(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
