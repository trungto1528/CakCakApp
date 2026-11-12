
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
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

  static const String _badgePrefix = '[[badge:';

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

  Future<void> _openSource(AiWsSource source) async {
    final uri = Uri.tryParse(source.url);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }

    await _openUrl(uri);
  }

  Future<void> _openUrl(Uri uri) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return;
    }

    try {
      final success = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!success && mounted) {
        _showOpenError();
      }
    } catch (_) {
      if (!mounted) return;
      _showOpenError();
    }
  }

  void _showOpenError() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Không thể mở liên kết nguồn.'),
        ),
      );
  }

  // ============================================================
  // Prepare badge markers before Markdown parsing.
  // ============================================================

  String _prepareMarkdownContent(
      String content,
      Map<int, BadgeData> badges,
      ) {
    var result = content;

    // Hide incomplete badge while streaming.
    if (widget.isStreaming) {
      final lastOpening = result.lastIndexOf(_badgePrefix);

      if (lastOpening >= 0) {
        final closing = result.indexOf(']]', lastOpening);

        if (closing < 0) {
          result = result.substring(0, lastOpening);
        }
      }

      // Handle incomplete opening marker:
      // [, [[, [[ba, [[badge...
      if (result.isNotEmpty) {
        for (var length = 1;
        length < _badgePrefix.length && length <= result.length;
        length++) {
          final suffix = result.substring(result.length - length);

          if (_badgePrefix.startsWith(suffix)) {
            result = result.substring(0, result.length - length);
            break;
          }
        }
      }
    }

    var badgeIndex = 0;

    final badgeRegex = RegExp(
      r'\[\[badge:([^\]|]+)\|([^\]]+)\]\]',
    );

    result = result.replaceAllMapped(badgeRegex, (match) {
      final label = match.group(1)?.trim() ?? '';
      final url = match.group(2)?.trim() ?? '';

      if (label.isEmpty || url.isEmpty) {
        return match.group(0) ?? '';
      }

      final uri = Uri.tryParse(url);

      if (uri == null ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.host.isEmpty) {
        return match.group(0) ?? '';
      }

      badges[badgeIndex] = BadgeData(
        label: label,
        url: url,
      );

      final marker = 'AIBADGEMARKER${badgeIndex}END';

      badgeIndex++;

      return marker;
    });

    return result;
  }

  MarkdownStyleSheet _buildMarkdownStyle(
      ThemeData theme,
      ColorScheme colorScheme,
      Color textColor,
      ) {
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: TextStyle(
        color: textColor,
        fontSize: 14,
        height: 1.5,
      ),
      h1: TextStyle(
        color: textColor,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
      h2: TextStyle(
        color: textColor,
        fontSize: 21,
        fontWeight: FontWeight.bold,
      ),
      h3: TextStyle(
        color: textColor,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      h4: TextStyle(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      h5: TextStyle(
        color: textColor,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
      h6: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
      strong: TextStyle(
        color: textColor,
        fontWeight: FontWeight.bold,
      ),
      em: TextStyle(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      a: TextStyle(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: colorScheme.primary,
      ),
      code: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 13,
        backgroundColor: colorScheme.surfaceContainerHighest,
        fontFamily: 'monospace',
      ),
      blockquote: TextStyle(
        color: textColor.withValues(alpha: 0.8),
        fontSize: 14,
        height: 1.5,
      ),
      listBullet: TextStyle(
        color: textColor,
        fontSize: 14,
      ),
      tableHead: TextStyle(
        color: textColor,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
      tableBody: TextStyle(
        color: textColor,
        fontSize: 13,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdown(
      ColorScheme colorScheme,
      Color textColor,
      ) {
    final theme = Theme.of(context);

    final badges = <int, BadgeData>{};

    final markdownContent = _prepareMarkdownContent(
      widget.content,
      badges,
    );

    return MarkdownBody(
      data: markdownContent,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [
        BadgeMarkerSyntax(badges),
        SourceBadgeSyntax(widget.sources.length),
      ],
      builders: {
        'custom_badge': CustomBadgeBuilder(
          colorScheme: colorScheme,
          onOpenUrl: _openUrl,
        ),
        'source_badge': SourceBadgeBuilder(
          sources: widget.sources,
          colorScheme: colorScheme,
          onOpenSource: _openSource,
        ),
      },
      styleSheet: _buildMarkdownStyle(
        theme,
        colorScheme,
        textColor,
      ),
      onTapLink: (text, href, title) {
        if (href == null) return;

        final uri = Uri.tryParse(href);

        if (uri == null) return;

        _openUrl(uri);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final bubbleColor = widget.isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);

    final textColor = widget.isUser
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

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
                  : _buildMarkdown(
                colorScheme,
                textColor,
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
                icon: const Icon(
                  Icons.refresh,
                  size: 16,
                ),
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

// ============================================================
// Badge data
// ============================================================

class BadgeData {
  final String label;
  final String url;

  const BadgeData({
    required this.label,
    required this.url,
  });
}

// ============================================================
// Badge marker syntax
// ============================================================

class BadgeMarkerSyntax extends md.InlineSyntax {
  final Map<int, BadgeData> badges;

  BadgeMarkerSyntax(this.badges)
      : super(r'AIBADGEMARKER(\d+)END');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final index = int.tryParse(match.group(1) ?? '');

    if (index == null) {
      return false;
    }

    final badge = badges[index];

    if (badge == null) {
      return false;
    }

    final element = md.Element.text(
      'custom_badge',
      badge.label,
    );

    element.attributes['url'] = badge.url;

    parser.addNode(element);

    return true;
  }
}

// ============================================================
// Source badge syntax
// ============================================================

class SourceBadgeSyntax extends md.InlineSyntax {
  final int sourceCount;

  SourceBadgeSyntax(this.sourceCount)
      : super(r'\[(?:Image\s+)?(\d+)\](?!\()');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final number = int.tryParse(match.group(1) ?? '');

    if (number == null ||
        number < 1 ||
        number > sourceCount) {
      return false;
    }

    final element = md.Element.text(
      'source_badge',
      number.toString(),
    );

    element.attributes['index'] = number.toString();

    parser.addNode(element);

    return true;
  }
}

// ============================================================
// Custom badge builder
// ============================================================

class CustomBadgeBuilder extends MarkdownElementBuilder {
  final ColorScheme colorScheme;
  final Future<void> Function(Uri uri) onOpenUrl;

  CustomBadgeBuilder({
    required this.colorScheme,
    required this.onOpenUrl,
  });

  @override
  Widget? visitElementAfter(
      md.Element element,
      TextStyle? preferredStyle,
      ) {
    final label = element.textContent;
    final url = element.attributes['url'] ?? '';

    final uri = Uri.tryParse(url);

    final isValidUrl = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
        vertical: 2,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isValidUrl
              ? () => onOpenUrl(uri)
              : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: 20,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isValidUrl) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new,
                    size: 11,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Source badge builder
// ============================================================

class SourceBadgeBuilder extends MarkdownElementBuilder {
  final List<AiWsSource> sources;
  final ColorScheme colorScheme;
  final Future<void> Function(AiWsSource source) onOpenSource;

  SourceBadgeBuilder({
    required this.sources,
    required this.colorScheme,
    required this.onOpenSource,
  });

  @override
  Widget? visitElementAfter(
      md.Element element,
      TextStyle? preferredStyle,
      ) {
    final number = int.tryParse(
      element.attributes['index'] ?? '',
    );

    if (number == null ||
        number < 1 ||
        number > sources.length) {
      return const SizedBox.shrink();
    }

    final source = sources[number - 1];

    final domain = source.domain.replaceFirst(
      RegExp(r'^www\.', caseSensitive: false),
      '',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
        vertical: 2,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onOpenSource(source),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: 18,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    domain,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.open_in_new,
                  size: 10,
                  color: colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
