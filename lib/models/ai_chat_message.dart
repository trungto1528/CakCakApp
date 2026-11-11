
import 'ai_ws_message.dart';

class AiChatMessage {
  final String role;
  final String content;
  final List<AiWsSource> sources;

  AiChatMessage({
    required this.role,
    required this.content,
    this.sources = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      "role": role,
      "content": content,
    };
  }

  AiChatMessage copyWith({
    String? content,
    List<AiWsSource>? sources,
  }) {
    return AiChatMessage(
      role: role,
      content: content ?? this.content,
      sources: sources ?? this.sources,
    );
  }
}
