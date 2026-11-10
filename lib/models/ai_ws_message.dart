enum AiWsMessageType {
  message,
  ping,
  cancel,
  status,
  delta,
  sources,
  done,
  error,
  pong,
}

class AiWsMessage {
  final String type;
  final String? conversationId;
  final String? content;
  final String? title;
  final String? url;
  final bool? usedSearch;
  final List<AiWsSource>? sources;
  final String? error;

  AiWsMessage({
    required this.type,
    this.conversationId,
    this.content,
    this.title,
    this.url,
    this.usedSearch,
    this.sources,
    this.error,
  });

  factory AiWsMessage.fromJson(Map<String, dynamic> json) {
    return AiWsMessage(
      type: json['type'] as String,
      conversationId: json['conversationId'] as String?,
      content: json['content'] as String?,
      title: json['title'] as String?,
      url: json['url'] as String?,
      usedSearch: json['usedSearch'] as bool?,
      sources: (json['sources'] as List<dynamic>?)
          ?.map((e) => AiWsSource.fromJson(e as Map<String, dynamic>))
          .toList(),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'conversationId': conversationId,
      'content': content,
      'title': title,
      'url': url,
      'usedSearch': usedSearch,
      'sources': sources?.map((e) => e.toJson()).toList(),
      'error': error,
    };
  }

  static AiWsMessage message(String content, [String? conversationId]) {
    return AiWsMessage(
      type: 'message',
      content: content,
      conversationId: conversationId,
    );
  }

  static AiWsMessage ping() {
    return AiWsMessage(type: 'ping');
  }

  static AiWsMessage cancel(String conversationId) {
    return AiWsMessage(type: 'cancel', conversationId: conversationId);
  }
}

class AiWsSource {
  final String title;
  final String url;
  final String content;
  final double? score;
  final String? publishedDate;

  AiWsSource({
    required this.title,
    required this.url,
    this.content = '',
    this.score,
    this.publishedDate,
  });

  factory AiWsSource.fromJson(Map<String, dynamic> json) {
    return AiWsSource(
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      content: json['content'] ?? '',
      score: json['score'] is num ? (json['score'] as num).toDouble() : null,
      publishedDate: json['publishedDate'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'content': content,
      'score': score,
      'publishedDate': publishedDate,
    };
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