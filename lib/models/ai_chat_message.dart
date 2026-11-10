class AiChatMessage {
  final String role;
  final String content;
  AiChatMessage({required this.role, required this.content});
  Map<String, dynamic> toJson() {
    return {"role": role, "content": content};
  }
}
