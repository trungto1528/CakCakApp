import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../platforms/windows/windows_storage_manager.dart';
/// Lớp lưu cài đặt:
/// - Windows: preferences.json trong thư mục dữ liệu tùy chỉnh.
/// - Các nền tảng khác: SharedPreferences như trước.
class AppPreferences {
  AppPreferences._({
    SharedPreferences? sharedPreferences,
    Map<String, dynamic>? values,
    File? file,
  })  : _sharedPreferences = sharedPreferences,
        _values = values,
        _file = file;
  static Future<AppPreferences>? _instanceFuture;
  final SharedPreferences? _sharedPreferences;
  final Map<String, dynamic>? _values;
  final File? _file;
  static Future<AppPreferences> getInstance() {
    return _instanceFuture ??= _createInstance();
  }
  static Future<AppPreferences> _createInstance() async {
    if (!WindowsStorageManager.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      return AppPreferences._(
        sharedPreferences: prefs,
      );
    }
    final root = WindowsStorageManager.rootPath;
    if (root == null) {
      throw StateError(
        'Chưa cấu hình thư mục lưu trữ trên Windows.',
      );
    }
    final file = File(
      '$root${Platform.pathSeparator}preferences.json',
    );
    Map<String, dynamic> values = {};
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          values = Map<String, dynamic>.from(decoded);
        }
      }
    } else {
      // Chuyển các cài đặt cũ sang file JSON lần đầu.
      // Không xóa dữ liệu SharedPreferences cũ.
      final legacy = await SharedPreferences.getInstance();
      for (final key in legacy.getKeys()) {
        final value = legacy.get(key);
        if (value != null) {
          values[key] = value;
        }
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(values),
        flush: true,
      );
    }
    return AppPreferences._(
      values: values,
      file: file,
    );
  }
  /// Gọi sau khi thay đổi thư mục lưu trữ để lần lấy tiếp theo
  /// khởi tạo lại với đường dẫn mới.
  static void resetInstance() {
    _instanceFuture = null;
  }
  dynamic get(String key) {
    if (_sharedPreferences != null) {
      return _sharedPreferences.get(key);
    }
    return _values![key];
  }
  String? getString(String key) {
    final value = get(key);
    return value is String ? value : null;
  }
  int? getInt(String key) {
    final value = get(key);
    return value is int ? value : null;
  }
  double? getDouble(String key) {
    final value = get(key);
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }
  bool? getBool(String key) {
    final value = get(key);
    return value is bool ? value : null;
  }
  List<String>? getStringList(String key) {
    final value = get(key);
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return null;
  }
  Set<String> getKeys() {
    if (_sharedPreferences != null) {
      return _sharedPreferences.getKeys();
    }
    return _values!.keys.toSet();
  }
  bool containsKey(String key) {
    if (_sharedPreferences != null) {
      return _sharedPreferences.containsKey(key);
    }
    return _values!.containsKey(key);
  }
  Future<bool> setString(String key, String value) {
    return _setValue(key, value);
  }
  Future<bool> setInt(String key, int value) {
    return _setValue(key, value);
  }
  Future<bool> setDouble(String key, double value) {
    return _setValue(key, value);
  }
  Future<bool> setBool(String key, bool value) {
    return _setValue(key, value);
  }
  Future<bool> setStringList(String key, List<String> value) {
    return _setValue(key, value);
  }
  Future<bool> _setValue(String key, Object value) async {
    if (_sharedPreferences != null) {
      if (value is String) {
        return _sharedPreferences.setString(key, value);
      }
      if (value is int) {
        return _sharedPreferences.setInt(key, value);
      }
      if (value is double) {
        return _sharedPreferences.setDouble(key, value);
      }
      if (value is bool) {
        return _sharedPreferences.setBool(key, value);
      }
      if (value is List<String>) {
        return _sharedPreferences.setStringList(key, value);
      }
      throw ArgumentError.value(value, 'value', 'Kiểu dữ liệu không hỗ trợ');
    }
    _values![key] = value;
    await _saveJson();
    return true;
  }
  Future<bool> remove(String key) async {
    if (_sharedPreferences != null) {
      return _sharedPreferences.remove(key);
    }
    _values!.remove(key);
    await _saveJson();
    return true;
  }
  Future<bool> clear() async {
    if (_sharedPreferences != null) {
      return _sharedPreferences.clear();
    }
    _values!.clear();
    await _saveJson();
    return true;
  }
  Future<void> _saveJson() async {
    final file = _file!;
    await file.parent.create(recursive: true);
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_values),
      flush: true,
    );
    // Windows không thể rename đè lên file đích đang tồn tại.
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }
}
