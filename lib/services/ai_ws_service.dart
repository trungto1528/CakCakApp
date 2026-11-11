
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/ai_ws_message.dart';

class AiWsService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final _messageController = StreamController<AiWsMessage>.broadcast();

  String? _conversationId;
  bool _isConnected = false;
  Timer? _pingTimer;

  Stream<AiWsMessage> get messages => _messageController.stream;
  bool get isConnected => _isConnected;
  String? get conversationId => _conversationId;

  static String formatError(
      Object? error, {
        bool connectionError = false,
      }) {
    if (error == null) {
      return connectionError
          ? 'Không thể kết nối đến máy chủ AI.'
          : 'AI không thể xử lý yêu cầu này.';
    }

    final raw = error.toString().trim();

    if (raw.isEmpty) {
      return connectionError
          ? 'Không thể kết nối đến máy chủ AI.'
          : 'AI không thể xử lý yêu cầu này.';
    }

    final lower = raw.toLowerCase();

    if (error is SocketException ||
        error is WebSocketException ||
        error is TimeoutException ||
        lower.contains('socketexception') ||
        lower.contains('websocketexception') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable')) {
      return 'Không thể kết nối đến máy chủ. Vui lòng thử lại.';
    }

    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('timeoutexception')) {
      return 'Máy chủ phản hồi quá lâu. Vui lòng thử lại.';
    }

    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('invalid api key') ||
        lower.contains('authentication')) {
      return 'Dịch vụ AI đang gặp lỗi xác thực. Vui lòng thử lại sau.';
    }

    if (lower.contains('429') ||
        lower.contains('rate limit') ||
        lower.contains('too many requests') ||
        lower.contains('quota exceeded')) {
      return 'Dịch vụ AI đang quá tải. Vui lòng thử lại sau.';
    }

    if (RegExp(r'\b5\d{2}\b').hasMatch(raw) ||
        lower.contains('internal server error') ||
        lower.contains('service unavailable') ||
        lower.contains('bad gateway')) {
      return 'Máy chủ AI đang gặp sự cố. Vui lòng thử lại sau.';
    }

    if (lower.contains('tavily')) {
      return 'Không thể tìm kiếm thông tin trên Internet lúc này.';
    }

    final firstLine = raw.split(RegExp(r'[\r\n]')).first.trim();

    final looksLikeException = RegExp(
      r'^(exception|error|runtimeexception|'
      r'illegalstateexception|illegalargumentexception|'
      r'java\.|org\.|com\.|io\.|dart\.)',
      caseSensitive: false,
    ).hasMatch(firstLine);

    if (looksLikeException ||
        firstLine.contains('{') ||
        firstLine.contains(' at ') ||
        firstLine.contains('Caused by:')) {
      return 'AI không thể xử lý yêu cầu này. Vui lòng thử lại.';
    }

    if (firstLine.length > 140) {
      return 'AI không thể xử lý yêu cầu này. Vui lòng thử lại.';
    }

    return firstLine;
  }

  Future<void> connect(int userId) async {
    if (_isConnected) return;

    final uri = Uri.parse(
      'ws://vps212.trungto.dpdns.org:7777/ws/ai/chat?userId=$userId',
    );

    try {
      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _isConnected = true;
      _startPingTimer();
    } catch (_) {
      _isConnected = false;
      _pingTimer?.cancel();

      throw Exception(
        formatError(
          'connection error',
          connectionError: true,
        ),
      );
    }
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final msg = AiWsMessage.fromJson(json);

      // Cập nhật conversationId ngay khi nhận được bất kỳ sự kiện nào.
      if (msg.conversationId != null &&
          msg.conversationId!.trim().isNotEmpty) {
        _conversationId = msg.conversationId;
      }

      // Ghi nhận dữ liệu nhận được để kiểm tra lỗi streaming.
      final contentLength = msg.content?.length ?? 0;

      print(
        '[AI WS IN] type=${msg.type} '
            'conversationId=${msg.conversationId} '
            'contentLength=$contentLength '
            'sources=${msg.sources?.length ?? 0}',
      );

      if (msg.type == 'delta' && contentLength > 0) {
        print(
          '[AI WS DELTA] ${msg.content!.substring(
            0,
            contentLength > 200 ? 200 : contentLength,
          )}',
        );
      }

      if (msg.type == 'error') {
        _messageController.add(
          AiWsMessage(
            type: 'error',
            conversationId: msg.conversationId,
            error: formatError(msg.error),
          ),
        );
        return;
      }

      _messageController.add(msg);
    } catch (e) {
      print('[AI WS PARSE ERROR] $e');

      _messageController.add(
        AiWsMessage(
          type: 'error',
          error: 'Không thể đọc phản hồi từ máy chủ AI.',
        ),
      );
    }
  }

  void _onError(dynamic error) {
    _isConnected = false;
    _pingTimer?.cancel();

    print('[AI WS ERROR] $error');

    _messageController.add(
      AiWsMessage(
        type: 'error',
        error: formatError(
          error,
          connectionError: true,
        ),
      ),
    );
  }

  void _onDone() {
    _isConnected = false;
    _pingTimer?.cancel();

    print('[AI WS CLOSED] conversationId=$_conversationId');
  }

  void _startPingTimer() {
    _pingTimer?.cancel();

    _pingTimer = Timer.periodic(
      const Duration(seconds: 5),
          (timer) {
        if (!_isConnected || _channel == null) {
          timer.cancel();
          return;
        }

        send(AiWsMessage.ping());
      },
    );
  }

  void send(AiWsMessage msg) {
    if (!_isConnected || _channel == null) return;

    try {
      _channel!.sink.add(jsonEncode(msg.toJson()));
    } catch (e) {
      print('[AI WS SEND ERROR] $e');
    }
  }

  void sendMessage(String content) {
    send(AiWsMessage.message(content, _conversationId));
  }

  void cancel() {
    if (_conversationId != null) {
      send(AiWsMessage.cancel(_conversationId!));
    }
  }

  void disconnect() {
    cancel();

    _pingTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();

    _isConnected = false;
    _conversationId = null;
  }

  void setConversationId(String? id) {
    _conversationId = id;
  }
}
