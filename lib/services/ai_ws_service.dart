import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../services/app_preference.dart';
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

  Future<void> connect(int userId) async {
    if (_isConnected) return;

    final uri = Uri.parse(
      '${ApiConfig.api.replaceFirst('http', 'ws')}/ws/ai/chat?userId=$userId',
    );

    _channel = WebSocketChannel.connect(uri);

    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
    );

    _isConnected = true;
    _startPingTimer();
  }

  void _onMessage(dynamic data) {
    try {
      final Map<String, dynamic> json = jsonDecode(data as String);
      final msg = AiWsMessage.fromJson(json);
      _messageController.add(msg);

      if (msg.type == 'done') {
        _conversationId = msg.conversationId;
      }
    } catch (e) {
      print('Error parsing WS message: $e');
    }
  }

  void _onError(dynamic error) {
    print('WS Error: $error');
    _isConnected = false;
    _pingTimer?.cancel();
    _messageController.add(AiWsMessage(
      type: 'error',
      error: 'Lỗi kết nối: $error',
    ));
  }

  void _onDone() {
    _isConnected = false;
    _pingTimer?.cancel();
    print('WS connection closed');
  }

  void _startPingTimer() {
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isConnected || _channel == null) {
        timer.cancel();
        return;
      }
      send(AiWsMessage.ping());
    });
  }

  void send(AiWsMessage msg) {
    if (!_isConnected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(msg.toJson()));
    } catch (e) {
      print('Error sending WS message: $e');
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