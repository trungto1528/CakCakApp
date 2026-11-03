import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/models/Story.dart';
import 'package:novel_app/screens/story_detail_screen.dart';
import 'package:novel_app/services/story_fetcher.dart';
import '../config/api_config.dart';

// Danh sách thể loại chuẩn (đồng bộ với backend TruyenGGVN:
// VIETNAMESE_TO_ENGLISH_GENRE), dùng cục bộ trên frontend.
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

  const SearchScreen({
    super.key,
    this.initialKeyword,
    this.initialGenres,
  });
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController controller = TextEditingController();
  Timer? _debounce;
  List<Story> stories = [];
  final Set<String> selectedGenres = <String>{};
  bool isLoading = false;
  String keyword = "";

  @override
  void initState() {
    super.initState();
    if (widget.initialKeyword != null &&
        widget.initialKeyword!.isNotEmpty) {
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

  Future<void> _search(String keyword) async {
    final hasKeyword = keyword.trim().isNotEmpty;
    final hasGenres = selectedGenres.isNotEmpty;
    if (!hasKeyword && !hasGenres) {
      setState(() => stories = []);
      return;
    }
    setState(() => isLoading = true);
    try {
      final data = await StoryFetcher().search(
        keyword.trim(),
        genres: hasGenres ? selectedGenres.toList() : null,
      );
      if (!mounted) return;
      setState(() {
        stories = data.map<Story>((e) => Story.fromJson(e)).toList();
      });
    } catch (e) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showGenreDialog() {
    final tempSelection = <String>{};
    tempSelection.addAll(selectedGenres);
    final genreFilterController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filterGenre = genreFilterController.text;
            final filteredGenres = _kGenreList
                .where((g) => g.toLowerCase().contains(filterGenre.toLowerCase()))
                .toList();

            return AlertDialog(
              title: const Text('Lọc theo thể loại'),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        key: const ValueKey('genre_search_field'),
                        controller: genreFilterController,
                        decoration: InputDecoration(
                          hintText: 'Tìm thể loại...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: filterGenre.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    genreFilterController.clear();
                                    setSheetState(() {});
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // Thể loại đã chọn lên đầu danh sách.
                          ...tempSelection.toList().map((g) => FilterChip(
                                label: Text(g, style: const TextStyle(fontSize: 13)),
                                selected: true,
                                onSelected: (_) {
                                  setSheetState(() => tempSelection.remove(g));
                                },
                              )),
                          FilterChip(
                            label: const Text('Tất cả thể loại',
                                style: TextStyle(fontSize: 13)),
                            selected: tempSelection.isEmpty,
                            onSelected: (_) {
                              setSheetState(() => tempSelection.clear());
                            },
                          ),
                          ...filteredGenres.where((g) => !tempSelection.contains(g)).map((g) => FilterChip(
                                label: Text(g, style: const TextStyle(fontSize: 13)),
                                selected: tempSelection.contains(g),
                                onSelected: (_) {
                                  setSheetState(() {
                                    if (tempSelection.contains(g)) {
                                      tempSelection.remove(g);
                                    } else {
                                      tempSelection.add(g);
                                    }
                                  });
                                },
                              )),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      selectedGenres
                        ..clear()
                        ..addAll(tempSelection);
                    });
                    Navigator.pop(dialogContext);
                    _search(controller.text.trim());
                  },
                  child: const Text('Áp dụng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      keyword = value;
      _search(keyword);
    });
  }

  void _clear() {
    controller.clear();
    setState(() {
      stories = [];
      keyword = "";
      selectedGenres.clear();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: "Tìm truyện...",
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clear,
            ),
          ),
          onChanged: _onChanged,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Lọc theo thể loại',
            onPressed: _showGenreDialog,
          ),
          if (selectedGenres.isNotEmpty)
            Chip(
              label: Text('${selectedGenres.length} thể loại'),
              onDeleted: () {
                setState(() => selectedGenres.clear());
                _search(controller.text.trim());
              },
            ),
        ],
      ),
      body: buildBody(),
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (keyword.isEmpty && selectedGenres.isEmpty) {
      return const Center(child: Text("Nhập từ khóa hoặc chọn thể loại để tìm truyện"));
    }
    if (stories.isEmpty) {
      return const Center(child: Text("Không tìm thấy kết quả"));
    }
    return ListView.builder(
      itemCount: stories.length,
      itemBuilder: (_, i) {
        final s = stories[i];
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
                    imageUrl: "${ApiConfig.coverImage}/${s.coverUrl}",
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
