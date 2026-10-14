
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
  final bool isPaused;
  final bool isCancelling;
  final bool isCancelled;
  final bool isCompleted;
  final String? error;

  const StoryDownloadProgress({
    this.status = '',
    this.completed = 0,
    this.total = 0,
    this.current = '',
    this.isDownloading = false,
    this.isPaused = false,
    this.isCancelling = false,
    this.isCancelled = false,
    this.isCompleted = false,
    this.error,
  });

  double get progress {
    if (total <= 0) return 0;
    return (completed / total).clamp(0.0, 1.0);
  }

  int get percent => (progress * 100).round();
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}

class StoryDownloadService {
  StoryDownloadService._();

  static final StoryDownloadService instance = StoryDownloadService._();

  static const int _maxConcurrentImages = 16;
  static const Duration _packageTimeout = Duration(seconds: 60);
  static const Duration _imageTimeout = Duration(seconds: 30);
  static const int _maxAttempts = 5;

  final Map<int, Future<void>> _activeDownloads = {};

  final Map<int, ValueNotifier<StoryDownloadProgress>>
  _progressNotifiers = {};

  final Set<int> _pauseRequested = {};
  final Set<int> _cancelRequested = {};
  final Map<int, Completer<void>> _resumeCompleters = {};

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
        bool? isPaused,
        bool? isCancelling,
        bool? isCancelled,
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
      isPaused: isPaused ?? old.isPaused,
      isCancelling: isCancelling ?? old.isCancelling,
      isCancelled: isCancelled ?? old.isCancelled,
      isCompleted: isCompleted ?? old.isCompleted,
      error: clearError ? null : (error ?? old.error),
    );
  }

  bool isDownloading(int storyId) {
    return _activeDownloads.containsKey(storyId);
  }

  bool isPaused(int storyId) {
    return _pauseRequested.contains(storyId) &&
        _activeDownloads.containsKey(storyId);
  }

  bool isCancelling(int storyId) {
    return _cancelRequested.contains(storyId);
  }

  Future<Directory> _storyDirectory(int storyId) async {
    final root = await getApplicationSupportDirectory();

    return Directory(
      '${root.path}${Platform.pathSeparator}'
          'offline_stories${Platform.pathSeparator}$storyId',
    );
  }

  void pauseDownload(int storyId) {
    if (!_activeDownloads.containsKey(storyId)) return;
    if (_cancelRequested.contains(storyId)) return;
    if (_pauseRequested.contains(storyId)) return;

    _pauseRequested.add(storyId);

    _updateProgress(
      storyId,
      status: 'Đang tạm dừng tải...',
      isDownloading: false,
      isPaused: true,
      isCancelling: false,
      isCancelled: false,
    );
  }

  void resumeDownload(int storyId) {
    if (!_activeDownloads.containsKey(storyId)) return;
    if (!_pauseRequested.contains(storyId)) return;
    if (_cancelRequested.contains(storyId)) return;

    _pauseRequested.remove(storyId);

    final completer = _resumeCompleters.remove(storyId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    _updateProgress(
      storyId,
      status: 'Đang tiếp tục tải...',
      isDownloading: true,
      isPaused: false,
      isCancelling: false,
      isCancelled: false,
      clearError: true,
    );
  }

  /// Hủy tải và xóa toàn bộ dữ liệu tải dở của truyện.
  ///
  /// Chờ tác vụ tải cùng các worker kết thúc trước khi xóa thư mục,
  /// tránh trường hợp worker ghi ảnh trở lại sau khi dữ liệu bị xóa.
  Future<void> cancelDownload(int storyId) async {
    final active = _activeDownloads[storyId];

    if (active == null) {
      _pauseRequested.remove(storyId);
      _cancelRequested.remove(storyId);

      await _deleteStoryDirectory(storyId);

      _updateProgress(
        storyId,
        status: 'Đã hủy tải',
        completed: 0,
        total: 0,
        current: '',
        isDownloading: false,
        isPaused: false,
        isCancelling: false,
        isCancelled: true,
        isCompleted: false,
        clearError: true,
      );
      return;
    }

    // Đặt cờ hủy ngay để các worker dừng tại điểm an toàn.
    _cancelRequested.add(storyId);
    _pauseRequested.remove(storyId);

    _updateProgress(
      storyId,
      status: 'Đang hủy tải...',
      isDownloading: false,
      isPaused: false,
      isCancelling: true,
      isCancelled: false,
      isCompleted: false,
    );

    // Đánh thức worker nếu đang đợi người dùng tiếp tục.
    final completer = _resumeCompleters.remove(storyId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    try {
      await active;
    } catch (_) {
      // Lỗi hủy được xử lý trong _downloadStoryInternal.
    }

    // Chỉ xóa sau khi future chính đã kết thúc.
    // Bao gồm ảnh, chapters, metadata.json và complete.json.
    await _deleteStoryDirectory(storyId);

    _pauseRequested.remove(storyId);
    _cancelRequested.remove(storyId);

    final resumeCompleter = _resumeCompleters.remove(storyId);
    if (resumeCompleter != null && !resumeCompleter.isCompleted) {
      resumeCompleter.complete();
    }

    _updateProgress(
      storyId,
      status: 'Đã hủy tải',
      completed: 0,
      total: 0,
      current: '',
      isDownloading: false,
      isPaused: false,
      isCancelling: false,
      isCancelled: true,
      isCompleted: false,
      clearError: true,
    );
  }

  /// Xóa hoàn toàn thư mục dữ liệu offline của truyện.
  Future<void> _deleteStoryDirectory(int storyId) async {
    final directory = await _storyDirectory(storyId);

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Dọn các file tạm, dùng khi cần giữ lại dữ liệu đã tải.
  Future<void> _cleanupTemporaryFiles(int storyId) async {
    final directory = await _storyDirectory(storyId);

    if (!await directory.exists()) return;

    await for (final entity
    in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.part')) {
        try {
          await entity.delete();
        } catch (_) {
          // File có thể đã được xóa bởi worker khác.
        }
      }
    }
  }

  Future<void> _throwIfCancelled(int storyId) async {
    if (_cancelRequested.contains(storyId)) {
      throw const _DownloadCancelled();
    }
  }

  Future<void> _waitIfPaused(int storyId) async {
    while (true) {
      if (_cancelRequested.contains(storyId)) {
        throw const _DownloadCancelled();
      }

      if (!_pauseRequested.contains(storyId)) {
        return;
      }

      _updateProgress(
        storyId,
        status: 'Đã tạm dừng tải',
        isDownloading: false,
        isPaused: true,
        isCancelling: false,
      );

      final completer = _resumeCompleters.putIfAbsent(
        storyId,
            () => Completer<void>(),
      );

      await completer.future;
    }
  }

  Future<void> downloadStory(
      int storyId, {
        void Function(int completed, int total, String current)? onProgress,
        void Function(String message)? onStatus,
      }) {
    final existing = _activeDownloads[storyId];

    if (existing != null) {
      if (_pauseRequested.contains(storyId)) {
        resumeDownload(storyId);
      }
      return existing;
    }

    _pauseRequested.remove(storyId);
    _cancelRequested.remove(storyId);

    _updateProgress(
      storyId,
      status: 'Đang chuẩn bị tải...',
      completed: 0,
      total: 0,
      current: '',
      isDownloading: true,
      isPaused: false,
      isCancelling: false,
      isCancelled: false,
      isCompleted: false,
      clearError: true,
    );

    final internalFuture = _downloadStoryInternal(
      storyId,
      onProgress: onProgress,
      onStatus: onStatus,
    );

    late final Future<void> trackedFuture;

    trackedFuture = internalFuture.whenComplete(() {
      if (identical(_activeDownloads[storyId], trackedFuture)) {
        _activeDownloads.remove(storyId);
      }

      _pauseRequested.remove(storyId);
      _cancelRequested.remove(storyId);

      final completer = _resumeCompleters.remove(storyId);
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    });

    _activeDownloads[storyId] = trackedFuture;

    return trackedFuture;
  }

  void _emitStatus(
      int storyId,
      String message,
      void Function(String message)? onStatus,
      ) {
    if (_cancelRequested.contains(storyId)) return;

    if (_pauseRequested.contains(storyId)) {
      _updateProgress(
        storyId,
        status: 'Đã tạm dừng tải',
        isDownloading: false,
        isPaused: true,
      );
      return;
    }

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
    if (_cancelRequested.contains(storyId)) return;

    _updateProgress(
      storyId,
      completed: completed,
      total: total,
      current: current,
    );

    onProgress?.call(completed, total, current);
  }

  Future<http.Response> _getWithRetry({
    required int storyId,
    required Uri uri,
    required Duration timeout,
    required String description,
    required void Function(String message) onRetryStatus,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      await _waitIfPaused(storyId);

      try {
        final response = await http.get(uri).timeout(timeout);

        await _waitIfPaused(storyId);

        if (response.statusCode == 200 &&
            response.bodyBytes.isNotEmpty) {
          return response;
        }

        throw HttpException(
          '$description: HTTP ${response.statusCode}',
        );
      } on _DownloadCancelled {
        rethrow;
      } catch (e) {
        if (_cancelRequested.contains(storyId)) {
          throw const _DownloadCancelled();
        }

        lastError = e;

        if (attempt >= _maxAttempts) break;

        await _waitIfPaused(storyId);

        onRetryStatus(
          '$description thất bại. Thử lại ($attempt/$_maxAttempts)...',
        );

        await Future<void>.delayed(
          Duration(milliseconds: 700 * attempt),
        );

        await _waitIfPaused(storyId);
      }
    }

    throw Exception(
      '$description thất bại sau $_maxAttempts lần thử: $lastError',
    );
  }

  Future<void> _downloadImage({
    required int storyId,
    required String imageUrl,
    required File targetFile,
    required String imagePath,
    required void Function(String message) onRetryStatus,
  }) async {
    final temporaryFile = File('${targetFile.path}.part');

    try {
      final response = await _getWithRetry(
        storyId: storyId,
        uri: Uri.parse(imageUrl),
        timeout: _imageTimeout,
        description: 'Tải ảnh $imagePath',
        onRetryStatus: onRetryStatus,
      );

      await _waitIfPaused(storyId);

      await targetFile.parent.create(recursive: true);
      await _waitIfPaused(storyId);

      await temporaryFile.writeAsBytes(
        response.bodyBytes,
        flush: true,
      );

      await _waitIfPaused(storyId);

      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      // Kiểm tra lần cuối trước khi chuyển file tạm thành file thật.
      await _throwIfCancelled(storyId);
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
      await _throwIfCancelled(storyId);

      final directory = await _storyDirectory(storyId);
      await directory.create(recursive: true);
      await _waitIfPaused(storyId);

      final completeMarker = File(
        '${directory.path}${Platform.pathSeparator}complete.json',
      );

      if (await completeMarker.exists()) {
        await completeMarker.delete();
      }

      await _waitIfPaused(storyId);

      status('Đang tải package truyện...');

      final packageUrl =
          '${ApiConfig.api}/stories/$storyId/package.zip';

      final response = await _getWithRetry(
        storyId: storyId,
        uri: Uri.parse(packageUrl),
        timeout: _packageTimeout,
        description: 'Tải package truyện',
        onRetryStatus: status,
      );

      await _waitIfPaused(storyId);

      status('Đang giải nén package...');

      final archive = ZipDecoder().decodeBytes(response.bodyBytes);
      final imageList = <String>[];

      for (final entry in archive.files) {
        await _waitIfPaused(storyId);

        if (!entry.isFile) continue;

        final name = entry.name.replaceAll('\\', '/');
        final parts = name.split('/');

        if (name.startsWith('/') ||
            name.contains(':') ||
            parts.any((part) => part == '..')) {
          throw Exception('Package chứa đường dẫn không hợp lệ: $name');
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
            throw Exception('Tên file chapter không hợp lệ: $name');
          }

          final chapterDirectory = Directory(
            '${directory.path}/chapters',
          );

          await chapterDirectory.create(recursive: true);
          await _waitIfPaused(storyId);

          await File(
            '${chapterDirectory.path}/$relativePath',
          ).writeAsBytes(bytes, flush: true);
        }
      }

      await _waitIfPaused(storyId);

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
      configuredBaseUrl != null && configuredBaseUrl.isNotEmpty
          ? configuredBaseUrl.replaceFirst(RegExp(r'/+$'), '')
          : ApiConfig.image;

      final uniqueImagePaths = imageList.toSet().toList();

      for (final imagePath in uniqueImagePaths) {
        _validateImagePath(imagePath);
      }

      final total = uniqueImagePaths.length;
      var completed = 0;
      var nextIndex = 0;

      final failures = <String>[];

      status('Chuẩn bị tải $total ảnh...');
      progress(0, total, '');

      Future<void> worker() async {
        while (true) {
          await _waitIfPaused(storyId);

          if (nextIndex >= total) return;

          final index = nextIndex++;
          final imagePath = uniqueImagePaths[index];
          final targetFile = File('${directory.path}/$imagePath');

          try {
            await targetFile.parent.create(recursive: true);
            await _waitIfPaused(storyId);

            if (!await targetFile.exists() ||
                await targetFile.length() == 0) {
              final imageUrl = '$imageBaseUrl/$imagePath';

              await _downloadImage(
                storyId: storyId,
                imageUrl: imageUrl,
                targetFile: targetFile,
                imagePath: imagePath,
                onRetryStatus: status,
              );
            }
          } on _DownloadCancelled {
            rethrow;
          } catch (e) {
            if (_cancelRequested.contains(storyId)) {
              throw const _DownloadCancelled();
            }

            failures.add('$imagePath: $e');
          } finally {
            if (!_cancelRequested.contains(storyId)) {
              completed++;
              progress(completed, total, imagePath);
              status('Đã xử lý $completed/$total ảnh');
            }
          }
        }
      }

      final workerCount = total < _maxConcurrentImages
          ? total
          : _maxConcurrentImages;

      // Future.wait mặc định chờ các worker hoàn tất trước khi trả lỗi.
      await Future.wait(
        List.generate(workerCount, (_) => worker()),
      );

      await _waitIfPaused(storyId);

      if (failures.isNotEmpty) {
        final preview = failures.take(5).join('\n');

        throw Exception(
          '${failures.length} ảnh không tải được:\n$preview'
              '${failures.length > 5 ? '\n...' : ''}\n'
              'Nhấn tải lại để tiếp tục tải các ảnh còn thiếu.',
        );
      }

      for (final imagePath in uniqueImagePaths) {
        await _waitIfPaused(storyId);

        final file = File('${directory.path}/$imagePath');

        if (!await file.exists() || await file.length() == 0) {
          throw Exception('Ảnh chưa được tải đầy đủ: $imagePath');
        }
      }

      await _waitIfPaused(storyId);
      await _throwIfCancelled(storyId);

      final manifest = <String, dynamic>{
        'storyId': storyId,
        'title': metadata['title'],
        'downloadedAt': DateTime.now().toIso8601String(),
        'imageCount': uniqueImagePaths.length,
        'images': uniqueImagePaths,
      };

      await _waitIfPaused(storyId);
      await _throwIfCancelled(storyId);

      await completeMarker.writeAsString(
        jsonEncode(manifest),
        flush: true,
      );

      if (_cancelRequested.contains(storyId)) {
        if (await completeMarker.exists()) {
          await completeMarker.delete();
        }
        throw const _DownloadCancelled();
      }

      _updateProgress(
        storyId,
        status: 'Tải truyện hoàn tất.',
        completed: total,
        total: total,
        current: '',
        isDownloading: false,
        isPaused: false,
        isCancelling: false,
        isCancelled: false,
        isCompleted: true,
        clearError: true,
      );

      onStatus?.call('Tải truyện hoàn tất.');
    } on _DownloadCancelled {
      // Không xóa thư mục tại đây vì cancelDownload sẽ chờ toàn bộ
      // future kết thúc rồi xóa thư mục đúng một lần.
      _updateProgress(
        storyId,
        status: 'Đang hủy tải...',
        isDownloading: false,
        isPaused: false,
        isCancelling: true,
        isCancelled: false,
        isCompleted: false,
        clearError: true,
      );
    } catch (e) {
      if (_cancelRequested.contains(storyId)) {
        _updateProgress(
          storyId,
          status: 'Đang hủy tải...',
          isDownloading: false,
          isPaused: false,
          isCancelling: true,
          isCancelled: false,
          isCompleted: false,
          clearError: true,
        );
        return;
      }

      final paused = _pauseRequested.contains(storyId);

      _updateProgress(
        storyId,
        status: paused ? 'Đã tạm dừng tải' : 'Tải truyện thất bại',
        isDownloading: false,
        isPaused: paused,
        isCancelling: false,
        isCancelled: false,
        isCompleted: false,
        error: paused ? null : e.toString(),
      );

      rethrow;
    }
  }

  Future<void> deleteDownloadedStory(int storyId) async {
    if (isDownloading(storyId)) {
      throw Exception(
        'Không thể xóa khi truyện đang tải hoặc đang tạm dừng. '
            'Hãy hủy tải trước.',
      );
    }

    await _deleteStoryDirectory(storyId);

    _updateProgress(
      storyId,
      status: '',
      completed: 0,
      total: 0,
      current: '',
      isDownloading: false,
      isPaused: false,
      isCancelling: false,
      isCancelled: false,
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
      throw Exception('Đường dẫn ảnh không hợp lệ: $imagePath');
    }
  }
}
