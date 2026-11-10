import 'package:flutter/material.dart';
import '../services/app_preference.dart';
import '../services/ai_service.dart';
import '../models/ai_chat_message.dart';
import '../widgets/ai_message_bubble.dart';
import '../widgets/ai_source_item.dart';
import '../widgets/ai_status_indicator.dart';
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}
class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _aiService = AiService();
  final List<AiChatMessage> _messages = [];
  String? _conversationId;
  bool _isSending = false;
  AiStatus _status = AiStatus.idle;
  AiChatResponse? _lastResponse;
  String? _error;
  bool get _hasSearchSources =>
      _lastResponse != null &&
      _lastResponse!.usedSearch &&
      _lastResponse!.sources.isNotEmpty;
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() {
      _messages.add(AiChatMessage(role: 'user', content: text));
      _controller.clear();
      _isSending = true;
      _status = AiStatus.thinking;
      _error = null;
      _lastResponse = null;
    });
    _scrollToBottom();
    try {
      final prefs = await AppPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null || userStr.isEmpty) {
        throw Exception('Chua dang nhap. Vui long dang nhap de su dung AI chat.');
      }
      final history = _messages
          .take(20)
          .map((e) => AiChatMessage(role: e.role, content: e.content))
          .toList();
      final res = await _aiService.sendMessage(
        message: text,
        conversationId: _conversationId ?? '',
        history: history,
      );
      if (!mounted) return;
      setState(() {
        _conversationId = res.conversationId;
        _lastResponse = res;
        _messages.add(AiChatMessage(role: 'assistant', content: res.answer));
        _status = AiStatus.idle;
        _isSending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _status = AiStatus.idle;
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loi: $e')),
      );
    } finally {
      if (mounted) {
        _scrollToBottom();
      }
    }
  }
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                return AiMessageBubble(message: m, isUser: m.role == 'user');
              },
            ),
          ),
          if (_status != AiStatus.idle) AiStatusIndicator(status: _status),
          if (_hasSearchSources) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Nguon tham co',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _lastResponse!.sources.length,
                itemBuilder: (context, index) {
                  return AiSourceItem(source: _lastResponse!.sources[index]);
                },
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isSending,
                    decoration: InputDecoration(
                      hintText: 'Nhap cau hoi...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}
