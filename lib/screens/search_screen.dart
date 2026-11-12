import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/models/Story.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/cover_cache_manager.dart';
import 'package:novel_app/services/story_fetcher.dart';

import '../config/api_config.dart';

const List<String> _kGenreList = [
  'Action',
  'Adventure',
  'Adult Cast',
  'Anthropomorphic',
  'Avant Garde',
  'Award Winning',
  'Boys Love',
  'CGDCT',
  'Childcare',
  'Combat Sports',
  'Comedy',
  'Crossdressing',
  'Delinquents',
  'Detective',
  'Demons',
  'Drama',
  'Ecchi',
  'Educational',
  'Erotica',
  'Fantasy',
  'Full Color',
  'Gag Humor',
  'Girls Love',
  'Gore',
  'Gourmet',
  'Harem',
  'Hentai',
  'Historical',
  'Horror',
  'Idols (Female)',
  'Idols (Male)',
  'Isekai',
  'Iyashikei',
  'Josei',
  'Kids',
  'Love Polygon',
  'Love Status Quo',
  'Magical Sex Shift',
  'Mahou Shoujo',
  'Martial Arts',
  'Mecha',
  'Medical',
  'Memoir',
  'Military',
  'Mystery',
  'Mythology',
  'One Shot',
  'Organized Crime',
  'Otaku Culture',
  'Parody',
  'Performing Arts',
  'Pets',
  'Psychological',
  'Racing',
  'Reincarnation',
  'Reverse Harem',
  'Romance',
  'Samurai',
  'School Life',
  'Sci-Fi',
  'Seinen',
  'Showbiz',
  'Slice of Life',
  'Space',
  'Sports',
  'Strategy Game',
  'Super Power',
  'Supernatural',
  'Suspense',
  'Survival',
  'Team Sports',
  'Time Travel',
  'Tragedy',
  'Urban Fantasy',
  'Vampire',
  'Video Game',
  'Villainess',
  'Visual Arts',
  'Workplace',
  'Shoujo',
  'Shounen',
  'Manga',
  'Manhua',
  'Manhwa',
  'Webtoon',
  'Anime',
  'Comic',
  'Doujinshi',
  'Gender Bender',
  'Magic',
  'Mafia',
];

class SearchScreen extends StatefulWidget {
  final String? initialKeyword;
  final List<String>? initialGenres;

  const SearchScreen({super.key, this.initialKeyword, this.initialGenres});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController controller = TextEditingController();

  Timer? _debounce;

  List<Story> stories = [];
  final Set<String> selectedGenres = <String>{};

  bool isLoading = false;
  bool searchByAuthor = false;

  String keyword = '';

  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();

    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      controller.text = widget.initialKeyword!;
      keyword = widget.initialKeyword!;
    }

    if (widget.initialGenres != null && widget.initialGenres!.isNotEmpty) {
      selectedGenres.addAll(widget.initialGenres!);
    }

    if (keyword.isNotEmpty || selectedGenres.isNotEmpty) {
      _search(keyword);
    }
  }

  // ============================================================
  // Search
  // ============================================================

  Future<void> _search(String value) async {
    final searchKeyword = value.trim();
    final hasKeyword = searchKeyword.isNotEmpty;
    final hasGenres = selectedGenres.isNotEmpty;

    final requestId = ++_searchRequestId;

    if (!hasKeyword && !hasGenres) {
      if (!mounted) return;

      setState(() {
        stories = [];
        isLoading = false;
      });

      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final data = await StoryFetcher().search(
        searchByAuthor ? '' : searchKeyword,
        genres: hasGenres ? selectedGenres.toList() : null,
        author: searchByAuthor ? searchKeyword : null,
      );

      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        stories = data.map<Story>((e) => Story.fromJson(e)).toList();
        isLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        stories = [];
        isLoading = false;
      });

      debugPrint('[SEARCH ERROR] $e');
    }
  }

  void _onChanged(String value) {
    setState(() {
      keyword = value;
    });

    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _search(value);
    });
  }

  void _onSearchModeChanged(bool value) {
    setState(() {
      searchByAuthor = value;
    });

    _debounce?.cancel();
    _search(controller.text);
  }

  // Xóa riêng từ khóa, không xóa thể loại đã chọn.
  void _clearKeyword() {
    _debounce?.cancel();

    controller.clear();

    setState(() {
      keyword = '';
    });

    _search('');
  }

  void _submitSearch() {
    _debounce?.cancel();
    _search(controller.text);
  }

  // ============================================================
  // Genre filter
  // ============================================================

  Future<void> _showGenreDialog() async {
    final tempSelection = <String>{...selectedGenres};
    final genreFilterController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filter = genreFilterController.text.trim();

            final filteredGenres = _kGenreList
                .where(
                  (genre) => genre.toLowerCase().contains(filter.toLowerCase()),
                )
                .toList();

            final colorScheme = Theme.of(context).colorScheme;

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: MediaQuery.of(context).size.height * 0.82,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tiêu đề.
                      Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            color: colorScheme.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Lọc thể loại',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                            },
                            icon: const Icon(Icons.close),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Đóng',
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Tìm thể loại.
                      TextField(
                        controller: genreFilterController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Tìm thể loại...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: filter.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    genreFilterController.clear();
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(Icons.close, size: 18),
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Số lượng đã chọn.
                      Row(
                        children: [
                          Text(
                            'Đã chọn ${tempSelection.length}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (tempSelection.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  tempSelection.clear();
                                });
                              },
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              child: const Text('Bỏ chọn tất cả'),
                            ),
                        ],
                      ),

                      const Divider(height: 12),

                      // Danh sách thể loại.
                      Expanded(
                        child: filteredGenres.isEmpty
                            ? Center(
                                child: Text(
                                  'Không tìm thấy thể loại',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 8,
                                ),
                                child: Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: filteredGenres.map((genre) {
                                    final selected = tempSelection.contains(
                                      genre,
                                    );

                                    return FilterChip(
                                      label: Text(genre),
                                      selected: selected,
                                      showCheckmark: true,
                                      labelStyle: TextStyle(
                                        fontSize: 12,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 0,
                                      ),
                                      onSelected: (value) {
                                        setDialogState(() {
                                          if (value) {
                                            tempSelection.add(genre);
                                          } else {
                                            tempSelection.remove(genre);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                      ),

                      const Divider(height: 16),

                      // Nút thao tác.
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Hủy'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  selectedGenres
                                    ..clear()
                                    ..addAll(tempSelection);
                                });

                                Navigator.pop(dialogContext);

                                _debounce?.cancel();
                                _search(controller.text);
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Áp dụng'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    genreFilterController.dispose();
  }

  // ============================================================
  // Search controls
  // ============================================================

  Widget _buildSearchControls() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Search box.
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submitSearch(),
                  decoration: InputDecoration(
                    hintText: searchByAuthor
                        ? 'Tên tác giả...'
                        : 'Tìm tên truyện...',
                    hintStyle: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    // Kính lúp và nút X dùng chung một vị trí.
                    suffixIcon: IconButton(
                      tooltip: controller.text.isEmpty
                          ? 'Tìm kiếm'
                          : 'Xóa nội dung',
                      icon: Icon(
                        controller.text.isEmpty ? Icons.search : Icons.close,
                        color: controller.text.isEmpty
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      onPressed: controller.text.isEmpty
                          ? _submitSearch
                          : _clearKeyword,
                    ),
                    filled: true,
                    fillColor: colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // Author checkbox on the right of search box.
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  _onSearchModeChanged(!searchByAuthor);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: searchByAuthor,
                        onChanged: (value) {
                          _onSearchModeChanged(value ?? false);
                        },
                        activeColor: colorScheme.primary,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Tác giả',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: searchByAuthor
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Selected genre filters.
          if (selectedGenres.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...selectedGenres.map(
                  (genre) => InputChip(
                    label: Text(genre, style: const TextStyle(fontSize: 11)),
                    onDeleted: () {
                      setState(() {
                        selectedGenres.remove(genre);
                      });
                      _search(controller.text);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.close, size: 14),
                  label: const Text(
                    'Xóa bộ lọc',
                    style: TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      selectedGenres.clear();
                    });
                    _search(controller.text);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // Body
  // ============================================================

  Widget buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (keyword.trim().isEmpty && selectedGenres.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 56,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Tìm kiếm truyện',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Nhập tên truyện, tên tác giả hoặc chọn thể loại để bắt đầu.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (stories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 48,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              const Text(
                'Không tìm thấy kết quả',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Thử thay đổi từ khóa hoặc bộ lọc thể loại.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      itemCount: stories.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 90,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      itemBuilder: (_, i) {
        final story = stories[i];

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoryDetailScreen(storyId: story.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    cacheManager: CoverCacheManager.instance,
                    width: 70,
                    height: 105,
                    fit: BoxFit.cover,
                    imageUrl: '${ApiConfig.coverImage}/${story.coverUrl}',
                    placeholder: (context, url) => Container(
                      width: 70,
                      height: 105,
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.book_outlined),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 70,
                      height: 105,
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // Main UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tìm kiếm'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: selectedGenres.isNotEmpty,
              label: Text('${selectedGenres.length}'),
              child: const Icon(Icons.tune),
            ),
            tooltip: 'Lọc theo thể loại',
            onPressed: _showGenreDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildSearchControls(),
          Expanded(child: buildBody()),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
