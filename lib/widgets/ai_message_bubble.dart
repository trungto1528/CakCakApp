import 'package:flutter/material.dart';
import '../models/ai_chat_message.dart';
class AiMessageBubble extends StatelessWidget {
  final AiChatMessage message;
  final bool isUser;
  const AiMessageBubble({
    super.key,
    required this.message,
    required this.isUser,
  });
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isUser
        ? colorScheme.primary
        : colorScheme.surfaceVariant.withOpacity(0.6);
    final textColor = isUser
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
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
        child: Text(
          message.content,
          style: TextStyle(color: textColor),
        ),
      ),
    );
  }
}
