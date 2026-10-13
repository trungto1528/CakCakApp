
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

  static const int _maxConcurrentImages = 12;
  static const Duration _requestTimeout = Duration(minutes: 3);

  final Map<int, Future<void>> _activeDownloads = {};
  final Map<int, ValueNotifier<StoryDownloadProgress>> _progressNotifiers =
  {};

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

  Future<void> _downloadStoryInternal(
      int storyId, {
        void Function(int completed, int total, String current)? onProgress,
        void Function(String message)? onStatus,
      }) async {
    void status(String message) {
      _updateProgress(storyId, status: message);
      onStatus?.call(message);
    }

    void progress(int completed, int total, String current) {
      _updateProgress(
        storyId,
        completed: completed,
        total: total,
        current: current,
      );
      onProgress?.call(completed, total, current);
    }

    try {
      final directory = await _storyDirectory(storyId);
      await directory.create(recursive: true);

      final completeMarker = File('${directory.path}/complete.json');

      if (await completeMarker.exists()) {
        await completeMarker.delete();
      }

      status('Đang tải package truyện...');

      final packageUrl =
          '${ApiConfig.api}/stories/$storyId/package.zip';

      final response = await http
          .get(Uri.parse(packageUrl))
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw Exception(
          'Không tải được package. HTTP ${response.statusCode}',
        );
      }

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

          final chapterDirectory =
          Directory('${directory.path}/chapters');

          await chapterDirectory.create(recursive: true);

          await File(
            '${chapterDirectory.path}/$relativePath',
          ).writeAsBytes(bytes, flush: true);
        }
      }

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

      status('Đang tải ảnh: ${uniqueImagePaths.length} ảnh...');

      var completed = 0;
      progress(completed, uniqueImagePaths.length, '');

      for (var i = 0;
      i < uniqueImagePaths.length;
      i += _maxConcurrentImages) {
        final end = (i + _maxConcurrentImages)
            .clamp(0, uniqueImagePaths.length);

        final batch = uniqueImagePaths.sublist(i, end);

        await Future.wait(
          batch.map((imagePath) async {
            final targetFile = File('${directory.path}/$imagePath');
            await targetFile.parent.create(recursive: true);

            if (await targetFile.exists() &&
                await targetFile.length() > 0) {
              completed++;
              progress(completed, uniqueImagePaths.length, imagePath);
              return;
            }

            final imageUrl = '$imageBaseUrl/$imagePath';

            final imageResponse = await http
                .get(Uri.parse(imageUrl))
                .timeout(_requestTimeout);

            if (imageResponse.statusCode != 200 ||
                imageResponse.bodyBytes.isEmpty) {
              throw Exception(
                'Không tải được ảnh $imagePath '
                    '(HTTP ${imageResponse.statusCode})',
              );
            }

            final temporaryFile = File('${targetFile.path}.part');

            try {
              await temporaryFile.writeAsBytes(
                imageResponse.bodyBytes,
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

            completed++;
            progress(completed, uniqueImagePaths.length, imagePath);
          }),
        );
      }

      for (final imagePath in uniqueImagePaths) {
        final file = File('${directory.path}/$imagePath');

        if (!await file.exists() || await file.length() == 0) {
          throw Exception('Ảnh chưa được tải đầy đủ: $imagePath');
        }
      }

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
        completed: uniqueImagePaths.length,
        total: uniqueImagePaths.length,
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
      throw Exception('Không thể xóa khi truyện đang được tải.');
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
      throw Exception('Đường dẫn ảnh không hợp lệ: $imagePath');
    }
  }
}
