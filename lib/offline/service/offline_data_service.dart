import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class OfflineDataService {
  OfflineDataService._();

  static Future<Directory> _getOfflineDirectory() async {
    final appDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      '${appDirectory.path}${Platform.pathSeparator}offline_data',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  static String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static Future<File> _getFile(String key) async {
    final directory = await _getOfflineDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}'
          '${_safeFileName(key)}.json',
    );
  }

  static Future<void> saveJson(
      String key,
      dynamic data,
      ) async {
    final file = await _getFile(key);

    await file.writeAsString(
      jsonEncode(data),
      flush: true,
    );
  }

  static Future<dynamic> readJson(String key) async {
    final file = await _getFile(key);

    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();

      if (content.trim().isEmpty) {
        return null;
      }

      return jsonDecode(content);
    } catch (e) {
      // Không sử dụng file cache bị lỗi hoặc không hợp lệ.
      return null;
    }
  }

  static Future<bool> hasData(String key) async {
    final file = await _getFile(key);
    return file.exists();
  }

  static Future<void> deleteData(String key) async {
    final file = await _getFile(key);

    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> clearAll() async {
    final directory = await _getOfflineDirectory();

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }

    await directory.create(recursive: true);
  }
}