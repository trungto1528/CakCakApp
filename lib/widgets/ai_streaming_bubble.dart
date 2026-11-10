import 'package:flutter/material.dart';

class AiStreamingBubble extends StatefulWidget {
  final String content;
  final bool isUser;
  final bool isStreaming;
  final VoidCallback? onRetry;

  const AiStreamingBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isStreaming = false,
    this.onRetry,
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = widget.isUser
        ? colorScheme.primary
        : colorScheme.surfaceVariant.withOpacity(0.6);
    final textColor = widget.isUser
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    return Align(
      alignment: widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                widget.content,
                style: TextStyle(color: textColor),
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