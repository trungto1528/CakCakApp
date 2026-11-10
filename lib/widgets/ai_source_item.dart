import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ai_source.dart';
class AiSourceItem extends StatelessWidget {
  final AiSource source;
  const AiSourceItem({super.key, required this.source});
  Future<void> _openUrl(BuildContext context) async {
    final uri = Uri.parse(source.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Khong the mo URL: ${source.url}')),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        source.title.isNotEmpty ? source.title : source.url,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            source.domain,
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontSize: 12,
            ),
          ),
          if (source.content.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              source.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _openUrl(context),
    );
  }
}
