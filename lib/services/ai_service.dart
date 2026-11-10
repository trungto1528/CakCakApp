import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/app_preference.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_source.dart';
class AiChatResponse {
  final String conversationId;
  final String answer;
  final bool usedSearch;
  final List<AiSource> sources;
  AiChatResponse({
    required this.conversationId,
    required this.answer,
    required this.usedSearch,
    required this.sources,
  });
  factory AiChatResponse.fromJson(Map<String, dynamic> json) {
    return AiChatResponse(
      conversationId: json['conversationId'] ?? '',
      answer: json['answer'] ?? '',
      usedSearch: json['usedSearch'] == true,
      sources: (json['sources'] as List<dynamic>?)
          ?.map((e) => AiSource.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}
class AiService {
  Future<AiChatResponse> sendMessage({
    required String message,
    required String conversationId,
    required List<AiChatMessage> history,
  }) async {
    final prefs = await AppPreferences.getInstance();
    final userStr = prefs.getString('user');
    if (userStr == null || userStr.isEmpty) {
      throw Exception('Chua dang nhap. Vui long dang nhap de su dung AI chat.');
    }
    final userJson = jsonDecode(userStr) as Map<String, dynamic>;
    final userId = userJson['id'];
    final body = <String, dynamic>{
      'message': message,
      'conversationId': conversationId,
      'history': history.map((e) => e.toJson()).toList(),
    };
    final res = await http.post(
      Uri.parse("${ApiConfig.api}/ai/chat"),
      headers: {
        'Content-Type': 'application/json',
        'userId': userId.toString(),
      },
      body: jsonEncode(body),
    );
    if (res.statusCode == 200) {
      return AiChatResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } else {
      throw Exception(res.body.isNotEmpty ? res.body : 'Loi server (${res.statusCode})');
    }
  }
}
