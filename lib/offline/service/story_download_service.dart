
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:novel_app/config/api_config.dart';
import 'package:path_provider/path_provider.dart';

class StoryDownloadProgress {
  final String status;
  final int completed;
  final int total;
  final String current;
  final bool isDownloading;
  final bool isCompleted;
  final String? error;

  const StoryDownloadProgress({
    this.status = '',
    this.completed = 0,
    this.total = 0,
    this.current = '',
    this.isDownloading = false,
    this.isCompleted = false,
    this.error,
  });

  double get progress {
    if (total <= 0) return 0;
    return (completed / total).clamp(0.0, 1.0);
  }

  int get percent => (progress * 100).round();
}

class StoryDownloadService {
  StoryDownloadService._();

  static final StoryDownloadService instance = StoryDownloadService._();

  // Giảm tải đồng thời để ổn định hơn trên mạng yếu.
  static const int _maxConcurrentImages = 16;

  // Timeout riêng cho package và từng ảnh.
  static const Duration _packageTimeout = Duration(seconds: 60);
  static const Duration _imageTimeout = Duration(seconds: 30);

  // Tổng số lần thử, tính cả lần đầu.
  static const int _maxAttempts = 5;

  final Map<int, Future<void>> _activeDownloads = {};

  final Map<int, ValueNotifier<StoryDownloadProgress>>
  _progressNotifiers = {};

  ValueNotifier<StoryDownloadProgress> progressFor(int storyId) {
    return _progressNotifiers.putIfAbsent(
      storyId,
          () => ValueNotifier(const StoryDownloadProgress()),
    );
  }

  void _updateProgress(
      int storyId, {
        String? status,
        int? completed,
        int? total,
        String? current,
        bool? isDownloading,
        bool? isCompleted,
        String? error,
        bool clearError = false,
      }) {
    final notifier = progressFor(storyId);
    final old = notifier.value;

    notifier.value = StoryDownloadProgress(
      status: status ?? old.status,
      completed: completed ?? old.completed,
      total: total ?? old.total,
      current: current ?? old.current,
      isDownloading: isDownloading ?? old.isDownloading,
      isCompleted: isCompleted ?? old.isCompleted,
      error: clearError ? null : (error ?? old.error),
    );
  }

  bool isDownloading(int storyId) {
    return _activeDownloads.containsKey(storyId);
  }

  Future<Directory> _storyDirectory(int storyId) async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/offline_stories/$storyId');
  }

  Future<void> downloadStory(
      int storyId, {
        void Function(int completed, int total, String current)? onProgress,
        void Function(String message)? onStatus,
      }) {
    final existing = _activeDownloads[storyId];

    if (existing != null) {
      return existing;
    }

    _updateProgress(
      storyId,
      status: 'Đang chuẩn bị tải...',
      completed: 0,
      total: 0,
      current: '',
      isDownloading: true,
      isCompleted: false,
      clearError: true,
    );

    final future = _downloadStoryInternal(
      storyId,
      onProgress: onProgress,
      onStatus: onStatus,
    );

    _activeDownloads[storyId] = future;

    return future.whenComplete(() {
      if (identical(_activeDownloads[storyId], future)) {
        _activeDownloads.remove(storyId);
      }
    });
  }

  void _emitStatus(
      int storyId,
      String message,
      void Function(String message)? onStatus,
      ) {
    _updateProgress(storyId, status: message);
    onStatus?.call(message);
  }

  void _emitProgress(
      int storyId,
      int completed,
      int total,
      String current,
      void Function(int completed, int total, String current)? onProgress,
      ) {
    _updateProgress(
      storyId,
      completed: completed,
      total: total,
      current: current,
    );

    onProgress?.call(completed, total, current);
  }

  /// Gửi HTTP request với timeout và retry.
  Future<http.Response> _getWithRetry({
    required Uri uri,
    required Duration timeout,
    required String description,
    required void Function(String message) onRetryStatus,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await http.get(uri).timeout(timeout);

        if (response.statusCode == 200 &&
            response.bodyBytes.isNotEmpty) {
          return response;
        }

        throw HttpException(
          '$description: HTTP ${response.statusCode}',
        );
      } catch (e) {
        lastError = e;

        if (attempt >= _maxAttempts) {
          break;
        }

        onRetryStatus(
          '$description thất bại. Thử lại '
              '($attempt/$_maxAttempts)...',
        );

        await Future<void>.delayed(
          Duration(milliseconds: 700 * attempt),
        );
      }
    }

    throw Exception(
      '$description thất bại sau $_maxAttempts lần thử: $lastError',
    );
  }

  Future<void> _downloadImage({
    required String imageUrl,
    required File targetFile,
    required String imagePath,
    required void Function(String message) onRetryStatus,
  }) async {
    final temporaryFile = File('${targetFile.path}.part');

    try {
      final response = await _getWithRetry(
        uri: Uri.parse(imageUrl),
        timeout: _imageTimeout,
        description: 'Tải ảnh $imagePath',
        onRetryStatus: onRetryStatus,
      );

      await targetFile.parent.create(recursive: true);

      // Ghi vào file tạm trước, tránh để lại ảnh tải dở.
      await temporaryFile.writeAsBytes(
        response.bodyBytes,
        flush: true,
      );

      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      await temporaryFile.rename(targetFile.path);
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  Future<void> _downloadStoryInternal(
      int storyId, {
        void Function(int completed, int total, String current)? onProgress,
        void Function(String message)? onStatus,
      }) async {
    void status(String message) {
      _emitStatus(storyId, message, onStatus);
    }

    void progress(int completed, int total, String current) {
      _emitProgress(
        storyId,
        completed,
        total,
        current,
        onProgress,
      );
    }

    try {
      final directory = await _storyDirectory(storyId);
      await directory.create(recursive: true);

      final completeMarker = File('${directory.path}/complete.json');

      if (await completeMarker.exists()) {
        await completeMarker.delete();
      }

      // 1. Tải package, tự thử lại nếu kết nối lỗi.
      status('Đang tải package truyện...');

      final packageUrl =
          '${ApiConfig.api}/stories/$storyId/package.zip';

      final response = await _getWithRetry(
        uri: Uri.parse(packageUrl),
        timeout: _packageTimeout,
        description: 'Tải package truyện',
        onRetryStatus: status,
      );

      // 2. Giải nén package.
      status('Đang giải nén package...');

      final archive = ZipDecoder().decodeBytes(response.bodyBytes);
      final imageList = <String>[];

      for (final entry in archive.files) {
        if (!entry.isFile) continue;

        final name = entry.name.replaceAll('\\', '/');
        final parts = name.split('/');

        if (name.startsWith('/') ||
            name.contains(':') ||
            parts.any((part) => part == '..')) {
          throw Exception(
            'Package chứa đường dẫn không hợp lệ: $name',
          );
        }

        final content = entry.content;
        final bytes = content is List<int>
            ? content
            : List<int>.from(content as Iterable);

        if (name == 'metadata.json') {
          await File('${directory.path}/metadata.json').writeAsBytes(
            bytes,
            flush: true,
          );
        } else if (name == 'images.txt') {
          imageList
            ..clear()
            ..addAll(
              utf8
                  .decode(bytes)
                  .split(RegExp(r'\r?\n'))
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty),
            );
        } else if (name.startsWith('chapters/') &&
            name.endsWith('.json')) {
          final relativePath = name.substring('chapters/'.length);

          if (relativePath.contains('/') ||
              relativePath.isEmpty ||
              relativePath == '.' ||
              relativePath == '..') {
            throw Exception(
              'Tên file chapter không hợp lệ: $name',
            );
          }

          final chapterDirectory =
          Directory('${directory.path}/chapters');

          await chapterDirectory.create(recursive: true);

          await File(
            '${chapterDirectory.path}/$relativePath',
          ).writeAsBytes(bytes, flush: true);
        }
      }

      // 3. Kiểm tra metadata.
      final metadataFile = File('${directory.path}/metadata.json');

      if (!await metadataFile.exists()) {
        throw Exception('Package không có metadata.json');
      }

      final decodedMetadata = jsonDecode(
        await metadataFile.readAsString(),
      );

      if (decodedMetadata is! Map) {
        throw Exception('metadata.json không hợp lệ');
      }

      final metadata = Map<String, dynamic>.from(decodedMetadata);
      metadata['id'] ??= storyId;

      final configuredBaseUrl =
      metadata['imageBaseUrl']?.toString().trim();

      final imageBaseUrl =
      configuredBaseUrl != null &&
          configuredBaseUrl.isNotEmpty
          ? configuredBaseUrl.replaceFirst(
        RegExp(r'/+$'),
        '',
      )
          : ApiConfig.image;

      // 4. Chuẩn hóa danh sách ảnh.
      final uniqueImagePaths = imageList.toSet().toList();

      for (final imagePath in uniqueImagePaths) {
        _validateImagePath(imagePath);
      }

      final total = uniqueImagePaths.length;
      var completed = 0;
      var nextIndex = 0;

      // Lưu các lỗi cuối cùng để thử hết ảnh còn lại,
      // không để một ảnh lỗi dừng cả hàng đợi.
      final failures = <String>[];

      status('Chuẩn bị tải $total ảnh...');
      progress(0, total, '');

      // 5. Mỗi worker xử lý ảnh kế tiếp trong hàng đợi.
      Future<void> worker() async {
        while (true) {
          if (nextIndex >= total) return;

          // Lấy chỉ số trước await để mỗi ảnh chỉ được xử lý một lần.
          final index = nextIndex++;

          final imagePath = uniqueImagePaths[index];
          final targetFile = File('${directory.path}/$imagePath');

          try {
            await targetFile.parent.create(recursive: true);

            // Giữ lại ảnh đã tải thành công ở lần trước.
            if (await targetFile.exists() &&
                await targetFile.length() > 0) {
              // Bỏ qua ảnh đã có.
            } else {
              final imageUrl = '$imageBaseUrl/$imagePath';

              await _downloadImage(
                imageUrl: imageUrl,
                targetFile: targetFile,
                imagePath: imagePath,
                onRetryStatus: (message) {
                  status(message);
                },
              );
            }
          } catch (e) {
            failures.add('$imagePath: $e');
          } finally {
            completed++;

            progress(
              completed,
              total,
              imagePath,
            );

            status(
              'Đã xử lý $completed/$total ảnh',
            );
          }
        }
      }

      final workerCount =
      total < _maxConcurrentImages ? total : _maxConcurrentImages;

      await Future.wait(
        List.generate(workerCount, (_) => worker()),
      );

      // 6. Không đánh dấu hoàn tất nếu còn ảnh lỗi hoặc thiếu.
      if (failures.isNotEmpty) {
        final preview = failures.take(5).join('\n');

        throw Exception(
          '${failures.length} ảnh không tải được:\n$preview'
              '${failures.length > 5 ? '\n...' : ''}\n'
              'Nhấn tải lại để tiếp tục tải các ảnh còn thiếu.',
        );
      }

      for (final imagePath in uniqueImagePaths) {
        final file = File('${directory.path}/$imagePath');

        if (!await file.exists() || await file.length() == 0) {
          throw Exception('Ảnh chưa được tải đầy đủ: $imagePath');
        }
      }

      // 7. Ghi manifest sau khi tất cả ảnh thành công.
      final manifest = <String, dynamic>{
        'storyId': storyId,
        'title': metadata['title'],
        'downloadedAt': DateTime.now().toIso8601String(),
        'imageCount': uniqueImagePaths.length,
        'images': uniqueImagePaths,
      };

      await completeMarker.writeAsString(
        jsonEncode(manifest),
        flush: true,
      );

      _updateProgress(
        storyId,
        status: 'Tải truyện hoàn tất.',
        completed: total,
        total: total,
        current: '',
        isDownloading: false,
        isCompleted: true,
        clearError: true,
      );

      onStatus?.call('Tải truyện hoàn tất.');
    } catch (e) {
      _updateProgress(
        storyId,
        status: 'Tải truyện thất bại',
        isDownloading: false,
        isCompleted: false,
        error: e.toString(),
      );

      rethrow;
    }
  }

  Future<void> deleteDownloadedStory(int storyId) async {
    if (isDownloading(storyId)) {
      throw Exception(
        'Không thể xóa khi truyện đang được tải.',
      );
    }

    final directory = await _storyDirectory(storyId);

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }

    _updateProgress(
      storyId,
      status: '',
      completed: 0,
      total: 0,
      current: '',
      isDownloading: false,
      isCompleted: false,
      clearError: true,
    );
  }

  void _validateImagePath(String imagePath) {
    final normalized = imagePath.replaceAll('\\', '/');
    final parts = normalized.split('/');

    if (parts.length != 2 ||
        (parts[0] != 'cover' && parts[0] != 'chapter') ||
        parts[1].isEmpty ||
        parts[1] == '.' ||
        parts[1] == '..' ||
        parts[1].contains(':')) {
      throw Exception(
        'Đường dẫn ảnh không hợp lệ: $imagePath',
      );
    }
  }
}
