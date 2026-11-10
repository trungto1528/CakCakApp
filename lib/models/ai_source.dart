class AiSource {
  final String title;
  final String url;
  final String content;
  final double? score;
  final String? publishedDate;
  AiSource({
    required this.title,
    required this.url,
    this.content = '',
    this.score,
    this.publishedDate,
  });
  factory AiSource.fromJson(Map<String, dynamic> json) {
    return AiSource(
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      content: json['content'] ?? '',
      score: json['score'] is num ? (json['score'] as num).toDouble() : null,
      publishedDate: json['published_date'],
    );
  }
  String get domain {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : url;
    } catch (_) {
      return url;
    }
  }
}
