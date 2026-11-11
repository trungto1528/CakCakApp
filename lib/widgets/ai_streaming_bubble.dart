
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ai_ws_message.dart';

class AiStreamingBubble extends StatefulWidget {
  final String content;
  final bool isUser;
  final bool isStreaming;
  final VoidCallback? onRetry;
  final List<AiWsSource> sources;

  const AiStreamingBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isStreaming = false,
    this.onRetry,
    this.sources = const [],
  });

  @override
  State<AiStreamingBubble> createState() => _AiStreamingBubbleState();
}

class _AiStreamingBubbleState extends State<AiStreamingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();

    _cursorController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  String _convertCitations(String content) {
    if (widget.sources.isEmpty || content.isEmpty) {
      return content;
    }

    return content.replaceAllMapped(
      RegExp(r'\[(\d+)\](?!\()'),
          (match) {
        final number = int.tryParse(match.group(1) ?? '');

        if (number == null ||
            number < 1 ||
            number > widget.sources.length) {
          return match.group(0)!;
        }

        return '[$number](citation:$number)';
      },
    );
  }

  Future<void> _openCitation(int number) async {
    if (number < 1 || number > widget.sources.length) {
      return;
    }

    final source = widget.sources[number - 1];
    final uri = Uri.tryParse(source.url);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }

    await _openUrl(uri);
  }

  Future<void> _openUrl(Uri uri) async {
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể mở liên kết nguồn.'),
        ),
      );
    }
  }

  void _handleLinkTap(
      String text,
      String? href,
      String? title,
      ) {
    if (href == null || href.isEmpty) {
      return;
    }

    if (href.startsWith('citation:')) {
      final number = int.tryParse(
        href.substring('citation:'.length),
      );

      if (number != null) {
        _openCitation(number);
      }

      return;
    }

    final uri = Uri.tryParse(href);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }

    _openUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final bubbleColor = widget.isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest.withOpacity(0.6);

    final textColor = widget.isUser
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    final markdownStyle = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).copyWith(
      p: TextStyle(
        color: textColor,
        fontSize: 14,
        height: 1.5,
      ),
      h1: TextStyle(
        color: textColor,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      h2: TextStyle(
        color: textColor,
        fontSize: 19,
        fontWeight: FontWeight.bold,
      ),
      h3: TextStyle(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      a: TextStyle(
        color: widget.isUser
            ? colorScheme.onPrimary
            : colorScheme.primary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.none,
      ),
      code: TextStyle(
        color: textColor,
        backgroundColor: colorScheme.surfaceContainerHighest,
        fontSize: 12,
      ),
    );

    return Align(
      alignment: widget.isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(
          vertical: 4,
          horizontal: 8,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: widget.isUser
                  ? Text(
                widget.content,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                ),
              )
                  : MarkdownBody(
                data: _convertCitations(widget.content),
                styleSheet: markdownStyle,
                onTapLink: _handleLinkTap,
              ),
            ),
            if (widget.isStreaming && !widget.isUser) ...[
              const SizedBox(width: 4),
              AnimatedBuilder(
                animation: _cursorController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _cursorController.value,
                    child: Container(
                      width: 2,
                      height: 16,
                      color: textColor,
                    ),
                  );
                },
              ),
            ],
            if (widget.onRetry != null && widget.isUser) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: widget.onRetry,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
