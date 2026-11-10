import 'package:flutter/material.dart';
enum AiStatus { idle, thinking, searching, synthesizing }
class AiStatusIndicator extends StatelessWidget {
  final AiStatus status;
  const AiStatusIndicator({super.key, required this.status});
  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      AiStatus.idle => '',
      AiStatus.thinking => 'AI dang suy nghinh...',
      AiStatus.searching => 'Dang tim kiem Internet...',
      AiStatus.synthesizing => 'Dang tong hop thong tin...',
    };
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}
