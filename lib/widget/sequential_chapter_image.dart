import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/chapter_cache_manager.dart';

class SequentialChapterImage extends StatefulWidget {
  final String imageUrl;
  final bool shouldLoad;
  final VoidCallback? onLoadFinished;
  final double? width;

  const SequentialChapterImage({
    super.key,
    required this.imageUrl,
    this.shouldLoad = true,
    this.onLoadFinished,
    this.width,
  });

  @override
  State<SequentialChapterImage> createState() =>
      _SequentialChapterImageState();
}

class _SequentialChapterImageState extends State<SequentialChapterImage> {
  bool _notifiedFinished = false;

  void _notifyFinished() {
    if (_notifiedFinished) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _notifiedFinished) return;

      _notifiedFinished = true;
      widget.onLoadFinished?.call();
    });
  }

  Widget _placeholder() {
    return SizedBox(
      width: widget.width,
      height: 220,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _errorWidget() {
    return SizedBox(
      width: widget.width,
      height: 160,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              size: 36,
              color: Colors.grey,
            ),
            const SizedBox(height: 8),
            const Text(
              'Không thể tải ảnh',
              style: TextStyle(color: Colors.grey),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _notifiedFinished = false;
                });
              },
              child: const Text('Thử tải lại'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant SequentialChapterImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.imageUrl != widget.imageUrl) {
      _notifiedFinished = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.shouldLoad) {
      return _placeholder();
    }

    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      width: widget.width,
      fit: BoxFit.fitWidth,
      cacheManager: ChapterCacheManager.instance,
      placeholder: (context, url) => _placeholder(),
      imageBuilder: (context, imageProvider) {
        _notifyFinished();

        return Image(
          image: imageProvider,
          width: widget.width,
          fit: BoxFit.fitWidth,
        );
      },
      errorWidget: (context, url, error) {
        _notifyFinished();
        return _errorWidget();
      },
    );
  }
}