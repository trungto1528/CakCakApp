import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/app_preference.dart';
import '../services/ai_ws_service.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_source.dart';
import '../models/ai_ws_message.dart';
import '../widgets/ai_streaming_bubble.dart';
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
  final _aiWsService = AiWsService();
  final List<AiChatMessage> _messages = [];
  bool _isSending = false;
  String? _error;
  bool _isConnecting = false;
  AiStatus _status = AiStatus.idle;
  List<AiWsSource> _sources = [];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _isConnecting = true);
    try {
      final prefs = await AppPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null || userStr.isEmpty) {
        throw Exception('Đăng nhập đê');
      }
      final userJson = jsonDecode(userStr) as Map<String, dynamic>;
      final userId = userJson['id'] as int;
      await _aiWsService.connect(userId);
      if (!mounted) return;
      _aiWsService.messages.listen(_handleWsMessage);
      setState(() {
        _isConnecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _error = 'Lỗi rồi: $e';
      });
    }
  }

  void _handleWsMessage(AiWsMessage msg) {
    if (!mounted) return;
    switch (msg.type) {
      case 'status':
        setState(() {
          _status = _parseStatus(msg.content ?? '');
        });
        break;
      case 'delta':
        setState(() {
          if (_messages.isEmpty || _messages.last.role == 'user') {
            _messages.add(AiChatMessage(role: 'assistant', content: msg.content ?? ''));
          } else {
            final last = _messages.last;
            _messages[_messages.length - 1] = AiChatMessage(
              role: last.role,
              content: last.content + (msg.content ?? ''),
            );
          }
          _scrollToBottom();
        });
        break;
      case 'sources':
        setState(() {
          _sources = msg.sources ?? [];
        });
        break;
      case 'done':
        setState(() {
          _status = AiStatus.idle;
          _isSending = false;
        });
        break;
      case 'error':
        setState(() {
          _status = AiStatus.idle;
          _isSending = false;
          _error = msg.error ?? 'Éo biết lỗi gì';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.error ?? 'Éo biết lỗi gì')),
        );
        break;
      case 'pong':
        break;
    }
  }

  AiStatus _parseStatus(String content) {
    if (content.contains('Nghĩ')) return AiStatus.thinking;
    if (content.contains('Tìm kiếm')) return AiStatus.searching;
    if (content.contains('Tổng hợp')) return AiStatus.synthesizing;
    return AiStatus.idle;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _aiWsService.disconnect();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending || !_aiWsService.isConnected) return;
    setState(() {
      _messages.add(AiChatMessage(role: 'user', content: text));
      _controller.clear();
      _isSending = true;
      _status = AiStatus.thinking;
      _error = null;
    });
    _scrollToBottom();
    _aiWsService.sendMessage(text);
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
        title: const Text('AI Chat (Trùm bốc phét, đừng tin)'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          if (_isConnecting)
            const LinearProgressIndicator(),
          if (_isConnecting)
            const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final isLast = index == _messages.length - 1;
                final isStreaming = isLast && m.role == 'assistant' && _isSending;
                return AiStreamingBubble(
                  content: m.content,
                  isUser: m.role == 'user',
                  isStreaming: isStreaming,
                );
              },
            ),
          ),
          if (_status != AiStatus.idle) AiStatusIndicator(status: _status),
          if (_sources.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Nguồn',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _sources.length,
                itemBuilder: (context, index) {
                  return AiSourceItem(
                    source: AiSource(
                      title: _sources[index].title,
                      url: _sources[index].url,
                      content: _sources[index].content,
                      score: _sources[index].score,
                      publishedDate: _sources[index].publishedDate,
                    ),
                  );
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
                    enabled: !_isSending && _aiWsService.isConnected,
                    decoration: InputDecoration(
                      hintText: _aiWsService.isConnected
                          ? 'Hỏi đê'
                          : 'Loading đến 99%',
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
                    color: _aiWsService.isConnected && !_isSending
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
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
                    onPressed: (!_isSending && _aiWsService.isConnected)
                        ? _sendMessage
                        : null,
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