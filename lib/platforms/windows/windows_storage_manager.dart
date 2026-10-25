import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
/// Quản lý thư mục dữ liệu tùy chỉnh của ứng dụng trên Windows.
///
/// File storage_config.json nằm cạnh file executable (.exe).
/// Dữ liệu ứng dụng được lưu trong thư mục mà người dùng chọn.
class WindowsStorageManager {
  WindowsStorageManager._();
  static String? _rootPath;
  /// Đường dẫn lưu trữ hiện tại; null nếu chưa cấu hình.
  static String? get rootPath => _rootPath;
  static bool get isConfigured => _rootPath != null;
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static String get _separator => Platform.pathSeparator;
  /// Thư mục chứa file .exe đang chạy.
  static Directory get _executableDirectory {
    return File(Platform.resolvedExecutable).parent;
  }
  /// File cấu hình nằm cạnh file .exe.
  static File get _configFile {
    return File(
      '${_executableDirectory.path}'
          '${_separator}storage_config.json',
    );
  }
  /// Đọc cấu hình đã lưu.
  ///
  /// Trả về null nếu chưa cấu hình, đường dẫn không tồn tại,
  /// không có quyền ghi hoặc file cấu hình không hợp lệ.
  static Future<String?> loadConfiguredRoot() async {
    if (!isWindows) {
      return null;
    }
    try {
      final config = _configFile;
      if (!await config.exists()) {
        _rootPath = null;
        return null;
      }
      final content = await config.readAsString();
      if (content.trim().isEmpty) {
        _rootPath = null;
        return null;
      }
      final decoded = jsonDecode(content);
      if (decoded is! Map ||
          decoded['storageRoot'] is! String) {
        _rootPath = null;
        return null;
      }
      final path = (decoded['storageRoot'] as String).trim();
      if (path.isEmpty) {
        _rootPath = null;
        return null;
      }
      final directory = Directory(path);
      if (!await directory.exists()) {
        _rootPath = null;
        return null;
      }
      // Kiểm tra quyền ghi thực tế.
      final probe = File(
        '${directory.path}${_separator}.novel_app_write_test',
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      _rootPath = directory.absolute.path;
      return _rootPath;
    } catch (_) {
      _rootPath = null;
      return null;
    }
  }
  /// Thiết lập thư mục lưu trữ.
  ///
  /// Chỉ ghi file cấu hình sau khi thư mục đã được tạo và kiểm tra
  /// quyền ghi thành công.
  static Future<void> configureRoot(String selectedPath) async {
    if (!isWindows) {
      throw UnsupportedError(
        'Chỉ Windows hỗ trợ cấu hình thư mục lưu trữ.',
      );
    }
    final path = selectedPath.trim();
    if (path.isEmpty) {
      throw ArgumentError('Đường dẫn lưu trữ không được để trống.');
    }
    final root = Directory(path);
    await root.create(recursive: true);
    // Xác minh quyền ghi.
    final probe = File(
      '${root.path}${_separator}.novel_app_write_test',
    );
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    // Chuẩn bị các thư mục dữ liệu.
    for (final name in [
      'offline_stories',
      'offline_data',
      'cache',
    ]) {
      await Directory(
        '${root.path}$_separator$name',
      ).create(recursive: true);
    }
    final config = _configFile;
    await config.parent.create(recursive: true);
    final temp = File('${config.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'storageRoot': root.absolute.path,
      }),
      flush: true,
    );
    // Thử thay thế cấu hình sau khi file tạm đã ghi thành công.
    // Nếu đã có cấu hình cũ thì giữ bản sao để có thể phục hồi.
    final backup = File('${config.path}.bak');
    final hadConfig = await config.exists();
    if (hadConfig) {
      if (await backup.exists()) {
        await backup.delete();
      }
      await config.rename(backup.path);
    }
    try {
      await temp.rename(config.path);
      if (await backup.exists()) {
        await backup.delete();
      }
      _rootPath = root.absolute.path;
    } catch (_) {
      if (await config.exists()) {
        await config.delete();
      }
      if (await backup.exists()) {
        await backup.rename(config.path);
      }
      rethrow;
    }
  }
  /// Lấy thư mục con và tự tạo nếu chưa tồn tại.
  static Future<Directory> directory(String name) async {
    final root = _rootPath;
    if (root == null) {
      throw StateError(
        'Chưa cấu hình thư mục lưu trữ trên Windows.',
      );
    }
    final directory = Directory(
      '$root$_separator$name',
    );
    await directory.create(recursive: true);
    return directory;
  }
  /// Lấy thư mục gốc dữ liệu.
  static Future<Directory> getRootDirectory() async {
    final root = _rootPath;
    if (root == null) {
      throw StateError(
        'Chưa cấu hình thư mục lưu trữ trên Windows.',
      );
    }
    return Directory(root);
  }
}
